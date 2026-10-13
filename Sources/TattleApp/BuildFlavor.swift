import Foundation

/// "Dev" is decided by the bundle id the build script stamps in, never by a
/// compile flag, so a production bundle cannot carry dev behaviour by accident.
/// (Debug-only: `TATTLE_RENDER_PRODUCTION=1` renders the production look for README images.)
#if DEBUG
let isDevBuild = ProcessInfo.processInfo.environment["TATTLE_RENDER_PRODUCTION"] == nil
    && (Bundle.main.bundleIdentifier?.hasSuffix(".dev") ?? true)
#else
let isDevBuild = Bundle.main.bundleIdentifier?.hasSuffix(".dev") ?? true
#endif
