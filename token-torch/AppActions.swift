import AppKit
import Foundation

enum AppActions {
    static let openSettingsNotification = Notification.Name("tokentorch.openSettings")
    /// Opens Settings on the Info tab, which holds the app's About details and update controls.
    static let openAboutNotification = Notification.Name("tokentorch.openAbout")
    static let tokenTorchRefreshRequested = Notification.Name("tokentorch.refreshRequested")
    /// Posted when a display-only preference (e.g. currency) changes; rebuilds the menu without refetching.
    static let tokenTorchDisplayChanged = Notification.Name("tokentorch.displayChanged")

    static func requestOpenSettings() {
        NotificationCenter.default.post(name: openSettingsNotification, object: nil)
    }

    @MainActor
    static func quit() {
        NSApplication.shared.terminate(nil)
    }
}

@MainActor
extension AppActions {
    /// Settings window tracked so a finished update session does not hide the app while Settings stays open.
    static weak var settingsWindow: NSWindow?

    /// The app's updater, reachable from the notification delegate that brings a pending update to the front.
    static weak var updater: AppUpdater?

    /// True while Sparkle shows an update window, so closing Settings does not hide it.
    static var isUpdateSessionActive = false

    static func activateForSettings() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    static func deactivateAfterSettings() {
        Self.restoreAccessoryActivationIfNeeded()
    }

    /// "About…" in the status menu and the app menu opens Settings on the Info tab.
    static func showAbout() {
        NotificationCenter.default.post(name: Self.openAboutNotification, object: nil)
    }

    static func showPendingUpdate() {
        Self.updater?.checkForUpdates()
    }

    static func restoreAccessoryActivationIfNeeded() {
        guard Self.hasVisibleUserPanel == false else { return }
        NSApplication.shared.hide(nil)
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    private static var hasVisibleUserPanel: Bool {
        return Self.settingsWindow?.isVisible == true || Self.isUpdateSessionActive == true
    }
}
