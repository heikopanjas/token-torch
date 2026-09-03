import Foundation

public enum ClaudeQuotaProvider {
    private static let retryDelays: [UInt64] = [2, 5, 10]
    private static let weeklyScopedLimitKind = "weekly_scoped"
    private static let fableModelName = "fable"
    private static let client = HTTPClient()

    public static func fetch(
        interactive: Bool = false,
        automaticRepairEnabled: Bool = false,
        claudeExecutablePath: String? = nil
    ) async throws -> SubscriptionQuotaReport {
        // Manual Refresh always repairs on auth failure; automatic refresh only when opted in.
        if interactive == true || automaticRepairEnabled == true {
            return try await Self.fetchWithRepair(
                interactive: interactive,
                claudeExecutablePath: claudeExecutablePath
            )
        }

        let reauth: () async throws -> OAuthSession = {
            return try await VendorCredentialImporter.reimportAfterAuthFailure(provider: .claude, interactive: interactive)
        }
        let session = try await QuotaHTTP.usableSession(
            try VendorCredentialsReader.loadClaudeSession(),
            provider: "Claude Code",
            vendorAction: "Re-login with Claude Code (/login).",
            reauthenticate: reauth
        )
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

    private static func fetchWithRepair(interactive: Bool, claudeExecutablePath: String?) async throws -> SubscriptionQuotaReport {
        let session = try await Self.repairableSession(
            interactive: interactive,
            claudeExecutablePath: claudeExecutablePath
        )
        do {
            return try await fetchUsage(session: session)
        }
        catch {
            if QuotaHTTP.isQuotaAuthError(error, policy: .strict) {
                let repaired = try await ClaudeCredentialRepair.repairAndImport(
                    baseline: session,
                    interactive: interactive,
                    claudeExecutablePath: claudeExecutablePath
                )
                return try await fetchUsage(session: repaired)
            }
            if QuotaHTTP.isQuotaRateLimitError(error) {
                return try await recoverRateLimit(session: session)
            }
            throw error
        }
    }

    private static func repairableSession(interactive: Bool, claudeExecutablePath: String?) async throws -> OAuthSession {
        let stored = try? VendorCredentialsReader.loadClaudeSession()
        if let stored, VendorCredentialsReader.sessionIsUsable(stored) {
            return stored
        }
        return try await ClaudeCredentialRepair.repairAndImport(
            baseline: stored,
            interactive: interactive,
            claudeExecutablePath: claudeExecutablePath
        )
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
        let headers = HTTPHeaders.bearerJSON(
            token: session.accessToken,
            extra: [
                "anthropic-beta": "oauth-2025-04-20",
                "User-Agent": AppBrand.claudeUsageUserAgent
            ]
        )
        let response: ClaudeUsageResponse = try await client.getJSON(
            url: url,
            headers: headers
        )
        return mapUsage(response, subscriptionType: session.subscriptionType, rateLimitTier: session.rateLimitTier)
    }

    public struct ClaudeUsageWindow: Decodable, Sendable {
        public let utilization: Double
        public let resetsAt: String?
        public init(utilization: Double, resetsAt: String?) {
            self.utilization = utilization
            self.resetsAt = resetsAt
        }

        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }
    }

    public struct ClaudeExtraUsage: Decodable, Sendable {
        public let isEnabled: Bool?
        public let usedCredits: Double?
        public let monthlyLimit: Double?
        public let utilization: Double?
        public let currency: String?

        enum CodingKeys: String, CodingKey {
            case isEnabled = "is_enabled"
            case usedCredits = "used_credits"
            case monthlyLimit = "monthly_limit"
            case utilization
            case currency
        }
    }

    public struct ClaudeLimitModel: Decodable, Sendable {
        public let displayName: String?
        public let id: String?

        public init(displayName: String? = nil, id: String? = nil) {
            self.displayName = displayName
            self.id = id
        }

        enum CodingKeys: String, CodingKey {
            case displayName = "display_name"
            case id
        }
    }

    public struct ClaudeLimitScope: Decodable, Sendable {
        public let model: ClaudeLimitModel?

        public init(model: ClaudeLimitModel? = nil) {
            self.model = model
        }
    }

    /// One entry of the `/api/oauth/usage` `limits` array. Only `kind == "weekly_scoped"` entries carry
    /// per-model limits (such as Fable); `session` and `weekly_all` restate `five_hour` / `seven_day`.
    public struct ClaudeLimitEntry: Decodable, Sendable {
        public let kind: String?
        public let percent: Double?
        public let resetsAt: String?
        public let scope: ClaudeLimitScope?

        public init(kind: String? = nil, percent: Double? = nil, resetsAt: String? = nil, scope: ClaudeLimitScope? = nil) {
            self.kind = kind
            self.percent = percent
            self.resetsAt = resetsAt
            self.scope = scope
        }

        enum CodingKeys: String, CodingKey {
            case kind
            case percent
            case resetsAt = "resets_at"
            case scope
        }
    }

    public struct ClaudeUsageResponse: Decodable, Sendable {
        public let fiveHour: ClaudeUsageWindow?
        public let sevenDay: ClaudeUsageWindow?
        public let sevenDayOpus: ClaudeUsageWindow?
        public let sevenDaySonnet: ClaudeUsageWindow?
        public let sevenDayCowork: ClaudeUsageWindow?
        public let sevenDayOmelette: ClaudeUsageWindow?
        public let sevenDayOauthApps: ClaudeUsageWindow?
        public let tangelo: ClaudeUsageWindow?
        public let iguanaNecktie: ClaudeUsageWindow?
        public let omelettePromotional: ClaudeUsageWindow?
        public let limits: [ClaudeLimitEntry]?
        public let extraUsage: ClaudeExtraUsage?

