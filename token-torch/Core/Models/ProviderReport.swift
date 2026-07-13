import Foundation

public enum ProviderReport: Sendable, Equatable {
    case subscription(SubscriptionQuotaReport)
    case org(OrgUsageReport)
    case needsAuthorization(provider: ProviderID, mode: String)
    case error(
        provider: ProviderID,
        mode: String,
        message: String,
        diagnosticOutput: String?,
        isRepairFailure: Bool
    )

    /// Which reorderable menu view this report belongs to (subscription vs org billing).
    public var sectionKind: ProviderSectionKind {
        switch self {
            case .subscription: .subscription
            case .org: .orgBilling
            case .needsAuthorization(_, let mode), .error(_, let mode, _, _, _):
                mode == "subscription" ? .subscription : .orgBilling
        }
    }
}

public struct ProviderFetchResult: Sendable {
    public let provider: ProviderID
    public let reports: [ProviderReport]

    public init(provider: ProviderID, reports: [ProviderReport]) {
        self.provider = provider
        self.reports = reports
    }
}

public struct AllProvidersResult: Sendable {
    public let fetchedAt: Date
    public let results: [ProviderFetchResult]

    public init(fetchedAt: Date = Date(), results: [ProviderFetchResult]) {
        self.fetchedAt = fetchedAt
        self.results = results
    }
}

extension AllProvidersResult {
    public var claudeRepairFailureMessage: String? {
        for result in results where result.provider == .claude {
            for report in result.reports {
                if case let .error(_, _, message, _, isRepairFailure) = report, isRepairFailure {
                    return message
                }
            }
        }
        return nil
    }
}
