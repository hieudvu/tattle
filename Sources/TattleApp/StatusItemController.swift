import AppKit
import SwiftUI
import TattleCore

/// The menu bar item and its popover. Created once. The icon is set straight on
/// the status button (no SwiftUI invalidation per animation frame), and the
/// popover sizes itself to the SwiftUI content as it grows and shrinks.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let model: NoiseModel
    private let preferences = UserDefaultsPreferencesStore()
    private var defaultsObserver: NSObjectProtocol?

    init(model: NoiseModel) {
        self.model = model
        super.init()
        popover.delegate = self

        let host = NSHostingController(rootView: NoisePanel(model: model))
        host.sizingOptions = [.preferredContentSize]  // popover follows the content's height
        popover.contentViewController = host
        popover.behavior = .transient                 // closes on an outside click
        popover.animates = true

        if let button = statusItem.button {
            button.image = model.menuBarImage
            button.target = self
            button.action = #selector(toggle(_:))
            button.setAccessibilityLabel("Tattle")
            button.toolTip = "Tattle"
        }
        applyVisibility()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.applyVisibility() } }
        model.onMenuBarVisibilityChange = { [weak self] visible in self?.statusItem.isVisible = visible }
        statusItem.isVisible = UserDefaultsPreferencesStore().get(PreferenceKeys.showMenuBarIcon)
        model.onDismissPanel = { [weak self] in self?.popover.performClose(nil) }
        model.onMenuBarImageChange = { [weak self] image in
            self?.statusItem.button?.image = image
        }
    }

    /// Settings ▸ General ▸ "Show menu bar icon". A hidden item can't show the popover.
    private func applyVisibility() {
        let visible = preferences.get(PreferenceKeys.showMenuBarIcon)
        guard statusItem.isVisible != visible else { return }
        if !visible { popover.performClose(nil) }
        statusItem.isVisible = visible
    }

    @objc private func toggle(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()  // so ⌘, and ⌘Q work
        }
    }

    func popoverWillShow(_ notification: Notification) { model.setPanelOpen(true) }
    func popoverDidClose(_ notification: Notification) { model.setPanelOpen(false) }
}
