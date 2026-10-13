import AppKit
import Observation
import TattleCore
import TattleSystem

@MainActor
@Observable
final class NoiseModel {
    private(set) var noisemakers: [Noisemaker] = []
    private(set) var lastError: String?
    /// Preview-only: pretend an update was found (render checks; real state is `UpdateController`).
    var previewUpdateAvailable = false
    /// Audible/muted tabs reported by the browser extensions.
    private(set) var tabs: [TabInfo] = []
    private var glyphStep = 0
    private var glyphTimer: Timer?
    /// Called when the menu bar image should change (audibility flipped or an animation frame).
    var onMenuBarImageChange: (@MainActor (NSImage) -> Void)?
    /// Asks the menu bar popover to close (e.g. after jumping to a tab).
    var onDismissPanel: (@MainActor () -> Void)?
    private var publishedImage: NSImage?

    /// Animates only while something is audible, and not at all under Reduce Motion.
    var menuBarImage: NSImage {
        guard isAnythingAudible else { return MenuBarGlyph.idle }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || !preferences.animateMenuBarIcon {
            return MenuBarGlyph.frame(rays: 0b111)
        }
        let sequence = MenuBarGlyph.activeSequence
        return MenuBarGlyph.frame(rays: sequence[glyphStep % sequence.count])
    }

    private let monitor = NoiseMonitor(audio: CoreAudioActivitySource(), inspector: SysctlProcessInspector(), ownPID: getpid())
    private let inspector = SysctlProcessInspector()
    private let quitter = Quitter(terminator: SignalTerminator(), ownPID: getpid(), inspector: SysctlProcessInspector())
    private let muter = CoreAudioProcessMuter()
    private let muting: MuteController
    private let bridge: TabBridgeService?
    private let preferencesStore = UserDefaultsPreferencesStore()
    private let reaper = HeadlessReaper()
    private let nowPlaying: MediaRemoteNowPlaying? = MediaRemoteNowPlaying.bundled()
    private var preferences: Preferences { Preferences(from: preferencesStore) }

    var isAnythingAudible: Bool { noisemakers.contains { !isMuted($0) } }

    /// Observed copy of which PIDs are muted. `MuteController` is not observable, so
    /// reading it straight from a view never re-rendered the row after a toggle.
    private(set) var mutedPIDs: Set<Int32> = []

    func isMuted(_ noisemaker: Noisemaker) -> Bool { previewMuted.contains(noisemaker.ownerPID) || mutedPIDs.contains(noisemaker.ownerPID) }

    private func syncMuted() {
        let now = Set(muting.muted.keys)
        if now != mutedPIDs { mutedPIDs = now }
    }

    /// Static data for rendering the panel in previews/screenshots; no timers, no system calls.
    init(previewing noisemakers: [Noisemaker], muted: Set<Int32> = [], tabs: [TabInfo] = [], playing: [Int32: NowPlayingInfo] = [:], error: String? = nil) {
        previewPlaying = playing
        let inspector = self.inspector
        bridge = nil
        self.tabs = tabs
        muting = MuteController(muter: muter, isAlive: { inspector.snapshot(of: $0) != nil })
        self.noisemakers = noisemakers
        self.lastError = error
        self.previewMuted = muted
    }
    private var previewMuted: Set<Int32> = []
    private var previewPlaying: [Int32: NowPlayingInfo] = [:]

    init() {
        let inspector = self.inspector
        muting = MuteController(muter: muter, isAlive: { inspector.snapshot(of: $0) != nil })
        let bridge = TabBridgeService()
        self.bridge = bridge
        do { try bridge.start() } catch { lastError = "Browser extensions unavailable: \(error)" }
        SettingsWindowPresenter.shared.integrations = bridge
        SettingsWindowPresenter.shared.noise = self
        Task { [weak self] in
            for await _ in bridge.changes { self?.tabs = bridge.tabs() }
        }
        nowPlaying?.start()
        refresh()
        rescheduleScanning()
    }

    // MARK: Scan cadence
    // Scanning Core Audio is cheap but not free, and nobody watches the list while the popover is
    // closed. So: 1 s while the popover or Settings is open (plus an immediate scan on open), a
    // relaxed 5 s only when something still needs a background look (the menu bar icon's state, or
    // the headless reaper), and no timer at all otherwise. Mutes live in their own taps, not here.
    private var panelOpen = false
    private var settingsOpen = false
    private var scanTimer: Timer?
    private var scanInterval: TimeInterval?
    /// Told when Settings ▸ General ▸ "Show in menu bar" flips.
    var onMenuBarVisibilityChange: (@MainActor (Bool) -> Void)?
    private var menuBarVisible: Bool?

