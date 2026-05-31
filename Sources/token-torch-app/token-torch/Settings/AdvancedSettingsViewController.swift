import AppKit
import TokenTorchCore

@MainActor
final class AdvancedSettingsViewController: NSViewController {
    private var headerLabel: NSTextField!
    private var infoLabel: NSTextField!
    private var resetButton: NSButton!
    private var statusLabel: NSTextField!

    override var preferredContentSize: NSSize {
        get { isViewLoaded ? view.bounds.size : NSSize(width: SettingsStyle.paneWidth, height: SettingsStyle.advancedPaneHeight) }
        set {}
    }

    override func loadView() {
        let w = SettingsStyle.paneWidth
        let h = SettingsStyle.advancedPaneHeight
        let x = SettingsStyle.contentPadding
        let controlW = w - 2 * x
        var y = h - x - 16

        view = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))

        headerLabel = NSTextField(labelWithString: "Reset Keychain")
        headerLabel.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        headerLabel.frame = NSRect(x: x, y: y, width: controlW, height: 16)
        headerLabel.autoresizingMask = [.minYMargin, .width]
        view.addSubview(headerLabel)

        y -= 8 + 88
        infoLabel = NSTextField(
            wrappingLabelWithString:
                "Permanently deletes every Keychain item \(AppBrand.displayName) created — the admin API keys you entered and the imported subscription OAuth copies (services starting with “com.tokentorch.”).\n\nVendor logins for Claude Code, Codex CLI, and Cursor are NOT touched. After resetting, re-enter admin keys and re-import subscription credentials from each provider tab."
        )
        infoLabel.frame = NSRect(x: x, y: y, width: controlW, height: 88)
        infoLabel.autoresizingMask = [.minYMargin, .width]
        infoLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        infoLabel.textColor = .secondaryLabelColor
        view.addSubview(infoLabel)

        y -= 16 + 22
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
        alert.messageText = "Reset \(AppBrand.displayName)’s Keychain items?"
        alert.informativeText =
            "This permanently deletes \(AppBrand.displayName)’s stored admin API keys and imported subscription credentials. Vendor logins (Claude Code, Codex, Cursor) are not affected. This cannot be undone."
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
