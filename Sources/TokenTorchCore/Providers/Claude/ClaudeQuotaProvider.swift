import Foundation

public enum ClaudeQuotaProvider {
    private static let retryDelays: [UInt64] = [2, 5, 10]
    private static let client = HTTPClient()

    public static func fetch(credentialStrategy: VendorCredentialStrategy = .directVendorRead) async throws -> SubscriptionQuotaReport {
        let session = try VendorCredentialsReader.loadClaudeSession(strategy: credentialStrategy)
        let reauth: (() throws -> OAuthSession)? =
            credentialStrategy == .tokenTorchOwnedCopy
            ? { try VendorCredentialImporter.reimportAfterAuthFailure(provider: .claude) }
            : nil
        do {
            return try await QuotaHTTP.fetchWithAuthRecovery(
                provider: "Claude Code",
                session: session,
                vendorAction: "Re-login with Claude Code (/login).",
                policy: .strict,
                reauthenticate: reauth
            ) { session in
                try await fetchUsage(session: session)
            }
        }
        catch {
            if QuotaHTTP.isQuotaRateLimitError(error) {
                return try await recoverRateLimit(session: session)
            }
            throw error
        }
    }

    private static func recoverRateLimit(session: OAuthSession) async throws -> SubscriptionQuotaReport {
        for delay in retryDelays {
            try await Task.sleep(nanoseconds: delay * 1_000_000_000)
            if let report = try? await fetchUsage(session: session) { return report }
        }
        throw TokenTorchError.message(
            "Claude usage API rate limited (credentials from \(session.sourceLabel())). Wait a few minutes and retry."
        )
    }

    private static func fetchUsage(session: OAuthSession) async throws -> SubscriptionQuotaReport {
        let url = URL(string: "https://api.anthropic.com/api/oauth/usage")!
        let response: ClaudeUsageResponse = try await client.getJSON(
            url: url,
            headers: [
                "Authorization": "Bearer \(session.accessToken)",
                "Accept": "application/json",
                "Content-Type": "application/json",
                "anthropic-beta": "oauth-2025-04-20"
            ]
        )
        return mapUsage(response, subscriptionType: session.subscriptionType)
    }

    public struct ClaudeUsageWindow: Decodable, Sendable {
        public let utilization: Double
        public let resetsAt: String?
        public init(utilization: Double, resetsAt: String?) {
            self.utilization = utilization
            self.resetsAt = resetsAt
        }
    }

    public struct ClaudeExtraUsage: Decodable, Sendable {
        public let isEnabled: Bool?
        public let usedCredits: Double?
        public let monthlyLimit: Double?
        public let currency: String?
    }

    public struct ClaudeUsageResponse: Decodable, Sendable {
        public let fiveHour: ClaudeUsageWindow?
        public let sevenDay: ClaudeUsageWindow?
        public let sevenDayOpus: ClaudeUsageWindow?
        public let sevenDayOmelette: ClaudeUsageWindow?
        public let extraUsage: ClaudeExtraUsage?

        public init(
            fiveHour: ClaudeUsageWindow?,
            sevenDay: ClaudeUsageWindow?,
            sevenDayOpus: ClaudeUsageWindow?,
            sevenDayOmelette: ClaudeUsageWindow?,
            extraUsage: ClaudeExtraUsage?
        ) {
            self.fiveHour = fiveHour
            self.sevenDay = sevenDay
            self.sevenDayOpus = sevenDayOpus
            self.sevenDayOmelette = sevenDayOmelette
            self.extraUsage = extraUsage
        }

        enum CodingKeys: String, CodingKey {
            case fiveHour = "five_hour"
            case sevenDay = "seven_day"
            case sevenDayOpus = "seven_day_opus"
            case sevenDayOmelette = "seven_day_omelette"
            case extraUsage = "extra_usage"
        }
    }

    public static func mapUsage(_ response: ClaudeUsageResponse, subscriptionType: String?) -> SubscriptionQuotaReport {
        var report = SubscriptionQuotaReport.forProvider("Claude Code")
        report.planTier = subscriptionType
        var windows: [QuotaWindow] = []
        pushWindow(&windows, label: "5-hour window", window: response.fiveHour)
        pushWindow(&windows, label: "7-day window", window: response.sevenDay)
        pushWindow(&windows, label: "7-day Opus window", window: response.sevenDayOpus)
        pushWindow(&windows, label: "7-day Design window", window: response.sevenDayOmelette)
        report.windows = windows
        if let extra = response.extraUsage, extra.isEnabled == true {
            report.credits = CreditsInfo(
                usedCents: UInt64((extra.usedCredits ?? 0).rounded()),
                limitCents: UInt64((extra.monthlyLimit ?? 0).rounded()),
                currency: extra.currency ?? "USD",
                balanceUSD: nil
            )
        }
        return report
    }

    private static func pushWindow(_ windows: inout [QuotaWindow], label: String, window: ClaudeUsageWindow?) {
        guard let window else { return }
        QuotaHelpers.pushWindow(
            &windows,
            label: label,
            usedPercent: window.utilization,
            resetsAt: window.resetsAt.flatMap(QuotaHelpers.parseRFC3339UTC),
            skipIfEmpty: true
        )
    }
}
