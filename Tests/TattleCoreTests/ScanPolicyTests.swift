import Testing
import TattleCore

@Suite struct ScanPolicyTests {
    @Test func scansFastWhileTheListIsOnScreen() {
        #expect(ScanPolicy.interval(listVisible: true, menuBarIconShown: false, reaping: false) == 1)
        #expect(ScanPolicy.interval(listVisible: true, menuBarIconShown: true, reaping: true) == 1)
    }

    @Test func scansRelaxedInTheBackgroundOnlyWhenSomethingNeedsIt() {
        #expect(ScanPolicy.interval(listVisible: false, menuBarIconShown: true, reaping: false) == 5)
        #expect(ScanPolicy.interval(listVisible: false, menuBarIconShown: false, reaping: true) == 5)
    }

    @Test func doesNotScanWhenNobodyIsLooking() {
        #expect(ScanPolicy.interval(listVisible: false, menuBarIconShown: false, reaping: false) == nil)
    }
}
