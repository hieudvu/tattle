import AppKit
import TattleCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: NoiseModel?
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = NoiseModel()
        self.model = model
        statusItem = StatusItemController(model: model)
        // With the menu bar icon hidden there is nothing to click, so open Settings (which lists
        // the same sounds) instead of leaving the user staring at nothing.
        if !UserDefaultsPreferencesStore().get(PreferenceKeys.showMenuBarIcon) {
            SettingsWindowPresenter.shared.show()
        }
        UpdateController.shared.start()
    }

    /// Opening Tattle again (Finder, Spotlight, Dock) is the way back in when the menu bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { SettingsWindowPresenter.shared.show() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.shutDown()  // release mute taps so muted apps are not left silent
    }
}
