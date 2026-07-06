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
            case .copilot: "Copilot"
        }
    }

    /// Copilot quota snapshot rows (one label/value pair per API field).
    static func copilotItems(_ window: QuotaWindow) -> [QuotaNote] {
        CopilotQuotaLabels.displayItems(window)
    }

    /// Trailing summary shown next to the provider caption: plan tier and/or price.
    /// Applies to every subscription (Cursor has a price; Claude/ChatGPT show just the tier).
    static func planSummary(_ quota: SubscriptionQuotaReport, pricing: DisplayPriceOptions) -> String? {
        switch (quota.planTier, quota.planPrice) {
            case (.some(let tier), .some(let price)): "\(tier) · \(pricing.formatPlanPrice(price))"
            case (.some(let tier), .none): tier
            case (.none, .some(let price)): pricing.formatPlanPrice(price)
            case (.none, .none): nil
        }
    }

    static func creditsTitle(for provider: String) -> String {
        switch provider {
            case "Codex": return "Extra usage"
            case "Copilot": return "AI Credits"
            default: return "On-demand credits"
        }
    }

    private static func percentUsedSuffix(_ percent: Double?) -> String {
        guard let percent else { return "" }
        return MenuFormat.percentUsed(percent, parenthesized: true)
    }

    /// Cursor spend counted against the included allowance, e.g. `$333.51/$400.00 (83% used)`.
    /// Styled like Claude's on-demand credits row. The used amount is the same value the previous
    /// Grand Total showed (`apiAllowance`, or `dollarUsage` for team), paired with its limit.
    static func cursorCreditsLabel(_ quota: SubscriptionQuotaReport, pricing: DisplayPriceOptions) -> String? {
        guard let usage = quota.apiAllowance ?? quota.dollarUsage, usage.limitCents > 0 else { return nil }
        let usedText = pricing.formatMinorUnits(usage.usedCents, from: "USD")
        let limitText = pricing.formatMinorUnits(usage.limitCents, from: "USD")
        let pct = usage.usedPercent ?? QuotaHelpers.creditUsedPercent(usedCents: usage.usedCents, limitCents: usage.limitCents)
        let pctText = Self.percentUsedSuffix(pct)
        return "\(usedText)/\(limitText)\(pctText)"
    }

    /// A non-Cursor credits row (e.g. Claude `extra_usage`, Copilot AI Credits).
    static func creditsLabel(_ credits: CreditsInfo, pricing: DisplayPriceOptions) -> String? {
        if credits.currency == CreditsInfo.creditUnitsCurrency {
            guard credits.limitCents > 0 || credits.usedCents > 0 else { return nil }
            let pct = credits.utilizationPercent ?? QuotaHelpers.creditUsedPercent(usedCents: credits.usedCents, limitCents: credits.limitCents)
            let pctText = Self.percentUsedSuffix(pct)
            return "\(credits.usedCents)/\(credits.limitCents)\(pctText)"
        }
        if let balance = credits.balanceUSD {
            return pricing.formatConverted(amount: balance, from: credits.currency)
        }
        guard credits.limitCents > 0 || credits.usedCents > 0 else { return nil }
        let used = pricing.formatMinorUnits(credits.usedCents, from: credits.currency)
        let limit =
            credits.limitCents == 0
            ? "unlimited"
            : pricing.formatMinorUnits(credits.limitCents, from: credits.currency)
        let pct = credits.utilizationPercent ?? QuotaHelpers.creditUsedPercent(usedCents: credits.usedCents, limitCents: credits.limitCents)
        let pctText = Self.percentUsedSuffix(pct)
        return "\(used)/\(limit)\(pctText)"
    }

    /// Codex `credits.balance` is a credit count. Display its fixed USD equivalent alongside the units.
    static func codexCreditsLabel(_ credits: CreditsInfo, pricing: DisplayPriceOptions) -> String? {
        guard let balance = credits.balanceCredits, balance >= 0 else { return nil }
        let wholeCredits = Int(balance.rounded(.down))
        let amount = pricing.formatConverted(
            amount: Double(wholeCredits) * CodexQuotaProvider.creditUSDValue,
            from: "USD"
        )
        let unit = wholeCredits == 1 ? "credit" : "credits"
        return "\(amount) · \(wholeCredits) \(unit)"
    }
}
