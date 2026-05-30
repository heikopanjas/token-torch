import Foundation

public enum CodexQuotaProvider {
    private static let client = HTTPClient()

    public static func fetch(credentialStrategy: VendorCredentialStrategy = .directVendorRead) async throws -> SubscriptionQuotaReport {
        let session = try VendorCredentialsReader.loadCodexSession(strategy: credentialStrategy)
        let reauth: (() throws -> OAuthSession)? =
            credentialStrategy == .tokenTorchOwnedCopy
            ? { try VendorCredentialImporter.reimportAfterAuthFailure(provider: .codex) }
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
        let primaryWindow: RateLimitWindow?
        let secondaryWindow: RateLimitWindow?

        enum CodingKeys: String, CodingKey {
            case primaryWindow = "primary_window"
            case secondaryWindow = "secondary_window"
        }
    }

    struct ChatGptCredits: Decodable {
        let hasCredits: Bool?
        let balance: BalanceValue?

        enum CodingKeys: String, CodingKey {
            case hasCredits = "has_credits"
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
        let credits: ChatGptCredits?

        enum CodingKeys: String, CodingKey {
            case planType = "plan_type"
            case rateLimit = "rate_limit"
            case codeReviewRateLimit = "code_review_rate_limit"
            case credits
        }
    }

    public static func mapUsage(_ response: ChatGptUsageResponse) -> SubscriptionQuotaReport {
        var report = SubscriptionQuotaReport.forProvider("ChatGPT")
        report.planTier = response.planType
        var windows: [QuotaWindow] = []
        if let rateLimit = response.rateLimit {
            pushRateWindow(&windows, label: "5-hour window", window: rateLimit.primaryWindow)
            pushRateWindow(&windows, label: "7-day window", window: rateLimit.secondaryWindow)
        }
        if let review = response.codeReviewRateLimit {
            pushRateWindow(&windows, label: "Code review window", window: review.primaryWindow)
        }
        report.windows = windows
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
