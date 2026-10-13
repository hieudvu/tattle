import Darwin
import Foundation

// Thin POSIX glue: an AF_UNIX stream client. Everything with a decision in it lives in SafariRelay.
final class UnixSocketLink: AppLink {
    struct Failure: Error { let call: String; let code: Int32 }

    private var fd: Int32

    private init(fd: Int32) { self.fd = fd }

    deinit { close() }

    static func connect(path: String) throws -> UnixSocketLink {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure(call: "socket", code: errno) }
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            Darwin.close(fd)
            throw Failure(call: "path", code: ENAMETOOLONG)
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if rc < 0 {
            let e = errno
            Darwin.close(fd)
            throw Failure(call: "connect", code: e)
        }
        return UnixSocketLink(fd: fd)
    }

    func write(_ data: Data) throws {
        guard fd >= 0 else { throw Failure(call: "write", code: EBADF) }
        var sent = 0
        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            while sent < raw.count {
                let n = Darwin.write(fd, raw.baseAddress! + sent, raw.count - sent)
                if n < 0 {
                    if errno == EINTR { continue }
                    throw Failure(call: "write", code: errno)
                }
                sent += n
            }
        }
    }

    func read(timeoutMS: Int32) throws -> Data {
        guard fd >= 0 else { throw Failure(call: "read", code: EBADF) }
        var out = Data()
        var wait = timeoutMS
        while true {
            var p = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&p, 1, wait)
            if ready < 0 {
                if errno == EINTR { continue }
                throw Failure(call: "poll", code: errno)
            }
            if ready == 0 { return out }
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            let n = Darwin.read(fd, &buffer, buffer.count)
            if n < 0 {
                if errno == EINTR { continue }
                throw Failure(call: "read", code: errno)
            }
            if n == 0 { throw Failure(call: "read", code: 0) }  // EOF: the app quit
            out.append(contentsOf: buffer[0..<n])
            wait = 0  // drain what is already there, then return
        }
    }

    func close() {
        if fd >= 0 { Darwin.close(fd) }
        fd = -1
    }
}
