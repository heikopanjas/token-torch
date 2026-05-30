import TokenTorchCore

enum ReportLabels {
    static func heading(provider: ProviderID, report: ProviderReport) -> String {
        switch provider {
            case .codex:
                switch report {
                    case .subscription: "ChatGPT & Codex"
                    case .org: "OpenAI Platform"
                    case .error(_, let mode, _): mode == "subscription" ? "ChatGPT & Codex" : "OpenAI Platform"
                }
            case .claude:
                switch report {
                    case .subscription: "Claude & Claude Code"
                    case .org: "Anthropic API"
                    case .error(_, let mode, _): mode == "subscription" ? "Claude & Claude Code" : "Anthropic API"
                }
            case .cursor:
                switch report {
                    case .subscription: "Cursor Plan"
                    case .org: provider.displayName
                    case .error(_, let mode, _): mode == "subscription" ? "Cursor Plan" : provider.displayName
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

    static func cursorGrandTotalLabel(_ quota: SubscriptionQuotaReport) -> String? {
        if let api = quota.apiAllowance {
            let used = QuotaHelpers.centsToDollars(api.usedCents)
            return String(format: "$%.2f", used)
        }
        if let usage = quota.dollarUsage {
            let used = QuotaHelpers.centsToDollars(usage.usedCents)
            return String(format: "$%.2f", used)
        }
        return nil
    }
}
