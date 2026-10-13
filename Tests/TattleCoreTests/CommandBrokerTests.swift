import Foundation
import Testing
import TattleCore

private struct Routing: CommandRouting {
    var connections: [Browser: ConnectionID] = [.chrome: 7]
    var tabs: Set<String> = ["chrome:1:1"]
    func connection(for browser: Browser) -> ConnectionID? { connections[browser] }
    func knows(tab: TabInfo) -> Bool { tabs.contains(tab.id) }
}

private final class Transport: CommandTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _sent: [(BridgeMessage, ConnectionID)] = []
    var onSend: (@Sendable (BridgeMessage, ConnectionID) -> Void)?
    var failWith: (any Error)?
    var sent: [(BridgeMessage, ConnectionID)] { lock.withLock { _sent } }
    func send(_ message: BridgeMessage, to connection: ConnectionID) throws {
        if let failWith { throw failWith }
        lock.withLock { _sent.append((message, connection)) }
        onSend?(message, connection)
    }
}

private struct InstantSleeper: Sleeper { func sleep(for duration: Duration) async throws {} }
/// Sleeps until cancelled, so a timeout can never fire in a test that expects a result.
private struct ForeverSleeper: Sleeper {
    func sleep(for duration: Duration) async throws { try await Task.sleep(for: .seconds(3600)) }
}

private let chromeTab = TabInfo(browser: .chrome, tabID: "1:1", title: "t", url: "u", isAudible: true, isMuted: false)

@Suite struct CommandBrokerTests {
    private func make(_ transport: Transport, sleeper: any Sleeper = ForeverSleeper(), routing: Routing = Routing()) -> CommandBroker {
        CommandBroker(routing: routing, transport: transport, sleeper: sleeper, makeID: { "id1" })
    }

    @Test func sendsCommandAndCompletesOnMatchingResult() async throws {
        let transport = Transport()
        let broker = make(transport)
        transport.onSend = { _, conn in Task { await broker.receive(id: "id1", ok: true, error: nil, from: conn) } }
        try await broker.send(.mute, to: chromeTab)
        #expect(transport.sent.count == 1)
        #expect(transport.sent[0].0 == .command(id: "id1", command: .mute, tabID: "1:1"))
        #expect(transport.sent[0].1 == 7)
    }

    @Test func rejectedResultThrows() async {
        let transport = Transport()
        let broker = make(transport)
        transport.onSend = { _, conn in Task { await broker.receive(id: "id1", ok: false, error: "tab not found", from: conn) } }
        await #expect(throws: CommandError.rejected("tab not found")) { try await broker.send(.close, to: chromeTab) }
    }

    @Test func timesOut() async {
        let broker = make(Transport(), sleeper: InstantSleeper())
        await #expect(throws: CommandError.timedOut) { try await broker.send(.pause, to: chromeTab) }
    }

    @Test func unknownBrowserAndTab() async {
        let transport = Transport()
        let broker = make(transport)
        let brave = TabInfo(browser: .brave, tabID: "1:1", title: "", url: "", isAudible: true, isMuted: false)
        await #expect(throws: CommandError.browserNotConnected(.brave)) { try await broker.send(.mute, to: brave) }
        let ghost = TabInfo(browser: .chrome, tabID: "9:9", title: "", url: "", isAudible: true, isMuted: false)
        await #expect(throws: CommandError.tabNotFound("9:9")) { try await broker.send(.mute, to: ghost) }
        #expect(transport.sent.isEmpty)
    }

    @Test func transportFailureSurfaces() async {
        struct Boom: Error {}
        let transport = Transport()
        transport.failWith = Boom()
        let broker = make(transport)
        await #expect(throws: CommandError.self) { try await broker.send(.mute, to: chromeTab) }
    }

    @Test func lateAndDuplicateResultsAreIgnored() async throws {
        let transport = Transport()
        let broker = make(transport)
        transport.onSend = { _, conn in
            Task {
                await broker.receive(id: "id1", ok: true, error: nil, from: conn)
                await broker.receive(id: "id1", ok: false, error: "dup", from: conn)
            }
        }
        try await broker.send(.mute, to: chromeTab)
        await broker.receive(id: "id1", ok: false, error: "late", from: 7)
        await broker.receive(id: "never-sent", ok: true, error: nil, from: 7)
    }

    @Test func resultFromAnotherConnectionIsIgnored() async {
        let transport = Transport()
        let broker = make(transport, sleeper: InstantSleeper())
        transport.onSend = { _, _ in Task { await broker.receive(id: "id1", ok: true, error: nil, from: 99) } }
        await #expect(throws: CommandError.timedOut) { try await broker.send(.mute, to: chromeTab) }
    }

    @Test func connectionLossFailsPending() async {
        let transport = Transport()
        let broker = make(transport)
        transport.onSend = { _, conn in Task { await broker.connectionLost(conn) } }
        await #expect(throws: CommandError.connectionLost) { try await broker.send(.mute, to: chromeTab) }
    }
}
