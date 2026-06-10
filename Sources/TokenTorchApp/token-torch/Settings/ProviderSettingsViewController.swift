import AppKit
import TokenTorchCore

@MainActor
final class ProviderSettingsViewController: NSViewController {
    let provider: ProviderID

    private let keychain = AppKeychainStore.shared
    private let preferences = ProviderPreferencesStore.shared

    private var hintLabel: NSTextField!
    private var resetButton: NSButton!
    private var additionalUsageToggle: NSButton?
    private var tokenLabel: NSTextField!
    private var tokenField: NSSecureTextField!
    private var saveTokenButton: NSButton!
    private var clearTokenButton: NSButton!
    private var adminKeyLabel: NSTextField!
    private var adminKeyField: NSSecureTextField!
    private var saveKeyButton: NSButton!
    private var clearKeyButton: NSButton!
    private var statusLabel: NSTextField!

    private var usesVendorOAuth: Bool { provider != .copilot }
    private var usesPersonalAccessToken: Bool { provider == .copilot }

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
        var y = h - x - 44

        view = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))

        if usesVendorOAuth {
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
        }

        if usesPersonalAccessToken {
            hintLabel = NSTextField(
                wrappingLabelWithString:
                    "Create a fine-grained GitHub Personal Access Token on your personal account with Account permission “Copilot requests” (Read-only) at github.com/settings/personal-access-tokens. Under Repository access, choose Public repositories only (or the most restrictive option available). Classic tokens (ghp_…) return HTTP 401. Token Torch only reads Copilot usage; it never writes back to GitHub."
            )
            hintLabel.frame = NSRect(x: x, y: y, width: controlW, height: 44)
            hintLabel.autoresizingMask = [.minYMargin, .width]
            hintLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            hintLabel.textColor = .secondaryLabelColor
            view.addSubview(hintLabel)

            y -= 16 + 16
            tokenLabel = NSTextField(labelWithString: "GitHub Personal Access Token")
            tokenLabel.frame = NSRect(x: x, y: y, width: controlW, height: 16)
            tokenLabel.autoresizingMask = [.minYMargin, .width]
            view.addSubview(tokenLabel)

            y -= 4 + 22
            tokenField = NSSecureTextField(frame: NSRect(x: x, y: y, width: controlW, height: 22))
            tokenField.placeholderString = "github_pat_…"
            tokenField.autoresizingMask = [.minYMargin, .width]
            view.addSubview(tokenField)

            y -= 16 + 22
            saveTokenButton = NSButton(title: "Save token", target: self, action: #selector(saveToken))
            saveTokenButton.bezelStyle = .rounded
            saveTokenButton.frame = NSRect(x: x, y: y, width: 100, height: 22)
            saveTokenButton.autoresizingMask = [.minYMargin]
            view.addSubview(saveTokenButton)

            clearTokenButton = NSButton(title: "Clear token", target: self, action: #selector(clearToken))
            clearTokenButton.bezelStyle = .rounded
            clearTokenButton.frame = NSRect(x: x + 108, y: y, width: 100, height: 22)
            clearTokenButton.autoresizingMask = [.minYMargin]
            view.addSubview(clearTokenButton)
        }

        if provider == .codex {
            y -= 16 + 22
            let toggle = NSButton(
                checkboxWithTitle: "Show additional model usage (e.g. Codex Spark)",
                target: self,
                action: #selector(additionalUsageChanged)
            )
            toggle.frame = NSRect(x: x, y: y, width: controlW, height: 22)
            toggle.autoresizingMask = [.minYMargin, .width]
            view.addSubview(toggle)
            additionalUsageToggle = toggle
        }

        if provider.supportsOrgBilling {
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
        additionalUsageToggle?.state = preferences.load().showAdditionalModelUsage ? .on : .off
        loadKeys()
    }

    @objc private func additionalUsageChanged() {
        var prefs = preferences.load()
        prefs.showAdditionalModelUsage = additionalUsageToggle?.state == .on
        preferences.save(prefs)
        NotificationCenter.default.post(name: AppActions.tokenTorchDisplayChanged, object: nil)
    }

    private func loadKeys() {
        adminKeyField?.stringValue = (try? keychain.load(provider: provider, kind: .adminKey)) ?? ""
        tokenField?.stringValue = (try? keychain.load(provider: provider, kind: .personalAccessToken)) ?? ""
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

    @objc private func saveToken() {
        guard let tokenField else { return }
        do {
            if tokenField.stringValue.isEmpty {
                try keychain.delete(provider: provider, kind: .personalAccessToken)
            }
            else {
                try keychain.save(provider: provider, kind: .personalAccessToken, value: tokenField.stringValue)
            }
            statusLabel.stringValue = "Saved."
        }
        catch {
            statusLabel.stringValue = Redaction.redactSecrets(error.localizedDescription)
        }
    }

    @objc private func clearToken() {
        try? keychain.delete(provider: provider, kind: .personalAccessToken)
        tokenField?.stringValue = ""
        statusLabel.stringValue = "Token cleared."
    }

    @objc private func resetCredentials() {
        let subscriptionEnabled = preferences.load().flags(for: provider).subscriptionQuotaEnabled
        do {
            if subscriptionEnabled {
                try VendorCredentialImporter.resetAndReimport(
                    provider: provider,
                    quotaEnabled: subscriptionEnabled,
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
