import AppKit
import Sparkle

/// Settings › Info: the app's About details and Sparkle's update controls. "About…" in the menus opens this tab.
@MainActor
final class InfoSettingsViewController: SettingsPaneViewController {
    private static let iconSide: CGFloat = 64
    private static let iconTextGap: CGFloat = 16
    private static let checkForUpdatesButtonWidth: CGFloat = 170

    private let appUpdater: AppUpdater

    private var checkForUpdatesButton: NSButton!
    private var automaticChecksToggle: NSButton!
    private var automaticDownloadsToggle: NSButton!

    init(appUpdater: AppUpdater) {
        self.appUpdater = appUpdater
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var paneHeight: CGFloat { SettingsStyle.infoPaneHeight }

    override func makeContentView() -> NSView {
        let w = SettingsStyle.paneWidth
        let h = self.paneHeight
        let x = SettingsStyle.contentPadding
        let controlW = w - 2 * x
        var y = h - SettingsStyle.contentPadding - Self.iconSide

        let content = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))

        let iconView = NSImageView(frame: NSRect(x: x, y: y, width: Self.iconSide, height: Self.iconSide))
        iconView.image = NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.autoresizingMask = [.minYMargin]
        content.addSubview(iconView)

        let textX = x + Self.iconSide + Self.iconTextGap
        let textW = controlW - Self.iconSide - Self.iconTextGap
        let nameLabel = NSTextField(labelWithString: AppBrand.displayName)
        nameLabel.font = .boldSystemFont(ofSize: 18)
        nameLabel.frame = NSRect(x: textX, y: y + 38, width: textW, height: 24)
        nameLabel.autoresizingMask = [.minYMargin, .width]
        content.addSubview(nameLabel)

        let versionLabel = NSTextField(labelWithString: InfoSettingsCopy.versionLine())
        versionLabel.frame = NSRect(x: textX, y: y + 18, width: textW, height: SettingsStyle.labelHeight)
        versionLabel.autoresizingMask = [.minYMargin, .width]
        versionLabel.isSelectable = true
        content.addSubview(versionLabel)

        let copyrightLabel = NSTextField(labelWithString: InfoSettingsCopy.copyrightLine())
        copyrightLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        copyrightLabel.textColor = .secondaryLabelColor
        copyrightLabel.frame = NSRect(x: textX, y: y, width: textW, height: SettingsStyle.labelHeight)
        copyrightLabel.autoresizingMask = [.minYMargin, .width]
        content.addSubview(copyrightLabel)

        y -= 32 + SettingsStyle.labelHeight
        content.addSubview(SettingsLayout.makeSectionLabel(InfoSettingsCopy.updatesSectionTitle, width: controlW, y: y))

        y -= SettingsLayout.groupedControlGap + SettingsStyle.controlHeight
        self.checkForUpdatesButton = SettingsLayout.makeRoundedButton(
            title: InfoSettingsCopy.checkForUpdatesTitle,
            width: Self.checkForUpdatesButtonWidth,
            x: x,
            y: y,
            target: self,
            action: #selector(self.checkForUpdates)
        )
        // Sparkle reports whether a check can start now; it stays false in Debug builds, where the updater never starts.
        self.checkForUpdatesButton.bind(.enabled, to: self.appUpdater.updater, withKeyPath: #keyPath(SPUUpdater.canCheckForUpdates))
        content.addSubview(self.checkForUpdatesButton)

        y -= 12 + SettingsStyle.controlHeight
        self.automaticChecksToggle = SettingsLayout.makeCheckbox(
            title: InfoSettingsCopy.automaticChecksTitle,
            width: controlW,
            y: y,
            target: self,
            action: #selector(self.automaticChecksChanged)
        )
        content.addSubview(self.automaticChecksToggle)

        y -= 4 + SettingsStyle.controlHeight
        self.automaticDownloadsToggle = SettingsLayout.makeCheckbox(
            title: InfoSettingsCopy.automaticDownloadsTitle,
            width: controlW,
            y: y,
            target: self,
            action: #selector(self.automaticDownloadsChanged)
        )
        content.addSubview(self.automaticDownloadsToggle)

        let hintLabel = SettingsLayout.makeHintLabel(InfoSettingsCopy.updatesHint)
        let hintHeight = SettingsLayout.measuredHintHeight(hintLabel, width: controlW)
        y -= SettingsLayout.groupedControlGap + hintHeight
        hintLabel.frame = NSRect(x: x, y: y, width: controlW, height: hintHeight)
        content.addSubview(hintLabel)

        return content
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        self.refreshUpdatePreferences()
    }

    @objc private func checkForUpdates() {
        self.appUpdater.checkForUpdates()
    }

    @objc private func automaticChecksChanged() {
        self.appUpdater.updater.automaticallyChecksForUpdates = self.automaticChecksToggle.state == .on
        self.refreshUpdatePreferences()
    }

    @objc private func automaticDownloadsChanged() {
        self.appUpdater.updater.automaticallyDownloadsUpdates = self.automaticDownloadsToggle.state == .on
        self.refreshUpdatePreferences()
    }

    /// Reads Sparkle's own persisted settings, so the toggles and Sparkle's second-launch prompt never disagree.
    private func refreshUpdatePreferences() {
        let updater = self.appUpdater.updater
        let enabled = AppEnvironment.updatesEnabled
        self.automaticChecksToggle.state = updater.automaticallyChecksForUpdates == true ? .on : .off
        self.automaticDownloadsToggle.state = updater.automaticallyDownloadsUpdates == true ? .on : .off
        self.automaticChecksToggle.isEnabled = enabled
        self.automaticDownloadsToggle.isEnabled = enabled == true && updater.automaticallyChecksForUpdates == true
    }
}
