import Testing
import TattleCore

final class FakeMuter: ProcessMuting, @unchecked Sendable {
    private(set) var calls: [String] = []
    var failNextMute = false
    struct Refused: Error {}

    func mute(ownerPID: Int32, audioPIDs: [Int32]) throws {
        if failNextMute { failNextMute = false; throw Refused() }
        calls.append("mute \(ownerPID) \(audioPIDs)")
    }
    func unmute(ownerPID: Int32) { calls.append("unmute \(ownerPID)") }
}

@Suite struct MuteControllerTests {
    private func noisemaker(owner: Int32, audio: [Int32], name: String = "Google Chrome") -> Noisemaker {
        let proc = Fixture.proc(owner, name: name, path: "/Applications/\(name).app/Contents/MacOS/\(name)")
        let helpers = audio.filter { $0 != owner }.map {
            Fixture.proc($0, parent: owner, name: "\(name) Helper", path: "/Applications/\(name).app/Contents/Helpers/h")
        }
        return try! NoiseMonitor(audio: FakeAudio(pids: audio), inspector: FakeInspector([proc] + helpers)).scan()[0]
    }

    @Test func toggleMutesThenUnmutes() throws {
        let muter = FakeMuter()
        let controller = MuteController(muter: muter, isAlive: { _ in true })
        let chrome = noisemaker(owner: 10, audio: [11, 12])
        try controller.toggle(chrome)
        #expect(controller.isMuted(chrome))
        try controller.toggle(chrome)
        #expect(!controller.isMuted(chrome))
        #expect(muter.calls == ["mute 10 [11, 12]", "unmute 10"])
    }

    @Test func failedMuteLeavesAppUnmuted() {
        let muter = FakeMuter()
        muter.failNextMute = true
        let controller = MuteController(muter: muter, isAlive: { _ in true })
        let chrome = noisemaker(owner: 10, audio: [11])
        #expect(throws: FakeMuter.Refused.self) { try controller.toggle(chrome) }
        #expect(!controller.isMuted(chrome))
    }

    @Test func newHelperTriggersRetapWithTheFullSet() throws {
        let muter = FakeMuter()
        let controller = MuteController(muter: muter, isAlive: { _ in true })
        try controller.toggle(noisemaker(owner: 10, audio: [11]))
        _ = controller.reconcile([noisemaker(owner: 10, audio: [11, 13])])
        #expect(muter.calls == ["mute 10 [11]", "mute 10 [11, 13]"])
    }

    @Test func unchangedAudioDoesNotRetap() throws {
        let muter = FakeMuter()
        let controller = MuteController(muter: muter, isAlive: { _ in true })
        let chrome = noisemaker(owner: 10, audio: [11])
        try controller.toggle(chrome)
        _ = controller.reconcile([chrome])
        #expect(muter.calls == ["mute 10 [11]"])
    }

    @Test func silentButAliveAppStaysListedAndMuted() throws {
        let muter = FakeMuter()
        let controller = MuteController(muter: muter, isAlive: { _ in true })
        let chrome = noisemaker(owner: 10, audio: [11])
        try controller.toggle(chrome)
        let listed = controller.reconcile([])  // muting silenced it, so the scan no longer sees it
        #expect(listed.map(\.ownerPID) == [10])
        #expect(controller.isMuted(chrome))
    }

    @Test func deadAppIsUnmutedAndForgotten() throws {
        let muter = FakeMuter()
        let controller = MuteController(muter: muter, isAlive: { _ in false })
        try controller.toggle(noisemaker(owner: 10, audio: [11]))
        #expect(controller.reconcile([]).isEmpty)
        #expect(muter.calls == ["mute 10 [11]", "unmute 10"])
        #expect(controller.muted.isEmpty)
    }

    @Test func failedRetapDropsTheMuteInsteadOfLeavingAStaleTap() throws {
        let muter = FakeMuter()
        let controller = MuteController(muter: muter, isAlive: { _ in true })
        try controller.toggle(noisemaker(owner: 10, audio: [11]))
        muter.failNextMute = true
        _ = controller.reconcile([noisemaker(owner: 10, audio: [11, 13])])
        #expect(controller.muted.isEmpty)
        #expect(muter.calls.last == "unmute 10")
    }

    @Test func unmuteAllReleasesEverything() throws {
        let muter = FakeMuter()
        let controller = MuteController(muter: muter, isAlive: { _ in true })
        try controller.toggle(noisemaker(owner: 10, audio: [11]))
        try controller.toggle(noisemaker(owner: 20, audio: [21], name: "Spotify"))
        controller.unmuteAll()
        #expect(controller.muted.isEmpty)
        #expect(Set(muter.calls.suffix(2)) == ["unmute 10", "unmute 20"])
    }
}
