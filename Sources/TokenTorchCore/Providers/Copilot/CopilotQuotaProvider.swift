import Foundation

public enum CopilotQuotaProvider {
    private static let apiURL = URL(string: "https://api.github.com/copilot_internal/user")!
    private static let client = HTTPClient()

    /// Quota snapshot keys with meaningful usage meters (fixed display order).
    static let quotaGroupKeys = ["chat", "completions", "premium_interactions"]

    public static func fetch(personalAccessToken: String) async throws -> SubscriptionQuotaReport {
        let response: CopilotUserResponse = try await client.getJSON(
            url: apiURL,
            headers: copilotHeaders(token: personalAccessToken)
        )
        return mapUsage(response)
    }

    public static func mapUsage(_ response: CopilotUserResponse) -> SubscriptionQuotaReport {
        var report = SubscriptionQuotaReport(provider: "Copilot")
        report.planTier = PlanBranding.copilot(
            copilotPlan: response.copilotPlan,
            accessTypeSKU: response.accessTypeSKU
        )
        report.planPrice = PlanBranding.copilotPrice(
            copilotPlan: response.copilotPlan,
            accessTypeSKU: response.accessTypeSKU
        )

        let resetAt = parseResetDate(response)
        if let assigned = response.assignedDate.flatMap(QuotaHelpers.parseRFC3339UTC) {
            report.billingCycleStart = assigned
        }
        if let resetAt {
            report.billingCycleEnd = resetAt
        }

        var windows: [QuotaWindow] = []

        if let snapshots = response.quotaSnapshots {
            for key in quotaGroupKeys {
                guard let snapshot = snapshots[key], snapshot.unlimited == false else { continue }
                guard let window = mapSnapshot(key: key, snapshot: snapshot, resetAt: resetAt) else { continue }
                windows.append(window)
            }
        }

        if windows.isEmpty,
            let monthly = response.monthlyQuotas,
            let limited = response.limitedUserQuotas
        {
            mapFreeTier(
                monthly: monthly,
                limited: limited,
                resetAt: resetAt,
                into: &windows
            )
        }

        report.windows = windows

        if windows.isEmpty {
            report.rawMessage = "Usage not exposed for this plan."
        }

        return report
    }

    // MARK: - Models

    public struct CopilotUserResponse: Decodable, Sendable {
        public let copilotPlan: String?
        public let accessTypeSKU: String?
        public let assignedDate: String?
        public let quotaResetDate: String?
        public let quotaResetDateUTC: String?
        public let limitedUserResetDate: String?
        public let quotaSnapshots: [String: CopilotQuotaSnapshot]?
        public let monthlyQuotas: CopilotQuotaBuckets?
        public let limitedUserQuotas: CopilotQuotaBuckets?

        enum CodingKeys: String, CodingKey {
            case copilotPlan = "copilot_plan"
            case accessTypeSKU = "access_type_sku"
            case assignedDate = "assigned_date"
            case quotaResetDate = "quota_reset_date"
            case quotaResetDateUTC = "quota_reset_date_utc"
            case limitedUserResetDate = "limited_user_reset_date"
            case quotaSnapshots = "quota_snapshots"
            case monthlyQuotas = "monthly_quotas"
            case limitedUserQuotas = "limited_user_quotas"
        }

        public init(
            copilotPlan: String? = nil,
            accessTypeSKU: String? = nil,
            assignedDate: String? = nil,
            quotaResetDate: String? = nil,
            quotaResetDateUTC: String? = nil,
            limitedUserResetDate: String? = nil,
            quotaSnapshots: [String: CopilotQuotaSnapshot]? = nil,
            monthlyQuotas: CopilotQuotaBuckets? = nil,
            limitedUserQuotas: CopilotQuotaBuckets? = nil
        ) {
            self.copilotPlan = copilotPlan
            self.accessTypeSKU = accessTypeSKU
            self.assignedDate = assignedDate
            self.quotaResetDate = quotaResetDate
            self.quotaResetDateUTC = quotaResetDateUTC
            self.limitedUserResetDate = limitedUserResetDate
            self.quotaSnapshots = quotaSnapshots
            self.monthlyQuotas = monthlyQuotas
            self.limitedUserQuotas = limitedUserQuotas
        }
    }

    public struct CopilotQuotaSnapshot: Decodable, Sendable {
        public let unlimited: Bool?
        public let entitlement: Int?
        public let remaining: Int?
        public let quotaRemaining: Double?
        public let percentRemaining: Double?
        public let overageCount: Int?
        public let overagePermitted: Bool?

