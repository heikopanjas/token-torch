import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var model: MenuBarViewModel!
    private var settingsController: SettingsWindowController!
    private var statusItemController: StatusItemController!
    private var appUpdater: AppUpdater!

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            bootstrap()
        }
    }

    @MainActor
    private func bootstrap() {
        CredentialStoreMigration.migrateFromBurnIfNeeded()
        UNUserNotificationCenter.current().delegate = self
        NotificationService.bootstrap()
        appUpdater = AppUpdater()
        AppActions.updater = appUpdater
        model = MenuBarViewModel()
        settingsController = SettingsWindowController(model: model, appUpdater: appUpdater)
        statusItemController = StatusItemController(
            model: model,
            settingsOpener: settingsController
        )
        setupMainMenu()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let identifier = response.notification.request.identifier
        completionHandler()
        guard identifier == AppNotification.updateAvailableIdentifier else { return }
        Task { @MainActor in
            AppActions.showPendingUpdate()
        }
    }

    @MainActor
    private func setupMainMenu() {
        let appMenu = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = appMenu

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        appMenu.addItem(settingsItem)

        let aboutItem = NSMenuItem(
            title: "About…",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        appMenu.addItem(aboutItem)

        appMenu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenu.addItem(quitItem)

        NSApp.mainMenu = NSMenu()
        NSApp.mainMenu?.addItem(appItem)
    }

    @objc private func openSettings() {
        AppActions.requestOpenSettings()
    }

    @MainActor @objc private func showAbout() {
        AppActions.showAbout()
    }
}
