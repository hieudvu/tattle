// tattle-bridge: the native-messaging host a browser launches. It is a dumb byte
// relay between the browser (stdin/stdout) and the Tattle app (Unix socket); both
// sides speak the same length-prefixed framing, so nothing is parsed here.
//
// If the app is not running we exit at once with a message on stderr instead of
// holding the browser port open. The browser then reports a disconnect and the
// extension's reconnect-with-backoff retries; a zombie port that accepts messages
// and delivers them nowhere would make the extension believe it is connected.
// Likewise EOF on either side ends the process: the app quitting or the browser
// closing the port both mean this connection is over.
import Darwin
import Foundation
import TattleCore
import TattleSystem

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("tattle-bridge: \(message)\n".utf8))
    exit(1)
}

signal(SIGPIPE, SIG_IGN)

let executable = Bundle.main.executablePath ?? CommandLine.arguments[0]
let flavour = AppFlavour(executablePath: executable)
let path: String
do {
    path = try BridgeSocketPath.resolve(
        flavour: flavour, home: FileManager.default.homeDirectoryForCurrentUser,
        environment: ProcessInfo.processInfo.environment).path
} catch {
    fail("cannot resolve socket path: \(error)")
}

let socketFD: Int32
do { socketFD = try UnixSocket.connect(path: path) } catch {
    fail("Tattle is not running (could not connect to \(path)): \(error)")
}

var fds = [
    pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0),
    pollfd(fd: socketFD, events: Int16(POLLIN), revents: 0),
]
while true {
    if poll(&fds, 2, -1) < 0 {
        if errno == EINTR { continue }
        fail("poll failed: errno \(errno)")
    }
    for (index, target) in [(0, socketFD), (1, STDOUT_FILENO)] where fds[index].revents != 0 {
        let chunk = UnixSocket.read(fds[index].fd)
        if chunk.isEmpty { exit(0) }  // EOF either side
        do { try UnixSocket.writeAll(target, chunk) } catch { exit(0) }  // peer went away mid-write
    }
}
