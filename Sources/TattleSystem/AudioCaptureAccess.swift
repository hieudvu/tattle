import Foundation
import TattleCore

/// The "System Audio Recording" privacy grant, read through TCC's preflight check.
/// There is no public API for this one: AudioHardwareCreateProcessTap simply fails or
/// returns silence until the user allows it. The symbols are looked up at runtime, so a
/// macOS that drops them degrades to `.notDetermined` instead of failing to launch.
public enum AudioCaptureAccess {
    private typealias Preflight = @convention(c) (CFString, CFDictionary?) -> Int
    // The block must be `@escaping`: TCC keeps it and calls back after the prompt is answered. Without
    // it Swift treats the block as non-escaping and traps (EXC_BREAKPOINT) when TCC retains it.
    private typealias Request = @convention(c) (CFString, CFDictionary?, @escaping @convention(block) (Bool) -> Void) -> Void

    private static func symbol(_ name: String) -> UnsafeMutableRawPointer? {
        guard let tcc = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW) else { return nil }
        return dlsym(tcc, name)
    }

    public static func status() -> AudioCaptureStatus {
        guard let symbol = symbol("TCCAccessPreflight") else { return .notDetermined }
        let preflight = unsafeBitCast(symbol, to: Preflight.self)
        return AudioCaptureStatus(tccPreflight: preflight("kTCCServiceAudioCapture" as CFString, nil))
    }

    /// Shows the system prompt (only possible while the status is `.notDetermined`).
    public static func request(completion: @escaping @Sendable () -> Void) {
        guard let symbol = symbol("TCCAccessRequest") else { return completion() }
        let request = unsafeBitCast(symbol, to: Request.self)
        request("kTCCServiceAudioCapture" as CFString, nil) { _ in completion() }
    }
}
