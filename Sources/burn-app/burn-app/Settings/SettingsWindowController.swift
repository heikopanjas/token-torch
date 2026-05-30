import AppKit

extension NSToolbarItem.Identifier {
    fileprivate static let burnGeneral = NSToolbarItem.Identifier("burn.settings.general")
    fileprivate static let burnClaude = NSToolbarItem.Identifier("burn.settings.claude")
    fileprivate static let burnCodex = NSToolbarItem.Identifier("burn.settings.codex")
    fileprivate static let burnCursor = NSToolbarItem.Identifier("burn.settings.cursor")
}

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let model: MenuBarViewModel
    private let generalController: GeneralSettingsViewController
    private let claudeController: ProviderSettingsViewController
    private let codexController: ProviderSettingsViewController
    private let cursorController: ProviderSettingsViewController
    private var selectedIdentifier = NSToolbarItem.Identifier.burnGeneral

    init(model: MenuBarViewModel) {
        self.model = model
        generalController = GeneralSettingsViewController()
        claudeController = ProviderSettingsViewController(provider: .claude)
        codexController = ProviderSettingsViewController(provider: .codex)
        cursorController = ProviderSettingsViewController(provider: .cursor)

        super.init(
            window: NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: SettingsStyle.paneWidth, height: 72),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            ))

        guard let window else { return }
        generalController.onRefreshIntervalChanged = { [weak model] in
            model?.rescheduleTimer()
        }
        window.title = "General"
        window.toolbarStyle = .preference
        window.contentViewController = generalController
        window.minSize = NSSize(
            width: SettingsStyle.paneWidth,
            height: minContentHeight + 80
        )
        window.delegate = self

        let toolbar = NSToolbar(identifier: "burn.settings.toolbar")
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.delegate = self
        window.toolbar = toolbar
        toolbar.selectedItemIdentifier = .burnGeneral

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openFromNotification),
            name: AppActions.openSettingsNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        AppActions.activateForSettings()
        let vc = viewController(for: selectedIdentifier)
        fitWindow(to: vc, centerOnScreen: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func openFromNotification() {
        show()
    }

    func windowWillClose(_ notification: Notification) {
        AppActions.deactivateAfterSettings()
    }

    @objc private func showGeneral() { switchToTab(.burnGeneral) }
    @objc private func showClaude() { switchToTab(.burnClaude) }
    @objc private func showCodex() { switchToTab(.burnCodex) }
    @objc private func showCursor() { switchToTab(.burnCursor) }

    private func switchToTab(_ identifier: NSToolbarItem.Identifier) {
        guard identifier != selectedIdentifier, let window else { return }
        selectedIdentifier = identifier
        let newVC = viewController(for: identifier)
        if let contentBounds = window.contentView?.bounds {
            _ = newVC.view
            newVC.view.frame = contentBounds
        }
        window.contentViewController = newVC
        window.title = title(for: identifier)
        window.toolbar?.selectedItemIdentifier = identifier
        fitWindow(to: newVC, centerOnScreen: false)
    }

    private var minContentHeight: CGFloat {
        min(
            SettingsStyle.generalPaneHeight,
            SettingsStyle.providerQuotaOnlyPaneHeight,
            SettingsStyle.providerPaneHeight
        )
    }

    private func fitWindow(to viewController: NSViewController, centerOnScreen: Bool) {
        guard let window else { return }
        _ = viewController.view
        let contentSize = viewController.preferredContentSize
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize))

        let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? frame
        let anchorX = centerOnScreen ? visible.midX : window.frame.midX
        let anchorY = centerOnScreen ? visible.midY : window.frame.midY
        frame.origin.x = (anchorX - frame.width / 2).rounded()
        frame.origin.y = (anchorY - frame.height / 2).rounded()
        frame = frame.intersection(visible)

        window.setFrame(frame, display: false)
    }

    private func viewController(for identifier: NSToolbarItem.Identifier) -> NSViewController {
        switch identifier {
            case .burnGeneral: generalController
            case .burnClaude: claudeController
            case .burnCodex: codexController
            case .burnCursor: cursorController
            default: generalController
        }
    }

    private static func toolbarGearIcon() -> NSImage? {
        guard
            let image = NSImage(
                systemSymbolName: "gearshape",
                accessibilityDescription: "General"
            )
        else {
            return nil
        }
        let config = NSImage.SymbolConfiguration(
            pointSize: SettingsStyle.toolbarIconPointSize,
            weight: .regular
        )
        return image.withSymbolConfiguration(config)
    }

    private func title(for identifier: NSToolbarItem.Identifier) -> String {
        switch identifier {
            case .burnGeneral: "General"
            case .burnClaude: "Claude"
            case .burnCodex: "Codex"
            case .burnCursor: "Cursor"
            default: "burn Settings"
        }
    }
}

extension SettingsWindowController: NSToolbarDelegate {
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.burnGeneral, .burnClaude, .burnCodex, .burnCursor]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        switch itemIdentifier {
            case .burnGeneral:
                item.toolTip = "General"
                item.paletteLabel = "General"
                item.image = Self.toolbarGearIcon()
                item.action = #selector(showGeneral)
                item.target = self
            case .burnClaude:
                item.toolTip = "Claude"
                item.paletteLabel = "Claude"
                item.image = ProviderIcons.settingsToolbarImage(for: .claude)
                item.action = #selector(showClaude)
                item.target = self
            case .burnCodex:
                item.toolTip = "Codex"
                item.paletteLabel = "Codex"
                item.image = ProviderIcons.settingsToolbarImage(for: .codex)
                item.action = #selector(showCodex)
                item.target = self
            case .burnCursor:
                item.toolTip = "Cursor"
                item.paletteLabel = "Cursor"
                item.image = ProviderIcons.settingsToolbarImage(for: .cursor)
                item.action = #selector(showCursor)
                item.target = self
            default:
                return nil
        }
        return item
    }
}
