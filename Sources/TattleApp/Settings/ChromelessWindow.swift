import AppKit
import SwiftUI

/// Chromeless window setup, copied from Continuo (which mirrors exelban/stats): a
/// plain titled window with a transparent titlebar + full-size content view and the
/// native traffic lights. That is all a `NavigationSplitView` sidebar needs to
/// render the System-Settings look: the frosted, elevated (on macOS 26 an inset
/// floating card) sidebar with the traffic lights on it. No hand-positioned buttons.
enum ChromelessWindowConfig {
    @MainActor
    static func apply(to window: NSWindow, showsMinimizeZoom: Bool, tallTitlebar: Bool = false) {
        window.styleMask.insert([.titled, .closable, .miniaturizable, .fullSizeContentView])
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        // An empty unified toolbar makes the titlebar taller so macOS places the
        // traffic lights lower/inset (System-Settings look). Installed ONCE: re-assigning
        // it on every apply recomputed the titlebar height and jumped the window.
        if tallTitlebar {
            if window.toolbar == nil {
                let toolbar = NSToolbar()
                window.toolbar = toolbar
                window.toolbarStyle = .unified
            }
        } else {
            window.toolbar = nil
        }
        window.isMovableByWindowBackground = true
        window.hasShadow = true
        // Non-opaque + clear so the native sidebar glass samples the desktop.
        window.isOpaque = false
        window.backgroundColor = .clear

        window.standardWindowButton(.closeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = !showsMinimizeZoom
        window.standardWindowButton(.zoomButton)?.isHidden = !showsMinimizeZoom

        // A non-opaque window drops the titlebar container (with the traffic lights)
        // behind the content; raise it, across a few layout ticks as AppKit reorders.
        raiseTrafficLights(window)
        for tick in 1...5 {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(24 * tick)) { [weak window] in
                guard let window else { return }
                raiseTrafficLights(window)
            }
        }
    }

    @MainActor
    private static func raiseTrafficLights(_ window: NSWindow) {
        guard let container = window.standardWindowButton(.closeButton)?.superview?.superview,
              let frameView = container.superview else { return }
        frameView.addSubview(container)
    }
}

/// Attach with `.background(ChromelessWindow(...))` on a window's root view.
struct ChromelessWindow: NSViewRepresentable {
    var showsMinimizeZoom = false
    var tallTitlebar = false

    func makeNSView(context: Context) -> NSView {
        let view = WindowAwareView()
        view.onMoveToWindow = { window in
            ChromelessWindowConfig.apply(to: window, showsMinimizeZoom: showsMinimizeZoom, tallTitlebar: tallTitlebar)
        }
        return view
    }

    // Deliberately no re-apply on update: moving the window between displays re-renders
    // SwiftUI, and re-touching the titlebar there jumped the window size.
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class WindowAwareView: NSView {
        var onMoveToWindow: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onMoveToWindow?(window) }
        }
    }
}
