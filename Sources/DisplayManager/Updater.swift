import AppKit
import Foundation
import Sparkle

/// Replaces Sparkle's raw failure alert with plain language.
///
/// A failed check nearly always means the feed could not be read — no network,
/// GitHub unreachable, or a release published without its appcast attached —
/// and Sparkle's stock text for that is a URL-loading error the user can do
/// nothing with. Say updates are unavailable and to try again later: true in
/// all of those cases, and without claiming the app is up to date when we do
/// not actually know that.
private final class FriendlyUserDriver: SPUStandardUserDriver {
    override func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        let zh = UserDefaults.standard.string(forKey: "language") == "zh"
        NSLog("DisplayManager: update check failed: \(error)")

        let alert = NSAlert()
        alert.messageText = zh ? "暂时无法获取更新" : "Update not available"
        alert.informativeText = zh
            ? "现在无法连接到更新服务器。请稍后再试，或从项目发布页下载最新版本。"
            : "Couldn't reach the update server. Please try again later, "
                + "or download the latest version from the releases page."
        alert.addButton(withTitle: zh ? "好" : "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
        acknowledgement()
    }
}

/// Updates via Sparkle, driven entirely by the user: nothing is checked,
/// downloaded or installed until "Check for Updates…" is clicked (see
/// SUEnableAutomaticChecks / SUAutomaticallyUpdate in Info.plist).
///
/// Installing through Sparkle matters because the running app performs the
/// swap itself. macOS never re-quarantines the bundle, so the Gatekeeper
/// approval only ever happens on the very first install.
enum Updater {
    private static let driver = FriendlyUserDriver(hostBundle: .main, delegate: nil)

    private static let updater = SPUUpdater(
        hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: nil)

    /// Start the updater at launch so a later check has a live controller.
    /// With automatic checks off this touches the network at no point.
    static func start() {
        do {
            try updater.start()
        } catch {
            NSLog("DisplayManager: updater failed to start: \(error)")
        }
    }

    /// "Check for Updates…" — the only thing that ever contacts the feed.
    /// Reports the outcome either way, including "you're up to date".
    static func checkNow() {
        updater.checkForUpdates()
    }

    /// The running version, for display next to the update button.
    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "—"
    }
}
