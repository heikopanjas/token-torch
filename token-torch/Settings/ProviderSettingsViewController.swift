import AppKit

@MainActor
final class ProviderSettingsViewController: SettingsPaneViewController {
    let provider: ProviderID

    private let keychain = AppKeychainStore.shared
    private let preferences = ProviderPreferencesStore.shared

    private static let sectionGap: CGFloat = 24

    private var resetHintLabel: NSTextField!
    private var resetButton: NSButton!
    private var tokenHintLabel: NSTextField!
    private var additionalUsageToggle: NSButton?
    private var additionalUsageHintLabel: NSTextField?
    private var cursorValueRowsToggle: NSButton?
    private var cursorValueRowsHintLabel: NSTextField?
    private var automaticRepairToggle: NSButton?
    private var notifyRepairFailureToggle: NSButton?
    private var notifyRepairHintLabel: NSTextField?
    private var claudeCLIPathLabel: NSTextField?
    private var claudeCLIPathHintLabel: NSTextField?
    private var claudeCLIPathField: NSTextField?
    private var claudeCLIPathBrowseButton: NSButton?
    private var tokenLabel: NSTextField!
    private var tokenField: NSSecureTextField!
    private var saveTokenButton: NSButton!
    private var clearTokenButton: NSButton!
    private var adminKeyLabel: NSTextField!
    private var adminKeyHintLabel: NSTextField?
    private var adminKeyField: NSSecureTextField!
    private var saveKeyButton: NSButton!
    private var clearKeyButton: NSButton!
    private var statusLabel: NSTextField!

    private var usesVendorOAuth: Bool { provider != .copilot }
    private var usesPersonalAccessToken: Bool { provider == .copilot }

