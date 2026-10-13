public enum QuitError: Error, Equatable, Sendable {
    case refused(pid: Int32)
    case failed(pid: Int32, errno: Int32)
    /// The pid now belongs to a different process than the one that was listed (it exited and the
    /// number was reused), so nothing was signalled.
    case stale(pid: Int32)
}

/// Quits the app that owns the noise. Guards the two pids that must never be
/// signalled: launchd (1) and ourselves. With an `inspector` it also re-reads the process
/// right before signalling and refuses if it is no longer the one that was listed.
public struct Quitter: Sendable {
    private let terminator: any ProcessTerminating
    private let ownPID: Int32
    private let inspector: (any ProcessInspecting)?

    public init(terminator: any ProcessTerminating, ownPID: Int32, inspector: (any ProcessInspecting)? = nil) {
        self.terminator = terminator
        self.ownPID = ownPID
        self.inspector = inspector
    }

    public func quit(_ noisemaker: Noisemaker) throws {
        let pid = noisemaker.ownerPID
        guard pid > 1, pid != ownPID else { throw QuitError.refused(pid: pid) }
        if let inspector {
            guard let current = inspector.snapshot(of: pid),
                  current.arguments.joined(separator: " ") == noisemaker.commandLine,
                  current.bundlePath == noisemaker.bundlePath
            else { throw QuitError.stale(pid: pid) }
        }
        try terminator.terminate(pid: pid)
    }
}
