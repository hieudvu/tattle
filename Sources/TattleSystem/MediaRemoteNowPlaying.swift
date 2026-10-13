import Foundation
import TattleCore

/// Reads the system Now Playing info (the text macOS's own widget shows) through a
/// small helper dylib run inside Apple's `/usr/bin/perl`. Third-party processes get
/// nothing from MediaRemote since macOS 15.4; an Apple-signed host is still allowed.
/// This is private API, so every failure degrades to "no title" and never throws.
public final class MediaRemoteNowPlaying: NowPlayingSource, @unchecked Sendable {
    private let dylibPath: String
    private let lock = NSLock()
    private var latest: NowPlayingInfo?
    private var process: Process?
    private var commandPipe: Pipe?
    private var stopped = false

    public init(dylibPath: String) { self.dylibPath = dylibPath }

    /// The helper shipped inside the app bundle, or nil when this build lacks it.
    public static func bundled() -> MediaRemoteNowPlaying? {
        guard let path = Bundle.main.resourceURL?.appendingPathComponent("libTattleNowPlaying.dylib").path,
              FileManager.default.fileExists(atPath: path) else { return nil }
        return MediaRemoteNowPlaying(dylibPath: path)
    }

    public func current() -> NowPlayingInfo? {
        lock.lock(); defer { lock.unlock() }
        return latest
    }

    public func start() {
        lock.lock(); stopped = false; lock.unlock()
        Thread.detachNewThread { [weak self] in self?.supervise() }
    }

    /// Forwards a transport command to the helper (which relays it to MediaRemote).
    /// Returns false when the command couldn't even be handed to the helper.
    @discardableResult
    public func send(_ command: NowPlayingCommand) -> Bool {
        lock.lock(); let pipe = commandPipe; lock.unlock()
        guard let handle = pipe?.fileHandleForWriting else { return false }
        return (try? handle.write(contentsOf: Data((command.rawValue + "\n").utf8))) != nil
    }

    public func stop() {
        lock.lock()
        stopped = true
        let p = process
        lock.unlock()
        if p?.isRunning == true { p?.terminate() }
    }

    private static let script = """
    use DynaLoader; $l = DynaLoader::dl_load_file($ARGV[0], 0) or exit 3; \
    $f = DynaLoader::dl_find_symbol($l, "tattle_nowplaying_stream") or exit 4; \
    $x = DynaLoader::dl_install_xsub("main::np", $f); &$x();
    """

    /// Runs the helper; if it exits, retries with backoff (max 60s).
    private func supervise() {
        var delay: TimeInterval = 2
        while true {
            lock.lock(); let done = stopped; lock.unlock()
            if done { return }
            let started = Date()
            run()
            setLatest(nil)
            // A helper that lived a while was healthy: restart quickly. A fast crash backs off.
            delay = Date().timeIntervalSince(started) > 30 ? 2 : min(delay * 2, 60)
            Thread.sleep(forTimeInterval: delay)
        }
    }

    private func run() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = ["-e", Self.script, dylibPath]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        let input = Pipe()
        p.standardInput = input
        lock.lock(); process = p; commandPipe = input; let done = stopped; lock.unlock()
        if done { return }
        do { try p.run() } catch { return }
        var buffer = Data()
        let handle = out.fileHandleForReading
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)
            while let nl = buffer.firstIndex(of: 0x0A) {
                let line = String(decoding: buffer[..<nl], as: UTF8.self)
                buffer.removeSubrange(...nl)
                setLatest(NowPlayingParser.parse(line: line))
            }
        }
        p.waitUntilExit()
        lock.lock(); commandPipe = nil; lock.unlock()
    }

    private func setLatest(_ info: NowPlayingInfo?) {
        lock.lock(); latest = info; lock.unlock()
    }
}
