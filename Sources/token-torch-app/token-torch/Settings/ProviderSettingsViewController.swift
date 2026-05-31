import AppKit
import TokenTorchCore

@MainActor
final class ProviderSettingsViewController: NSViewController {
    let provider: ProviderID

    private let keychain = AppKeychainStore.shared
    private let preferences = ProviderPreferencesStore.shared

    private var flags: ProviderModeFlags
    private var subscriptionToggle: NSButton!
    private var hintLabel: NSTextField!
    private var resetButton: NSButton!
    private var orgToggle: NSButton!
    private var adminKeyLabel: NSTextField!
    private var adminKeyField: NSSecureTextField!
    private var saveKeyButton: NSButton!
    private var clearKeyButton: NSButton!
    private var statusLabel: NSTextField!

    override var preferredContentSize: NSSize {
        get { isViewLoaded ? view.bounds.size : NSSize(width: SettingsStyle.paneWidth, height: preferredHeight) }
        set {}
    }

    private var preferredHeight: CGFloat {
        provider.supportsOrgBilling
            ? SettingsStyle.providerPaneHeight
            : SettingsStyle.providerQuotaOnlyPaneHeight
    }

    init(provider: ProviderID) {
        self.provider = provider
        self.flags = ProviderPreferencesStore.shared.load().flags(for: provider)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let w = SettingsStyle.paneWidth
        let h = preferredHeight
        let x = SettingsStyle.contentPadding
        let controlW = w - 2 * x
        var y = h - x - 22

        view = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))

        subscriptionToggle = NSButton(checkboxWithTitle: "Enable subscription quota", target: self, action: #selector(toggleChanged))
        subscriptionToggle.frame = NSRect(x: x, y: y, width: controlW, height: 22)
        subscriptionToggle.autoresizingMask = [.minYMargin, .width]
        view.addSubview(subscriptionToggle)

        y -= 8 + 44
        hintLabel = NSTextField(
            wrappingLabelWithString:
                "Clears \(AppBrand.displayName)'s copied subscription credentials only. Vendor app logins are not changed. Use after re-login in Claude Code, Codex CLI, or Cursor IDE."
        )
        hintLabel.frame = NSRect(x: x, y: y, width: controlW, height: 44)
        hintLabel.autoresizingMask = [.minYMargin, .width]
        hintLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        hintLabel.textColor = .secondaryLabelColor
        view.addSubview(hintLabel)

        y -= 16 + 22
        resetButton = NSButton(title: "Reset subscription credentials", target: self, action: #selector(resetCredentials))
        resetButton.bezelStyle = .rounded
        resetButton.frame = NSRect(x: x, y: y, width: 220, height: 22)
        resetButton.autoresizingMask = [.minYMargin]
        view.addSubview(resetButton)

        if provider.supportsOrgBilling {
            y -= 16 + 22
            orgToggle = NSButton(checkboxWithTitle: "Enable API billing", target: self, action: #selector(toggleChanged))
            orgToggle.frame = NSRect(x: x, y: y, width: controlW, height: 22)
            orgToggle.autoresizingMask = [.minYMargin, .width]
            view.addSubview(orgToggle)

            y -= 16 + 16
            adminKeyLabel = NSTextField(labelWithString: "Admin API key")
            adminKeyLabel.frame = NSRect(x: x, y: y, width: controlW, height: 16)
            adminKeyLabel.autoresizingMask = [.minYMargin, .width]
            view.addSubview(adminKeyLabel)

            y -= 4 + 22
            adminKeyField = NSSecureTextField(frame: NSRect(x: x, y: y, width: controlW, height: 22))
            adminKeyField.placeholderString = "Admin key"
            adminKeyField.autoresizingMask = [.minYMargin, .width]
            view.addSubview(adminKeyField)

            y -= 16 + 22
            saveKeyButton = NSButton(title: "Save key", target: self, action: #selector(saveKey))
            saveKeyButton.bezelStyle = .rounded
            saveKeyButton.frame = NSRect(x: x, y: y, width: 90, height: 22)
            saveKeyButton.autoresizingMask = [.minYMargin]
            view.addSubview(saveKeyButton)

            clearKeyButton = NSButton(title: "Clear key", target: self, action: #selector(clearKey))
            clearKeyButton.bezelStyle = .rounded
            clearKeyButton.frame = NSRect(x: x + 98, y: y, width: 90, height: 22)
            clearKeyButton.autoresizingMask = [.minYMargin]
            view.addSubview(clearKeyButton)
        }

        y -= 16 + 16
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.frame = NSRect(x: x, y: y, width: controlW, height: 16)
        statusLabel.autoresizingMask = [.minYMargin, .width]
        statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        statusLabel.textColor = .secondaryLabelColor
        view.addSubview(statusLabel)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        subscriptionToggle.state = flags.subscriptionQuotaEnabled ? .on : .off
        orgToggle?.state = flags.orgBillingEnabled ? .on : .off
        loadKeys()
    }

    @objc private func toggleChanged() {
        flags.subscriptionQuotaEnabled = subscriptionToggle.state == .on
        if let orgToggle {
            flags.orgBillingEnabled = orgToggle.state == .on
        }
        saveFlags()
    }

    private func saveFlags() {
        var prefs = preferences.load()
        prefs.setFlags(flags, for: provider)
        preferences.save(prefs)
    }

    private func loadKeys() {
        adminKeyField?.stringValue = (try? keychain.load(provider: provider, kind: .adminKey)) ?? ""
    }

    @objc private func saveKey() {
        guard let adminKeyField else { return }
        do {
            if adminKeyField.stringValue.isEmpty {
                try keychain.delete(provider: provider, kind: .adminKey)
            }
            else {
                try keychain.save(provider: provider, kind: .adminKey, value: adminKeyField.stringValue)
            }
            statusLabel.stringValue = "Saved."
        }
        catch {
            statusLabel.stringValue = Redaction.redactSecrets(error.localizedDescription)
        }
    }

    @objc private func clearKey() {
        try? keychain.delete(provider: provider, kind: .adminKey)
        adminKeyField?.stringValue = ""
        statusLabel.stringValue = "Key cleared."
    }

    @objc private func resetCredentials() {
        do {
            if flags.subscriptionQuotaEnabled {
                try VendorCredentialImporter.resetAndReimport(
                    provider: provider,
                    quotaEnabled: flags.subscriptionQuotaEnabled,
                    interactive: true
                )
                statusLabel.stringValue = "Credentials reset and re-imported."
            }
            else {
                try VendorCredentialImporter.reset(provider: provider)
                statusLabel.stringValue = "Stored credentials cleared."
            }
            NotificationCenter.default.post(name: AppActions.tokenTorchRefreshRequested, object: nil)
        }
        catch {
            statusLabel.stringValue = Redaction.redactSecrets(error.localizedDescription)
        }
    }
}
