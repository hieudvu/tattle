import Foundation

/// "Dev" is decided by the bundle id the build script stamps in, never by a
/// compile flag, so a pro bundle cannot carry dev behaviour by accident.
/// (Debug-only: `TATTLE_RENDER_PRO=1` renders the pro look for README images.)
#if DEBUG
let isDevBuild = ProcessInfo.processInfo.environment["TATTLE_RENDER_PRO"] == nil
    && (Bundle.main.bundleIdentifier?.hasSuffix(".dev") ?? true)
#else
let isDevBuild = Bundle.main.bundleIdentifier?.hasSuffix(".dev") ?? true
#endif
