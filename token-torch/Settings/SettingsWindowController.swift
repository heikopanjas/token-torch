import AppKit

extension NSToolbarItem.Identifier {
    fileprivate static let tokenTorchGeneral = NSToolbarItem.Identifier("tokentorch.settings.general")
    fileprivate static let tokenTorchInfo = NSToolbarItem.Identifier("tokentorch.settings.info")
    fileprivate static let tokenTorchClaude = NSToolbarItem.Identifier("tokentorch.settings.claude")
    fileprivate static let tokenTorchCodex = NSToolbarItem.Identifier("tokentorch.settings.codex")
    fileprivate static let tokenTorchCursor = NSToolbarItem.Identifier("tokentorch.settings.cursor")
    fileprivate static let tokenTorchCopilot = NSToolbarItem.Identifier("tokentorch.settings.copilot")
    fileprivate static let tokenTorchNotifications = NSToolbarItem.Identifier("tokentorch.settings.notifications")
    fileprivate static let tokenTorchAdvanced = NSToolbarItem.Identifier("tokentorch.settings.advanced")
}

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let model: MenuBarViewModel
    private let generalController: GeneralSettingsViewController
    private let infoController: InfoSettingsViewController
    private let claudeController: ProviderSettingsViewController
    private let codexController: ProviderSettingsViewController
    private let cursorController: ProviderSettingsViewController
    private let copilotController: ProviderSettingsViewController
    private let notificationsController: NotificationSettingsViewController
    private let advancedController: AdvancedSettingsViewController
    private var selectedIdentifier = NSToolbarItem.Identifier.tokenTorchGeneral

    init(model: MenuBarViewModel) {
        self.model = model
        generalController = GeneralSettingsViewController()
        infoController = InfoSettingsViewController()
        claudeController = ProviderSettingsViewController(provider: .claude)
        codexController = ProviderSettingsViewController(provider: .codex)
        cursorController = ProviderSettingsViewController(provider: .cursor)
        copilotController = ProviderSettingsViewController(provider: .copilot)
        notificationsController = NotificationSettingsViewController()
        advancedController = AdvancedSettingsViewController()

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
        AppActions.settingsWindow = window

        let toolbar = NSToolbar(identifier: "tokentorch.settings.toolbar")
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.delegate = self
        window.toolbar = toolbar
        toolbar.selectedItemIdentifier = .tokenTorchGeneral

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
        AppActions.settingsWindow = nil
        AppActions.deactivateAfterSettings()
    }

    @objc private func showGeneral() { switchToTab(.tokenTorchGeneral) }
    @objc private func showInfo() { switchToTab(.tokenTorchInfo) }
    @objc private func showClaude() { switchToTab(.tokenTorchClaude) }
    @objc private func showCodex() { switchToTab(.tokenTorchCodex) }
    @objc private func showCursor() { switchToTab(.tokenTorchCursor) }
    @objc private func showCopilot() { switchToTab(.tokenTorchCopilot) }
    @objc private func showNotifications() { switchToTab(.tokenTorchNotifications) }
    @objc private func showAdvanced() { switchToTab(.tokenTorchAdvanced) }

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
            SettingsStyle.infoPaneHeight,
            SettingsStyle.providerQuotaOnlyPaneHeight,
            SettingsStyle.providerPaneHeight,
            SettingsStyle.copilotPaneHeight,
            SettingsStyle.notificationsPaneHeight,
            SettingsStyle.advancedPaneHeight
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
            case .tokenTorchGeneral: generalController
            case .tokenTorchInfo: infoController
            case .tokenTorchClaude: claudeController
            case .tokenTorchCodex: codexController
            case .tokenTorchCursor: cursorController
            case .tokenTorchCopilot: copilotController
            case .tokenTorchNotifications: notificationsController
            case .tokenTorchAdvanced: advancedController
            default: generalController
        }
    }

    private static func toolbarSymbolIcon(_ symbolName: String, label: String) -> NSImage? {
        guard
            let image = NSImage(
                systemSymbolName: symbolName,
                accessibilityDescription: label
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
            case .tokenTorchGeneral: "General"
            case .tokenTorchInfo: "Info"
            case .tokenTorchClaude: "Claude"
            case .tokenTorchCodex: "Codex"
            case .tokenTorchCursor: "Cursor"
            case .tokenTorchCopilot: "Copilot"
            case .tokenTorchNotifications: "Notifications"
            case .tokenTorchAdvanced: "Advanced"
            default: "\(AppBrand.displayName) Settings"
        }
    }
}

extension SettingsWindowController: NSToolbarDelegate {
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .tokenTorchGeneral,
            .tokenTorchClaude,
            .tokenTorchCodex,
            .tokenTorchCursor,
            .tokenTorchCopilot,
            .tokenTorchNotifications,
            .tokenTorchAdvanced,
            .tokenTorchInfo
        ]
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
            case .tokenTorchGeneral:
                item.toolTip = "General"
                item.paletteLabel = "General"
                item.image = Self.toolbarSymbolIcon("gearshape", label: "General")
                item.action = #selector(showGeneral)
                item.target = self
            case .tokenTorchInfo:
                item.toolTip = "Info"
                item.paletteLabel = "Info"
                item.image = Self.toolbarSymbolIcon("info.circle", label: "Info")
                item.action = #selector(showInfo)
                item.target = self
            case .tokenTorchClaude:
                item.toolTip = "Claude"
                item.paletteLabel = "Claude"
                item.image = ProviderIcons.settingsToolbarImage(for: .claude)
                item.action = #selector(showClaude)
                item.target = self
            case .tokenTorchCodex:
                item.toolTip = "Codex"
                item.paletteLabel = "Codex"
                item.image = ProviderIcons.settingsToolbarImage(for: .codex)
                item.action = #selector(showCodex)
                item.target = self
            case .tokenTorchCursor:
                item.toolTip = "Cursor"
                item.paletteLabel = "Cursor"
                item.image = ProviderIcons.settingsToolbarImage(for: .cursor)
                item.action = #selector(showCursor)
                item.target = self
            case .tokenTorchCopilot:
                item.toolTip = "Copilot"
                item.paletteLabel = "Copilot"
                item.image = ProviderIcons.settingsToolbarImage(for: .copilot)
                item.action = #selector(showCopilot)
                item.target = self
            case .tokenTorchNotifications:
                item.toolTip = "Notifications"
                item.paletteLabel = "Notifications"
                item.image = Self.toolbarSymbolIcon("bell", label: "Notifications")
                item.action = #selector(showNotifications)
                item.target = self
            case .tokenTorchAdvanced:
                item.toolTip = "Advanced"
                item.paletteLabel = "Advanced"
                item.image = Self.toolbarSymbolIcon("wrench.and.screwdriver", label: "Advanced")
                item.action = #selector(showAdvanced)
                item.target = self
            default:
                return nil
        }
        return item
    }
}
