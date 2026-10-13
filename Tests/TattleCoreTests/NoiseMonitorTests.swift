import Testing
import TattleCore

@Suite struct NoiseMonitorTests {
    @Test func nothingPlayingYieldsNothing() throws {
        let monitor = NoiseMonitor(audio: FakeAudio(), inspector: FakeInspector([]))
        #expect(try monitor.scan().isEmpty)
    }

    @Test func helperAudioCollapsesIntoOwningApp() throws {
        let chrome = Fixture.proc(100, name: "Google Chrome", path: Fixture.chromePath)
        let helperA = Fixture.proc(101, parent: 100, name: "Google Chrome Helper", path: Fixture.chromeHelperPath)
        let helperB = Fixture.proc(102, parent: 100, name: "Google Chrome Helper", path: Fixture.chromeHelperPath)
        let monitor = NoiseMonitor(
            audio: FakeAudio(pids: [102, 101]),
            inspector: FakeInspector([chrome, helperA, helperB])
        )
        let result = try monitor.scan()
        #expect(result.count == 1)
        #expect(result[0].ownerPID == 100)
        #expect(result[0].name == "Google Chrome")
        #expect(result[0].audioPIDs == [101, 102])
        #expect(result[0].isHeadless == false)
    }

    @Test func webKitXPCServiceIsAttributedToResponsibleApp() throws {
        let safariPath = "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app/Contents/MacOS/Safari"
        let gpuPath = "/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.GPU.xpc/Contents/MacOS/com.apple.WebKit.GPU"
        let safari = Fixture.proc(300, name: "Safari", path: safariPath)
        var gpu = Fixture.proc(301, name: "com.apple.WebKit.GPU", path: gpuPath)
        gpu.responsiblePID = 300
        let result = try NoiseMonitor(audio: FakeAudio(pids: [301]), inspector: FakeInspector([safari, gpu])).scan()
        #expect(result.map(\.ownerPID) == [300])
        #expect(result[0].name == "Safari")
        #expect(result[0].audioPIDs == [301])
    }

    @Test func responsibleAppIsIgnoredForNonServiceProcesses() throws {
        let terminal = Fixture.proc(10, name: "Terminal", path: "/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal")
        var player = Fixture.proc(11, parent: 10, name: "afplay", path: "/usr/bin/afplay")
        player.responsiblePID = 10
        let result = try NoiseMonitor(audio: FakeAudio(pids: [11]), inspector: FakeInspector([terminal, player])).scan()
        #expect(result.map(\.ownerPID) == [11])  // a command-line tool is never blamed on its terminal
    }

    @Test func headlessChromeIsFlagged() throws {
        let args = [Fixture.chromePath, "--headless=new", "--user-data-dir=/tmp/test"]
        let chrome = Fixture.proc(200, parent: 50, name: "Google Chrome", path: Fixture.chromePath, args: args)
        let helper = Fixture.proc(201, parent: 200, name: "Google Chrome Helper", path: Fixture.chromeHelperPath)
        let node = Fixture.proc(50, name: "node", path: "/usr/local/bin/node")
        let monitor = NoiseMonitor(audio: FakeAudio(pids: [201]), inspector: FakeInspector([chrome, helper, node]))
        let result = try monitor.scan()
        #expect(result.map(\.ownerPID) == [200])  // climbs to chrome, not on to the node that launched it
        #expect(result[0].isHeadless)
        #expect(result[0].commandLine.contains("--user-data-dir=/tmp/test"))
    }

    @Test func processOutsideAnyBundleIsItsOwnOwner() throws {
        let shell = Fixture.proc(10, name: "zsh", path: "/bin/zsh")
        let player = Fixture.proc(11, parent: 10, name: "afplay", path: "/usr/bin/afplay")
        let monitor = NoiseMonitor(audio: FakeAudio(pids: [11]), inspector: FakeInspector([shell, player]))
        let result = try monitor.scan()
        #expect(result.map(\.ownerPID) == [11])
        #expect(result[0].name == "afplay")
    }

    @Test func unrelatedAppsStaySeparateAndSortedByName() throws {
        let spotify = Fixture.proc(30, name: "Spotify", path: "/Applications/Spotify.app/Contents/MacOS/Spotify")
        let chrome = Fixture.proc(20, name: "Google Chrome", path: Fixture.chromePath)
        let monitor = NoiseMonitor(audio: FakeAudio(pids: [30, 20]), inspector: FakeInspector([spotify, chrome]))
        #expect(try monitor.scan().map(\.name) == ["Google Chrome", "Spotify"])
    }

    @Test func processThatExitedBetweenReadsIsSkipped() throws {
        let monitor = NoiseMonitor(audio: FakeAudio(pids: [999]), inspector: FakeInspector([]))
        #expect(try monitor.scan().isEmpty)
    }

    @Test func parentCycleTerminates() throws {
        let a = Fixture.proc(1000, parent: 1001, name: "Google Chrome", path: Fixture.chromePath)
        let b = Fixture.proc(1001, parent: 1000, name: "Google Chrome Helper", path: Fixture.chromeHelperPath)
        let monitor = NoiseMonitor(audio: FakeAudio(pids: [1001]), inspector: FakeInspector([a, b]))
        #expect(try monitor.scan().count == 1)
    }

    @Test func audioSourceFailurePropagates() {
        struct Boom: Error {}
        let monitor = NoiseMonitor(audio: FakeAudio(error: Boom()), inspector: FakeInspector([]))
        #expect(throws: Boom.self) { try monitor.scan() }
    }
}

@Suite struct OwnProcessTests {
    @Test func tattleNeverListsItself() throws {
        let me = Fixture.proc(500, name: "Tattle Dev", path: "/x/Tattle Dev.app/Contents/MacOS/Tattle Dev")
        let chrome = Fixture.proc(20, name: "Google Chrome", path: Fixture.chromePath)
        let monitor = NoiseMonitor(audio: FakeAudio(pids: [500, 20]), inspector: FakeInspector([me, chrome]), ownPID: 500)
        #expect(try monitor.scan().map(\.name) == ["Google Chrome"])
    }

    @Test func bundlePathIsExposedForIcons() throws {
        let chrome = Fixture.proc(20, name: "Google Chrome", path: Fixture.chromePath)
        let monitor = NoiseMonitor(audio: FakeAudio(pids: [20]), inspector: FakeInspector([chrome]))
        #expect(try monitor.scan()[0].bundlePath == "/Applications/Google Chrome.app")
    }
}
