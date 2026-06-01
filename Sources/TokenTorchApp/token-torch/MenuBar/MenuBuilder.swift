import AppKit
import TokenTorchCore

@MainActor
final class MenuBuilder {
    weak var settingsTarget: AnyObject?
    var openSettingsAction: Selector?
    var refreshAction: Selector?

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
        let currency = prefs.displayCurrency
        let showAdditional = prefs.showAdditionalModelUsage

        guard prefs.hasAnyEnabledProvider else {
            menu.addItem(UsageMenuItemViews.emptyState())
            appendCommandItems(to: menu, model: model)
            return
        }

        let hasResult = model.result != nil
        if let result = model.result {
            // Flatten every present report into its menu view (provider + subscription/org) and sort
            // by the current user order, so each of the five views can be arranged independently and
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
                appendReport(to: menu, provider: section.provider, report: section.report, currency: currency, showAdditional: showAdditional)
            }
        }

        if hasResult || model.isLoading {
            if hasResult {
                menu.addItem(.separator())
            }
            menu.addItem(UsageMenuItemViews.header(result: model.result, isLoading: model.isLoading))
        }
        appendCommandItems(to: menu, model: model)
    }

    private func appendReport(to menu: NSMenu, provider: ProviderID, report: ProviderReport, currency: DisplayCurrency, showAdditional: Bool) {
        let trailing: String? = {
            if case .subscription(let quota) = report {
                return ReportLabels.planSummary(quota)
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
                if quota.provider == "Cursor" {
                    appendCursorSubscription(to: menu, quota: quota, currency: currency)
                }
                else {
                    let windows = showAdditional ? quota.windows + quota.additionalWindows : quota.windows
                    for window in windows {
                        let resetCaption = window.resetsAt.map(MenuFormat.resetCaption) ?? MenuFormat.noResetCaption
                        menu.addItem(
                            UsageMenuItemViews.costRow(
                                label: window.label,
                                value: String(format: "%.0f%% used", window.usedPercent),
                                caption: resetCaption
                            ))
                    }
                    for note in quota.notes {
                        menu.addItem(UsageMenuItemViews.costRow(label: note.label, value: note.value))
                    }
                    if let credits = quota.credits, let label = ReportLabels.creditsLabel(credits, in: currency) {
                        menu.addItem(UsageMenuItemViews.costRow(label: "On-demand credits", value: label))
                    }
                }
            case .org(let org):
                appendOrgBilling(to: menu, org: org, currency: currency)
            case .needsAuthorization:
                menu.addItem(UsageMenuItemViews.noticeRow("Click Refresh to authorize Keychain access."))
            case .error(_, let mode, let message):
                menu.addItem(UsageMenuItemViews.errorRow(mode: mode, message: message))
        }
    }

    private func appendCursorSubscription(to menu: NSMenu, quota: SubscriptionQuotaReport, currency: DisplayCurrency) {
        if let start = quota.billingCycleStart, let end = quota.billingCycleEnd {
            menu.addItem(
                UsageMenuItemViews.caption(
                    "Billing cycle: \(MenuFormat.billingCycleDate(start)) → \(MenuFormat.billingCycleDate(end))"
                ))
        }
        let meterLabels = ["Included total usage", "Auto + Composer", "Included API usage"]
        let meterRows = meterLabels.compactMap { label -> NSMenuItem? in
            guard let window = quota.windows.first(where: { $0.label == label }) else { return nil }
            return UsageMenuItemViews.costRow(
                label: label,
                value: String(format: "%.0f%% used", window.usedPercent)
            )
        }
        if !meterRows.isEmpty {
            if quota.billingCycleStart != nil {
                menu.addItem(UsageMenuItemViews.menuSpacer())
            }
            for item in meterRows {
                menu.addItem(item)
            }
        }
        if let total = quota.totalSpendCents {
            menu.addItem(
                UsageMenuItemViews.costRow(
                    label: "Total usage value",
                    value: CurrencyConverter.formatMinorUnits(total, from: "USD", to: currency)))
        }
        if let bonus = quota.bonusSpendCents, bonus > 0 {
            menu.addItem(
                UsageMenuItemViews.costRow(
                    label: "Bonus",
                    value: CurrencyConverter.formatMinorUnits(bonus, from: "USD", to: currency),
                    caption: "Free usage beyond what you've purchased"))
        }
        if let credits = ReportLabels.cursorCreditsLabel(quota, in: currency) {
            menu.addItem(UsageMenuItemViews.costRow(label: "Credits", value: credits))
        }
    }

    private func appendOrgBilling(to menu: NSMenu, org: OrgUsageReport, currency: DisplayCurrency) {
        let cycleLine: String = {
            if let end = org.endDate {
                return "Billing cycle: \(org.startDate) → \(end)"
            }
            return "Billing cycle: \(org.startDate)"
        }()
        menu.addItem(UsageMenuItemViews.caption(cycleLine))

        let sorted = org.costRows.sorted { $0.costUSD > $1.costUSD }
        if sorted.isEmpty {
            let empty =
                org.provider == "OpenAI"
                ? "No billed costs in this period."
                : "No billable usage in this period."
            menu.addItem(UsageMenuItemViews.secondaryCaption(empty))
        }
        else {
            menu.addItem(UsageMenuItemViews.menuSpacer())
            for row in sorted {
                menu.addItem(
                    UsageMenuItemViews.costRow(
                        label: row.label,
                        value: MenuFormat.orgCost(row.costUSD, in: currency)
                    ))
            }
            menu.addItem(UsageMenuItemViews.menuSpacer())
            menu.addItem(UsageMenuItemViews.grandTotalRow(value: MenuFormat.orgCost(org.grandTotalUSD, in: currency)))
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
        refresh.isEnabled = !model.isLoading
        menu.addItem(refresh)

        let settings = NSMenuItem(
            title: "Settings…",
            action: openSettingsAction,
            keyEquivalent: ","
        )
        settings.target = settingsTarget
        menu.addItem(settings)

        let quit = NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quit)
    }
}
