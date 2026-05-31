import Foundation

public enum CursorQuotaProvider {
    private static let apiBase = "https://api2.cursor.sh"
    private static let client = HTTPClient()

    public static func fetch(
        credentialStrategy: VendorCredentialStrategy = .directVendorRead, interactive: Bool = false
    ) async throws -> SubscriptionQuotaReport {
        let session = try VendorCredentialsReader.loadCursorSession(strategy: credentialStrategy)
        try QuotaHTTP.requireUsableSession(session, provider: "Cursor", vendorAction: "Re-login via the Cursor IDE or `cursor agent login`.")
        let reauth: (() throws -> OAuthSession)? =
            credentialStrategy == .tokenTorchOwnedCopy
            ? { try VendorCredentialImporter.reimportAfterAuthFailure(provider: .cursor, interactive: interactive) }
            : nil
        return try await QuotaHTTP.fetchWithAuthRecovery(
            provider: "Cursor",
            session: session,
            vendorAction: "Re-login via the Cursor IDE or `cursor agent login`.",
            policy: .extended,
            reauthenticate: reauth
        ) { session in
            try await fetchUsage(session: session)
        }
    }

    private static func fetchUsage(session: OAuthSession) async throws -> SubscriptionQuotaReport {
        let usage: CursorUsageResponse = try await postConnectRPC(method: "GetCurrentPeriodUsage", token: session.accessToken)
        let plan: CursorPlanResponse = try await postConnectRPC(method: "GetPlanInfo", token: session.accessToken)
        return mapUsage(usage: usage, plan: plan, membershipType: session.subscriptionType)
    }

    private static func postConnectRPC<T: Decodable>(method: String, token: String) async throws -> T {
        let url = URL(string: "\(apiBase)/aiserver.v1.DashboardService/\(method)")!
        return try await client.postJSON(
            url: url,
            headers: [
                "Authorization": "Bearer \(token)",
                "Content-Type": "application/json",
                "Connect-Protocol-Version": "1"
            ]
        )
    }

    public struct CursorPlanUsage: Decodable, Sendable {
        public let includedSpend: UInt64?
        public let totalSpend: UInt64?
        public let bonusSpend: UInt64?
        public let remaining: UInt64?
        public let limit: UInt64?
        public let autoPercentUsed: Double?
        public let apiPercentUsed: Double?
        public let totalPercentUsed: Double?

        public init(
            includedSpend: UInt64?,
            totalSpend: UInt64? = nil,
            bonusSpend: UInt64? = nil,
            remaining: UInt64?,
            limit: UInt64?,
            autoPercentUsed: Double?,
            apiPercentUsed: Double?,
            totalPercentUsed: Double?
        ) {
            self.includedSpend = includedSpend
            self.totalSpend = totalSpend
            self.bonusSpend = bonusSpend
            self.remaining = remaining
            self.limit = limit
            self.autoPercentUsed = autoPercentUsed
            self.apiPercentUsed = apiPercentUsed
            self.totalPercentUsed = totalPercentUsed
        }
    }

    public struct CursorSpendLimitUsage: Decodable, Sendable {
        public let pooledLimit: UInt64?
        public let limitType: String?
    }

    public struct CursorPlanInfo: Decodable, Sendable {
        public let planName: String?
        public let includedAmountCents: UInt64?
        public let price: String?
        public let billingCycleEnd: String?

        public init(planName: String?, includedAmountCents: UInt64?, price: String?, billingCycleEnd: String?) {
            self.planName = planName
            self.includedAmountCents = includedAmountCents
            self.price = price
            self.billingCycleEnd = billingCycleEnd
        }
    }

    public struct CursorUsageResponse: Decodable, Sendable {
        public let billingCycleStart: String?
        public let billingCycleEnd: String?
        public let planUsage: CursorPlanUsage?
        public let spendLimitUsage: CursorSpendLimitUsage?
        public let displayMessage: String?

        public init(
            billingCycleStart: String?,
            billingCycleEnd: String?,
            planUsage: CursorPlanUsage?,
            spendLimitUsage: CursorSpendLimitUsage?,
            displayMessage: String?
        ) {
            self.billingCycleStart = billingCycleStart
            self.billingCycleEnd = billingCycleEnd
            self.planUsage = planUsage
            self.spendLimitUsage = spendLimitUsage
            self.displayMessage = displayMessage
        }
    }

    public struct CursorPlanResponse: Decodable, Sendable {
        public let planInfo: CursorPlanInfo?

        public init(planInfo: CursorPlanInfo?) {
            self.planInfo = planInfo
        }
    }

    public static func mapUsage(
        usage: CursorUsageResponse,
        plan: CursorPlanResponse,
        membershipType: String?
    ) -> SubscriptionQuotaReport {
        var report = SubscriptionQuotaReport.forProvider("Cursor")
        let planInfo = plan.planInfo
        report.planTier = planInfo?.planName ?? membershipType?.uppercased()
        report.planPrice = planInfo?.price
        report.includedAllowanceCents = planInfo?.includedAmountCents ?? usage.planUsage?.limit
        report.billingCycleStart = usage.billingCycleStart.flatMap(QuotaHelpers.parseUnixMillisStrUTC)
        report.billingCycleEnd =
            usage.billingCycleEnd.flatMap(QuotaHelpers.parseUnixMillisStrUTC)
            ?? planInfo?.billingCycleEnd.flatMap(QuotaHelpers.parseUnixMillisStrUTC)
        report.rawMessage = usage.displayMessage

        let isTeam = report.planTier == "Team" || usage.spendLimitUsage?.limitType == "team" || usage.spendLimitUsage?.pooledLimit != nil

        guard let planUsage = usage.planUsage else { return report }

        if let included = planUsage.includedSpend {
            report.periodSpendCents = included
        }
        report.totalSpendCents = planUsage.totalSpend
        report.bonusSpendCents = planUsage.bonusSpend

        if isTeam {
            if let limit = planUsage.limit, let included = planUsage.includedSpend {
                let remaining = planUsage.remaining ?? (limit >= included ? limit - included : 0)
                report.dollarUsage = DollarUsage(
                    usedCents: included,
                    limitCents: limit,
                    remainingCents: remaining,
                    usedPercent: QuotaHelpers.creditUsedPercent(usedCents: included, limitCents: limit)
                )
            }
        }
        else {
            var windows: [QuotaWindow] = []
            if let total = planUsage.totalPercentUsed {
                windows.append(QuotaWindow(label: "Included total usage", usedPercent: total, resetsAt: report.billingCycleEnd))
            }
            if let auto = planUsage.autoPercentUsed, auto.isFinite {
                windows.append(QuotaWindow(label: "Auto + Composer", usedPercent: auto, resetsAt: report.billingCycleEnd))
            }
            if let api = planUsage.apiPercentUsed, api.isFinite {
                windows.append(QuotaWindow(label: "Included API usage", usedPercent: api, resetsAt: report.billingCycleEnd))
                if let limit = report.includedAllowanceCents ?? planUsage.limit, limit > 0 {
                    report.apiAllowance = QuotaHelpers.dollarUsageFromPercent(limitCents: limit, usedPercent: api)
                }
            }
            report.windows = windows
        }
        return report
    }
}
