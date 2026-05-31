import AppKit
import TokenTorchCore

@MainActor
final class StatusItemController: NSObject {
    private let model: MenuBarViewModel
    private let menuBuilder = MenuBuilder()
    private let statusItem: NSStatusItem
    private var cachedMenu: NSMenu?
    private weak var settingsOpener: SettingsWindowController?

    init(model: MenuBarViewModel, settingsOpener: SettingsWindowController) {
        self.model = model
        self.settingsOpener = settingsOpener
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        menuBuilder.settingsTarget = self
        menuBuilder.refreshAction = #selector(refreshFromMenu)
        menuBuilder.openSettingsAction = #selector(openSettings)
        model.onUpdated = { [weak self] in
            self?.rebuildMenu()
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(displayChanged),
            name: AppActions.tokenTorchDisplayChanged,
            object: nil
        )
        configureStatusItemButton()
        rebuildMenu()
    }

    @objc private func displayChanged() {
        rebuildMenu()
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
        button.target = self
        button.action = #selector(showMenu)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem.isVisible = true
    }

    func rebuildMenu() {
        cachedMenu = menuBuilder.buildMenu(model: model)
    }

    @objc private func showMenu() {
        guard let button = statusItem.button else { return }
        let menu = cachedMenu ?? menuBuilder.buildMenu(model: model)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
    }

    @objc private func refreshFromMenu() {
        model.refresh()
    }

    @objc private func openSettings() {
        settingsOpener?.show()
    }
}
