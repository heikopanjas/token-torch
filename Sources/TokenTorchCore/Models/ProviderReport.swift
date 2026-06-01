import Foundation

public enum ProviderReport: Sendable, Equatable {
    case subscription(SubscriptionQuotaReport)
    case org(OrgUsageReport)
    case needsAuthorization(provider: ProviderID, mode: String)
    case error(provider: ProviderID, mode: String, message: String)

    /// Which reorderable menu view this report belongs to (subscription vs org billing).
    public var sectionKind: ProviderSectionKind {
        switch self {
            case .subscription: .subscription
            case .org: .orgBilling
            case .needsAuthorization(_, let mode), .error(_, let mode, _):
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
