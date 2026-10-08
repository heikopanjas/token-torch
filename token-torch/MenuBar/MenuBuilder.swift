import AppKit

@MainActor
final class MenuBuilder {
    weak var settingsTarget: AnyObject?
    var openSettingsAction: Selector?
    var refreshAction: Selector?
    var aboutAction: Selector?

    func buildMenu(model: MenuBarViewModel) -> NSMenu {
        let menu = NSMenu()
        populate(menu, model: model)
        return menu
    }

    /// Rebuilds `menu` contents in place. Safe to call while the menu is being tracked (open) so
    /// usage that finishes loading mid-session is reflected without dismissing the menu.
    func populate(_ menu: NSMenu, model: MenuBarViewModel) {
        menu.removeAllItems()
        menu.minimumWidth = MenuFormat.menuWidth
        let prefs = ProviderPreferencesStore.shared.load()
        let pricing = DisplayPriceOptions(preferences: prefs)

        guard prefs.hasAnyEnabledProvider == true else {
            menu.addItem(UsageMenuItemViews.emptyState())
            appendCommandItems(to: menu, model: model)
            return
        }

        let hasResult = model.result != nil
        if let result = model.result {
            // Flatten every present report into its menu view (provider + subscription/org) and sort
            // by the current user order, so each of the six views can be arranged independently and
            // a display-only rebuild (no refetch) reorders them immediately.
            let sections = result.results
                .flatMap { providerResult in
                    providerResult.reports.map { (provider: providerResult.provider, report: $0) }
                }
                // Honor the current enabled state so disabling a view removes it on a display-only
                // rebuild (no refetch needed), even though the cached result still holds its data.
                .filter { prefs.isSectionEnabled(ProviderSection(provider: $0.provider, kind: $0.report.sectionKind)) }
            let ordered = sections.sorted {
                prefs.sectionOrderIndex(of: ProviderSection(provider: $0.provider, kind: $0.report.sectionKind))
                    < prefs.sectionOrderIndex(of: ProviderSection(provider: $1.provider, kind: $1.report.sectionKind))
            }
            for (index, section) in ordered.enumerated() {
                if index > 0 {
                    menu.addItem(.separator())
                }
                appendReport(
                    to: menu,
                    provider: section.provider,
                    report: section.report,
                    pricing: pricing,
                    preferences: prefs
                )
            }
        }

        if hasResult || model.isLoading {
            if hasResult == true {
                menu.addItem(.separator())
            }
            menu.addItem(UsageMenuItemViews.header(result: model.result, isLoading: model.isLoading))
        }
        appendCommandItems(to: menu, model: model)
    }

    private func appendReport(
        to menu: NSMenu,
        provider: ProviderID,
        report: ProviderReport,
        pricing: DisplayPriceOptions,
        preferences: ProviderPreferences
    ) {
        let trailing: String? = {
            if case .subscription(let quota) = report {
                return ReportLabels.planSummary(quota, pricing: pricing)
            }
            return nil
        }()
        menu.addItem(
            UsageMenuItemViews.providerHeader(
                provider: provider,
                report: report,
                trailingSummary: trailing
            ))

        switch report {
            case .subscription(let quota):
                if provider == .cursor {
                    appendCursorSubscription(
                        to: menu,
                        quota: quota,
                        pricing: pricing,
                        showValueRows: preferences.showCursorUsageValueAndBonus
                    )
                }
                else {
                    let windows = preferences.visibleWindows(provider: provider, quota: quota)
                    for window in windows {
                        appendWindowRow(to: menu, window: window, pricing: pricing)
                        if quota.provider == "Copilot" {
                            appendCopilotDetails(to: menu, window: window)
                        }
                    }
                    for note in quota.notes {
                        menu.addItem(UsageMenuItemViews.costRow(label: note.label, value: note.value, caption: note.expiresAt.map(MenuFormat.expiryCaption)))
                    }
                    if let credits = quota.credits,
                        let label = creditsLabel(for: quota, credits: credits, pricing: pricing)
                    {
                        let creditsTitle = ReportLabels.creditsTitle(for: quota.provider)
                        menu.addItem(
                            UsageMenuItemViews.costRow(
                                label: creditsTitle,
                                value: label,
                                usedPercent: quota.creditsRowPercent
                            ))
                    }
                }
            case .org(let org):
                appendOrgBilling(to: menu, org: org, pricing: pricing)
            case .needsAuthorization:
                menu.addItem(UsageMenuItemViews.noticeRow("Click Refresh to authorize Keychain access."))
            case .error(_, let mode, let message, let diagnosticOutput, _):
                menu.addItem(
                    UsageMenuItemViews.errorRow(
                        mode: mode,
                        message: message,
                        diagnosticOutput: diagnosticOutput
                    )
                )
        }
    }

    private func creditsLabel(
        for quota: SubscriptionQuotaReport,
        credits: CreditsInfo,
        pricing: DisplayPriceOptions
    ) -> String? {
        if quota.provider == "Codex" {
            return ReportLabels.codexCreditsLabel(credits)
        }
        return ReportLabels.creditsLabel(credits, pricing: pricing)
    }

