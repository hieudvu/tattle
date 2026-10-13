import Testing
import TattleCore

@Suite struct HeadlessReaperTests {
    private let headless = Noisemaker(ownerPID: 10, name: "Google Chrome", isHeadless: true)
    private let normal = Noisemaker(ownerPID: 20, name: "Spotify")

    @Test func notDueBeforeTheThreshold() {
        let reaper = HeadlessReaper()
        #expect(reaper.due([headless], enabled: true, afterSeconds: 600, now: 0).isEmpty)
        #expect(reaper.due([headless], enabled: true, afterSeconds: 600, now: 599).isEmpty)
    }

    @Test func dueOnceTheThresholdPasses() {
        let reaper = HeadlessReaper()
        _ = reaper.due([headless], enabled: true, afterSeconds: 600, now: 0)
        #expect(reaper.due([headless], enabled: true, afterSeconds: 600, now: 600).map(\.ownerPID) == [10])
    }

    @Test func neverTouchesNormalApps() {
        let reaper = HeadlessReaper()
        _ = reaper.due([normal], enabled: true, afterSeconds: 1, now: 0)
        #expect(reaper.due([normal], enabled: true, afterSeconds: 1, now: 10_000).isEmpty)
    }

    @Test func disabledDoesNothingAndForgets() {
        let reaper = HeadlessReaper()
        _ = reaper.due([headless], enabled: true, afterSeconds: 60, now: 0)
        #expect(reaper.due([headless], enabled: false, afterSeconds: 60, now: 1_000).isEmpty)
        // re-enabling starts a fresh clock rather than firing instantly
        #expect(reaper.due([headless], enabled: true, afterSeconds: 60, now: 1_001).isEmpty)
    }

    @Test func goingQuietResetsTheClock() {
        let reaper = HeadlessReaper()
        _ = reaper.due([headless], enabled: true, afterSeconds: 600, now: 0)
        _ = reaper.due([], enabled: true, afterSeconds: 600, now: 400)         // quiet
        #expect(reaper.due([headless], enabled: true, afterSeconds: 600, now: 700).isEmpty)  // back: clock restarted at 700
    }

    @Test func retriesOnlyAfterTheRetryInterval() {
        let reaper = HeadlessReaper()
        _ = reaper.due([headless], enabled: true, afterSeconds: 60, now: 0)
        #expect(reaper.due([headless], enabled: true, afterSeconds: 60, now: 60).count == 1)
        #expect(reaper.due([headless], enabled: true, afterSeconds: 60, now: 70).isEmpty)  // SIGTERM ignored: don't spam
        #expect(reaper.due([headless], enabled: true, afterSeconds: 60, now: 91).count == 1)
    }
}
