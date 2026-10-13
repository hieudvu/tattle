import Foundation

public enum BridgePathError: Error, Equatable, Sendable {
    /// `sockaddr_un.sun_path` holds 104 bytes on macOS, including the NUL.
    case tooLong(path: String, bytes: Int)
}

/// Where the app listens and the bridge connects. Pure: home and environment are parameters.
public enum BridgeSocketPath {
    public static let environmentKey = "TATTLE_BRIDGE_SOCKET"
    public static let maxBytes = 103

    public struct Resolved: Equatable, Sendable {
        public let path: String
        /// True when `TATTLE_BRIDGE_SOCKET` chose it (the directory is then not ours to chmod).
        public let isOverride: Bool
    }

    public static func resolve(flavour: AppFlavour, home: URL, environment: [String: String]) throws -> Resolved {
        let override = environment[environmentKey].flatMap { $0.isEmpty ? nil : $0 }
        let path = override ?? home
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(flavour.supportDirectoryName, isDirectory: true)
            .appendingPathComponent("bridge.sock").path
        let bytes = path.utf8.count
        guard bytes <= maxBytes else { throw BridgePathError.tooLong(path: path, bytes: bytes) }
        return Resolved(path: path, isOverride: override != nil)
    }
}
