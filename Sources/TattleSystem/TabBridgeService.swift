import Darwin
import Foundation
import TattleCore

extension AppFlavour {
    /// Flavour of the bundle this code lives in.
    public static var current: AppFlavour { AppFlavour(bundleIdentifier: Bundle.main.bundleIdentifier) }
}

private final class Connection: @unchecked Sendable {
    let id: ConnectionID
    let fd: Int32
    private let lock = NSLock()
    private var closed = false

    init(id: ConnectionID, fd: Int32) {
        self.id = id
        self.fd = fd
        var timeout = timeval(tv_sec: 2, tv_usec: 0)  // a stuck extension must not wedge the broker
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }

    func write(_ data: Data) throws {
        try lock.withLock {
            guard !closed else { throw UnixSocketError.syscall("write", errno: EBADF) }
            try UnixSocket.writeAll(fd, data)
        }
    }

    func close() {
        lock.withLock {
            guard !closed else { return }
            closed = true
            Darwin.close(fd)
        }
    }
}

/// Shared mutable state behind one lock; also the broker's routing and transport.
private final class BridgeState: CommandRouting, CommandTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var store = TabStore()
    private var connections: [ConnectionID: Connection] = [:]
    private var nextID = 0

    func add(fd: Int32) -> Connection {
        lock.withLock {
            nextID += 1
            let c = Connection(id: nextID, fd: fd)
            connections[c.id] = c
            return c
        }
    }

    func apply(_ message: BridgeMessage, from id: ConnectionID) -> Bool {
        lock.withLock { store.apply(message, from: id) }
    }

    func remove(_ id: ConnectionID) -> Bool {
        lock.withLock {
            connections[id] = nil
            return store.disconnect(id)
        }
    }

    func tabs() -> [TabInfo] { lock.withLock { store.tabs() } }
    func isConnected(_ browser: Browser) -> Bool { lock.withLock { store.isConnected(browser) } }

    func connection(for browser: Browser) -> ConnectionID? { lock.withLock { store.connection(for: browser) } }
    func knows(tab: TabInfo) -> Bool { lock.withLock { store.knows(tab) } }

    func send(_ message: BridgeMessage, to id: ConnectionID) throws {
        guard let c = lock.withLock({ connections[id] }) else { throw CommandError.connectionLost }
        try c.write(try NativeMessageFraming.encode(try message.encoded()))
    }
}

/// The app side of the browser-extension link: a Unix-socket server that the
/// `tattle-bridge` processes (one per connected extension) dial into.
///
///     let bridge = TabBridgeService()          // flavour from the running bundle
///     try bridge.start()
///     Task { for await _ in bridge.changes { model.refreshTabs() } }
///     // pass it as both `TabSource` and `BrowserIntegrations`
///
/// `changes` yields (coalesced, newest-1) whenever tabs or any browser's connection
/// state changed; it is a single-consumer stream.
public final class TabBridgeService: TabSource, BrowserIntegrations, @unchecked Sendable {
    public let changes: AsyncStream<Void>

    private let flavour: AppFlavour
    private let home: URL
    private let environment: [String: String]
    private let hostExecutable: URL
    private let applicationDirectories: [URL]
    private let state = BridgeState()
    private let broker: CommandBroker
    private let continuation: AsyncStream<Void>.Continuation
    private let lifecycle = NSLock()
    private var listenFD: Int32 = -1
    private var socketPath: String?
    private var running = false