    func setPanelOpen(_ open: Bool) {
        panelOpen = open
        if open { refresh() }
        rescheduleScanning()
    }

    func setSettingsOpen(_ open: Bool) {
        settingsOpen = open
        if open { refresh() }
        rescheduleScanning()
    }

    private func rescheduleScanning() {
        let prefs = preferences
        if menuBarVisible != prefs.showMenuBarIcon {
            menuBarVisible = prefs.showMenuBarIcon
            onMenuBarVisibilityChange?(prefs.showMenuBarIcon)
        }
        let wanted = ScanPolicy.interval(listVisible: panelOpen || settingsOpen,
                                         menuBarIconShown: prefs.showMenuBarIcon, reaping: prefs.autoQuitHeadless)
        guard wanted != scanInterval else { return }
        scanTimer?.invalidate()
        scanInterval = wanted
        scanTimer = wanted.map { interval in
            let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            timer.tolerance = interval * 0.2  // let macOS coalesce the wake-ups
            RunLoop.main.add(timer, forMode: .common)  // keep ticking while the popover tracks events
            return timer
        }
    }

    func refresh() {
        do {
            let latest = muting.reconcile(try monitor.scan())
            if latest != noisemakers { noisemakers = latest }
            syncMuted()
            settlePendingPlayback()
            updateGlyphTimer()
            publishGlyph()
            reapHeadless(latest)
            rescheduleScanning()  // preferences may have changed since the last tick
        } catch {
            lastError = "Couldn't read audio state: \(error)"
        }
    }

    /// Auto-quit headless browsers that have been noisy too long (Settings ▸ Behavior).
    private func reapHeadless(_ current: [Noisemaker]) {
        let prefs = preferences
        let due = reaper.due(
            current.filter { !isMuted($0) },
            enabled: prefs.autoQuitHeadless,
            afterSeconds: Double(prefs.autoQuitHeadlessAfterMinutes) * 60,
            now: ProcessInfo.processInfo.systemUptime
        )
        for noisemaker in due { try? quitter.quit(noisemaker) }
    }

    /// Cached frames are shared instances, so identity is enough to skip no-op updates.
    private func publishGlyph() {
        let image = menuBarImage
        guard image !== publishedImage else { return }
        publishedImage = image
        onMenuBarImageChange?(image)
    }

