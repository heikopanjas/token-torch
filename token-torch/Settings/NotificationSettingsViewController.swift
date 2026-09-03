import AppKit

@MainActor
final class NotificationSettingsViewController: SettingsPaneViewController {
    /// Only these two bands are offered as a starting point — `.low`/`.moderate` are still green and
    /// escalating past `.critical` isn't a thing, so those cases would be meaningless popup items.
    private static let startLevelOptions: [UsageLevel] = [.high, .severe]

    private let preferences = ProviderPreferencesStore.shared

    private var notifyToggle: NSButton!
    private var startLevelLabel: NSTextField!
    private var startLevelPopup: NSPopUpButton!
    private var startLevelHintLabel: NSTextField!

    override var paneHeight: CGFloat { SettingsStyle.notificationsPaneHeight }

    override func makeContentView() -> NSView {
        let w = SettingsStyle.paneWidth
        let h = self.paneHeight
        let x = SettingsStyle.contentPadding
        let controlW = w - 2 * x
        var y = h - SettingsStyle.contentPadding - 16

        let content = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))

        let sectionLabel = NSTextField(labelWithString: NotificationSettingsCopy.usageAlertsSectionTitle)
        sectionLabel.frame = NSRect(x: x, y: y, width: controlW, height: 16)
        sectionLabel.autoresizingMask = [.minYMargin, .width]
        content.addSubview(sectionLabel)

        y -= SettingsLayout.groupedControlGap + SettingsStyle.controlHeight
        notifyToggle = NSButton(
            checkboxWithTitle: "Notify when a usage limit runs high",
            target: self,
            action: #selector(notifyToggleChanged)
        )
        notifyToggle.frame = NSRect(x: x, y: y, width: controlW, height: SettingsStyle.controlHeight)
        notifyToggle.autoresizingMask = [.minYMargin, .width]
        content.addSubview(notifyToggle)

        y -= 16 + 16
        startLevelLabel = NSTextField(labelWithString: "Starting at")
        startLevelLabel.frame = NSRect(x: x, y: y, width: controlW, height: 16)
        startLevelLabel.autoresizingMask = [.minYMargin, .width]
        content.addSubview(startLevelLabel)

        y -= 4 + SettingsStyle.popupHeight
        startLevelPopup = NSPopUpButton(
            frame: NSRect(x: x, y: y, width: 220, height: SettingsStyle.popupHeight),
            pullsDown: false
        )
        startLevelPopup.autoresizingMask = [.minYMargin]
        for level in Self.startLevelOptions {
            startLevelPopup.addItem(withTitle: NotificationSettingsCopy.startLevelTitle(level))
        }
        startLevelPopup.target = self
        startLevelPopup.action = #selector(startLevelChanged)
        content.addSubview(startLevelPopup)

        startLevelHintLabel = SettingsLayout.makeHintLabel(NotificationSettingsCopy.notifyOnUsageThresholdHint)
        let hintHeight = SettingsLayout.measuredHintHeight(startLevelHintLabel, width: controlW)
        y -= SettingsLayout.groupedControlGap + hintHeight
        startLevelHintLabel.frame = NSRect(x: x, y: y, width: controlW, height: hintHeight)
        content.addSubview(startLevelHintLabel)

        return content
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        let prefs = preferences.load()
        notifyToggle.state = prefs.notifyOnUsageThreshold ? .on : .off
        if let index = Self.startLevelOptions.firstIndex(of: prefs.usageAlertStartLevel) {
            startLevelPopup.selectItem(at: index)
        }
        updateDependentControls()
    }

    @objc private func notifyToggleChanged() {
        var prefs = preferences.load()
        prefs.notifyOnUsageThreshold = notifyToggle.state == .on
        preferences.save(prefs)
        updateDependentControls()
    }

    @objc private func startLevelChanged() {
        let index = startLevelPopup.indexOfSelectedItem
        guard Self.startLevelOptions.indices.contains(index) else { return }
        var prefs = preferences.load()
        prefs.usageAlertStartLevel = Self.startLevelOptions[index]
        preferences.save(prefs)
    }

    private func updateDependentControls() {
        let enabled = notifyToggle.state == .on
        startLevelPopup.isEnabled = enabled
        let labelColor: NSColor = enabled ? .labelColor : .tertiaryLabelColor
        let hintColor: NSColor = enabled ? .secondaryLabelColor : .tertiaryLabelColor
        startLevelLabel.textColor = labelColor
        startLevelHintLabel.textColor = hintColor
    }
}
