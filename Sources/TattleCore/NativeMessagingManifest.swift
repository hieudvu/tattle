import Foundation

public enum IntegrationError: Error, Equatable, Sendable {
    case unsupportedBrowser(Browser)
    case hostExecutableMissing(String)
}

/// Native-messaging host manifests: contents and where each browser looks for them.
public enum NativeMessagingManifest {
    public static func json(for browser: Browser, flavour: AppFlavour, hostPath: String) throws -> Data {
        guard directoryComponents(for: browser) != nil else { throw IntegrationError.unsupportedBrowser(browser) }
        var object: [String: Any] = [
            "name": flavour.hostName,
            "description": flavour == .production ? "Tattle browser bridge" : "Tattle Dev browser bridge",
            "path": hostPath,
            "type": "stdio",
        ]
        if browser.isChromiumFamily {
            object["allowed_origins"] = ["chrome-extension://\(ExtensionIdentity.chromiumID)/"]
        } else {
            object["allowed_extensions"] = [ExtensionIdentity.firefoxID]
        }
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    /// Path below `~/Library/Application Support`. Safari has no native-messaging host.
    /// Chrome, Edge, Brave, Vivaldi, Chromium and Firefox are well documented; Arc and
    /// Opera follow the Chromium layout but are less certain.
    static func directoryComponents(for browser: Browser) -> String? {
        switch browser {
        case .chrome: "Google/Chrome/NativeMessagingHosts"
        case .chromium: "Chromium/NativeMessagingHosts"
        case .edge: "Microsoft Edge/NativeMessagingHosts"
        case .brave: "BraveSoftware/Brave-Browser/NativeMessagingHosts"
        case .vivaldi: "Vivaldi/NativeMessagingHosts"
        case .arc: "Arc/User Data/NativeMessagingHosts"
        case .opera: "com.operasoftware.Opera/NativeMessagingHosts"
        case .firefox: "Mozilla/NativeMessagingHosts"
        case .safari: nil
        }
    }

    public static func directory(for browser: Browser, home: URL) -> URL? {
        directoryComponents(for: browser).map {
            home.appendingPathComponent("Library/Application Support", isDirectory: true)
                .appendingPathComponent($0, isDirectory: true)
        }
    }

    public static func fileURL(for browser: Browser, flavour: AppFlavour, home: URL) -> URL? {
        directory(for: browser, home: home)?.appendingPathComponent("\(flavour.hostName).json")
    }

    /// Bundle name looked for in /Applications and ~/Applications.
    public static func applicationBundleName(for browser: Browser) -> String {
        switch browser {
        case .chrome: "Google Chrome.app"
        case .edge: "Microsoft Edge.app"
        case .brave: "Brave Browser.app"
        case .arc: "Arc.app"
        case .vivaldi: "Vivaldi.app"
        case .opera: "Opera.app"
        case .chromium: "Chromium.app"
        case .firefox: "Firefox.app"
        case .safari: "Safari.app"
        }
    }
}