        public init(
            fiveHour: ClaudeUsageWindow? = nil,
            sevenDay: ClaudeUsageWindow? = nil,
            sevenDayOpus: ClaudeUsageWindow? = nil,
            sevenDaySonnet: ClaudeUsageWindow? = nil,
            sevenDayCowork: ClaudeUsageWindow? = nil,
            sevenDayOmelette: ClaudeUsageWindow? = nil,
            sevenDayOauthApps: ClaudeUsageWindow? = nil,
            tangelo: ClaudeUsageWindow? = nil,
            iguanaNecktie: ClaudeUsageWindow? = nil,
            omelettePromotional: ClaudeUsageWindow? = nil,
            limits: [ClaudeLimitEntry]? = nil,
            extraUsage: ClaudeExtraUsage? = nil
        ) {
            self.fiveHour = fiveHour
            self.sevenDay = sevenDay
            self.sevenDayOpus = sevenDayOpus
            self.sevenDaySonnet = sevenDaySonnet
            self.sevenDayCowork = sevenDayCowork
            self.sevenDayOmelette = sevenDayOmelette
            self.sevenDayOauthApps = sevenDayOauthApps
            self.tangelo = tangelo
            self.iguanaNecktie = iguanaNecktie
            self.omelettePromotional = omelettePromotional
            self.limits = limits
            self.extraUsage = extraUsage
        }

        enum CodingKeys: String, CodingKey {
            case fiveHour = "five_hour"
            case sevenDay = "seven_day"
            case sevenDayOpus = "seven_day_opus"
            case sevenDaySonnet = "seven_day_sonnet"
            case sevenDayCowork = "seven_day_cowork"
            case sevenDayOmelette = "seven_day_omelette"
            case sevenDayOauthApps = "seven_day_oauth_apps"
            case tangelo
            case iguanaNecktie = "iguana_necktie"
            case omelettePromotional = "omelette_promotional"
            case limits
            case extraUsage = "extra_usage"
        }
    }

    public static func mapUsage(
        _ response: ClaudeUsageResponse, subscriptionType: String?, rateLimitTier: String? = nil
    ) -> SubscriptionQuotaReport {
        var report = SubscriptionQuotaReport.forProvider("Claude Code")
        report.planTier = PlanBranding.claude(subscriptionType: subscriptionType, rateLimitTier: rateLimitTier)
        report.planPrice = PlanBranding.claudePrice(subscriptionType: subscriptionType, rateLimitTier: rateLimitTier)
        var windows: [QuotaWindow] = []
        pushWindow(&windows, label: "5-hour window", window: response.fiveHour, skipIfEmpty: false)
        pushWindow(&windows, label: "7-day window", window: response.sevenDay, skipIfEmpty: false)
        pushWindow(
            &windows,
            label: QuotaWindowLabel.claudeFableShare,
            window: Self.fableWindow(in: response.limits),
            skipIfEmpty: false
        )
        pushWindow(&windows, label: "7-day Opus window", window: response.sevenDayOpus)
        pushWindow(&windows, label: "7-day Sonnet window", window: response.sevenDaySonnet)
        pushWindow(&windows, label: "7-day Cowork window", window: response.sevenDayCowork)
        pushWindow(&windows, label: "7-day Design window", window: response.sevenDayOmelette)
        pushWindow(&windows, label: "7-day OAuth apps window", window: response.sevenDayOauthApps)
        pushWindow(&windows, label: "Tangelo", window: response.tangelo)
        pushWindow(&windows, label: "Iguana Necktie", window: response.iguanaNecktie)
        pushWindow(&windows, label: "Omelette (promo)", window: response.omelettePromotional)
        report.windows = windows
        if let extra = response.extraUsage {
            if let isEnabled = extra.isEnabled {
                report.notes = [QuotaNote(label: "Extra usage", value: isEnabled ? "enabled" : "disabled")]
            }
            if extra.isEnabled == true {
                report.credits = CreditsInfo(
                    usedCents: UInt64((extra.usedCredits ?? 0).rounded()),
                    limitCents: UInt64((extra.monthlyLimit ?? 0).rounded()),
                    currency: extra.currency ?? "USD",
                    balanceUSD: nil,
                    utilizationPercent: extra.utilization
                )
            }
        }
        return report
    }

    /// Fable has no top-level `seven_day_*` key; the usage API reports it only as a model-scoped
    /// entry of the `limits` array, so it must be read from there. An unstarted Fable window comes
    /// back as `percent: 0` with a null reset, hence the caller pushes it with `skipIfEmpty: false`.
    /// The model name is matched as a substring so a versioned display name such as `Fable 5` still resolves.
    private static func fableWindow(in limits: [ClaudeLimitEntry]?) -> ClaudeUsageWindow? {
        guard let limits else { return nil }
        for limit in limits where limit.kind == Self.weeklyScopedLimitKind {
            let displayName = limit.scope?.model?.displayName?.lowercased()
            let identifier = limit.scope?.model?.id?.lowercased()
            if displayName?.contains(Self.fableModelName) == true || identifier?.contains(Self.fableModelName) == true {
                return ClaudeUsageWindow(utilization: limit.percent ?? 0, resetsAt: limit.resetsAt)
            }
        }
        return nil
    }

    private static func pushWindow(
        _ windows: inout [QuotaWindow], label: String, window: ClaudeUsageWindow?, skipIfEmpty: Bool = true
    ) {
        guard let window else { return }
        QuotaHelpers.pushWindow(
            &windows,
            label: label,
            usedPercent: window.utilization,
            resetsAt: window.resetsAt.flatMap(QuotaHelpers.parseRFC3339UTC),
            skipIfEmpty: skipIfEmpty
        )
    }
}
