/// Whether macOS lets Tattle tap other apps' audio (needed to mute an app).
public enum AudioCaptureStatus: Equatable, Sendable {
    case granted
    case denied
    /// macOS has not asked yet.
    case notDetermined

    /// Maps the result of TCC's preflight check: 0 allowed, 1 refused, anything else unasked.
    public init(tccPreflight result: Int) {
        switch result {
        case 0: self = .granted
        case 1: self = .denied
        default: self = .notDetermined
        }
    }
}
