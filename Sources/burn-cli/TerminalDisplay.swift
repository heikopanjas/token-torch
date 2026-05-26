import BurnCore
import Foundation

enum TerminalDisplay {
    private static let sectionWidth = 80
    private static let quotaDisclaimer =
        "Personal subscription quota via local OAuth (undocumented API; may change without notice)."

    static func displayAnthropicUsage(_ usage: AnthropicUsageResponse, pricingMap: [String: Pricing.ModelPricing]) {
        displayAnthropicUsage(usage, pricingMap: pricingMap, emptyHint: nil)
    }

    static func displayAnthropicUsage(
        _ usage: AnthropicUsageResponse,
        pricingMap: [String: Pricing.ModelPricing],
        emptyHint: String?
    ) {
        if usage.rows.isEmpty {
            print(ANSIColor.yellow("No usage data found."))
            if let emptyHint { print(ANSIColor.dimmed(emptyHint)) }
            return
        }

        print("\n" + ANSIColor.brightBlueBold("Usage Statistics"))
        print(ANSIColor.brightBlueBold(String(repeating: "=", count: sectionWidth)))
        print(TableRenderer.renderUsageTable(usage.rows))

        let totalInput = usage.rows.reduce(0) { $0 + $1.inputTokens }
        let totalOutput = usage.rows.reduce(0) { $0 + $1.outputTokens }
        let totalCacheCreation = usage.rows.reduce(0) { $0 + $1.cacheCreationTokens }
        let totalCacheRead = usage.rows.reduce(0) { $0 + $1.cacheReadTokens }
        let total = totalInput + totalOutput + totalCacheCreation + totalCacheRead

        print("\n" + ANSIColor.brightGreenBold("Summary"))
        print(ANSIColor.brightGreenBold(String(repeating: "=", count: sectionWidth)))
        print("Total Input Tokens:          \(ANSIColor.brightWhiteBold(String(totalInput)))")
        print("Total Output Tokens:         \(ANSIColor.brightWhiteBold(String(totalOutput)))")
        print("Total Cache Creation Tokens: \(ANSIColor.brightWhiteBold(String(totalCacheCreation)))")
        print("Total Cache Read Tokens:     \(ANSIColor.brightWhiteBold(String(totalCacheRead)))")
        print("Total Tokens:                \(ANSIColor.brightWhiteBold(String(total)))")

        print("\n" + ANSIColor.brightYellowBold("Cost by Model"))
        print(ANSIColor.brightYellowBold(String(repeating: "=", count: sectionWidth)))

        var modelCosts: [String: Double] = [:]
        var unattributedCost = 0.0
        for row in usage.rows {
            if let model = row.model {
                let pricing = Pricing.resolveModelPricing(for: model, map: pricingMap)
                let cost = pricing.calculateCostEUR(
                    input: row.inputTokens,
                    output: row.outputTokens,
                    cacheCreation: row.cacheCreationTokens,
                    cacheRead: row.cacheReadTokens
                )
                modelCosts[model, default: 0] += cost
            }
            else {
                let pricing = Pricing.resolveModelPricing(for: "sonnet", map: pricingMap)
                unattributedCost += pricing.calculateCostEUR(
                    input: row.inputTokens,
                    output: row.outputTokens,
                    cacheCreation: row.cacheCreationTokens,
                    cacheRead: row.cacheReadTokens
                )
            }
        }

        if modelCosts.isEmpty, unattributedCost == 0 {
            print(ANSIColor.dimmed("No billable usage in this period."))
            return
        }

        var grandTotalEUR = 0.0
        for (model, cost) in modelCosts.sorted(by: { $0.value > $1.value }) {
            printCostLine(costEUR: cost, label: model)
            grandTotalEUR += cost
        }
        if unattributedCost > 0 {
            printCostLine(costEUR: unattributedCost, label: "(unknown model, priced as Sonnet)")
            grandTotalEUR += unattributedCost
        }

        printGrandTotal(grandTotalEUR)
        print(ANSIColor.brightBlueBold("Match the cost above with your Anthropic Console dashboard."))
    }

