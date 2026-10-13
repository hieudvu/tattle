import Foundation

/// "Dev" is decided by the bundle id the build script stamps in, never by a
/// compile flag, so a pro bundle cannot carry dev behaviour by accident.
let isDevBuild = Bundle.main.bundleIdentifier?.hasSuffix(".dev") ?? true