    private func updateGlyphTimer() {
        let animating = isAnythingAudible && preferences.animateMenuBarIcon && preferences.showMenuBarIcon
        if animating, glyphTimer == nil {
            let timer = Timer(timeInterval: MenuBarGlyph.stepInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.glyphStep += 1
                    self?.publishGlyph()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            glyphTimer = timer
        } else if !animating, glyphTimer != nil {
            glyphTimer?.invalidate()
            glyphTimer = nil
            glyphStep = 0
        }
    }

    func toggleMute(_ noisemaker: Noisemaker) {
        do {
            try muting.toggle(noisemaker)
            lastError = nil
        } catch {
            lastError = "Couldn't mute \(noisemaker.name): \(error). Allow Tattle under System Settings › Privacy & Security › Screen & System Audio Recording."
        }
        syncMuted()
        refresh()
    }

    func shutDown() {
        muting.unmuteAll()
        bridge?.stop()
        nowPlaying?.stop()
    }

    /// Tabs to show under a browser's row. Empty when the master switch is off,
    /// the app isn't a browser, or its extension isn't connected.
    func tabs(for noisemaker: Noisemaker) -> [TabInfo] {
        guard preferences.useBrowserExtensions, let browser = Browser(appName: noisemaker.name) else { return [] }
        return tabs.filter { $0.browser == browser }
    }

    /// A play/pause the user just asked for, shown right away. It is dropped as soon as the
    /// system reports the same state, or after `optimisticWindow` (the command failed or the
    /// app ignored it), at which point the row falls back to what is really happening.
    private struct PendingPlayback { let target: Bool; let since: Date }
    private var pendingPlayback: [Int32: PendingPlayback] = [:]
    private let optimisticWindow: TimeInterval = 3

    /// What this app is playing, as macOS's Now Playing widget knows it (nil = unknown or disabled).
    func nowPlaying(for noisemaker: Noisemaker) -> NowPlayingInfo? {
        if let p = previewPlaying[noisemaker.ownerPID] { return p }
        guard preferences.showNowPlayingTitles,
              let info = NowPlayingMatcher.info(for: noisemaker, from: nowPlaying?.current(),
                                                bundleID: { Bundle(path: $0)?.bundleIdentifier }) else { return nil }
        // Now Playing is one global "last controlled" item, not "what is making noise". A paused
        // video can stay in it while a different tab is the one actually audible. When the browser
        // extension tells us which tabs make noise, only trust Now Playing if it is one of them.
        let browserTabs = tabs(for: noisemaker)
        if !browserTabs.isEmpty {
            let wanted = info.title.lowercased()
            let isOneOfTheTabs = browserTabs.contains { tab in
                let t = tab.title.lowercased()
                return !t.isEmpty && (t.contains(wanted) || wanted.contains(t))
            }
            if !isOneOfTheTabs { return nil }
        }
        if let pending = pendingPlayback[noisemaker.ownerPID], info.isPlaying != pending.target,
           Date().timeIntervalSince(pending.since) < optimisticWindow {
            return info.withPlaying(pending.target)
        }
        return info
    }

    func sendMedia(_ command: NowPlayingCommand, for noisemaker: Noisemaker) {
        let pid = noisemaker.ownerPID
        guard let current = nowPlaying(for: noisemaker), nowPlaying?.send(command) == true else { return }
        switch command {
        case .toggle: pendingPlayback[pid] = PendingPlayback(target: !current.isPlaying, since: Date())
        case .play: pendingPlayback[pid] = PendingPlayback(target: true, since: Date())
        case .pause: pendingPlayback[pid] = PendingPlayback(target: false, since: Date())
        case .next, .previous: break
        }
    }

    /// Drops optimistic states the system has confirmed or that timed out (called each tick).
    private func settlePendingPlayback() {
        guard !pendingPlayback.isEmpty else { return }
        let alive = Set(noisemakers.map(\.ownerPID))
        let real = nowPlaying?.current()
        let now = Date()
        let settled = pendingPlayback.filter { pid, p in
            !alive.contains(pid) || now.timeIntervalSince(p.since) >= optimisticWindow || real?.isPlaying == p.target
        }.keys
        for pid in settled { pendingPlayback[pid] = nil }
    }

    func send(_ command: TabCommand, to tab: TabInfo) {
        guard let bridge else { return }
        if command == .focus { onDismissPanel?() }  // get out of the way of the page being shown
        Task { [weak self] in
            do {
                try await bridge.send(command, to: tab)
                self?.lastError = nil
                if command == .focus { self?.bringBrowserToFront(tab.browser) }
            } catch {
                self?.lastError = "Couldn't \(command.rawValue) “\(tab.title)”: \(error)"
            }
        }
    }

    /// The extension selects the tab and focuses its window, but that doesn't necessarily
    /// bring a background browser app forward, so do that here.
    private func bringBrowserToFront(_ browser: Browser) {
        let name = NativeMessagingManifest.applicationBundleName(for: browser)
        NSWorkspace.shared.runningApplications
            .first { $0.bundleURL?.lastPathComponent == name }?
            .activate(options: [.activateAllWindows])
    }

    /// Quit button: asks first when Settings ▸ General ▸ "Confirm before quitting apps" is on.
    func requestQuit(_ noisemaker: Noisemaker, tabCount: Int = 0) {
        if preferences.confirmBeforeQuittingApps {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Quit \(noisemaker.name)?"
            alert.informativeText = tabCount > 1
                ? "This closes all of \(noisemaker.name), including \(tabCount) tabs playing audio. Unsaved work may be lost."
                : "Unsaved work in \(noisemaker.name) may be lost."
            alert.addButton(withTitle: "Quit")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        quit(noisemaker)
    }

    private func quit(_ noisemaker: Noisemaker) {
        do {
            try quitter.quit(noisemaker)
            lastError = nil
        } catch {
            lastError = "Couldn't quit \(noisemaker.name): \(error)"
        }
        refresh()
    }
}
