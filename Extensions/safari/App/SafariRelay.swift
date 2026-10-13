import Foundation

// Pure relay logic for the Safari extension handler. No Safari, no sockets: the app link is a
// protocol, so test/ exercises all of it with a fake. Compiled into the appex by
// scripts/build-safari-extension.sh and into test/run-tests.sh.
//
// Wire format to the Tattle app is the one tattle-bridge relays for Chrome/Firefox: a 4-byte
// little-endian length, then UTF-8 JSON (docs/extension-protocol.md). JS <-> handler is one
// request/response per runtime.sendNativeMessage call:
//   request  {v:1,type:"hello"|"tabs"|"result"|"poll"|"bye", ...}
//   response {ok:true, messages:[<commands from Tattle>]}  or  {ok:false, error:"..."}

enum AppFlavour: String {
    case dev, pro

    var supportDirectoryName: String { self == .pro ? "Tattle" : "Tattle Dev" }

    /// Same location TattleCore's BridgeSocketPath resolves, minus the env override (a sandboxed
    /// appex does not inherit the user's environment).
    func socketPath(home: String) -> String {
        "\(home)/Library/Application Support/\(supportDirectoryName)/bridge.sock"
    }
}

enum RelayFraming {
    static let maxFrameBytes = 1 << 20

    static func encode(_ payload: Data) -> Data? {
        guard payload.count <= maxFrameBytes else { return nil }
        var length = UInt32(payload.count).littleEndian
        var out = Data(bytes: &length, count: 4)
        out.append(payload)
        return out
    }

    struct Decoder {
        struct Oversize: Error {}
        private var buffer = Data()

        mutating func feed(_ chunk: Data) throws -> [Data] {
            buffer.append(chunk)
            var frames: [Data] = []
            var offset = buffer.startIndex
            while buffer.endIndex - offset >= 4 {
                let length = (0..<4).reduce(0) { $0 | Int(buffer[offset + $1]) << (8 * $1) }
                if length > RelayFraming.maxFrameBytes { buffer = Data(); throw Oversize() }
                guard buffer.endIndex - offset - 4 >= length else { break }
                frames.append(Data(buffer[(offset + 4)..<(offset + 4 + length)]))
                offset += 4 + length
            }
            buffer = Data(buffer[offset...])
            return frames
        }
    }
}

/// One connection to the Tattle app. `read` waits at most `timeoutMS`; empty Data means "nothing yet".
/// Both throw when the app went away.
protocol AppLink: AnyObject {
    func write(_ data: Data) throws
    func read(timeoutMS: Int32) throws -> Data
    func close()
}

final class SafariRelay: @unchecked Sendable {
    static let notRunning = "tattle-not-running"
    static let lost = "tattle-connection-lost"
    /// Only these go to the app; anything else from the page is dropped.
    static let forwarded: Set<String> = ["hello", "tabs", "result"]
    static let maxPending = 256

    private let connect: () throws -> AppLink
    private let lock = NSLock()
    private var link: AppLink?
    private var decoder = RelayFraming.Decoder()
    private var pending: [Any] = []

    init(connect: @escaping () throws -> AppLink) {
        self.connect = connect
    }

    /// Handles one sendNativeMessage request and returns the response dictionary.
    func handle(_ request: [String: Any]?) -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }

        guard let request, request["v"] as? Int == 1, let type = request["type"] as? String else {
            return ["ok": false, "error": "malformed request"]
        }
        if type == "bye" {
            dropLink()
            return ["ok": true, "messages": [Any]()]
        }
        guard let link = ensureLink() else { return ["ok": false, "error": Self.notRunning] }

        if SafariRelay.forwarded.contains(type) {
            guard
                JSONSerialization.isValidJSONObject(request),
                let json = try? JSONSerialization.data(withJSONObject: request),
                let frame = RelayFraming.encode(json)
            else { return ["ok": false, "error": "request not encodable"] }
            do { try link.write(frame) } catch {
                dropLink()
                return ["ok": false, "error": Self.lost]
            }
        }

        // Pick up whatever Tattle has queued for us; never block the extension on it.
        do {
            for frame in try decoder.feed(try link.read(timeoutMS: 0)) {
                if let object = try? JSONSerialization.jsonObject(with: frame), object is [String: Any] {
                    pending.append(object)
                }
            }
        } catch {
            dropLink()
            return ["ok": false, "error": Self.lost]
        }
        if pending.count > Self.maxPending { pending.removeFirst(pending.count - Self.maxPending) }
        let messages = pending
        pending = []
        return ["ok": true, "messages": messages]
    }

    private func ensureLink() -> AppLink? {
        if let link { return link }
        guard let fresh = try? connect() else { return nil }
        link = fresh
        decoder = RelayFraming.Decoder()
        pending = []
        return fresh
    }

    private func dropLink() {
        link?.close()
        link = nil
        pending = []
    }
}
