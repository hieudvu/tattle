import Foundation

/// Identifies one bridge connection (one running `tattle-bridge`, i.e. one extension port).
public typealias ConnectionID = Int

/// Pure per-browser tab state.
///
/// Freshness rule: the extension only speaks on change, so silence proves nothing and
/// there is no time-based expiry. A browser is `connected` exactly while a live
/// connection has said hello (or sent a snapshot). When Chrome sleeps the extension
/// service worker the native port closes, the bridge exits, the socket drops, and the
/// browser's tabs are forgotten. A newer connection for the same browser supersedes
/// the older one, so a late disconnect of the old one cannot wipe the new one's state.
public struct TabStore: Sendable {
    public static let maxTabsPerBrowser = 1000

    private struct Entry: Sendable {
        var connection: ConnectionID
        var extensionVersion: String?
        var tabs: [TabInfo]
    }

    private var entries: [Browser: Entry] = [:]
    private var bound: [ConnectionID: Browser] = [:]

    public init() {}

    /// Applies a message from a connection. Returns true when observable state changed.
    /// `result`/`command` messages are not the store's business and return false.
    @discardableResult
    public mutating func apply(_ message: BridgeMessage, from connection: ConnectionID) -> Bool {
        switch message {
        case let .hello(browser, version):
            guard bind(connection, to: browser) else { return false }
            entries[browser]?.extensionVersion = version
            return true
        case let .tabs(browser, tabs, _):
            guard bind(connection, to: browser) else { return false }
            var seen = Set<String>()
            let kept = tabs
                .filter { $0.browser == browser && ($0.isAudible || $0.isMuted) && seen.insert($0.tabID).inserted }
                .prefix(Self.maxTabsPerBrowser)
            entries[browser]?.tabs = Array(kept)
            return true
        case .result, .command:
            return false
        }
    }

    /// A connection went away. Returns true when it was the live connection of a browser.
    @discardableResult
    public mutating func disconnect(_ connection: ConnectionID) -> Bool {
        guard let browser = bound.removeValue(forKey: connection) else { return false }
        guard entries[browser]?.connection == connection else { return false }
        entries[browser] = nil
        return true
    }

    /// Binds a connection to a browser; false if it is already bound to a different one.
    private mutating func bind(_ connection: ConnectionID, to browser: Browser) -> Bool {
        if let existing = bound[connection], existing != browser { return false }
        bound[connection] = browser
        if entries[browser]?.connection != connection {
            if let old = entries[browser]?.connection { bound[old] = nil }
            entries[browser] = Entry(connection: connection, extensionVersion: nil, tabs: [])
        }
        return true
    }

    /// Audible or muted tabs of every connected browser: browser order, then title, then id.
    public func tabs() -> [TabInfo] {
        let order = Dictionary(uniqueKeysWithValues: Browser.allCases.enumerated().map { ($1, $0) })
        return entries.values.flatMap(\.tabs).sorted { a, b in
            if a.browser != b.browser { return order[a.browser]! < order[b.browser]! }
            let t = a.title.localizedCaseInsensitiveCompare(b.title)
            if t != .orderedSame { return t == .orderedAscending }
            return a.tabID < b.tabID
        }
    }

    public func isConnected(_ browser: Browser) -> Bool { entries[browser] != nil }
    public func connection(for browser: Browser) -> ConnectionID? { entries[browser]?.connection }
    public func extensionVersion(of browser: Browser) -> String? { entries[browser]?.extensionVersion }
    public func knows(_ tab: TabInfo) -> Bool {
        entries[tab.browser]?.tabs.contains { $0.tabID == tab.tabID } ?? false
    }

    /// `connected` only while that browser's extension is connected; otherwise whether
    /// the host manifest is in place decides between `hostInstalled` and `notInstalled`.
    public func status(of browser: Browser, hostInstalled: Bool = false) -> IntegrationStatus {
        isConnected(browser) ? .connected : (hostInstalled ? .hostInstalled : .notInstalled)
    }
}
