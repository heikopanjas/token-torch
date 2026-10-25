import AppKit
import Sparkle
import UserNotifications

/// Owns the app's single Sparkle updater.
///
/// Token Torch has no Dock icon, so an update found by a scheduled check could open its alert behind other
/// windows. Scheduled updates therefore use Sparkle's gentle reminders: unless Sparkle wants to show the update
/// in immediate focus (e.g. right after launch), a desktop notification announces it, and clicking the
/// notification brings Sparkle's window to the front through `checkForUpdates()`.
@MainActor
final class AppUpdater: NSObject {
    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: AppEnvironment.updatesEnabled,
        updaterDelegate: nil,
        userDriverDelegate: self
    )

    override init() {
        super.init()
        // Sparkle schedules its checks when the controller starts, so it is created with the app.
        _ = self.controller
    }

    /// Sparkle's updater: the Info tab binds to `canCheckForUpdates` and edits its automatic check settings.
    var updater: SPUUpdater {
        return self.controller.updater
    }

    /// Target for the Info tab's button; Sparkle's action validates against `canCheckForUpdates`.
    var updaterController: SPUStandardUpdaterController {
        return self.controller
    }

    /// Brings Sparkle's window to the front: a manual check, or the pending update after its notification is clicked.
    func checkForUpdates() {
        guard AppEnvironment.updatesEnabled == true else { return }
        AppActions.isUpdateSessionActive = true
        AppActions.activateForSettings()
        self.controller.checkForUpdates(nil)
    }
}

extension AppUpdater: @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool {
        return true
    }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        return immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if handleShowingUpdate == true {
            AppActions.isUpdateSessionActive = true
            AppActions.activateForSettings()
            return
        }
        NotificationService.post(.updateAvailable(version: update.displayVersionString))
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [AppNotification.updateAvailableIdentifier])
    }

    func standardUserDriverWillFinishUpdateSession() {
        AppActions.isUpdateSessionActive = false
        AppActions.restoreAccessoryActivationIfNeeded()
    }
}
