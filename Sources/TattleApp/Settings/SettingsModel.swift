import Foundation
import Observation
import TattleCore

/// Observable wrapper over the store. Every property writes through on change;
/// views bind to it with `@Bindable`.
@MainActor @Observable
final class SettingsModel {
    struct BrowserRow: Identifiable, Equatable {
        let browser: Browser
        let status: IntegrationStatus
        var id: Browser { browser }
    }

    @ObservationIgnored private let store: PreferencesStore
    @ObservationIgnored private let loginItem: LaunchAtLoginControlling
    @ObservationIgnored private let integrations: BrowserIntegrations

    var showMenuBarIcon: Bool { didSet { store.set(showMenuBarIcon, for: PreferenceKeys.showMenuBarIcon) } }
    var animateMenuBarIcon: Bool { didSet { store.set(animateMenuBarIcon, for: PreferenceKeys.animateMenuBarIcon) } }
    var confirmBeforeQuittingApps: Bool { didSet { store.set(confirmBeforeQuittingApps, for: PreferenceKeys.confirmBeforeQuittingApps) } }
    var autoQuitHeadless: Bool { didSet { store.set(autoQuitHeadless, for: PreferenceKeys.autoQuitHeadless) } }
    var autoQuitHeadlessAfterMinutes: Int {
        didSet {
            let clamped = Preferences.clampMinutes(autoQuitHeadlessAfterMinutes)
            if clamped != autoQuitHeadlessAfterMinutes { autoQuitHeadlessAfterMinutes = clamped; return }
            store.set(clamped, for: PreferenceKeys.autoQuitHeadlessAfterMinutes)
        }
    }
    var showNowPlayingTitles: Bool { didSet { store.set(showNowPlayingTitles, for: PreferenceKeys.showNowPlayingTitles) } }
    var useBrowserExtensions: Bool { didSet { store.set(useBrowserExtensions, for: PreferenceKeys.useBrowserExtensions) } }
    private(set) var launchAtLogin: Bool
    private(set) var launchAtLoginError: String?
    private(set) var browserRows: [BrowserRow] = []
    private(set) var browserError: String?

    init(store: PreferencesStore, loginItem: LaunchAtLoginControlling, integrations: BrowserIntegrations) {
        self.store = store
        self.loginItem = loginItem
        self.integrations = integrations
        let p = Preferences(from: store)
        showMenuBarIcon = p.showMenuBarIcon
        animateMenuBarIcon = p.animateMenuBarIcon
        confirmBeforeQuittingApps = p.confirmBeforeQuittingApps
        autoQuitHeadless = p.autoQuitHeadless
        autoQuitHeadlessAfterMinutes = p.autoQuitHeadlessAfterMinutes
        useBrowserExtensions = p.useBrowserExtensions
        showNowPlayingTitles = p.showNowPlayingTitles
        launchAtLogin = loginItem.isEnabled   // the system is the source of truth
        refreshBrowsers()
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            try loginItem.setEnabled(on)
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        launchAtLogin = loginItem.isEnabled
        store.set(launchAtLogin, for: PreferenceKeys.launchAtLogin)
    }

    func refreshBrowsers() {
        browserRows = integrations.installedBrowsers().map { BrowserRow(browser: $0, status: integrations.status(of: $0)) }
    }

    func revealExtension(for browser: Browser) {
        do { try ExtensionFiles.reveal(for: browser); browserError = nil } catch { browserError = Self.describe(error) }
    }

    func install(_ browser: Browser) { perform { try integrations.installHost(for: browser) } }
    func remove(_ browser: Browser) { perform { try integrations.removeHost(for: browser) } }

    /// macOS blocks writing into another app's data folder (Edge, Chrome…) unless the user
    /// allows it; say so instead of surfacing a bare "Operation not permitted".
    static func describe(_ error: Error) -> String {
        let ns = error as NSError
        let denied = (ns.domain == NSCocoaErrorDomain && (ns.code == 513 || ns.code == 4))
            || (ns.domain == NSPOSIXErrorDomain && (ns.code == Int(EPERM) || ns.code == Int(EACCES)))
            || (ns.userInfo[NSUnderlyingErrorKey] as? NSError).map { $0.domain == NSPOSIXErrorDomain && ($0.code == Int(EPERM) || $0.code == Int(EACCES)) } == true
        if denied {
            return "macOS blocked access to the browser's folder. Allow Tattle in Privacy & Security › App Management, then press Set Up again."
        }
        return error.localizedDescription
    }

    private func perform(_ action: () throws -> Void) {
        do { try action(); browserError = nil } catch { browserError = Self.describe(error) }
        refreshBrowsers()
    }

    /// Per-pane "Reset to Defaults" (as in Continuo). General deliberately leaves
    /// "Open at login" alone: it is a system registration, not a stored preference.
    func resetGeneral() {
        let d = Preferences()
        showMenuBarIcon = d.showMenuBarIcon
        animateMenuBarIcon = d.animateMenuBarIcon
        confirmBeforeQuittingApps = d.confirmBeforeQuittingApps
        showNowPlayingTitles = d.showNowPlayingTitles
    }

    func resetBehavior() {
        let d = Preferences()
        autoQuitHeadless = d.autoQuitHeadless
        autoQuitHeadlessAfterMinutes = d.autoQuitHeadlessAfterMinutes
    }
}

/// Fake for previews/rendering; the real implementation is injected by the app.
struct PreviewBrowserIntegrations: BrowserIntegrations {
    func installedBrowsers() -> [Browser] { [.chrome, .safari, .firefox] }
    func status(of browser: Browser) -> IntegrationStatus {
        switch browser { case .chrome: .connected; case .safari: .hostInstalled; default: .notInstalled }
    }
    func installHost(for browser: Browser) throws {}
    func removeHost(for browser: Browser) throws {}
}
