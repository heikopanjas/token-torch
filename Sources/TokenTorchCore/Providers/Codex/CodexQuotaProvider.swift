import Foundation

public enum CodexQuotaProvider {
    private static let client = HTTPClient()

    public static func fetch(
        credentialStrategy: VendorCredentialStrategy = .directVendorRead, interactive: Bool = false
    ) async throws -> SubscriptionQuotaReport {
        let session = try VendorCredentialsReader.loadCodexSession(strategy: credentialStrategy)
        try QuotaHTTP.requireUsableSession(session, provider: "ChatGPT/Codex", vendorAction: "Re-login with the Codex CLI (`codex login`).")
        let reauth: (() throws -> OAuthSession)? =
            credentialStrategy == .tokenTorchOwnedCopy
            ? { try VendorCredentialImporter.reimportAfterAuthFailure(provider: .codex, interactive: interactive) }
            : nil
        return try await QuotaHTTP.fetchWithAuthRecovery(
            provider: "ChatGPT/Codex",
            session: session,
            vendorAction: "Re-login with the Codex CLI (`codex login`).",
            policy: .standard,
            reauthenticate: reauth
        ) { session in
            try await fetchUsage(session: session)
        }
    }

    private static func fetchUsage(session: OAuthSession) async throws -> SubscriptionQuotaReport {
        let url = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
        var headers = [
            "Authorization": "Bearer \(session.accessToken)",
            "Accept": "application/json"
        ]
        if let accountID = session.accountID {
            headers["ChatGPT-Account-Id"] = accountID
        }
        let response: ChatGptUsageResponse = try await client.getJSON(url: url, headers: headers)
        return mapUsage(response)
    }

