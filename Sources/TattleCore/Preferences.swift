/// User preferences: a pure value type plus a typed-key store protocol.
/// No AppKit, no UserDefaults; the App target supplies the real store.

public protocol PreferenceValue: Sendable, Equatable {}
extension Bool: PreferenceValue {}
extension Int: PreferenceValue {}

/// A named, typed preference with its default.
public struct PreferenceKey<Value: PreferenceValue>: Sendable {
    public let name: String
    public let defaultValue: Value
    public init(_ name: String, default defaultValue: Value) {
        self.name = name
        self.defaultValue = defaultValue
    }
}

public enum PreferenceKeys {
    public static let showMenuBarIcon = PreferenceKey("tattle.showMenuBarIcon", default: true)
    public static let animateMenuBarIcon = PreferenceKey("tattle.animateMenuBarIcon", default: true)
    public static let confirmBeforeQuittingApps = PreferenceKey("tattle.confirmBeforeQuittingApps", default: true)
    public static let autoQuitHeadless = PreferenceKey("tattle.autoQuitHeadless", default: false)
    public static let autoQuitHeadlessAfterMinutes = PreferenceKey("tattle.autoQuitHeadlessAfterMinutes", default: 10)
    public static let useBrowserExtensions = PreferenceKey("tattle.useBrowserExtensions", default: true)
    public static let launchAtLogin = PreferenceKey("tattle.launchAtLogin", default: false)
    public static let showNowPlayingTitles = PreferenceKey("tattle.showNowPlayingTitles", default: true)

    /// Every key name, for "Restore Defaults" and tests.
    public static let all: [String] = [
        showMenuBarIcon.name, animateMenuBarIcon.name, confirmBeforeQuittingApps.name, autoQuitHeadless.name,
        autoQuitHeadlessAfterMinutes.name, useBrowserExtensions.name, launchAtLogin.name, showNowPlayingTitles.name,
    ]
}

/// Typed key/value storage. A missing value reads as the key's default.
public protocol PreferencesStore: AnyObject {
    func get<V: PreferenceValue>(_ key: PreferenceKey<V>) -> V
    func set<V: PreferenceValue>(_ value: V, for key: PreferenceKey<V>)
    /// Forget every Tattle preference so all read as defaults again.
    func removeAll()
}

public struct Preferences: Equatable, Sendable {
    public static let autoQuitMinutesRange = 1...120

    public var showMenuBarIcon = PreferenceKeys.showMenuBarIcon.defaultValue
    public var animateMenuBarIcon = PreferenceKeys.animateMenuBarIcon.defaultValue
    public var confirmBeforeQuittingApps = PreferenceKeys.confirmBeforeQuittingApps.defaultValue
    public var autoQuitHeadless = PreferenceKeys.autoQuitHeadless.defaultValue
    public var autoQuitHeadlessAfterMinutes = PreferenceKeys.autoQuitHeadlessAfterMinutes.defaultValue {
        didSet { autoQuitHeadlessAfterMinutes = Self.clampMinutes(autoQuitHeadlessAfterMinutes) }
    }
    public var useBrowserExtensions = PreferenceKeys.useBrowserExtensions.defaultValue
    public var launchAtLogin = PreferenceKeys.launchAtLogin.defaultValue
    public var showNowPlayingTitles = PreferenceKeys.showNowPlayingTitles.defaultValue

    public init() {}

    public static func clampMinutes(_ m: Int) -> Int {
        min(max(m, autoQuitMinutesRange.lowerBound), autoQuitMinutesRange.upperBound)
    }

    public init(from store: PreferencesStore) {
        showMenuBarIcon = store.get(PreferenceKeys.showMenuBarIcon)
        animateMenuBarIcon = store.get(PreferenceKeys.animateMenuBarIcon)
        confirmBeforeQuittingApps = store.get(PreferenceKeys.confirmBeforeQuittingApps)
        autoQuitHeadless = store.get(PreferenceKeys.autoQuitHeadless)
        autoQuitHeadlessAfterMinutes = Self.clampMinutes(store.get(PreferenceKeys.autoQuitHeadlessAfterMinutes))
        useBrowserExtensions = store.get(PreferenceKeys.useBrowserExtensions)
        launchAtLogin = store.get(PreferenceKeys.launchAtLogin)
        showNowPlayingTitles = store.get(PreferenceKeys.showNowPlayingTitles)
    }

    public func write(to store: PreferencesStore) {
        store.set(showMenuBarIcon, for: PreferenceKeys.showMenuBarIcon)
        store.set(animateMenuBarIcon, for: PreferenceKeys.animateMenuBarIcon)
        store.set(confirmBeforeQuittingApps, for: PreferenceKeys.confirmBeforeQuittingApps)
        store.set(autoQuitHeadless, for: PreferenceKeys.autoQuitHeadless)
        store.set(Self.clampMinutes(autoQuitHeadlessAfterMinutes), for: PreferenceKeys.autoQuitHeadlessAfterMinutes)
        store.set(useBrowserExtensions, for: PreferenceKeys.useBrowserExtensions)
        store.set(launchAtLogin, for: PreferenceKeys.launchAtLogin)
        store.set(showNowPlayingTitles, for: PreferenceKeys.showNowPlayingTitles)
    }
}
