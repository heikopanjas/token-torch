import Foundation

public enum ProviderReport: Sendable, Equatable {
    case subscription(SubscriptionQuotaReport)
    case org(OrgUsageReport)
    case error(provider: ProviderID, mode: String, message: String)
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
