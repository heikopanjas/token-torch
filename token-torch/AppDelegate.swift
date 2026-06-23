import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: MenuBarViewModel!
    private var settingsController: SettingsWindowController!
    private var statusItemController: StatusItemController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            bootstrap()
        }
    }

    @MainActor
    private func bootstrap() {
        CredentialStoreMigration.migrateFromBurnIfNeeded()
        model = MenuBarViewModel()
        settingsController = SettingsWindowController(model: model)
        statusItemController = StatusItemController(
            model: model,
            settingsOpener: settingsController
        )
        setupMainMenu()
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
