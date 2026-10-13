import Foundation

public enum BridgeMessageError: Error, Equatable, Sendable {
    case unsupportedVersion(Int?)
    case unknownType(String?)
    case missingField(String)
    case unknownBrowser(String)
    case unknownCommand(String)
}

/// Every message of the extension protocol (docs/extension-protocol.md), version 1.
public enum BridgeMessage: Equatable, Sendable, Codable {
    case hello(browser: Browser, extensionVersion: String)
    /// A full snapshot. `dropped` counts malformed tabs that were skipped: one bad
    /// tab must not cost the user every other tab, so the snapshot survives without it.
    case tabs(browser: Browser, tabs: [TabInfo], dropped: Int)
    case result(id: String, ok: Bool, error: String?)
    case command(id: String, command: TabCommand, tabID: String)

    public static let version = 1

    private enum Key: String, CodingKey {
        case v, type, browser, extensionVersion, tabs, id, ok, error, command, tabId
    }

    private enum TabKey: String, CodingKey { case id, title, url, audible, muted }

    /// Decodes one frame payload. Never traps; throws for anything not v1.
    public static func decode(_ data: Data) throws -> BridgeMessage {
        try JSONDecoder().decode(BridgeMessage.self, from: data)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        let version = try? c.decode(Int.self, forKey: .v)
        guard version == Self.version else { throw BridgeMessageError.unsupportedVersion(version) }
        let type = try? c.decode(String.self, forKey: .type)

        func string(_ key: Key) throws -> String {
            guard let s = try? c.decode(String.self, forKey: key) else { throw BridgeMessageError.missingField(key.rawValue) }
            return s
        }
        func browser() throws -> Browser {
            let raw = try string(.browser)
            guard let b = Browser(rawValue: raw) else { throw BridgeMessageError.unknownBrowser(raw) }
            return b
        }

        switch type {
        case "hello":
            self = .hello(browser: try browser(), extensionVersion: try string(.extensionVersion))
        case "tabs":
            let b = try browser()
            guard c.contains(.tabs) else { throw BridgeMessageError.missingField("tabs") }
            guard var list = try? c.nestedUnkeyedContainer(forKey: .tabs) else { throw BridgeMessageError.missingField("tabs") }
            var tabs: [TabInfo] = []
            var dropped = 0
            while !list.isAtEnd {
                // Lossy wrapper never throws, so the container always advances.
                let element = try list.decode(LossyTab.self)
                if let info = element.tab?.info(browser: b) { tabs.append(info) } else { dropped += 1 }
            }
            self = .tabs(browser: b, tabs: tabs, dropped: dropped)
        case "result":
            guard let ok = try? c.decode(Bool.self, forKey: .ok) else { throw BridgeMessageError.missingField("ok") }
            self = .result(id: try string(.id), ok: ok, error: try? c.decode(String.self, forKey: .error))
        case "command":
            let raw = try string(.command)
            guard let command = TabCommand(rawValue: raw) else { throw BridgeMessageError.unknownCommand(raw) }
            self = .command(id: try string(.id), command: command, tabID: try string(.tabId))
        default:
            throw BridgeMessageError.unknownType(type)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        try c.encode(Self.version, forKey: .v)
        switch self {
        case let .hello(browser, version):
            try c.encode("hello", forKey: .type)
            try c.encode(browser, forKey: .browser)
            try c.encode(version, forKey: .extensionVersion)
        case let .tabs(browser, tabs, _):
            try c.encode("tabs", forKey: .type)
            try c.encode(browser, forKey: .browser)
            try c.encode(tabs.map(WireTab.init), forKey: .tabs)
        case let .result(id, ok, error):
            try c.encode("result", forKey: .type)
            try c.encode(id, forKey: .id)
            try c.encode(ok, forKey: .ok)
            try c.encodeIfPresent(error, forKey: .error)
        case let .command(id, command, tabID):
            try c.encode("command", forKey: .type)
            try c.encode(id, forKey: .id)
            try c.encode(command, forKey: .command)
            try c.encode(tabID, forKey: .tabId)
        }
    }

    private struct LossyTab: Decodable {
        let tab: WireTab?
        init(from decoder: any Decoder) throws { tab = try? WireTab(from: decoder) }
    }

    private struct WireTab: Codable {
        let id: String
        let title: String
        let url: String
        let audible: Bool
        let muted: Bool

        init(_ tab: TabInfo) {
            id = tab.tabID; title = tab.title; url = tab.url; audible = tab.isAudible; muted = tab.isMuted
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: TabKey.self)
            id = try c.decode(String.self, forKey: .id)
            title = (try? c.decode(String.self, forKey: .title)) ?? ""
            url = (try? c.decode(String.self, forKey: .url)) ?? ""
            audible = try c.decode(Bool.self, forKey: .audible)
            muted = try c.decode(Bool.self, forKey: .muted)
        }

        func info(browser: Browser) -> TabInfo? {
            guard !id.isEmpty else { return nil }
            return TabInfo(browser: browser, tabID: id, title: title, url: url, isAudible: audible, isMuted: muted)
        }
    }
}
