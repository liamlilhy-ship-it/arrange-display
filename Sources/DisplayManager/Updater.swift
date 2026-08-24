import Foundation
import Sparkle

/// Updates via Sparkle, driven entirely by the user: nothing is checked,
/// downloaded or installed until "Check for Updates…" is clicked (see
/// SUEnableAutomaticChecks / SUAutomaticallyUpdate in Info.plist).
///
/// Installing through Sparkle matters because the running app performs the
/// swap itself. macOS never re-quarantines the bundle, so the Gatekeeper
/// approval only ever happens on the very first install.
enum Updater {
    private static let controller = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    /// Start the updater at launch so a later check has a live controller.
    /// With automatic checks off this touches the network at no point.
    static func start() {
        _ = controller
    }

    /// "Check for Updates…" — the only thing that ever contacts the feed.
    /// Reports the outcome either way, including "you're up to date".
    static func checkNow() {
        controller.updater.checkForUpdates()
    }

    /// The running version, for display next to the update button.
    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "—"
    }
}
