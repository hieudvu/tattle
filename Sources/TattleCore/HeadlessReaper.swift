/// Policy for "auto-quit headless browsers": a headless app that has been making
/// noise continuously for `afterSeconds` is due to be quit. Pure — the caller
/// supplies the clock and does the quitting.
public final class HeadlessReaper {
    /// Re-ask at most this often if a quit did not take (the app ignored SIGTERM).
    public static let retryInterval: Double = 30

    private var firstSeen: [Int32: Double] = [:]
    private var lastAttempt: [Int32: Double] = [:]

    public init() {}

    /// `now` is monotonic seconds. Returns the noisemakers to quit right now.
    public func due(_ current: [Noisemaker], enabled: Bool, afterSeconds: Double, now: Double) -> [Noisemaker] {
        guard enabled else {
            firstSeen.removeAll()
            lastAttempt.removeAll()
            return []
        }
        let headless = current.filter(\.isHeadless)
        let present = Set(headless.map(\.ownerPID))
        firstSeen = firstSeen.filter { present.contains($0.key) }   // went quiet / exited: the clock resets
        lastAttempt = lastAttempt.filter { present.contains($0.key) }

        var result: [Noisemaker] = []
        for noisemaker in headless {
            let since = firstSeen[noisemaker.ownerPID] ?? now
            firstSeen[noisemaker.ownerPID] = since
            guard now - since >= afterSeconds else { continue }
            if let last = lastAttempt[noisemaker.ownerPID], now - last < Self.retryInterval { continue }
            lastAttempt[noisemaker.ownerPID] = now
            result.append(noisemaker)
        }
        return result
    }
}
