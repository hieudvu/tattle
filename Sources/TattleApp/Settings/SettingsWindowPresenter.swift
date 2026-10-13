import AppKit
import SwiftUI
import TattleCore

/// Owns the single Settings window. `SettingsWindowPresenter.shared.show()` is
/// the only entry point. Pattern from Continuo: flip the accessory app to
/// `.regular` while the window is open (so it can take focus and show in
/// Cmd-Tab), flip back on close, reuse one window.
@MainActor
final class SettingsWindowPresenter: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowPresenter()

    private var window: NSWindow?
    /// The real app uses the defaults; the lead can inject a real
    /// `BrowserIntegrations` via `shared.integrations = ...` before first `show()`.
    var integrations: BrowserIntegrations = PreviewBrowserIntegrations()
    /// Live noise model, so Settings ▸ Sound shows the same list as the menu bar.
    var noise: NoiseModel?

    func show() {
        if window == nil {
            let model = SettingsModel(store: UserDefaultsPreferencesStore(),
                                      loginItem: SMAppServiceLaunchAtLogin(),
                                      integrations: integrations)
            let w = Self.makeWindow(model: model, noise: noise)
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.setFrameAutosaveName("TattleSettings")
            window = w
        }
        noise?.setSettingsOpen(true)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Window setup as in Continuo's AppMain: AppKit owns size and minimum
    /// (`sizingOptions = []` keeps it stable), SwiftUI just fills it.
    static func makeWindow(model: SettingsModel, noise: NoiseModel? = nil) -> NSWindow {
        let host = NSHostingController(rootView: SettingsRootView(model: model, noise: noise))
        host.sizingOptions = []
        let w = NSWindow(contentViewController: host)
        w.title = "Tattle Settings"
        w.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        w.contentMinSize = NSSize(width: 720, height: 480)
        w.setContentSize(NSSize(width: 820, height: 560))
        w.center()
        return w
    }

    func windowWillClose(_ notification: Notification) {
        noise?.setSettingsOpen(false)
        window = nil   // rebuild next time so state (e.g. launch-at-login) is fresh
        NSApp.setActivationPolicy(.accessory)
    }
}
