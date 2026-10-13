import AppKit
import TattleCore

/// Hands the user the browser extension: copies the bundled build to a stable folder
/// (so "Load unpacked" keeps working when the app is moved or rebuilt), reveals it, and
/// opens the browser's extensions page.
@MainActor
enum ExtensionFiles {
    private static var appSupportName: String {
        (Bundle.main.bundleIdentifier?.hasSuffix(".dev") ?? false) ? "Tattle Dev" : "Tattle"
    }

    static func stableFolder(for browser: Browser) -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let kind = browser == .firefox ? "firefox" : "chromium"
        return base.appendingPathComponent(appSupportName).appendingPathComponent("Extension").appendingPathComponent(kind)
    }

    /// Copies the bundled extension to the stable folder and reveals it in Finder.
    static func reveal(for browser: Browser) throws {
        let kind = browser == .firefox ? "firefox" : "chromium"
        guard let source = Bundle.main.resourceURL?.appendingPathComponent("Extensions/\(kind)"),
              FileManager.default.fileExists(atPath: source.path),
              let dest = stableFolder(for: browser) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "This build doesn't include the browser extension."])
        }
        let fm = FileManager.default
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try fm.copyItem(at: source, to: dest)
        NSWorkspace.shared.activateFileViewerSelecting([dest])
    }

    static func extensionsPage(for browser: Browser) -> (scheme: String, app: String)? {
        switch browser {
        case .chrome: ("chrome://extensions", "Google Chrome")
        case .edge: ("edge://extensions", "Microsoft Edge")
        case .brave: ("brave://extensions", "Brave Browser")
        case .vivaldi: ("vivaldi://extensions", "Vivaldi")
        case .opera: ("opera://extensions", "Opera")
        case .arc: ("arc://extensions", "Arc")
        case .chromium: ("chrome://extensions", "Chromium")
        case .firefox: ("about:debugging#/runtime/this-firefox", "Firefox")
        case .safari: nil
        }
    }

    static func openExtensionsPage(for browser: Browser) {
        guard let page = extensionsPage(for: browser) else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-a", page.app, page.scheme]
        try? p.run()
    }
}
