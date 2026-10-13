import TattleCore

struct FakeAudio: AudioActivitySource {
    var pids: [Int32] = []
    var error: (any Error)?
    func outputtingPIDs() throws -> [Int32] {
        if let error { throw error }
        return pids
    }
}

struct FakeInspector: ProcessInspecting {
    var table: [Int32: ProcessSnapshot] = [:]
    init(_ snapshots: [ProcessSnapshot]) { table = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.pid, $0) }) }
    func snapshot(of pid: Int32) -> ProcessSnapshot? { table[pid] }
}

final class FakeTerminator: ProcessTerminating, @unchecked Sendable {
    private(set) var terminated: [Int32] = []
    var failWith: (any Error)?
    func terminate(pid: Int32) throws {
        if let failWith { throw failWith }
        terminated.append(pid)
    }
}

enum Fixture {
    static let chromePath = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    static let chromeHelperPath =
        "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/1/Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper"

    static func proc(_ pid: Int32, parent: Int32 = 1, name: String, path: String, args: [String] = []) -> ProcessSnapshot {
        ProcessSnapshot(pid: pid, parentPID: parent, name: name, executablePath: path, arguments: args.isEmpty ? [path] : args)
    }
}
