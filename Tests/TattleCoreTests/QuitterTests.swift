import Testing
import TattleCore

@Suite struct QuitterTests {
    private func noisemaker(_ pid: Int32) -> Noisemaker {
        let chrome = Fixture.proc(pid, name: "Google Chrome", path: Fixture.chromePath)
        let monitor = NoiseMonitor(audio: FakeAudio(pids: [pid]), inspector: FakeInspector([chrome]))
        return try! monitor.scan()[0]
    }

    @Test func terminatesTheOwnerOnly() throws {
        let terminator = FakeTerminator()
        try Quitter(terminator: terminator, ownPID: 5).quit(noisemaker(400))
        #expect(terminator.terminated == [400])
    }

    @Test func refusesLaunchdAndItself() {
        let terminator = FakeTerminator()
        let quitter = Quitter(terminator: terminator, ownPID: 5)
        #expect(throws: QuitError.refused(pid: 5)) { try quitter.quit(noisemaker(5)) }
        #expect(throws: QuitError.refused(pid: 1)) { try quitter.quit(noisemaker(1)) }
        #expect(terminator.terminated.isEmpty)
    }

    @Test func failureFromTheTerminatorSurfaces() {
        let terminator = FakeTerminator()
        terminator.failWith = QuitError.failed(pid: 400, errno: 1)
        #expect(throws: QuitError.failed(pid: 400, errno: 1)) {
            try Quitter(terminator: terminator, ownPID: 5).quit(noisemaker(400))
        }
    }

    @Test func refusesWhenThePidWasReusedByAnotherProcess() {
        let terminator = FakeTerminator()
        let listed = noisemaker(400)
        let reused = Fixture.proc(400, name: "Mail", path: "/Applications/Mail.app/Contents/MacOS/Mail")
        let quitter = Quitter(terminator: terminator, ownPID: 5, inspector: FakeInspector([reused]))
        #expect(throws: QuitError.stale(pid: 400)) { try quitter.quit(listed) }
        #expect(terminator.terminated.isEmpty)
    }

    @Test func refusesWhenTheProcessIsAlreadyGone() {
        let terminator = FakeTerminator()
        let quitter = Quitter(terminator: terminator, ownPID: 5, inspector: FakeInspector([]))
        #expect(throws: QuitError.stale(pid: 400)) { try quitter.quit(noisemaker(400)) }
    }

    @Test func quitsWhenTheProcessIsStillTheListedOne() throws {
        let terminator = FakeTerminator()
        let chrome = Fixture.proc(400, name: "Google Chrome", path: Fixture.chromePath)
        try Quitter(terminator: terminator, ownPID: 5, inspector: FakeInspector([chrome])).quit(noisemaker(400))
        #expect(terminator.terminated == [400])
    }
}
