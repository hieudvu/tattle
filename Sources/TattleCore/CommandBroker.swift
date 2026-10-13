import Foundation

public enum CommandError: Error, Equatable, Sendable {
    case browserNotConnected(Browser)
    case tabNotFound(String)
    case timedOut
    /// The extension answered `ok:false`.
    case rejected(String)
    case transport(String)
    case connectionLost
}

public protocol CommandRouting: Sendable {
    func connection(for browser: Browser) -> ConnectionID?
    func knows(tab: TabInfo) -> Bool
}

public protocol CommandTransport: Sendable {
    func send(_ message: BridgeMessage, to connection: ConnectionID) throws
}

public protocol Sleeper: Sendable {
    func sleep(for duration: Duration) async throws
}

public struct TaskSleeper: Sleeper {
    public init() {}
    public func sleep(for duration: Duration) async throws { try await Task.sleep(for: duration) }
}

/// Sends a command to the right connection and awaits the `result` carrying its id.
public actor CommandBroker {
    private struct Pending {
        let connection: ConnectionID
        let continuation: CheckedContinuation<Void, any Error>
        var timer: Task<Void, Never>?
    }

    private let routing: any CommandRouting
    private let transport: any CommandTransport
    private let sleeper: any Sleeper
    private let timeout: Duration
    private let makeID: @Sendable () -> String
    private var pending: [String: Pending] = [:]

    public init(
        routing: any CommandRouting,
        transport: any CommandTransport,
        sleeper: any Sleeper = TaskSleeper(),
        timeout: Duration = .seconds(3),
        makeID: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.routing = routing
        self.transport = transport
        self.sleeper = sleeper
        self.timeout = timeout
        self.makeID = makeID
    }

    public func send(_ command: TabCommand, to tab: TabInfo) async throws {
        guard let connection = routing.connection(for: tab.browser) else { throw CommandError.browserNotConnected(tab.browser) }
        guard routing.knows(tab: tab) else { throw CommandError.tabNotFound(tab.tabID) }
        let id = makeID()
        let message = BridgeMessage.command(id: id, command: command, tabID: tab.tabID)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            pending[id] = Pending(connection: connection, continuation: continuation, timer: nil)
            do {
                try transport.send(message, to: connection)
            } catch {
                pending[id] = nil
                continuation.resume(throwing: CommandError.transport(String(describing: error)))
                return
            }
            let sleeper = self.sleeper, timeout = self.timeout
            pending[id]?.timer = Task { [weak self] in
                try? await sleeper.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                await self?.finish(id, with: .failure(CommandError.timedOut))
            }
        }
    }

    /// Feeds a `result` message. Unknown ids (late, duplicate) and results arriving on a
    /// different connection than the command went out on are ignored.
    public func receive(id: String, ok: Bool, error: String?, from connection: ConnectionID) {
        guard pending[id]?.connection == connection else { return }
        finish(id, with: ok ? .success(()) : .failure(CommandError.rejected(error ?? "unknown error")))
    }

    public func connectionLost(_ connection: ConnectionID) {
        for (id, p) in pending where p.connection == connection {
            finish(id, with: .failure(CommandError.connectionLost))
        }
    }

    private func finish(_ id: String, with result: Result<Void, any Error>) {
        guard let p = pending.removeValue(forKey: id) else { return }
        p.timer?.cancel()
        p.continuation.resume(with: result)
    }
}
