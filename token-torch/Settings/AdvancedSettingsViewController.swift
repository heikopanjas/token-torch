import AppKit

@MainActor
final class AdvancedSettingsViewController: SettingsPaneViewController {
    private var sectionLabel: NSTextField!
    private var hintLabel: NSTextField!
    private var resetButton: NSButton!
    private var statusLabel: NSTextField!

    override var paneHeight: CGFloat { SettingsStyle.advancedPaneHeight }

    override func loadView() {
        let w = SettingsStyle.paneWidth
        let h = self.paneHeight
        let x = SettingsStyle.contentPadding
        let controlW = w - 2 * x
        var y = h - SettingsStyle.contentPadding - 16

        view = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))

        sectionLabel = NSTextField(labelWithString: "Reset Keychain")
        sectionLabel.frame = NSRect(x: x, y: y, width: controlW, height: 16)
        sectionLabel.autoresizingMask = [.minYMargin, .width]
        view.addSubview(sectionLabel)

        hintLabel = SettingsLayout.makeHintLabel(AdvancedSettingsCopy.resetKeychainHint)
        let hintHeight = SettingsLayout.measuredHintHeight(hintLabel, width: controlW)
        y -= 4 + hintHeight
        hintLabel.frame = NSRect(x: x, y: y, width: controlW, height: hintHeight)
        view.addSubview(hintLabel)

        y -= SettingsLayout.groupedControlGap + 22
        resetButton = NSButton(title: "Reset Keychain…", target: self, action: #selector(resetKeychain))
        resetButton.bezelStyle = .rounded
        resetButton.hasDestructiveAction = true
        resetButton.contentTintColor = .systemRed
        resetButton.frame = NSRect(x: x, y: y, width: 160, height: 22)
        resetButton.autoresizingMask = [.minYMargin]
        view.addSubview(resetButton)

        y -= 16 + 16
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.frame = NSRect(x: x, y: y, width: controlW, height: 16)
        statusLabel.autoresizingMask = [.minYMargin, .width]
        statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        statusLabel.textColor = .secondaryLabelColor
        view.addSubview(statusLabel)
    }

    @objc private func resetKeychain() {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Reset \(AppBrand.displayName)'s Keychain items?"
        alert.informativeText =
            "This permanently deletes \(AppBrand.displayName)'s stored admin API keys and imported subscription credentials. Vendor logins (Claude Code, Codex, Cursor) are not affected. This cannot be undone."
        let resetAction = alert.addButton(withTitle: "Reset Keychain")
        resetAction.hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")

        let respond: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.performReset()
        }

        if let window = view.window {
            alert.beginSheetModal(for: window, completionHandler: respond)
        }
        else {
            respond(alert.runModal())
        }
    }

    private func performReset() {
        let count = TokenTorchKeychainMaintenance.resetTokenTorchKeychain()
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue =
            count == 0
            ? "No \(AppBrand.displayName) Keychain items found."
            : "Deleted \(count) \(AppBrand.displayName) Keychain item\(count == 1 ? "" : "s")."
        NotificationCenter.default.post(name: AppActions.tokenTorchRefreshRequested, object: nil)
    }
}
