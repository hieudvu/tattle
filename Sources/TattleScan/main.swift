import Darwin
import TattleCore
import TattleSystem

// Dev aid: one real scan from the terminal, using the same stack as the app.
//   tattle-scan            list who is making noise
//   tattle-scan quit <pid> quit the owner app with that pid (via Quitter's guards)
//   tattle-scan mute <pid> [seconds]  mute the owner for a while (default 8s), then release
let monitor = NoiseMonitor(audio: CoreAudioActivitySource(), inspector: SysctlProcessInspector(), ownPID: getpid())
let args = CommandLine.arguments.dropFirst()

do {
    let noisemakers = try monitor.scan()
    if args.first == "quit", let raw = args.dropFirst().first, let pid = Int32(raw) {
        guard let target = noisemakers.first(where: { $0.ownerPID == pid }) else {
            print("pid \(pid) is not making noise"); exit(1)
        }
        try Quitter(terminator: SignalTerminator(), ownPID: getpid(), inspector: SysctlProcessInspector()).quit(target)
        print("sent SIGTERM to \(target.name) (pid \(pid))")
    } else if args.first == "mute", let raw = args.dropFirst().first, let pid = Int32(raw) {
        guard let target = noisemakers.first(where: { $0.ownerPID == pid }) else {
            print("pid \(pid) is not making noise"); exit(1)
        }
        let seconds = args.dropFirst(2).first.flatMap(UInt32.init) ?? 8
        let controller = MuteController(muter: CoreAudioProcessMuter(), isAlive: { _ in true })
        try controller.toggle(target)
        print("muted \(target.name) (audio \(target.audioPIDs)) for \(seconds)s")
        for second in 1...seconds {
            sleep(1)
            let listed = (try? monitor.scan()) ?? []
            let still = listed.first { $0.ownerPID == pid }.map { "still reports output \($0.audioPIDs)" } ?? "no longer reports output"
            print("  +\(second)s: \(still)")
        }
        controller.unmuteAll()
        print("released")
    } else if noisemakers.isEmpty {
        print("nothing is making noise")
    } else {
        for n in noisemakers {
            print("\(n.name)\tpid \(n.ownerPID)\taudio \(n.audioPIDs)\(n.isHeadless ? "\theadless" : "")")
        }
    }
} catch {
    print("error: \(error)"); exit(1)
}
