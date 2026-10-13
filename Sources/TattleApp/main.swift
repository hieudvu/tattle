import AppKit

#if DEBUG
renderSettingsIfRequested()
renderStoryIfRequested()
renderPanelIfRequested()  // dev aid: writes PNGs and exits when TATTLE_RENDER_PANEL is set
#endif

// Plain AppKit entry point: the status item and popover are created exactly once
// in AppDelegate. (SwiftUI's MenuBarExtra window kept a stale height when its
// content shrank, leaving blank bands above and below the panel.)
let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
