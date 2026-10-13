#if DEBUG
import AppKit
import SwiftUI
import TattleCore

/// Dev aid: `TATTLE_RENDER_PANEL=/tmp/panel .build/debug/Tattle` writes PNGs of the
/// panel (sample data, light/dark, busy/empty) through a real NSHostingView and exits.
/// Debug builds only. Note: the offscreen dark render has no window backdrop, so
/// text can look invisible there; trust the light render for layout.
@MainActor func renderPanelIfRequested() {
    guard let out = ProcessInfo.processInfo.environment["TATTLE_RENDER_PANEL"] else { return }
    let sample = [
        Noisemaker(ownerPID: 101, name: "Microsoft Edge", bundlePath: "/Applications/Microsoft Edge.app"),
        Noisemaker(ownerPID: 102, name: "Safari", bundlePath: "/Applications/Safari.app"),
        Noisemaker(ownerPID: 103, name: "Google Chrome", bundlePath: "/Applications/Google Chrome.app", isHeadless: true),
    ]
    for (suffix, items, muted) in [("busy", sample, Set<Int32>([102])), ("single", [sample[0]], Set<Int32>()), ("empty", [], Set<Int32>())] {
        let all = [
            TabInfo(browser: .edge, tabID: "1:1", title: "Lo-fi hip hop radio — beats to relax/study to", url: "https://www.youtube.com/watch?v=x", isAudible: true, isMuted: false),
            TabInfo(browser: .edge, tabID: "1:2", title: "Spotify — Web Player", url: "https://open.spotify.com/", isAudible: false, isMuted: true),
        ]
        let tabs = items.isEmpty ? [] : (suffix == "single" ? Array(all.prefix(1)) : all)
        let model = NoiseModel(previewing: items, muted: muted, tabs: tabs, playing: (items.isEmpty || suffix == "single") ? [:] : [101: NowPlayingInfo(title: "Lo-fi hip hop radio — beats to relax/study to", artist: "Lofi Girl"), 102: NowPlayingInfo(title: "Blinding Lights", artist: "The Weeknd", isPlaying: false)])
        model.previewUpdateAvailable = suffix == "busy"
        for scheme in [ColorScheme.light, .dark] {
            let view = NoisePanel(model: model).environment(\.colorScheme, scheme)
            let host = NSHostingView(rootView: view)
            let size = host.fittingSize
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            window.contentView = host
            window.layoutIfNeeded()
            host.frame = NSRect(origin: .zero, size: size)
            if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: rep)
                if let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: "\(out)-\(suffix)-\(scheme == .dark ? "dark" : "light").png"))
                }
            }
        }
    }
    exit(0)
}

/// Dev aid: `TATTLE_RENDER_SETTINGS=/tmp/settings .build/debug/Tattle` writes light/dark PNGs of
/// the General and About panes and the permission row in each state, then exits.
@MainActor func renderSettingsIfRequested() {
    guard let out = ProcessInfo.processInfo.environment["TATTLE_RENDER_SETTINGS"] else { return }
    let model = SettingsModel(store: UserDefaultsPreferencesStore(defaults: UserDefaults(suiteName: "tattle.render")!),
                              loginItem: SMAppServiceLaunchAtLogin(), integrations: PreviewBrowserIntegrations())
    func row(_ status: AudioCaptureStatus) -> some View {
        SettingsForm {
            Section {
                PermissionRow(symbol: "speaker.slash", title: "System Audio Recording",
                              detail: "Lets Tattle mute an app. It never records or stores audio.",
                              status: status, onGrant: {}, onOpenSettings: {})
            } header: { Text("Required to mute") }
        }
    }
    let panes: [(String, AnyView)] = [
        ("general", AnyView(GeneralTab(model: model))),
        ("about", AnyView(AboutTab())),
        ("perm-notdetermined", AnyView(row(.notDetermined))),
        ("perm-denied", AnyView(row(.denied))),
        ("perm-granted", AnyView(row(.granted))),
    ]
    for scheme in [ColorScheme.light, .dark] {
        for (name, pane) in panes {
            let host = NSHostingView(rootView: pane.frame(width: 560, height: 420).background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, scheme))
            let size = NSSize(width: 560, height: 420)
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            window.contentView = host
            window.layoutIfNeeded()
            host.frame = NSRect(origin: .zero, size: size)
            if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: "\(out)-\(name)-\(scheme == .dark ? "dark" : "light").png"))
            }
        }
    }
    exit(0)
}
#endif