    public struct RateLimitWindow: Decodable {
        let usedPercent: Double
        let resetAt: Int64

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case resetAt = "reset_at"
        }
    }

    struct RateLimitPair: Decodable {
        let allowed: Bool?
        let limitReached: Bool?
        let primaryWindow: RateLimitWindow?
        let secondaryWindow: RateLimitWindow?

        enum CodingKeys: String, CodingKey {
            case allowed
            case limitReached = "limit_reached"
            case primaryWindow = "primary_window"
            case secondaryWindow = "secondary_window"
        }
    }

    struct AdditionalRateLimit: Decodable {
        let limitName: String?
        let meteredFeature: String?
        let rateLimit: RateLimitPair?

        enum CodingKeys: String, CodingKey {
            case limitName = "limit_name"
            case meteredFeature = "metered_feature"
            case rateLimit = "rate_limit"
        }
    }

    struct SpendControl: Decodable {
        let reached: Bool?
        let individualLimit: Double?

        enum CodingKeys: String, CodingKey {
            case reached
            case individualLimit = "individual_limit"
        }
    }

    struct ChatGptCredits: Decodable {
        let hasCredits: Bool?
        let unlimited: Bool?
        let overageLimitReached: Bool?
        let balance: BalanceValue?

        enum CodingKeys: String, CodingKey {
            case hasCredits = "has_credits"
            case unlimited
            case overageLimitReached = "overage_limit_reached"
            case balance
        }
    }

    enum BalanceValue: Decodable {
        case double(Double)
        case string(String)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(Double.self) {
                self = .double(value)
            }
            else if let value = try? container.decode(String.self), let parsed = Double(value) {
                self = .double(parsed)
            }
            else if let value = try? container.decode(String.self) {
                self = .string(value)
            }
            else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "invalid balance")
            }
        }

        var doubleValue: Double? {
            switch self {
                case .double(let value): value
                case .string(let text): Double(text)
            }
        }
    }

    public struct ChatGptUsageResponse: Decodable {
        let planType: String?
        let rateLimit: RateLimitPair?
        let codeReviewRateLimit: RateLimitPair?
        let additionalRateLimits: [AdditionalRateLimit]?
        let credits: ChatGptCredits?
        let spendControl: SpendControl?
        let rateLimitReachedType: String?
        let promo: JSONValue?

        enum CodingKeys: String, CodingKey {
            case planType = "plan_type"
            case rateLimit = "rate_limit"
            case codeReviewRateLimit = "code_review_rate_limit"
            case additionalRateLimits = "additional_rate_limits"
            case credits
            case spendControl = "spend_control"
            case rateLimitReachedType = "rate_limit_reached_type"
            case promo
        }
    }

    public static func mapUsage(_ response: ChatGptUsageResponse) -> SubscriptionQuotaReport {
        var report = SubscriptionQuotaReport.forProvider("Codex")
        report.planTier = PlanBranding.chatGPT(response.planType)
        report.planPrice = PlanBranding.chatGPTPrice(response.planType)

        var windows: [QuotaWindow] = []
        if let rateLimit = response.rateLimit {
            pushRateWindow(&windows, label: "5-hour window", window: rateLimit.primaryWindow)
            pushRateWindow(&windows, label: "7-day window", window: rateLimit.secondaryWindow)
        }
        if let review = response.codeReviewRateLimit {
            pushRateWindow(&windows, label: "Code review (5h)", window: review.primaryWindow)
            pushRateWindow(&windows, label: "Code review (7d)", window: review.secondaryWindow)
        }
        report.windows = windows

        var additional: [QuotaWindow] = []
        for limit in response.additionalRateLimits ?? [] {
            let name = limit.limitName ?? "Additional"
            pushRateWindow(&additional, label: "\(name) (5h)", window: limit.rateLimit?.primaryWindow)
            pushRateWindow(&additional, label: "\(name) (7d)", window: limit.rateLimit?.secondaryWindow)
        }
        report.additionalWindows = additional

        // D7: only surface status flags when they signal a non-default, actionable state.
        var notes: [QuotaNote] = []
        if response.rateLimit?.allowed == false {
            notes.append(QuotaNote(label: "Rate limited", value: "yes"))
        }
        if response.rateLimit?.limitReached == true {
            notes.append(QuotaNote(label: "Limit reached", value: "yes"))
        }
        if let type = response.rateLimitReachedType {
            notes.append(QuotaNote(label: "Rate limit type", value: friendlyReachedType(type)))
        }
        if response.credits?.unlimited == true {
            notes.append(QuotaNote(label: "Unlimited credits", value: "yes"))
        }
        if response.credits?.overageLimitReached == true {
            notes.append(QuotaNote(label: "Overage limit reached", value: "yes"))
        }
        if response.spendControl?.reached == true {
            notes.append(QuotaNote(label: "Spend control reached", value: "yes"))
        }
        if let limit = response.spendControl?.individualLimit {
            notes.append(QuotaNote(label: "Spend limit", value: String(limit)))
        }
        if let promo = response.promo, !promo.isEmpty {
            for leaf in promo.flattenedScalars(prefix: "promo") {
                notes.append(QuotaNote(label: leaf.label, value: leaf.value))
            }
        }
        report.notes = notes

        if let credits = response.credits, credits.hasCredits == true {
            report.credits = CreditsInfo(
                usedCents: 0,
                limitCents: 0,
                currency: "USD",
                balanceUSD: credits.balance?.doubleValue
            )
        }
        return report
    }

    private static func friendlyReachedType(_ type: String) -> String {
        switch type {
            case "primary": "5-hour limit"
            case "secondary": "weekly limit"
            default: type
        }
    }

    private static func pushRateWindow(_ windows: inout [QuotaWindow], label: String, window: RateLimitWindow?) {
        guard let window else { return }
        QuotaHelpers.pushWindow(
            &windows,
            label: label,
            usedPercent: window.usedPercent,
            resetsAt: QuotaHelpers.parseUnixSecsUTC(window.resetAt),
            skipIfEmpty: false
        )
    }
}
