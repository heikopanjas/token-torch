import Foundation

public enum CodexQuotaProvider {
    static let creditUSDValue = 0.04

    private static let client = HTTPClient()
    private static let fiveHourWindowSeconds: Int64 = 18_000
    private static let sevenDayWindowSeconds: Int64 = 604_800

    private enum RateWindowKind {
        case fiveHour
        case sevenDay
    }

    private struct RateWindowCandidate {
        let window: RateLimitWindow
        let fallbackKind: RateWindowKind
    }

    public static func fetch(interactive: Bool = false) async throws -> SubscriptionQuotaReport {
        return try await QuotaHTTP.fetchSubscriptionQuota(
            providerID: .codex,
            interactive: interactive,
            loadSession: VendorCredentialsReader.loadCodexSession,
            fetchUsage: Self.fetchUsage
        )
    }

    private static func fetchUsage(session: OAuthSession) async throws -> SubscriptionQuotaReport {
        let url = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
        var headers = HTTPHeaders.bearerJSON(token: session.accessToken)
        if let accountID = session.accountID {
            headers["ChatGPT-Account-Id"] = accountID
        }
        let response: ChatGptUsageResponse = try await client.getJSON(url: url, headers: headers)
        return mapUsage(response)
    }

    public struct RateLimitWindow: Decodable {
        let usedPercent: Double
        let resetAt: Int64
        let limitWindowSeconds: Int64?

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case resetAt = "reset_at"
            case limitWindowSeconds = "limit_window_seconds"
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

    struct RateLimitResetCredits: Decodable {
        let availableCount: Int?

        enum CodingKeys: String, CodingKey {
            case availableCount = "available_count"
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
        let rateLimitResetCredits: RateLimitResetCredits?
        let promo: JSONValue?

        enum CodingKeys: String, CodingKey {
            case planType = "plan_type"
            case rateLimit = "rate_limit"
            case codeReviewRateLimit = "code_review_rate_limit"
            case additionalRateLimits = "additional_rate_limits"
            case credits
            case spendControl = "spend_control"
            case rateLimitReachedType = "rate_limit_reached_type"
            case rateLimitResetCredits = "rate_limit_reset_credits"
            case promo
        }
    }

    public static func mapUsage(_ response: ChatGptUsageResponse) -> SubscriptionQuotaReport {
        var report = SubscriptionQuotaReport.forProvider("Codex")
        report.planTier = PlanBranding.chatGPT(response.planType)
        report.planPrice = PlanBranding.chatGPTPrice(response.planType)

        var windows: [QuotaWindow] = []
        if let rateLimit = response.rateLimit {
            windows.append(
                contentsOf: Self.classifiedRateWindows(
                    rateLimit,
                    labels: (fiveHour: "5-hour window", sevenDay: "7-day window")
                )
            )
        }
        if let review = response.codeReviewRateLimit {
            windows.append(
                contentsOf: Self.classifiedRateWindows(
                    review,
                    labels: (fiveHour: "Code review (5h)", sevenDay: "Code review (7d)")
                )
            )
        }
        report.windows = windows

        var additional: [QuotaWindow] = []
        for limit in response.additionalRateLimits ?? [] {
            let name = limit.limitName ?? "Additional"
            if let rateLimit = limit.rateLimit {
                additional.append(
                    contentsOf: Self.classifiedRateWindows(
                        rateLimit,
                        labels: (fiveHour: "\(name) (5h)", sevenDay: "\(name) (7d)")
                    )
                )
            }
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
            notes.append(
                QuotaNote(
                    label: "Rate limit type",
                    value: Self.friendlyReachedType(type, rateLimit: response.rateLimit)
                )
            )
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
        if let availableCount = response.rateLimitResetCredits?.availableCount, availableCount > 0 {
            notes.append(QuotaNote(label: "Rate limit resets", value: "\(availableCount) available"))
        }
        if let promo = response.promo, promo.isEmpty == false {
            for leaf in promo.flattenedScalars(prefix: "promo") {
                notes.append(QuotaNote(label: leaf.label, value: leaf.value))
            }
        }
        report.notes = notes

        if let credits = response.credits, credits.hasCredits == true {
            report.credits = CreditsInfo(
                usedCents: 0,
                limitCents: 0,
                currency: CreditsInfo.creditUnitsCurrency,
                balanceUSD: nil,
                balanceCredits: credits.balance?.doubleValue
            )
        }
        return report
    }

    private static func friendlyReachedType(_ type: String, rateLimit: RateLimitPair?) -> String {
        switch type {
            case "primary":
                return Self.rateLimitTypeLabel(
                    window: rateLimit?.primaryWindow,
                    fallbackKind: .fiveHour
                )
            case "secondary":
                return Self.rateLimitTypeLabel(
                    window: rateLimit?.secondaryWindow,
                    fallbackKind: .sevenDay
                )
            default:
                return type
        }
    }

    /// Codex can move a temporarily sole weekly limit into `primary_window`, so explicit
    /// durations take precedence over slot position. Unknown durations keep the legacy fallback.
    private static func classifiedRateWindows(
        _ rateLimit: RateLimitPair,
        labels: (fiveHour: String, sevenDay: String)
    ) -> [QuotaWindow] {
        let candidates = [
            rateLimit.primaryWindow.map {
                RateWindowCandidate(window: $0, fallbackKind: .fiveHour)
            },
            rateLimit.secondaryWindow.map {
                RateWindowCandidate(window: $0, fallbackKind: .sevenDay)
            }
        ].compactMap { $0 }
        var windows: [QuotaWindow] = []
        Self.pushRateWindow(
            &windows,
            label: labels.fiveHour,
            window: Self.rateWindowCandidate(kind: .fiveHour, candidates: candidates)
        )
        Self.pushRateWindow(
            &windows,
            label: labels.sevenDay,
            window: Self.rateWindowCandidate(kind: .sevenDay, candidates: candidates)
        )
        return windows
    }

    private static func rateWindowCandidate(
        kind: RateWindowKind,
        candidates: [RateWindowCandidate]
    ) -> RateLimitWindow? {
        if let exact = candidates.first(where: { Self.exactRateWindowKind($0.window) == kind }) {
            return exact.window
        }
        return candidates.first(where: {
            return Self.exactRateWindowKind($0.window) == nil && $0.fallbackKind == kind
        })?.window
    }

    private static func exactRateWindowKind(_ window: RateLimitWindow) -> RateWindowKind? {
        switch window.limitWindowSeconds {
            case Self.fiveHourWindowSeconds:
                return .fiveHour
            case Self.sevenDayWindowSeconds:
                return .sevenDay
            default:
                return nil
        }
    }

    private static func rateLimitTypeLabel(
        window: RateLimitWindow?,
        fallbackKind: RateWindowKind
    ) -> String {
        let kind = window.flatMap(Self.exactRateWindowKind) ?? fallbackKind
        switch kind {
            case .fiveHour:
                return "5-hour limit"
            case .sevenDay:
                return "weekly limit"
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