        enum CodingKeys: String, CodingKey {
            case unlimited
            case entitlement
            case remaining
            case quotaRemaining = "quota_remaining"
            case percentRemaining = "percent_remaining"
            case overageCount = "overage_count"
            case overagePermitted = "overage_permitted"
        }

        public init(
            unlimited: Bool? = nil,
            entitlement: Int? = nil,
            remaining: Int? = nil,
            quotaRemaining: Double? = nil,
            percentRemaining: Double? = nil,
            overageCount: Int? = nil,
            overagePermitted: Bool? = nil
        ) {
            self.unlimited = unlimited
            self.entitlement = entitlement
            self.remaining = remaining
            self.quotaRemaining = quotaRemaining
            self.percentRemaining = percentRemaining
            self.overageCount = overageCount
            self.overagePermitted = overagePermitted
        }
    }

    public struct CopilotQuotaBuckets: Decodable, Sendable {
        public let chat: Int?
        public let completions: Int?

        public init(chat: Int? = nil, completions: Int? = nil) {
            self.chat = chat
            self.completions = completions
        }
    }

    // MARK: - Private

    private static func copilotHeaders(token: String) -> [String: String] {
        [
            "Authorization": "token \(token)",
            "Accept": "application/json",
            "Editor-Version": "vscode/1.96.2",
            "Editor-Plugin-Version": "copilot-chat/0.26.7",
            "User-Agent": "GitHubCopilotChat/0.26.7",
            "X-Github-Api-Version": "2025-04-01"
        ]
    }

    private static func parseResetDate(_ response: CopilotUserResponse) -> Date? {
        if let utc = response.quotaResetDateUTC.flatMap(QuotaHelpers.parseRFC3339UTC) { return utc }
        if let date = response.limitedUserResetDate {
            return QuotaHelpers.parseRFC3339UTC("\(date)T00:00:00Z")
        }
        if let date = response.quotaResetDate {
            return QuotaHelpers.parseRFC3339UTC("\(date)T00:00:00Z")
        }
        return nil
    }

    static func snapshotUsedPercent(_ snapshot: CopilotQuotaSnapshot) -> Double? {
        guard snapshot.unlimited == false else { return nil }
        let entitlement = snapshot.entitlement ?? 0
        let remaining = snapshot.remaining ?? 0
        if entitlement == 0, remaining == 0, snapshot.percentRemaining == nil { return nil }
        if let pctRemaining = snapshot.percentRemaining {
            return ((100 - pctRemaining) * 10).rounded() / 10
        }
        guard entitlement > 0 else { return nil }
        let used = entitlement - remaining
        return max(0, min(100, Double(used) / Double(entitlement) * 100))
    }

    private static func mapSnapshot(
        key: String,
        snapshot: CopilotQuotaSnapshot,
        resetAt: Date?
    ) -> QuotaWindow? {
        guard let usedPercent = snapshotUsedPercent(snapshot) else { return nil }
        return QuotaWindow(
            label: snapshotLabel(for: key),
            usedPercent: usedPercent,
            resetsAt: resetAt,
            entitlement: snapshot.entitlement,
            remaining: snapshot.remaining,
            quotaRemaining: snapshot.quotaRemaining,
            percentRemaining: snapshot.percentRemaining,
            overageCount: snapshot.overageCount,
            overagePermitted: snapshot.overagePermitted
        )
    }

    private static func snapshotLabel(for key: String) -> String {
        switch key {
            case "chat": "Chat"
            case "completions": "Completions"
            case "premium_interactions": "AI Credits"
            default: key.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private static func mapFreeTier(
        monthly: CopilotQuotaBuckets,
        limited: CopilotQuotaBuckets,
        resetAt: Date?,
        into windows: inout [QuotaWindow]
    ) {
        pushFreeWindow(
            &windows,
            label: "Chat",
            limit: monthly.chat,
            remaining: limited.chat,
            resetAt: resetAt
        )
        pushFreeWindow(
            &windows,
            label: "Completions",
            limit: monthly.completions,
            remaining: limited.completions,
            resetAt: resetAt
        )
    }

    private static func pushFreeWindow(
        _ windows: inout [QuotaWindow],
        label: String,
        limit: Int?,
        remaining: Int?,
        resetAt: Date?
    ) {
        guard let limit, limit > 0, let remaining else { return }
        let used = max(0, limit - remaining)
        let usedPercent = max(0, min(100, Double(used) / Double(limit) * 100))
        let percentRemaining = max(0, min(100, Double(remaining) / Double(limit) * 100))
        windows.append(
            QuotaWindow(
                label: label,
                usedPercent: usedPercent,
                resetsAt: resetAt,
                entitlement: limit,
                remaining: remaining,
                quotaRemaining: Double(remaining),
                percentRemaining: percentRemaining
            ))
    }
}
