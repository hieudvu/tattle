/// One thing making noise, aggregated to the app that owns the audio.
/// Chrome plays sound from a helper process, so several audio pids collapse
/// into the single owning app.
public struct Noisemaker: Identifiable, Equatable, Sendable {
    public var id: Int32 { ownerPID }
    public let ownerPID: Int32
    public let name: String
    /// The owning `.app`, when there is one — used to show the app's icon.
    public let bundlePath: String?
    public let audioPIDs: [Int32]
    public let isHeadless: Bool
    public let commandLine: String

    public init(ownerPID: Int32, name: String, bundlePath: String? = nil, audioPIDs: [Int32] = [], isHeadless: Bool = false, commandLine: String = "") {
        self.ownerPID = ownerPID
        self.name = name
        self.bundlePath = bundlePath
        self.audioPIDs = audioPIDs.isEmpty ? [ownerPID] : audioPIDs
        self.isHeadless = isHeadless
        self.commandLine = commandLine
    }
}

extension ProcessSnapshot {
    /// Path of the outermost `.app` bundle this executable lives in.
    var bundlePath: String? {
        guard let range = executablePath.firstRange(of: ".app/") else { return nil }
        return String(executablePath[..<range.lowerBound]) + ".app"
    }

    var displayName: String {
        guard let bundle = bundlePath, let last = bundle.split(separator: "/").last else { return name }
        return String(last.dropLast(".app".count))
    }

    /// An XPC service (`…/Foo.xpc/…`): a system helper that plays sound on behalf of an app.
    var isXPCService: Bool { executablePath.contains(".xpc/") }

    var isHeadless: Bool { arguments.contains { $0.hasPrefix("--headless") } }
}
