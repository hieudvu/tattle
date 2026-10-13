/// Which of the two apps a piece of code belongs to. Dev and production never share a
/// native-messaging host name, a socket path or an extension identity.
///
/// Fail-safe direction: anything that is not provably the production bundle is dev, so
/// an unbundled `swift run` can never talk to the production app's extensions.
public enum AppFlavour: Equatable, Sendable {
    case dev, production

    public static let productionBundleID = "dev.hieuvd.tattle"
    public static let devBundleID = "dev.hieuvd.tattle.dev"

    public init(bundleIdentifier: String?) {
        self = bundleIdentifier == Self.productionBundleID ? .production : .dev
    }

    /// Derived from where an executable lives: inside `Tattle.app` is production.
    public init(executablePath: String) {
        self = executablePath.contains("/Tattle.app/") ? .production : .dev
    }

    public var hostName: String {
        self == .production ? ExtensionIdentity.hostNameProduction : ExtensionIdentity.hostNameDev
    }

    /// Folder under `~/Library/Application Support`.
    public var supportDirectoryName: String { self == .production ? "Tattle" : "Tattle Dev" }
}
