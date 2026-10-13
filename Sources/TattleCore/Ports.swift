/// A point-in-time description of one process, as the OS reports it.
public struct ProcessSnapshot: Equatable, Sendable {
    public var pid: Int32
    public var parentPID: Int32
    public var name: String
    public var executablePath: String
    public var arguments: [String]
    /// The process macOS holds accountable for this one (Activity Monitor's "responsible pid"). An
    /// XPC service such as WebKit's GPU process is parented to launchd, so this is the only link
    /// back to the app that owns it.
    public var responsiblePID: Int32?

    public init(pid: Int32, parentPID: Int32, name: String, executablePath: String, arguments: [String], responsiblePID: Int32? = nil) {
        self.pid = pid
        self.parentPID = parentPID
        self.name = name
        self.executablePath = executablePath
        self.arguments = arguments
        self.responsiblePID = responsiblePID
    }
}

/// Which processes are currently producing audio output.
public protocol AudioActivitySource: Sendable {
    func outputtingPIDs() throws -> [Int32]
}

/// Looks a process up by pid. Returns nil when it has already exited.
public protocol ProcessInspecting: Sendable {
    func snapshot(of pid: Int32) -> ProcessSnapshot?
}

/// Asks a process to exit.
public protocol ProcessTerminating: Sendable {
    func terminate(pid: Int32) throws
}
