/// Which of the two apps a piece of code belongs to. Dev and pro never share a
/// native-messaging host name, a socket path or an extension identity.
///
/// Fail-safe direction: anything that is not provably the pro bundle is dev, so
/// an unbundled `swift run` can never talk to the pro app's extensions.
public enum AppFlavour: Equatable, Sendable {
    case dev, pro

    public static let proBundleID = "dev.hieuvd.tattle"
    public static let devBundleID = "dev.hieuvd.tattle.dev"

    public init(bundleIdentifier: String?) {
        self = bundleIdentifier == Self.proBundleID ? .pro : .dev
    }

    /// Derived from where an executable lives: inside `Tattle.app` is pro.
    public init(executablePath: String) {
        self = executablePath.contains("/Tattle.app/") ? .pro : .dev
    }

    public var hostName: String {
        self == .pro ? ExtensionIdentity.hostNamePro : ExtensionIdentity.hostNameDev
    }

    /// Folder under `~/Library/Application Support`.
    public var supportDirectoryName: String { self == .pro ? "Tattle" : "Tattle Dev" }
}
