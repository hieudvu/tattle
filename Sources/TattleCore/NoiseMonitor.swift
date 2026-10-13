public struct NoiseMonitor: Sendable {
    private let audio: any AudioActivitySource
    private let inspector: any ProcessInspecting
    private let ownPID: Int32?

    /// `ownPID` is skipped: Tattle's own mute taps make it a "process running
    /// output", and listing ourselves as a noisemaker is wrong.
    public init(audio: any AudioActivitySource, inspector: any ProcessInspecting, ownPID: Int32? = nil) {
        self.audio = audio
        self.inspector = inspector
        self.ownPID = ownPID
    }

    public func scan() throws -> [Noisemaker] {
        var groups: [Int32: (owner: ProcessSnapshot, audioPIDs: [Int32])] = [:]
        for pid in try audio.outputtingPIDs() {
            guard let owner = owner(of: pid) else { continue }  // exited between the two reads
            guard owner.pid != ownPID else { continue }
            groups[owner.pid, default: (owner, [])].audioPIDs.append(pid)
        }
        return groups.values
            .map { group in
                Noisemaker(
                    ownerPID: group.owner.pid,
                    name: group.owner.displayName,
                    bundlePath: group.owner.bundlePath,
                    audioPIDs: group.audioPIDs.sorted(),
                    isHeadless: group.owner.isHeadless,
                    commandLine: group.owner.arguments.joined(separator: " ")
                )
            }
            .sorted { ($0.name, $0.ownerPID) < ($1.name, $1.ownerPID) }
    }

    /// Climbs from an audio process to the top process of the same `.app`
    /// bundle. A process outside any bundle is its own owner, so a bare `node`
    /// is never mistaken for its shell.
    private func owner(of pid: Int32) -> ProcessSnapshot? {
        guard var current = inspector.snapshot(of: pid) else { return nil }
        // WebKit's GPU/WebContent services sit outside any .app and under launchd, so neither the
        // bundle nor the parent chain leads to Safari. Ask who is responsible for them instead:
        // but only for XPC services, so a bare `node` is still never blamed on its terminal.
        if current.bundlePath == nil, current.isXPCService,
           let responsible = current.responsiblePID, responsible != current.pid,
           let host = inspector.snapshot(of: responsible), host.bundlePath != nil {
            current = host
        }
        guard let bundle = current.bundlePath else { return current }
        var seen: Set<Int32> = [current.pid]
        while current.parentPID > 1,
              !seen.contains(current.parentPID),
              let parent = inspector.snapshot(of: current.parentPID),
              parent.bundlePath == bundle {
            seen.insert(parent.pid)
            current = parent
        }
        return current
    }
}
