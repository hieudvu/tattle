import Darwin
import Foundation

public enum UnixSocketError: Error, Equatable, Sendable {
    case syscall(String, errno: Int32)
    case alreadyRunning(String)
    case notASocket(String)
}

/// Thin POSIX glue shared by the app's server and the bridge's client.
public enum UnixSocket {
    static func address(_ path: String) -> sockaddr_un {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            let bytes = Array(path.utf8.prefix(raw.count - 1))
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        return addr
    }

    private static func call(_ name: String, _ result: Int32) throws -> Int32 {
        if result < 0 { throw UnixSocketError.syscall(name, errno: errno) }
        return result
    }

    private static func makeSocket() throws -> Int32 {
        let fd = try call("socket", socket(AF_UNIX, SOCK_STREAM, 0))
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        return fd
    }

    public static func connect(path: String) throws -> Int32 {
        let fd = try makeSocket()
        var addr = address(path)
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        if rc < 0 {
            let e = errno
            close(fd)
            throw UnixSocketError.syscall("connect", errno: e)
        }
        return fd
    }

    /// Binds a 0600 listening socket. A leftover socket file nobody answers on is
    /// removed; one that answers means another instance owns it; anything that is
    /// not a socket is never touched.
    public static func listen(path: String) throws -> Int32 {
        var st = stat()
        if lstat(path, &st) == 0 {
            guard (st.st_mode & S_IFMT) == S_IFSOCK else { throw UnixSocketError.notASocket(path) }
            if let probe = try? connect(path: path) {
                close(probe)
                throw UnixSocketError.alreadyRunning(path)
            }
            unlink(path)
        }
        let fd = try makeSocket()
        var addr = address(path)
        let old = umask(0o177)
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        let bindErrno = errno
        umask(old)
        if rc < 0 { close(fd); throw UnixSocketError.syscall("bind", errno: bindErrno) }
        chmod(path, 0o600)
        if Darwin.listen(fd, 16) < 0 {
            let e = errno
            close(fd); unlink(path)
            throw UnixSocketError.syscall("listen", errno: e)
        }
        return fd
    }

    /// Waits up to `timeoutMS` for the fd to become readable (or hang up).
    public static func waitReadable(_ fd: Int32, timeoutMS: Int32) -> Bool {
        var p = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        return poll(&p, 1, timeoutMS) > 0
    }

    public static func writeAll(_ fd: Int32, _ data: Data) throws {
        try data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let n = write(fd, raw.baseAddress! + offset, raw.count - offset)
                if n < 0 {
                    if errno == EINTR { continue }
                    throw UnixSocketError.syscall("write", errno: errno)
                }
                offset += n
            }
        }
    }

    /// One read; empty Data means EOF or error.
    public static func read(_ fd: Int32, max: Int = 65536) -> Data {
        var buf = [UInt8](repeating: 0, count: max)
        while true {
            let n = Darwin.read(fd, &buf, max)
            if n < 0 && errno == EINTR { continue }
            return n > 0 ? Data(buf[0..<n]) : Data()
        }
    }
}
