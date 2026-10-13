import Foundation
import Testing
import TattleCore

@Suite struct BridgeMessageTests {
    private func decode(_ json: String) throws -> BridgeMessage { try BridgeMessage.decode(Data(json.utf8)) }

    @Test func decodesHello() throws {
        #expect(try decode(#"{"v":1,"type":"hello","browser":"chrome","extensionVersion":"0.1.0"}"#)
            == .hello(browser: .chrome, extensionVersion: "0.1.0"))
    }

    @Test func decodesTabs() throws {
        let m = try decode(#"{"v":1,"type":"tabs","browser":"brave","tabs":[{"id":"1:2","title":"Lo-fi","url":"https://x","audible":true,"muted":false}]}"#)
        #expect(m == .tabs(browser: .brave, tabs: [TabInfo(browser: .brave, tabID: "1:2", title: "Lo-fi", url: "https://x", isAudible: true, isMuted: false)], dropped: 0))
    }

    @Test func oneBadTabDoesNotDropTheSnapshot() throws {
        let m = try decode(#"""
        {"v":1,"type":"tabs","browser":"chrome","tabs":[
          {"id":"1:1","audible":true,"muted":false},
          {"id":5,"audible":true,"muted":false},
          "garbage",
          {"id":"","audible":true,"muted":false},
          {"id":"1:2","audible":"yes","muted":false},
          {"id":"1:3","audible":false,"muted":true}]}
        """#)
        guard case let .tabs(_, tabs, dropped) = m else { Issue.record("not tabs"); return }
        #expect(tabs.map(\.tabID) == ["1:1", "1:3"])
        #expect(dropped == 4)
        #expect(tabs[0].title == "")
    }

    @Test func decodesResults() throws {
        #expect(try decode(#"{"v":1,"type":"result","id":"a","ok":true}"#) == .result(id: "a", ok: true, error: nil))
        #expect(try decode(#"{"v":1,"type":"result","id":"a","ok":false,"error":"tab not found"}"#)
            == .result(id: "a", ok: false, error: "tab not found"))
    }

    @Test func commandRoundTrips() throws {
        let m = BridgeMessage.command(id: "b2", command: .mute, tabID: "12:345")
        let json = String(decoding: try m.encoded(), as: UTF8.self)
        #expect(json == #"{"command":"mute","id":"b2","tabId":"12:345","type":"command","v":1}"#)
        #expect(try BridgeMessage.decode(try m.encoded()) == m)
    }

    @Test func tabsRoundTrip() throws {
        let t = TabInfo(browser: .edge, tabID: "1:1", title: "t", url: "https://a/b", isAudible: true, isMuted: true)
        let m = BridgeMessage.tabs(browser: .edge, tabs: [t], dropped: 0)
        #expect(try BridgeMessage.decode(try m.encoded()) == m)
    }

    @Test func rejectsWrongVersion() {
        #expect(throws: BridgeMessageError.unsupportedVersion(2)) { try decode(#"{"v":2,"type":"hello","browser":"chrome","extensionVersion":"1"}"#) }
        #expect(throws: BridgeMessageError.unsupportedVersion(nil)) { try decode(#"{"type":"hello"}"#) }
    }

    @Test func rejectsUnknownAndMalformed() {
        #expect(throws: BridgeMessageError.unknownType("ping")) { try decode(#"{"v":1,"type":"ping"}"#) }
        #expect(throws: BridgeMessageError.unknownBrowser("netscape")) { try decode(#"{"v":1,"type":"hello","browser":"netscape","extensionVersion":"1"}"#) }
        #expect(throws: BridgeMessageError.missingField("tabs")) { try decode(#"{"v":1,"type":"tabs","browser":"chrome"}"#) }
        #expect(throws: BridgeMessageError.missingField("tabs")) { try decode(#"{"v":1,"type":"tabs","browser":"chrome","tabs":3}"#) }
        #expect(throws: BridgeMessageError.unknownCommand("explode")) { try decode(#"{"v":1,"type":"command","id":"a","command":"explode","tabId":"1"}"#) }
        #expect(throws: (any Error).self) { try decode("not json") }
        #expect(throws: (any Error).self) { try decode("[1,2]") }
        #expect(throws: (any Error).self) { try decode("") }
    }
}

@Suite struct NativeMessageFramingTests {
    private func frame(_ s: String) throws -> Data { try NativeMessageFraming.encode(Data(s.utf8)) }

    @Test func encodesLittleEndianLength() throws {
        #expect(Array(try frame("{}")) == [2, 0, 0, 0, 0x7B, 0x7D])
    }

    @Test func decodesMultipleFramesInOneRead() throws {
        var d = NativeMessageFrameDecoder()
        let out = try d.feed(try frame("a") + frame("bb") + frame("ccc"))
        #expect(out.map { String(decoding: $0, as: UTF8.self) } == ["a", "bb", "ccc"])
    }

    @Test func toleratesByteAtATimeReads() throws {
        var d = NativeMessageFrameDecoder()
        var out: [Data] = []
        for byte in try frame("hello") + frame("x") { out += try d.feed(Data([byte])) }
        #expect(out.map { String(decoding: $0, as: UTF8.self) } == ["hello", "x"])
    }

    @Test func emptyFrameIsDelivered() throws {
        var d = NativeMessageFrameDecoder()
        #expect(try d.feed(Data([0, 0, 0, 0])) == [Data()])
    }

    @Test func oversizeFailsCleanlyAndStaysFailed() throws {
        var d = NativeMessageFrameDecoder()
        let len = UInt32(NativeMessageFraming.maxFrameBytes + 1)
        let header = Data([UInt8(len & 0xFF), UInt8(len >> 8 & 0xFF), UInt8(len >> 16 & 0xFF), UInt8(len >> 24)])
        #expect(throws: FramingError.oversize(length: Int(len))) { try d.feed(header) }
        #expect(throws: FramingError.failed) { try d.feed(Data([1])) }
        // A hostile 4 GiB length is rejected from the header alone, nothing is buffered.
        var e = NativeMessageFrameDecoder()
        #expect(throws: FramingError.self) { try e.feed(Data([0xFF, 0xFF, 0xFF, 0xFF])) }
    }

    @Test func maxSizeFrameIsAccepted() throws {
        var d = NativeMessageFrameDecoder()
        let out = try d.feed(try NativeMessageFraming.encode(Data(count: NativeMessageFraming.maxFrameBytes)))
        #expect(out.first?.count == NativeMessageFraming.maxFrameBytes)
        #expect(throws: FramingError.self) { try NativeMessageFraming.encode(Data(count: NativeMessageFraming.maxFrameBytes + 1)) }
    }
}
