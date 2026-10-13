import Testing
import TattleCore

@Suite struct TabStoreTests {
    private func tab(_ b: Browser, _ id: String, _ title: String = "t", audible: Bool = true, muted: Bool = false) -> TabInfo {
        TabInfo(browser: b, tabID: id, title: title, url: "https://x", isAudible: audible, isMuted: muted)
    }
    private func snap(_ b: Browser, _ tabs: [TabInfo]) -> BridgeMessage { .tabs(browser: b, tabs: tabs, dropped: 0) }

    @Test func helloMarksConnected() {
        var s = TabStore()
        #expect(s.status(of: .chrome) == .notInstalled)
        #expect(s.status(of: .chrome, hostInstalled: true) == .hostInstalled)
        let ch0 = s.apply(.hello(browser: .chrome, extensionVersion: "1"), from: 1)
        #expect(ch0)
        #expect(s.status(of: .chrome, hostInstalled: true) == .connected)
        #expect(s.status(of: .brave) == .notInstalled)
        #expect(s.extensionVersion(of: .chrome) == "1")
    }

    @Test func snapshotReplacesAndFiltersSilentTabs() {
        var s = TabStore()
        s.apply(snap(.chrome, [tab(.chrome, "1:1"), tab(.chrome, "1:2", audible: false)]), from: 1)
        #expect(s.tabs().map(\.tabID) == ["1:1"])
        s.apply(snap(.chrome, [tab(.chrome, "1:3", muted: true)]), from: 1)
        #expect(s.tabs().map(\.tabID) == ["1:3"])
    }

    @Test func duplicateIDsCollapse() {
        var s = TabStore()
        s.apply(snap(.chrome, [tab(.chrome, "1:1", "a"), tab(.chrome, "1:1", "b")]), from: 1)
        #expect(s.tabs().count == 1)
    }

    @Test func disconnectForgetsOnlyThatBrowser() {
        var s = TabStore()
        s.apply(snap(.chrome, [tab(.chrome, "1:1")]), from: 1)
        s.apply(snap(.firefox, [tab(.firefox, "2:2")]), from: 2)
        let ch1 = s.disconnect(1)
        #expect(ch1)
        #expect(s.tabs().map(\.browser) == [.firefox])
        #expect(s.status(of: .chrome, hostInstalled: true) == .hostInstalled)
        let ch2 = s.disconnect(1)
        #expect(!ch2)
    }

    @Test func newerConnectionSupersedesAndOldDisconnectIsHarmless() {
        var s = TabStore()
        s.apply(snap(.chrome, [tab(.chrome, "1:1")]), from: 1)
        s.apply(.hello(browser: .chrome, extensionVersion: "1"), from: 2)
        s.apply(snap(.chrome, [tab(.chrome, "1:9")]), from: 2)
        #expect(s.connection(for: .chrome) == 2)
        let ch3 = s.disconnect(1)
        #expect(!ch3)
        #expect(s.tabs().map(\.tabID) == ["1:9"])
        // The superseded connection can no longer write.
        #expect(s.connection(for: .chrome) == 2)
    }

    @Test func connectionCannotSwitchBrowser() {
        var s = TabStore()
        s.apply(.hello(browser: .chrome, extensionVersion: "1"), from: 1)
        let ch4 = s.apply(snap(.firefox, [tab(.firefox, "1")]), from: 1)
        #expect(!ch4)
        #expect(!s.isConnected(.firefox))
    }

    @Test func tabsFromOtherBrowserAreFiltered() {
        var s = TabStore()
        s.apply(snap(.chrome, [tab(.firefox, "1:1")]), from: 1)
        #expect(s.tabs().isEmpty)
    }

    @Test func stableSort() {
        var s = TabStore()
        s.apply(snap(.firefox, [tab(.firefox, "1", "Zed")]), from: 2)
        s.apply(snap(.chrome, [tab(.chrome, "9", "beta"), tab(.chrome, "2", "Alpha"), tab(.chrome, "1", "beta")]), from: 1)
        #expect(s.tabs().map(\.id) == ["chrome:2", "chrome:1", "chrome:9", "firefox:1"])
    }

    @Test func knowsTabs() {
        var s = TabStore()
        s.apply(snap(.chrome, [tab(.chrome, "1:1")]), from: 1)
        #expect(s.knows(tab(.chrome, "1:1")))
        #expect(!s.knows(tab(.chrome, "1:2")))
        #expect(!s.knows(tab(.brave, "1:1")))
    }

    @Test func resultsAndCommandsDoNotChangeState() {
        var s = TabStore()
        let ch5 = s.apply(.result(id: "a", ok: true, error: nil), from: 1)
        #expect(!ch5)
        let ch6 = s.apply(.command(id: "a", command: .mute, tabID: "1"), from: 1)
        #expect(!ch6)
    }
}
