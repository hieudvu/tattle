/// Browsers Tattle can talk to through its extensions.
public enum Browser: String, Codable, CaseIterable, Sendable {
    case chrome, edge, brave, arc, vivaldi, opera, chromium, firefox, safari

    /// Maps a `Noisemaker.name` (the app's bundle name) to a browser.
    public init?(appName: String) {
        let name = appName.lowercased()
        switch true {
        case name == "google chrome" || name.hasPrefix("google chrome "): self = .chrome
        case name == "microsoft edge" || name.hasPrefix("microsoft edge "): self = .edge
        case name.hasPrefix("brave browser"): self = .brave
        case name == "arc": self = .arc
        case name == "vivaldi": self = .vivaldi
        case name == "opera": self = .opera
        case name == "chromium": self = .chromium
        case name.hasPrefix("firefox"): self = .firefox
        case name.hasPrefix("safari"): self = .safari
        default: return nil
        }
    }

    /// Extension flavour: Chrome/Edge/Brave/Arc/... share one Chromium extension.
    public var isChromiumFamily: Bool { self != .firefox && self != .safari }
}

/// One browser tab, as reported by a Tattle extension.
public struct TabInfo: Identifiable, Equatable, Codable, Sendable {
    public var id: String { "\(browser.rawValue):\(tabID)" }
    public let browser: Browser
    /// Opaque, browser-assigned (the extension uses "<windowId>:<tabId>").
    public let tabID: String
    public let title: String
    public let url: String
    public let isAudible: Bool
    public let isMuted: Bool

    public init(browser: Browser, tabID: String, title: String, url: String, isAudible: Bool, isMuted: Bool) {
        self.browser = browser
        self.tabID = tabID
        self.title = title
        self.url = url
        self.isAudible = isAudible
        self.isMuted = isMuted
    }
}

public enum TabCommand: String, Codable, Sendable {
    case mute, unmute, pause, close, focus
}

/// Where tab information comes from and where tab commands go. The real
/// implementation talks to the extensions; the UI and tests use fakes.
public protocol TabSource: Sendable {
    /// Latest known tabs that are audible or muted, across connected browsers.
    func tabs() -> [TabInfo]
    func send(_ command: TabCommand, to tab: TabInfo) async throws
}

public enum IntegrationStatus: Equatable, Sendable {
    case notInstalled   // nothing set up for this browser
    case hostInstalled  // native-messaging manifest written; extension not seen yet
    case connected      // the extension has said hello recently
}

/// Setting up and inspecting the browser extensions. Real implementation lives
/// in TattleSystem; Settings and tests use fakes.
public protocol BrowserIntegrations: Sendable {
    /// Browsers actually present on this Mac.
    func installedBrowsers() -> [Browser]
    func status(of browser: Browser) -> IntegrationStatus
    /// Writes the native-messaging host manifest for the browser.
    func installHost(for browser: Browser) throws
    func removeHost(for browser: Browser) throws
}
