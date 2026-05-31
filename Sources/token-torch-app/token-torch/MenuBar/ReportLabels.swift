import TokenTorchCore

enum ReportLabels {
    static func heading(provider: ProviderID, report: ProviderReport) -> String {
        switch provider {
            case .codex:
                switch report {
                    case .subscription: "ChatGPT & Codex"
                    case .org: "OpenAI Platform"
                    case .needsAuthorization(_, let mode), .error(_, let mode, _):
                        mode == "subscription" ? "ChatGPT & Codex" : "OpenAI Platform"
                }
            case .claude:
                switch report {
                    case .subscription: "Claude & Claude Code"
                    case .org: "Anthropic API"
                    case .needsAuthorization(_, let mode), .error(_, let mode, _):
                        mode == "subscription" ? "Claude & Claude Code" : "Anthropic API"
                }
            case .cursor:
                switch report {
                    case .subscription: "Cursor Plan"
                    case .org: provider.displayName
                    case .needsAuthorization(_, let mode), .error(_, let mode, _):
                        mode == "subscription" ? "Cursor Plan" : provider.displayName
                }
        }
    }

    static func cursorPlanSummary(_ quota: SubscriptionQuotaReport) -> String? {
        switch (quota.planTier, quota.planPrice) {
            case (.some(let tier), .some(let price)): "\(tier) · \(price)"
            case (.some(let tier), .none): tier
            case (.none, .some(let price)): price
            case (.none, .none): nil
        }
    }

    static func cursorGrandTotalLabel(_ quota: SubscriptionQuotaReport, in currency: DisplayCurrency) -> String? {
        if let api = quota.apiAllowance {
            return CurrencyConverter.formatMinorUnits(api.usedCents, from: "USD", to: currency)
        }
        if let usage = quota.dollarUsage {
            return CurrencyConverter.formatMinorUnits(usage.usedCents, from: "USD", to: currency)
        }
        return nil
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
        return "\(used) / \(limit)\(pctText)"
    }
}
