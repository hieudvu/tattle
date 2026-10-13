import Darwin
import TattleCore

/// SIGTERM, so the app gets to clean up. No SIGKILL escalation yet.
public struct SignalTerminator: ProcessTerminating {
    public init() {}

    public func terminate(pid: Int32) throws {
        guard kill(pid, SIGTERM) == 0 else { throw QuitError.failed(pid: pid, errno: errno) }
    }
}