    static func displayAnthropicWorkspaces(_ workspaces: [AnthropicWorkspace]) {
        if workspaces.isEmpty {
            print(ANSIColor.yellow("No workspaces found."))
            return
        }

        print("\n" + ANSIColor.brightBlueBold("Workspaces"))
        print(ANSIColor.brightBlueBold(String(repeating: "=", count: sectionWidth)))
        print(TableRenderer.renderWorkspacesTable(workspaces))
        print()
        print(ANSIColor.dimmed("The org default workspace is not listed here; use `--workspace default` to view its usage."))
        print()
        print(ANSIColor.dimmed("\(workspaces.count) named workspace(s). Pass an ID from above to `--workspace`."))
    }

    static func displayOpenAIReport(_ report: OrgUsageReport, emptyHint: String?) {
        if report.usageRows.isEmpty, report.costRows.isEmpty {
            print(ANSIColor.yellow("No usage data found."))
            if let emptyHint { print(ANSIColor.dimmed(emptyHint)) }
            return
        }

        if !report.usageRows.isEmpty {
            print("\n" + ANSIColor.brightBlueBold("Usage Statistics"))
            print(ANSIColor.brightBlueBold(String(repeating: "=", count: sectionWidth)))
            print(TableRenderer.renderOpenAIUsageTable(report.usageRows))

            let totalInput = report.usageRows.reduce(0) { $0 + $1.inputTokens }
            let totalOutput = report.usageRows.reduce(0) { $0 + $1.outputTokens }
            let totalCached = report.usageRows.reduce(0) { $0 + $1.cacheReadTokens }
            let total = report.usageRows.reduce(0) { $0 + $1.totalTokens }

            print("\n" + ANSIColor.brightGreenBold("Summary"))
            print(ANSIColor.brightGreenBold(String(repeating: "=", count: sectionWidth)))
            print("Total Input Tokens:      \(ANSIColor.brightWhiteBold(String(totalInput)))")
            print("Total Output Tokens:     \(ANSIColor.brightWhiteBold(String(totalOutput)))")
            print("Total Cached Input:      \(ANSIColor.brightWhiteBold(String(totalCached)))")
            print("Total Tokens:            \(ANSIColor.brightWhiteBold(String(total)))")
        }

        print("\n" + ANSIColor.brightYellowBold("Cost by Line Item"))
        print(ANSIColor.brightYellowBold(String(repeating: "=", count: sectionWidth)))

        if report.costRows.isEmpty {
            print(ANSIColor.dimmed("No billed costs in this period."))
            return
        }

        var grandTotalUSD = 0.0
        for row in report.costRows {
            printCostLine(costEUR: row.costEUR, label: row.label)
            grandTotalUSD += row.costUSD
        }
        printGrandTotal(grandTotalUSD * Pricing.usdToEUR)
        print(ANSIColor.brightBlueBold("Match the cost above with your OpenAI Platform dashboard."))
    }

    static func displayOpenAIProjects(_ projects: [OpenAIProject]) {
        if projects.isEmpty {
            print(ANSIColor.yellow("No projects found."))
            return
        }

        print("\n" + ANSIColor.brightBlueBold("Projects"))
        print(ANSIColor.brightBlueBold(String(repeating: "=", count: sectionWidth)))
        print(TableRenderer.renderOpenAIProjectsTable(projects))
        print()
        print(ANSIColor.dimmed("Usage with no project is shown as `default`; use `--project default` to filter to it."))
        print()
        print(ANSIColor.dimmed("\(projects.count) named project(s). Pass an ID from above to `--project`."))
    }