    override var paneHeight: CGFloat {
        switch self.provider {
            case .codex: return SettingsStyle.providerPaneHeight + 40
            case .copilot: return SettingsStyle.copilotPaneHeight
            case .claude: return SettingsStyle.claudePaneHeight
            case .cursor: return SettingsStyle.providerQuotaOnlyPaneHeight
        }
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
        let h = self.paneHeight
        let x = SettingsStyle.contentPadding
        let controlW = w - 2 * x
        var y = h - SettingsStyle.contentPadding - 22

        view = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))

        if usesVendorOAuth == true {
            resetButton = NSButton(title: "Reset subscription credentials", target: self, action: #selector(resetCredentials))
            resetButton.bezelStyle = .rounded
            resetButton.frame = NSRect(x: x, y: y, width: 240, height: 22)
            resetButton.autoresizingMask = [.minYMargin]
            view.addSubview(resetButton)

            resetHintLabel = SettingsLayout.makeHintLabel(ProviderSettingsCopy.resetHint(for: provider))
            let resetHintHeight = SettingsLayout.measuredHintHeight(resetHintLabel, width: controlW)
            y -= SettingsLayout.groupedControlGap + resetHintHeight
            resetHintLabel.frame = NSRect(x: x, y: y, width: controlW, height: resetHintHeight)
            view.addSubview(resetHintLabel)
        }

        if provider == .claude {
            y -= Self.sectionGap + 16
            let sectionLabel = NSTextField(labelWithString: ProviderSettingsCopy.claudeBackgroundRepairSectionTitle())
            sectionLabel.frame = NSRect(x: x, y: y, width: controlW, height: 16)
            sectionLabel.autoresizingMask = [.minYMargin, .width]
            view.addSubview(sectionLabel)

            y -= SettingsLayout.groupedControlGap + 22
            let repairToggle = NSButton(
                checkboxWithTitle: "Automatically repair credentials in the background",
                target: self,
                action: #selector(automaticRepairChanged)
            )
            repairToggle.frame = NSRect(x: x, y: y, width: controlW, height: 22)
            repairToggle.autoresizingMask = [.minYMargin, .width]
            view.addSubview(repairToggle)
            automaticRepairToggle = repairToggle

            let repairHint = SettingsLayout.makeHintLabel(ProviderSettingsCopy.claudeAutomaticRepairHint())
            let repairHintHeight = SettingsLayout.measuredHintHeight(repairHint, width: controlW)
            y -= SettingsLayout.groupedControlGap + repairHintHeight
            repairHint.frame = NSRect(x: x, y: y, width: controlW, height: repairHintHeight)
            view.addSubview(repairHint)

            y -= Self.sectionGap + 22
            let notifyToggle = NSButton(
                checkboxWithTitle: "Notify me when background credential repair fails",
                target: self,
                action: #selector(notifyRepairFailureChanged)
            )
            notifyToggle.frame = NSRect(x: x, y: y, width: controlW, height: 22)
            notifyToggle.autoresizingMask = [.minYMargin, .width]
            view.addSubview(notifyToggle)
            notifyRepairFailureToggle = notifyToggle

            let notifyHint = SettingsLayout.makeHintLabel(ProviderSettingsCopy.claudeRepairFailureNotificationHint())
            let notifyHintHeight = SettingsLayout.measuredHintHeight(notifyHint, width: controlW)
            y -= SettingsLayout.groupedControlGap + notifyHintHeight
            notifyHint.frame = NSRect(x: x, y: y, width: controlW, height: notifyHintHeight)
            view.addSubview(notifyHint)
            notifyRepairHintLabel = notifyHint

            y -= Self.sectionGap + 16
            let pathLabel = NSTextField(labelWithString: "Claude CLI path")
            pathLabel.frame = NSRect(x: x, y: y, width: controlW, height: 16)
            pathLabel.autoresizingMask = [.minYMargin, .width]
            view.addSubview(pathLabel)
            claudeCLIPathLabel = pathLabel

            let pathHint = SettingsLayout.makeHintLabel(ProviderSettingsCopy.claudeCLIPathHint())
            let pathHintHeight = SettingsLayout.measuredHintHeight(pathHint, width: controlW)
            y -= 4 + pathHintHeight
            pathHint.frame = NSRect(x: x, y: y, width: controlW, height: pathHintHeight)
            view.addSubview(pathHint)
            claudeCLIPathHintLabel = pathHint

            y -= SettingsLayout.groupedControlGap + 22
            let browseWidth: CGFloat = 88
            let pathField = NSTextField(
                frame: NSRect(x: x, y: y, width: controlW - browseWidth - 8, height: 22)
            )
            pathField.placeholderString = "/opt/homebrew/bin/claude"
            pathField.autoresizingMask = [.minYMargin, .width]
            pathField.delegate = self
            view.addSubview(pathField)
            claudeCLIPathField = pathField

            let browseButton = NSButton(title: "Browse…", target: self, action: #selector(browseClaudeCLIPath))
            browseButton.bezelStyle = .rounded
            browseButton.frame = NSRect(x: w - x - browseWidth, y: y, width: browseWidth, height: 22)
            browseButton.autoresizingMask = [.minYMargin, .minXMargin]
            view.addSubview(browseButton)
            claudeCLIPathBrowseButton = browseButton
        }

        if self.usesPersonalAccessToken == true {
            y = h - SettingsStyle.contentPadding - SettingsStyle.labelHeight
            let tokenSection = SettingsLayout.addSecureFieldSection(
                to: self.view,
                title: "GitHub Personal Access Token",
                hint: ProviderSettingsCopy.personalAccessTokenHint(),
                placeholder: "github_pat_…",
                saveTitle: "Save token",
                clearTitle: "Clear token",
                saveButtonWidth: 100,
                clearButtonWidth: 100,
                width: controlW,
                x: x,
                y: y,
                target: self,
                saveAction: #selector(self.saveToken),
                clearAction: #selector(self.clearToken)
            )
            self.tokenLabel = tokenSection.titleLabel
            self.tokenHintLabel = tokenSection.hintLabel!
            self.tokenField = tokenSection.field
            self.saveTokenButton = tokenSection.saveButton
            self.clearTokenButton = tokenSection.clearButton
            y = tokenSection.newY
        }

        if self.provider.supportsOrgBilling == true {
            y -= Self.sectionGap + SettingsStyle.labelHeight
            let adminHint = ProviderSettingsCopy.adminKeyHint(for: self.provider)
            let adminSection = SettingsLayout.addSecureFieldSection(
                to: self.view,
                title: "Admin API key",
                hint: adminHint,
                placeholder: "Admin key",
                saveTitle: "Save key",
                clearTitle: "Clear key",
                saveButtonWidth: 90,
                clearButtonWidth: 90,
                width: controlW,
                x: x,
                y: y,
                target: self,
                saveAction: #selector(self.saveKey),
                clearAction: #selector(self.clearKey)
            )
            self.adminKeyLabel = adminSection.titleLabel
            self.adminKeyHintLabel = adminSection.hintLabel
            self.adminKeyField = adminSection.field
            self.saveKeyButton = adminSection.saveButton
            self.clearKeyButton = adminSection.clearButton
            y = adminSection.newY
        }

        if self.provider == .codex {
            let codexToggle = SettingsLayout.addCheckboxWithHint(
                to: self.view,
                title: "Show additional model usage (e.g. Codex Spark)",
                hint: ProviderSettingsCopy.additionalModelUsageHint(),
                width: controlW,
                x: x,
                y: y,
                sectionGapAbove: Self.sectionGap,
                target: self,
                action: #selector(self.additionalUsageChanged)
            )
            self.additionalUsageToggle = codexToggle.checkbox
            self.additionalUsageHintLabel = codexToggle.hintLabel
            y = codexToggle.newY
        }

        if self.provider == .cursor {
            let cursorToggle = SettingsLayout.addCheckboxWithHint(
                to: self.view,
                title: "Show Total usage value and Bonus",
                hint: ProviderSettingsCopy.cursorValueRowsHint(),
                width: controlW,
                x: x,
                y: y,
                sectionGapAbove: Self.sectionGap,
                target: self,
                action: #selector(self.cursorValueRowsChanged)
            )
            self.cursorValueRowsToggle = cursorToggle.checkbox
            self.cursorValueRowsHintLabel = cursorToggle.hintLabel
            y = cursorToggle.newY
        }

        y -= SettingsStyle.labelHeight + SettingsStyle.labelHeight
        self.statusLabel = SettingsLayout.makeStatusLabel(width: controlW, y: y)
        self.view.addSubview(self.statusLabel)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        let prefs = preferences.load()
        additionalUsageToggle?.state = prefs.showAdditionalModelUsage ? .on : .off
        cursorValueRowsToggle?.state = prefs.showCursorUsageValueAndBonus ? .on : .off
        automaticRepairToggle?.state = prefs.claudeAutomaticRepair ? .on : .off
        notifyRepairFailureToggle?.state = prefs.notifyOnRepairFailure ? .on : .off
        claudeCLIPathField?.stringValue = prefs.claudeCLIPath ?? ""
        updateClaudeRepairDependentControls()
        loadKeys()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        saveClaudeCLIPath()
    }

    @objc private func additionalUsageChanged() {
        var prefs = preferences.load()
        prefs.showAdditionalModelUsage = additionalUsageToggle?.state == .on
        preferences.save(prefs)
        NotificationCenter.default.post(name: AppActions.tokenTorchDisplayChanged, object: nil)
    }

    @objc private func cursorValueRowsChanged() {
        var prefs = preferences.load()
        prefs.showCursorUsageValueAndBonus = cursorValueRowsToggle?.state == .on
        preferences.save(prefs)
        NotificationCenter.default.post(name: AppActions.tokenTorchDisplayChanged, object: nil)
    }

    @objc private func automaticRepairChanged() {
        var prefs = preferences.load()
        prefs.claudeAutomaticRepair = automaticRepairToggle?.state == .on
        preferences.save(prefs)
        updateClaudeRepairDependentControls()
    }

    private func updateClaudeRepairDependentControls() {
        let enabled = automaticRepairToggle?.state == .on
        notifyRepairFailureToggle?.isEnabled = enabled
        claudeCLIPathField?.isEnabled = enabled
        claudeCLIPathBrowseButton?.isEnabled = enabled

        let labelColor: NSColor = enabled ? .labelColor : .tertiaryLabelColor
        let hintColor: NSColor = enabled ? .secondaryLabelColor : .tertiaryLabelColor
        claudeCLIPathLabel?.textColor = labelColor
        notifyRepairHintLabel?.textColor = hintColor
        claudeCLIPathHintLabel?.textColor = hintColor
    }

    @objc private func notifyRepairFailureChanged() {
        var prefs = preferences.load()
        prefs.notifyOnRepairFailure = notifyRepairFailureToggle?.state == .on
        preferences.save(prefs)
    }

    @objc private func browseClaudeCLIPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.treatsFilePackagesAsDirectories = true
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        claudeCLIPathField?.stringValue = url.path
        saveClaudeCLIPath()
    }

    private func saveClaudeCLIPath() {
        guard let claudeCLIPathField else { return }
        let trimmed = claudeCLIPathField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let newValue = trimmed.isEmpty ? nil : trimmed
        var prefs = preferences.load()
        guard prefs.claudeCLIPath != newValue else { return }
        prefs.claudeCLIPath = newValue
        preferences.save(prefs)
    }

    private func loadKeys() {
        adminKeyField?.stringValue = (try? keychain.load(provider: provider, kind: .adminKey)) ?? ""
        tokenField?.stringValue = (try? keychain.load(provider: provider, kind: .personalAccessToken)) ?? ""
    }

    @objc private func saveKey() {
        guard let adminKeyField else { return }
        SettingsLayout.persistKeychainField(
            value: adminKeyField.stringValue,
            provider: provider,
            kind: .adminKey,
            using: keychain,
            statusLabel: statusLabel
        )
    }

    @objc private func clearKey() {
        try? keychain.delete(provider: provider, kind: .adminKey)
        adminKeyField?.stringValue = ""
        SettingsLayout.showStatus("Key cleared.", on: statusLabel)
    }

    @objc private func saveToken() {
        guard let tokenField else { return }
        SettingsLayout.persistKeychainField(
            value: tokenField.stringValue,
            provider: provider,
            kind: .personalAccessToken,
            using: keychain,
            statusLabel: statusLabel
        )
    }

    @objc private func clearToken() {
        try? keychain.delete(provider: provider, kind: .personalAccessToken)
        tokenField?.stringValue = ""
        SettingsLayout.showStatus("Token cleared.", on: statusLabel)
    }

    @objc private func resetCredentials() {
        let subscriptionEnabled = preferences.load().flags(for: provider).subscriptionQuotaEnabled
        if provider == .claude, subscriptionEnabled == true {
            repairClaudeCredentials()
            return
        }

        do {
            if subscriptionEnabled == true {
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
            SettingsLayout.showError(error.localizedDescription, on: statusLabel)
        }
    }

    private func repairClaudeCredentials() {
        statusLabel.stringValue = "Repairing Claude Code credentials…"
        resetButton.isEnabled = false
        Task {
            defer { resetButton.isEnabled = true }
            do {
                let baseline = try? VendorCredentialsReader.loadClaudeSession()
                _ = try await ClaudeCredentialRepair.repairAndImport(
                    baseline: baseline,
                    claudeExecutablePath: preferences.load().claudeCLIPath
                )
                SettingsLayout.showStatus("Claude Code credentials repaired and imported.", on: statusLabel)
                NotificationCenter.default.post(name: AppActions.tokenTorchRefreshRequested, object: nil)
            }
            catch {
                SettingsLayout.showError(error.localizedDescription, on: statusLabel)
            }
        }
    }
}

extension ProviderSettingsViewController: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field === claudeCLIPathField else { return }
        saveClaudeCLIPath()
    }
}