    /// - Parameters:
    ///   - flavour: defaults to the running bundle's flavour (dev unless it is exactly the production bundle).
    ///   - hostExecutable: the `tattle-bridge` the manifests point at; defaults to the one next to the app executable.
    ///   - applicationDirectories: where `installedBrowsers()` looks; defaults to /Applications and ~/Applications.
    public init(
        flavour: AppFlavour = .current,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        hostExecutable: URL? = nil,
        applicationDirectories: [URL]? = nil,
        commandTimeout: Duration = .seconds(3)
    ) {
        self.flavour = flavour
        self.home = home
        self.environment = environment
        self.hostExecutable = hostExecutable ?? Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/tattle-bridge")
        self.applicationDirectories = applicationDirectories
            ?? [URL(filePath: "/Applications"), home.appendingPathComponent("Applications", isDirectory: true)]
        (changes, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        broker = CommandBroker(routing: state, transport: state, timeout: commandTimeout)
    }

    deinit { stop() }

    // MARK: Server

    /// Binds the socket and starts accepting. Throws if the path is too long, another
    /// instance owns the socket, or the directory cannot be prepared.
    public func start() throws {
        try lifecycle.withLock {
            guard !running else { return }
            let resolved = try BridgeSocketPath.resolve(flavour: flavour, home: home, environment: environment)
            let dir = (resolved.path as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(
                atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            if !resolved.isOverride { chmod(dir, 0o700) }
            let fd = try UnixSocket.listen(path: resolved.path)
            listenFD = fd
            socketPath = resolved.path
            running = true
            let thread = Thread { [weak self] in self?.acceptLoop(fd) }
            thread.name = "tattle-bridge-accept"
            thread.start()
        }
    }

    public func stop() {
        let path: String? = lifecycle.withLock {
            guard running else { return nil }
            running = false
            return socketPath
        }
        if let path { unlink(path) }  // the accept loop notices `running` and closes the fd
    }

    private var isRunning: Bool { lifecycle.withLock { running } }

    private func acceptLoop(_ listener: Int32) {
        while isRunning {
            guard UnixSocket.waitReadable(listener, timeoutMS: 250) else { continue }
            let fd = accept(listener, nil, nil)
            if fd < 0 { continue }
            var uid: uid_t = 0, gid: gid_t = 0
            guard getpeereid(fd, &uid, &gid) == 0, uid == getuid() else { close(fd); continue }
            var one: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
            let connection = state.add(fd: fd)
            let thread = Thread { [weak self] in self?.readLoop(connection) }
            thread.name = "tattle-bridge-conn-\(connection.id)"
            thread.start()
        }
        close(listener)
    }

    private func readLoop(_ connection: Connection) {
        var decoder = NativeMessageFrameDecoder()
        read: while isRunning {
            guard UnixSocket.waitReadable(connection.fd, timeoutMS: 250) else { continue }
            let chunk = UnixSocket.read(connection.fd)
            if chunk.isEmpty { break }
            let frames: [Data]
            do { frames = try decoder.feed(chunk) } catch { break read }  // oversize: stream is unsynchronised
            for frame in frames {
                guard let message = try? BridgeMessage.decode(frame) else { continue }  // unknown / v2 / malformed: ignore
                handle(message, from: connection.id)
            }
        }
        connection.close()
        let changed = state.remove(connection.id)
        Task { [broker, id = connection.id] in await broker.connectionLost(id) }
        if changed { continuation.yield() }
    }

    private func handle(_ message: BridgeMessage, from id: ConnectionID) {
        switch message {
        case let .result(resultID, ok, error):
            Task { [broker] in await broker.receive(id: resultID, ok: ok, error: error, from: id) }
        case .hello, .tabs:
            if state.apply(message, from: id) { continuation.yield() }
        case .command:
            break  // commands only flow app -> extension
        }
    }

    // MARK: TabSource

    public func tabs() -> [TabInfo] { state.tabs() }

    public func send(_ command: TabCommand, to tab: TabInfo) async throws {
        try await broker.send(command, to: tab)
    }

    // MARK: BrowserIntegrations

    /// Browsers present on this Mac. Safari ships with macOS and has no host to install, but it
    /// is listed so the user can see whether its extension has connected.
    public func installedBrowsers() -> [Browser] {
        Browser.allCases.filter { browser in
            if browser == .safari { return true }
            let name = NativeMessagingManifest.applicationBundleName(for: browser)
            return applicationDirectories.contains {
                FileManager.default.fileExists(atPath: $0.appendingPathComponent(name).path)
            }
        }
    }

    public func status(of browser: Browser) -> IntegrationStatus {
        if state.isConnected(browser) { return .connected }
        if browser == .safari { return .hostInstalled }  // the appex rides inside the app: only enabling is left
        let installed = NativeMessagingManifest.fileURL(for: browser, flavour: flavour, home: home)
            .map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        return installed ? .hostInstalled : .notInstalled
    }

    public func installHost(for browser: Browser) throws {
        guard let file = NativeMessagingManifest.fileURL(for: browser, flavour: flavour, home: home) else {
            throw IntegrationError.unsupportedBrowser(browser)
        }
        guard FileManager.default.isExecutableFile(atPath: hostExecutable.path) else {
            throw IntegrationError.hostExecutableMissing(hostExecutable.path)
        }
        let json = try NativeMessagingManifest.json(for: browser, flavour: flavour, hostPath: hostExecutable.path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try json.write(to: file, options: .atomic)
        continuation.yield()
    }

    public func removeHost(for browser: Browser) throws {
        guard let file = NativeMessagingManifest.fileURL(for: browser, flavour: flavour, home: home) else {
            throw IntegrationError.unsupportedBrowser(browser)
        }
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
        continuation.yield()
    }
}