    static func displaySubscriptionQuota(_ report: SubscriptionQuotaReport) {
        let isCursor = report.provider == "Cursor"
        printBlueSection(subscriptionTitle(report))

        if isCursor {
            if let allowanceCents = report.includedAllowanceCents {
                let allowance = QuotaHelpers.centsToDollars(allowanceCents)
                print(
                    ANSIColor.dimmed(
                        "Includes $\(String(format: "%.0f", allowance))/mo API agent usage at provider rates, plus a separate Auto + Composer allowance (Cursor docs)."
                    ))
                print()
            }
        }
        else if let dollarUsage = report.dollarUsage {
            let used = QuotaHelpers.centsToDollars(dollarUsage.usedCents)
            let limit = QuotaHelpers.centsToDollars(dollarUsage.limitCents)
            let remaining = QuotaHelpers.centsToDollars(dollarUsage.remainingCents)
            let percent = dollarUsage.usedPercent.map { " (\(String(format: "%.0f", $0))% used)" } ?? ""
            print(
                "\(ANSIColor.brightWhite(pad("Plan usage", 22))) \(ANSIColor.brightWhiteBold(String(format: "$%.2f / $%.2f", used, limit)))   $\(String(format: "%.2f", remaining)) remaining\(ANSIColor.dimmed(percent))"
            )
            print()
        }

        if !isCursor, let message = report.rawMessage {
            print(ANSIColor.brightWhite(message))
            print()
        }

        printBillingCycle(start: report.billingCycleStart, end: report.billingCycleEnd)

        if !report.windows.isEmpty {
            if isCursor {
                print(ANSIColor.dimmed("Auto + Composer = automatic model routing and Composer; API = named models (OpenAI, Claude, …)."))
            }
            for window in report.windows {
                printQuotaWindow(window)
                if isCursor, window.label == "Included total usage" {
                    let auto = report.windows.first { $0.label == "Auto + Composer" }?.usedPercent.rounded()
                    let api = report.windows.first { $0.label == "Included API usage" }?.usedPercent.rounded()
                    if let auto, let api {
                        print("                       \(Int(auto))% Auto and \(Int(api))% API used")
                    }
                }
            }
            if isCursor { print() }
        }

        if isCursor {
            if let api = report.apiAllowance {
                let used = QuotaHelpers.centsToDollars(api.usedCents)
                let limit = QuotaHelpers.centsToDollars(api.limitCents)
                let remaining = QuotaHelpers.centsToDollars(api.remainingCents)
                let percent = api.usedPercent.map { " (\(String(format: "%.0f", $0))%)" } ?? ""
                print(
                    "\(ANSIColor.brightWhite(pad("API ($400 incl.)", 22))) \(ANSIColor.brightWhiteBold(String(format: "~$%.2f / $%.2f", used, limit)))   ~$\(String(format: "%.2f", remaining)) remaining\(ANSIColor.dimmed(percent))"
                )
                print(ANSIColor.dimmed("From apiPercentUsed × $400 API allowance (named models)."))
            }

            if report.windows.isEmpty, report.apiAllowance == nil, report.dollarUsage == nil {
                print(ANSIColor.yellow("No quota data returned."))
            }

            if let message = report.rawMessage {
                print()
                print("\(ANSIColor.dimmed("Dollar spend (dashboard):")) \(ANSIColor.dimmed(message))")
                print(ANSIColor.dimmed("This is includedSpend ÷ API allowance at provider rates. It is separate from the percentage meters above."))
            }
        }
        else {
            printSubscriptionCredits(report)
            if report.windows.isEmpty, report.dollarUsage == nil, report.credits == nil {
                print(ANSIColor.yellow("No quota data returned."))
            }
        }

        print()
        print(ANSIColor.dimmed(quotaDisclaimer))
    }

    static func displayCursorOrgUnavailable() {
        print()
        print(ANSIColor.yellow("Cursor organization billing is not available in burn."))
        print(ANSIColor.dimmed("Use `burn cursor --quota` for personal subscription plan usage (macOS local OAuth)."))
        print()
    }

    static func printPricingFetchBanner() {
        print(ANSIColor.brightCyan("Fetching current pricing from Anthropic documentation..."))
    }

    static func printPricingLoaded() {
        print(ANSIColor.brightGreenBold("Pricing data loaded successfully."))
    }

