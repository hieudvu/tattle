import Foundation
import Testing
import TattleCore

@Suite struct NativeMessagingManifestTests {
    private func obj(_ d: Data) throws -> [String: Any] { try #require(JSONSerialization.jsonObject(with: d) as? [String: Any]) }

    @Test func chromiumManifest() throws {
        let o = try obj(try NativeMessagingManifest.json(for: .brave, flavour: .production, hostPath: "/Applications/Tattle.app/Contents/MacOS/tattle-bridge"))
        #expect(o["name"] as? String == "dev.hieuvd.tattle")
        #expect(o["type"] as? String == "stdio")
        #expect(o["path"] as? String == "/Applications/Tattle.app/Contents/MacOS/tattle-bridge")
        #expect(o["allowed_origins"] as? [String] == ["chrome-extension://\(ExtensionIdentity.chromiumID)/"])
        #expect(o["allowed_extensions"] == nil)
        #expect((o["description"] as? String)?.isEmpty == false)
    }

    @Test func firefoxManifestAndDevName() throws {
        let o = try obj(try NativeMessagingManifest.json(for: .firefox, flavour: .dev, hostPath: "/x"))
        #expect(o["name"] as? String == "dev.hieuvd.tattle.dev")
        #expect(o["allowed_extensions"] as? [String] == [ExtensionIdentity.firefoxID])
        #expect(o["allowed_origins"] == nil)
    }

    @Test func safariHasNoHost() {
        #expect(throws: IntegrationError.unsupportedBrowser(.safari)) { try NativeMessagingManifest.json(for: .safari, flavour: .production, hostPath: "/x") }
        #expect(NativeMessagingManifest.fileURL(for: .safari, flavour: .production, home: URL(filePath: "/h")) == nil)
    }

    @Test func manifestPathsDifferPerFlavourAndBrowser() {
        let home = URL(filePath: "/tmp/h")
        let paths = Browser.allCases.compactMap { NativeMessagingManifest.fileURL(for: $0, flavour: .production, home: home)?.path }
        #expect(Set(paths).count == paths.count)
        #expect(NativeMessagingManifest.fileURL(for: .chrome, flavour: .dev, home: home)?.path
            == "/tmp/h/Library/Application Support/Google/Chrome/NativeMessagingHosts/dev.hieuvd.tattle.dev.json")
        #expect(NativeMessagingManifest.fileURL(for: .firefox, flavour: .production, home: home)?.path
            == "/tmp/h/Library/Application Support/Mozilla/NativeMessagingHosts/dev.hieuvd.tattle.json")
    }
}

@Suite struct FlavourAndSocketPathTests {
    private let home = URL(filePath: "/Users/me")

    @Test func flavourFromBundleAndPath() {
        #expect(AppFlavour(bundleIdentifier: "dev.hieuvd.tattle") == .production)
        #expect(AppFlavour(bundleIdentifier: "dev.hieuvd.tattle.dev") == .dev)
        #expect(AppFlavour(bundleIdentifier: nil) == .dev)
        #expect(AppFlavour(executablePath: "/Applications/Tattle.app/Contents/MacOS/tattle-bridge") == .production)
        #expect(AppFlavour(executablePath: "/x/build/Tattle Dev.app/Contents/MacOS/tattle-bridge") == .dev)
        #expect(AppFlavour(executablePath: "/x/.build/debug/tattle-bridge") == .dev)
    }

    @Test func defaultPathsAreSeparate() throws {
        let production = try BridgeSocketPath.resolve(flavour: .production, home: home, environment: [:])
        let dev = try BridgeSocketPath.resolve(flavour: .dev, home: home, environment: [:])
        #expect(production.path == "/Users/me/Library/Application Support/Tattle/bridge.sock")
        #expect(dev.path == "/Users/me/Library/Application Support/Tattle Dev/bridge.sock")
        #expect(!production.isOverride)
    }

    @Test func environmentOverrideWins() throws {
        let r = try BridgeSocketPath.resolve(flavour: .production, home: home, environment: ["TATTLE_BRIDGE_SOCKET": "/tmp/t.sock"])
        #expect(r.path == "/tmp/t.sock" && r.isOverride)
        let empty = try BridgeSocketPath.resolve(flavour: .production, home: home, environment: ["TATTLE_BRIDGE_SOCKET": ""])
        #expect(!empty.isOverride)
    }

    @Test func tooLongPathIsRejected() {
        let long = "/" + String(repeating: "a", count: 104)
        #expect(throws: BridgePathError.self) { try BridgeSocketPath.resolve(flavour: .production, home: home, environment: ["TATTLE_BRIDGE_SOCKET": long]) }
        let exact = "/" + String(repeating: "a", count: 102)
        #expect(throws: Never.self) { try BridgeSocketPath.resolve(flavour: .production, home: home, environment: ["TATTLE_BRIDGE_SOCKET": exact]) }
    }
}
