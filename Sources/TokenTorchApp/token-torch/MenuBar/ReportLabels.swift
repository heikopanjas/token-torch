import TokenTorchCore

enum ReportLabels {
    static func heading(provider: ProviderID, report: ProviderReport) -> String {
        heading(provider: provider, kind: report.sectionKind)
    }

    /// Human label for a menu view's kind, used in the Settings providers table "Type" column.
    static func typeLabel(_ kind: ProviderSectionKind) -> String {
        kind == .subscription ? "Subscription" : "API billing"
    }

    /// The exact caption shown for a menu view (provider + subscription/org). Single source of truth
    /// shared by the menu headers and the Settings provider-order list.
    static func heading(provider: ProviderID, kind: ProviderSectionKind) -> String {
        switch provider {
            case .codex: kind == .subscription ? "Codex" : "OpenAI Platform"
            case .claude: kind == .subscription ? "Claude Code" : "Anthropic API"
            case .cursor: kind == .subscription ? "Cursor" : provider.displayName
        }
    }

    /// Trailing summary shown next to the provider caption: plan tier and/or price.
    /// Applies to every subscription (Cursor has a price; Claude/ChatGPT show just the tier).
    static func planSummary(_ quota: SubscriptionQuotaReport) -> String? {
        switch (quota.planTier, quota.planPrice) {
            case (.some(let tier), .some(let price)): "\(tier) · \(price)"
            case (.some(let tier), .none): tier
            case (.none, .some(let price)): price
            case (.none, .none): nil
        }
    }

    /// Cursor spend counted against the included allowance, e.g. `$333.51/$400.00 (83% used)`.
    /// Styled like Claude's on-demand credits row. The used amount is the same value the previous
    /// Grand Total showed (`apiAllowance`, or `dollarUsage` for team), paired with its limit.
    static func cursorCreditsLabel(_ quota: SubscriptionQuotaReport, in currency: DisplayCurrency) -> String? {
        guard let usage = quota.apiAllowance ?? quota.dollarUsage, usage.limitCents > 0 else { return nil }
        let usedText = CurrencyConverter.formatMinorUnits(usage.usedCents, from: "USD", to: currency)
        let limitText = CurrencyConverter.formatMinorUnits(usage.limitCents, from: "USD", to: currency)
        let pct = usage.usedPercent ?? QuotaHelpers.creditUsedPercent(usedCents: usage.usedCents, limitCents: usage.limitCents)
        let pctText = pct.map { String(format: " (%.0f%% used)", $0) } ?? ""
        return "\(usedText)/\(limitText)\(pctText)"
    }

    /// A non-Cursor credits row (e.g. Claude `extra_usage`): "used / limit (NN% used)" or balance.
    static func creditsLabel(_ credits: CreditsInfo, in currency: DisplayCurrency) -> String? {
        if let balance = credits.balanceUSD {
            return CurrencyConverter.formatConverted(amount: balance, from: credits.currency, to: currency)
        }
        guard credits.limitCents > 0 || credits.usedCents > 0 else { return nil }
        let used = CurrencyConverter.formatMinorUnits(credits.usedCents, from: credits.currency, to: currency)
        let limit =
            credits.limitCents == 0
            ? "unlimited"
            : CurrencyConverter.formatMinorUnits(credits.limitCents, from: credits.currency, to: currency)
        let pct = credits.utilizationPercent ?? QuotaHelpers.creditUsedPercent(usedCents: credits.usedCents, limitCents: credits.limitCents)
        let pctText = pct.map { String(format: " (%.0f%% used)", $0) } ?? ""
        return "\(used)/\(limit)\(pctText)"
    }
}
