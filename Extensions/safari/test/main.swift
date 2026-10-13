import Darwin
import Foundation

// Standalone checks for SafariRelay + UnixSocketLink (run: test/run-tests.sh). No Safari and no
// Tattle app: a fake link, plus a real AF_UNIX socket in a private temp directory.

var failures = 0
@MainActor func check(_ ok: Bool, _ name: String, line: Int = #line) {
    if ok { print("ok   \(name)") } else { failures += 1; print("FAIL \(name) (line \(line))") }
}

final class FakeLink: AppLink {
    var written: [Data] = []
    var inbound = Data()
    var failWrite = false
    var failRead = false
    var closed = false
    func write(_ data: Data) throws { if failWrite { throw NSError(domain: "t", code: 1) }; written.append(data) }
    func read(timeoutMS: Int32) throws -> Data {
        if failRead { throw NSError(domain: "t", code: 2) }
        defer { inbound = Data() }
        return inbound
    }
    func close() { closed = true }
}

func frame(_ obj: [String: Any]) -> Data {
    RelayFraming.encode(try! JSONSerialization.data(withJSONObject: obj))!
}
func decodeWritten(_ data: Data) -> [String: Any] {
    var d = RelayFraming.Decoder()
    let f = try! d.feed(data)
    return try! JSONSerialization.jsonObject(with: f[0]) as! [String: Any]
}

// framing
do {
    let payload = Data("{\"a\":1}".utf8)
    let enc = RelayFraming.encode(payload)!
    check(Array(enc.prefix(4)) == [7, 0, 0, 0], "frame header is 4-byte little endian")
    var d = RelayFraming.Decoder()
    let a = try! d.feed(enc.prefix(3)); let b = try! d.feed(enc.dropFirst(3) + enc)
    check(a.isEmpty && b.count == 2 && b[0] == payload, "decoder reassembles split + coalesced frames")
    var big = RelayFraming.Decoder()
    var oversize = Data([0xff, 0xff, 0xff, 0x7f])
    oversize.append(0)
    check((try? big.feed(oversize)) == nil, "oversize length is rejected")
    check(RelayFraming.encode(Data(count: RelayFraming.maxFrameBytes + 1)) == nil, "oversize payload is not encoded")
}

// socket path / flavour isolation
check(AppFlavour.dev.socketPath(home: "/Users/u") == "/Users/u/Library/Application Support/Tattle Dev/bridge.sock", "dev socket path")
check(AppFlavour.pro.socketPath(home: "/Users/u") == "/Users/u/Library/Application Support/Tattle/bridge.sock", "pro socket path")
check(AppFlavour.dev.socketPath(home: "/h") != AppFlavour.pro.socketPath(home: "/h"), "dev and pro never share a socket")

// relay
do {
    let link = FakeLink()
    var connects = 0
    let relay = SafariRelay(connect: { connects += 1; return link })

    let hello = relay.handle(["v": 1, "type": "hello", "browser": "safari", "extensionVersion": "0.1.0"])
    check(hello["ok"] as? Bool == true && (hello["messages"] as? [Any])?.isEmpty == true, "hello -> ok, no messages")
    check(link.written.count == 1 && decodeWritten(link.written[0])["type"] as? String == "hello", "hello forwarded as one frame")

    link.inbound = frame(["v": 1, "type": "command", "id": "c1", "command": "mute", "tabId": "1:2"])
        + frame(["v": 1, "type": "command", "id": "c2", "command": "close", "tabId": "1:3"])
    let poll = relay.handle(["v": 1, "type": "poll", "browser": "safari"])
    let msgs = poll["messages"] as? [[String: Any]] ?? []
    check(msgs.map { $0["id"] as? String } == ["c1", "c2"], "poll returns queued commands in order")
    check(link.written.count == 1, "poll writes nothing to the app")
    check((relay.handle(["v": 1, "type": "poll"])["messages"] as? [Any])?.isEmpty == true, "commands are delivered once")
    check(connects == 1, "one connection is reused")

    link.inbound = frame(["v": 1, "type": "command", "id": "c3", "command": "mute", "tabId": "1:2"])
    let res = relay.handle(["v": 1, "type": "result", "id": "c1", "ok": true])
    check((res["messages"] as? [Any])?.count == 1 && link.written.count == 2, "any request piggybacks pending commands")

    let before = link.written.count
    _ = relay.handle(["v": 1, "type": "bogus"])
    check(link.written.count == before, "unknown types are not forwarded")
    check(relay.handle(["type": "hello"])["ok"] as? Bool == false, "missing v is rejected")
    check(relay.handle(nil)["ok"] as? Bool == false, "nil message is rejected")

    _ = relay.handle(["v": 1, "type": "bye"])
    check(link.closed, "bye closes the link")
    _ = relay.handle(["v": 1, "type": "poll"])
    check(connects == 2, "next request reconnects")
}
do {
    let relay = SafariRelay(connect: { throw NSError(domain: "t", code: 3) })
    let r = relay.handle(["v": 1, "type": "hello"])
    check(r["ok"] as? Bool == false && r["error"] as? String == "tattle-not-running", "app down -> tattle-not-running")
}
do {
    let link = FakeLink()
    var connects = 0
    let relay = SafariRelay(connect: { connects += 1; return link })
    link.failWrite = true
    let r = relay.handle(["v": 1, "type": "tabs", "browser": "safari", "tabs": [Any]()])
    check(r["error"] as? String == "tattle-connection-lost" && link.closed, "write failure drops the link and reports lost")
    link.failWrite = false; link.closed = false
    link.failRead = true
    let r2 = relay.handle(["v": 1, "type": "poll"])
    check(r2["ok"] as? Bool == false && connects == 2, "read failure (app quit) reports lost; link rebuilt on demand")
}

// real socket in a temp dir
do {
    let dir = (NSTemporaryDirectory() as NSString).appendingPathComponent("tattle-safari-\(getpid())")
    try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: dir) }
    let path = dir + "/s.sock"
    let srv = socket(AF_UNIX, SOCK_STREAM, 0)
    var addr = sockaddr_un(); addr.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: Array(path.utf8)); $0[path.utf8.count] = 0 }
    _ = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(srv, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
    listen(srv, 1)

    check((try? UnixSocketLink.connect(path: dir + "/nope.sock")) == nil, "connect to a missing socket throws")
    let link = try! UnixSocketLink.connect(path: path)
    let peer = accept(srv, nil, nil)
    let out = frame(["v": 1, "type": "hello"])
    try! link.write(out)
    var got = [UInt8](repeating: 0, count: 256)
    let n = Darwin.read(peer, &got, got.count)
    check(Data(got[0..<n]) == out, "real socket: bytes written arrive intact")
    check(try! link.read(timeoutMS: 0).isEmpty, "real socket: idle read returns empty immediately")
    let cmd = frame(["v": 1, "type": "command", "id": "z", "command": "focus", "tabId": "1:1"])
    _ = cmd.withUnsafeBytes { Darwin.write(peer, $0.baseAddress, cmd.count) }
    check(try! link.read(timeoutMS: 500) == cmd, "real socket: inbound frame is read")
    Darwin.close(peer)
    check((try? link.read(timeoutMS: 500)) == nil, "real socket: peer EOF throws")
    link.close()
    Darwin.close(srv)
}

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
