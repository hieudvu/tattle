import Foundation
import Observation
import Sparkle

/// Sparkle's delegate callbacks, forwarded as a plain flag the panel can show.
final class UpdateFlagDelegate: NSObject, SPUUpdaterDelegate {
    var onChange: (@MainActor (Bool) -> Void)?
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Task { @MainActor in self.onChange?(true) }
    }
    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Task { @MainActor in self.onChange?(false) }
    }
}

/// Owns the one Sparkle updater. It only runs in a pro bundle that carries a feed:
/// `scripts/bundle.sh` stamps `SUFeedURL` and `SUPublicEDKey` into pro builds and
/// nothing else, so a dev build (or a plain `swift run`) never checks for updates.
@MainActor
@Observable
final class UpdateController {
    static let shared = UpdateController()

    private let controller: SPUStandardUpdaterController?
    private let flagDelegate = UpdateFlagDelegate()

    /// A newer version was found by the last check (the panel then offers "Update").
    private(set) var updateAvailable = false

    /// False in dev builds; the About pane hides the update controls then.
    var isAvailable: Bool { controller != nil }

    /// Mirrors Sparkle's `automaticallyChecksForUpdates` (persisted by Sparkle itself).
    var automaticallyChecks: Bool {
        didSet { controller?.updater.automaticallyChecksForUpdates = automaticallyChecks }
    }

    private init() {
        let hasFeed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") is String
        if !isDevBuild && hasFeed {
            controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: flagDelegate, userDriverDelegate: nil)
        } else {
            controller = nil
        }
        automaticallyChecks = controller?.updater.automaticallyChecksForUpdates ?? false
        flagDelegate.onChange = { [weak self] found in self?.updateAvailable = found }
    }

    /// Starts the updater at launch (the singleton is otherwise created lazily).
    func start() { _ = isAvailable }

    func checkForUpdates() { controller?.checkForUpdates(nil) }
}
