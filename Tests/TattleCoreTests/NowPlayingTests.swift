import Testing
import TattleCore

@Suite struct NowPlayingTests {
    @Test func parsesATitleAndArtist() {
        let line = #"{"title":"2 Ngày 1 Đêm Mùa 5","artist":"ĐÔNG TÂY PROMOTION","bundleID":"com.microsoft.edgemac","rate":1}"#
        let info = NowPlayingParser.parse(line: line)
        #expect(info?.title == "2 Ngày 1 Đêm Mùa 5")
        #expect(info?.artist == "ĐÔNG TÂY PROMOTION")
        #expect(info?.isPlaying == true)
        #expect(info?.summary == "2 Ngày 1 Đêm Mùa 5 · ĐÔNG TÂY PROMOTION")
    }

    @Test func pausedMeansRateZero() {
        #expect(NowPlayingParser.parse(line: #"{"title":"x","rate":0}"#)?.isPlaying == false)
    }

    @Test(arguments: ["null", "", "   ", "{}", #"{"title":""}"#, "not json", #"{"artist":"only artist"}"#, #"[1,2]"#])
    func nothingWorthNamingIsNil(line: String) {
        #expect(NowPlayingParser.parse(line: line) == nil)
    }

    @Test func emptyArtistFallsBackToTitleOnly() {
        #expect(NowPlayingParser.parse(line: #"{"title":"Song","artist":""}"#)?.summary == "Song")
    }

    private let edge = Noisemaker(ownerPID: 1, name: "Microsoft Edge", bundlePath: "/Applications/Microsoft Edge.app")
    private let resolve: (String) -> String? = { $0.hasSuffix("Microsoft Edge.app") ? "com.microsoft.edgemac" : nil }

    @Test func matchesByPublisherBundleID() {
        let info = NowPlayingInfo(title: "t", bundleID: "com.microsoft.edgemac")
        #expect(NowPlayingMatcher.info(for: edge, from: info, bundleID: resolve) == info)
    }

    @Test func matchesAHelperThroughItsParentOrPrefix() {
        let viaParent = NowPlayingInfo(title: "t", bundleID: "x.helper", parentBundleID: "com.microsoft.edgemac")
        let viaPrefix = NowPlayingInfo(title: "t", bundleID: "com.microsoft.edgemac.helper.renderer")
        #expect(NowPlayingMatcher.info(for: edge, from: viaParent, bundleID: resolve) != nil)
        #expect(NowPlayingMatcher.info(for: edge, from: viaPrefix, bundleID: resolve) != nil)
    }

    @Test func doesNotMatchOtherAppsOrLookalikePrefixes() {
        let spotify = NowPlayingInfo(title: "t", bundleID: "com.spotify.client")
        let lookalike = NowPlayingInfo(title: "t", bundleID: "com.microsoft.edgemacOS")  // no "." boundary
        #expect(NowPlayingMatcher.info(for: edge, from: spotify, bundleID: resolve) == nil)
        #expect(NowPlayingMatcher.info(for: edge, from: lookalike, bundleID: resolve) == nil)
        #expect(NowPlayingMatcher.info(for: edge, from: nil, bundleID: resolve) == nil)
    }

    @Test func noBundlePathMeansNoMatch() {
        let bare = Noisemaker(ownerPID: 2, name: "afplay")
        #expect(NowPlayingMatcher.info(for: bare, from: NowPlayingInfo(title: "t", bundleID: "x"), bundleID: resolve) == nil)
    }
}