    static func printPricingWarning(_ message: String) {
        print(ANSIColor.yellow("Warning: Failed to fetch pricing: \(Redaction.redactSecrets(message))"))
        print(ANSIColor.yellow("Using fallback pricing values."))
    }

    private static func subscriptionTitle(_ report: SubscriptionQuotaReport) -> String {
        switch (report.planTier, report.planPrice) {
            case (.some(let plan), .some(let price)):
                "\(report.provider) subscription (\(plan) · \(price))"
            case (.some(let plan), .none):
                "\(report.provider) subscription (\(plan))"
            case (.none, _):
                "\(report.provider) subscription"
        }
    }

    private static func printBlueSection(_ title: String) {
        print("\n" + ANSIColor.brightBlueBold(title))
        print(ANSIColor.brightBlueBold(String(repeating: "=", count: sectionWidth)))
    }

    private static func printBillingCycle(start: Date?, end: Date?) {
        guard let start, let end else { return }
        print("\(ANSIColor.brightWhite("Billing cycle:")) \(ANSIColor.dimmed(formatResetTime(start))) → \(ANSIColor.dimmed(formatResetTime(end)))")
        print()
    }

    private static func printQuotaWindow(_ window: QuotaWindow) {
        let percentText = String(format: "%.0f%% used", window.usedPercent)
        let resetText = window.resetsAt.map(formatResetTime) ?? "unknown"
        print("\(ANSIColor.brightWhite(pad(window.label, 22))) \(colorizePercent(window.usedPercent, text: percentText))   resets \(ANSIColor.dimmed(resetText))")
    }

    private static func printSubscriptionCredits(_ report: SubscriptionQuotaReport) {
        guard let credits = report.credits else { return }
        if let balance = credits.balanceUSD {
            print("\(ANSIColor.brightWhite(pad("Credits balance", 22))) \(ANSIColor.brightWhiteBold(String(format: "$%.2f %@", balance, credits.currency)))")
        }
        else if credits.limitCents > 0 || credits.usedCents > 0 {
            let used = QuotaHelpers.centsToDollars(credits.usedCents)
            let limit = QuotaHelpers.centsToDollars(credits.limitCents)
            let limitLabel = limit == 0 ? "unlimited" : String(format: "$%.2f", limit)
            print("\(ANSIColor.brightWhite(pad("On-demand credits", 22))) \(ANSIColor.brightWhiteBold(String(format: "$%.2f / %@ %@", used, limitLabel, credits.currency)))")
        }
    }

    private static func colorizePercent(_ usedPercent: Double, text: String) -> String {
        if usedPercent >= 80 { return ANSIColor.redBold(text) }
        if usedPercent >= 50 { return ANSIColor.yellow(text) }
        return ANSIColor.greenBold(text)
    }

    private static func formatResetTime(_ value: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: value) + " UTC"
    }

    private static func printCostLine(costEUR: Double, label: String) {
        let costUSD = costEUR / Pricing.usdToEUR
        print("\(ANSIColor.brightWhiteBold(String(format: "€%.2f ($%.2f USD)", costEUR, costUSD))) \(ANSIColor.dimmed("→")) \(ANSIColor.brightCyanLabel(label))")
    }

    private static func printGrandTotal(_ grandTotalEUR: Double) {
        print()
        print(ANSIColor.dimmed(String(repeating: "-", count: sectionWidth)))
        let grandTotalUSD = grandTotalEUR / Pricing.usdToEUR
        print("\(ANSIColor.brightWhiteBold("Grand Total:")) \(ANSIColor.brightGreenBold(String(format: "€%.2f ($%.2f USD)", grandTotalEUR, grandTotalUSD)))")
        print()
        print(ANSIColor.dimmed("Exchange rate: 1 USD = \(Pricing.usdToEUR) EUR"))
    }

    private static func pad(_ text: String, _ width: Int) -> String {
        if text.count >= width { return text }
        return text + String(repeating: " ", count: width - text.count)
    }
}
