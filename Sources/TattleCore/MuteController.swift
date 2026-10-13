/// Silences the audio processes of an app without quitting it.
public protocol ProcessMuting: Sendable {
    /// Replaces any existing mute for `ownerPID`.
    func mute(ownerPID: Int32, audioPIDs: [Int32]) throws
    func unmute(ownerPID: Int32)
}

/// Tracks which apps are muted and keeps the mute honest as the app churns
/// helper processes. A muted app may stop *reporting* output (it is silent now),
/// so it stays listed until the process is really gone.
public final class MuteController {
    private let muter: any ProcessMuting
    private let isAlive: (Int32) -> Bool
    public private(set) var muted: [Int32: Noisemaker] = [:]

    public init(muter: any ProcessMuting, isAlive: @escaping (Int32) -> Bool) {
        self.muter = muter
        self.isAlive = isAlive
    }

    public func isMuted(_ noisemaker: Noisemaker) -> Bool { muted[noisemaker.ownerPID] != nil }

    /// On failure the app stays unmuted.
    public func toggle(_ noisemaker: Noisemaker) throws {
        let owner = noisemaker.ownerPID
        if muted[owner] != nil {
            muter.unmute(ownerPID: owner)
            muted[owner] = nil
        } else {
            try muter.mute(ownerPID: owner, audioPIDs: noisemaker.audioPIDs)
            muted[owner] = noisemaker
        }
    }

    /// Call after every scan. Returns what the UI should list: the scan plus any
    /// muted app that went quiet but is still running.
    public func reconcile(_ current: [Noisemaker]) -> [Noisemaker] {
        for (owner, last) in muted {
            if let now = current.first(where: { $0.ownerPID == owner }) {
                guard now.audioPIDs != last.audioPIDs else { continue }  // a new helper appeared: re-tap
                do {
                    try muter.mute(ownerPID: owner, audioPIDs: now.audioPIDs)
                    muted[owner] = now
                } catch {
                    muter.unmute(ownerPID: owner)
                    muted[owner] = nil
                }
            } else if !isAlive(owner) {
                muter.unmute(ownerPID: owner)
                muted[owner] = nil
            }
        }
        let quietButMuted = muted.values.filter { held in !current.contains { $0.ownerPID == held.ownerPID } }
        return (current + quietButMuted).sorted { ($0.name, $0.ownerPID) < ($1.name, $1.ownerPID) }
    }

    public func unmuteAll() {
        for owner in muted.keys { muter.unmute(ownerPID: owner) }
        muted.removeAll()
    }
}
