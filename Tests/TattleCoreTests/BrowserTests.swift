import Testing
import TattleCore

@Suite struct BrowserTests {
    @Test(arguments: [
        ("Google Chrome", Browser.chrome), ("Google Chrome Canary", .chrome), ("Microsoft Edge", .edge),
        ("Brave Browser", .brave), ("Arc", .arc), ("Firefox", .firefox), ("Firefox Developer Edition", .firefox),
        ("Safari", .safari), ("Safari Technology Preview", .safari),
    ])
    func recognisesBrowsers(name: String, expected: Browser) {
        #expect(Browser(appName: name) == expected)
    }

    @Test func ignoresNonBrowsers() {
        #expect(Browser(appName: "Spotify") == nil)
        #expect(Browser(appName: "Architect") == nil)  // not "Arc"
    }

    @Test func chromiumFamily() {
        #expect(Browser.edge.isChromiumFamily)
        #expect(!Browser.firefox.isChromiumFamily)
        #expect(!Browser.safari.isChromiumFamily)
    }
}
