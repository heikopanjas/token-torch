import AppKit

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let model: MenuBarViewModel
    private let menuBuilder = MenuBuilder()
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var isMenuOpen = false
    private weak var settingsOpener: SettingsWindowController?

    init(model: MenuBarViewModel, settingsOpener: SettingsWindowController) {
        self.model = model
        self.settingsOpener = settingsOpener
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        menuBuilder.settingsTarget = self
        menuBuilder.refreshAction = #selector(refreshFromMenu)
        menuBuilder.openSettingsAction = #selector(openSettings)
        menuBuilder.aboutAction = #selector(showAboutFromMenu)
        model.onUpdated = { [weak self] in
            self?.refreshOpenMenu()
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(displayChanged),
            name: AppActions.tokenTorchDisplayChanged,
            object: nil
        )
        menu.delegate = self
        statusItem.menu = menu
        configureStatusItemButton()
        menuBuilder.populate(menu, model: model)
    }

    @objc private func displayChanged() {
        configureStatusItemButton()
        menuBuilder.populate(menu, model: model)
        refreshOpenMenu()
    }

    private func configureStatusItemButton() {
        guard let button = statusItem.button else { return }
        if let image = MenuBarStatusIcon.image() {
            button.image = image
            button.imagePosition = .imageOnly
            button.title = ""
        }
        else {
            button.image = nil
            button.title = AppBrand.displayName
        }
        button.toolTip = AppBrand.displayName
        statusItem.isVisible = true
    }

    /// Repopulates the live menu while it is open. Scheduled on the common run loop so the update
    /// is applied during menu tracking (AppKit runs a nested tracking loop that starves the default
    /// run loop mode, otherwise leaving the open menu frozen until it is dismissed and reopened).
    private func refreshOpenMenu() {
        guard isMenuOpen else { return }
        MenuTrackingRefresh.perform { [weak self] in
            guard let self, self.isMenuOpen else { return }
            self.menuBuilder.populate(self.menu, model: self.model)
            self.menu.update()
        }
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        menuBuilder.populate(menu, model: model)
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
    }

    // MARK: - Actions

    @objc private func refreshFromMenu() {
        model.refresh(interactive: true)
    }

    @objc private func openSettings() {
        settingsOpener?.show()
    }

    @objc private func showAboutFromMenu() {
        AppActions.showAbout()
    }
}

enum MenuTrackingRefresh {
    /// Schedules work on the common run loop modes so it runs while an NSMenu is being tracked.
    static func perform(_ block: @escaping @MainActor () -> Void) {
        RunLoop.main.perform(inModes: [.common]) {
            MainActor.assumeIsolated { block() }
        }
    }
}