    /// One window row, the same for every non-Cursor provider: percent (or dollar amounts), reset or expiry
    /// caption, and the usage bar.
    private func appendWindowRow(to menu: NSMenu, window: QuotaWindow, pricing: DisplayPriceOptions) {
        let caption =
            (window.label == QuotaWindowLabel.claudeCloudSessionCredit)
            ? window.resetsAt.map(MenuFormat.expiryCaption)
            : window.resetsAt.map(MenuFormat.resetCaption)
        // Window dollar amounts are granted allowances (e.g. the cloud session credit), not
        // VAT-inclusive charges, so they are converted but never VAT-deducted.
        let value =
            window.dollarUsage.map { ReportLabels.dollarUsageLabel($0, pricing: pricing.withoutVATDeduction) }
            ?? MenuFormat.percentUsed(window.cappedUsedPercent)
        menu.addItem(
            UsageMenuItemViews.costRow(
                label: window.label,
                value: value,
                caption: caption ?? MenuFormat.noResetCaption,
                usedPercent: window.cappedUsedPercent
            ))
    }

    /// Copilot's unit rows under its window row (entitlement, usage and overage); the window row carries the bar.
    private func appendCopilotDetails(to menu: NSMenu, window: QuotaWindow) {
        for item in ReportLabels.copilotItems(window) {
            menu.addItem(UsageMenuItemViews.costRow(label: item.label, value: item.value))
        }
    }

    private func appendCursorSubscription(
        to menu: NSMenu,
        quota: SubscriptionQuotaReport,
        pricing: DisplayPriceOptions,
        showValueRows: Bool
    ) {
        if let start = quota.billingCycleStart, let end = quota.billingCycleEnd {
            menu.addItem(
                UsageMenuItemViews.caption(
                    MenuFormat.billingCycleCaption(start: start, end: end)
                ))
        }
        let meterRows = QuotaWindowLabel.cursorMeters.compactMap { label -> NSMenuItem? in
            guard let window = quota.windows.first(where: { $0.label == label }) else { return nil }
            return UsageMenuItemViews.costRow(
                label: label,
                value: MenuFormat.percentUsed(window.cappedUsedPercent),
                usedPercent: window.cappedUsedPercent
            )
        }
        if meterRows.isEmpty == false {
            if quota.billingCycleStart != nil {
                menu.addItem(UsageMenuItemViews.menuSpacer())
            }
            for item in meterRows {
                menu.addItem(item)
            }
        }
        if showValueRows == true {
            if let total = quota.totalSpendCents {
                menu.addItem(
                    UsageMenuItemViews.costRow(
                        label: "Total usage value",
                        value: pricing.formatMinorUnits(total, from: "USD")))
            }
            if let bonus = quota.bonusSpendCents, bonus > 0 {
                menu.addItem(
                    UsageMenuItemViews.costRow(
                        label: "Bonus",
                        value: pricing.formatMinorUnits(bonus, from: "USD"),
                        caption: "Free usage beyond what you've purchased"))
            }
        }
        if let credits = ReportLabels.cursorCreditsLabel(quota, pricing: pricing) {
            menu.addItem(
                UsageMenuItemViews.costRow(
                    label: "Credits",
                    value: credits,
                    usedPercent: quota.cursorCreditsPercent
                ))
        }
    }

    private func appendOrgBilling(to menu: NSMenu, org: OrgUsageReport, pricing: DisplayPriceOptions) {
        let cycleLine = MenuFormat.billingCycleCaption(start: org.startDate, end: org.endDate)
        menu.addItem(UsageMenuItemViews.caption(cycleLine))

        let sorted = org.costRows.sorted { $0.costUSD > $1.costUSD }
        if sorted.isEmpty == true {
            let empty =
                org.provider == "OpenAI"
                ? "No billed costs in this period."
                : "No billable usage in this period."
            menu.addItem(UsageMenuItemViews.caption(empty))
        }
        else {
            menu.addItem(UsageMenuItemViews.menuSpacer())
            for row in sorted {
                menu.addItem(
                    UsageMenuItemViews.costRow(
                        label: row.label,
                        value: MenuFormat.orgCost(row.costUSD, pricing: pricing)
                    ))
            }
            menu.addItem(UsageMenuItemViews.menuSpacer())
            menu.addItem(UsageMenuItemViews.grandTotalRow(value: MenuFormat.orgCost(org.grandTotalUSD, pricing: pricing)))
        }
    }

    private func appendCommandItems(to menu: NSMenu, model: MenuBarViewModel) {
        let refresh = NSMenuItem(
            title: "Refresh",
            action: refreshAction,
            keyEquivalent: "r"
        )
        refresh.keyEquivalentModifierMask = .command
        refresh.target = settingsTarget
        refresh.isEnabled = model.isLoading == false
        menu.addItem(refresh)

        menu.addItem(.separator())

        let settings = NSMenuItem(
            title: "Settings…",
            action: openSettingsAction,
            keyEquivalent: ","
        )
        settings.target = settingsTarget
        menu.addItem(settings)

        let about = NSMenuItem(
            title: "About…",
            action: aboutAction,
            keyEquivalent: ""
        )
        about.target = settingsTarget
        menu.addItem(about)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quit)
    }
}
