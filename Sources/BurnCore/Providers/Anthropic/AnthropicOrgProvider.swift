import Foundation

public enum AnthropicOrgProvider {
    private static let baseURL = "https://api.anthropic.com/v1"
    private static let client = HTTPClient()

    public static func listWorkspaces(
        adminKey: String,
        pageCallback: ((Int) -> Void)? = nil
    ) async throws -> [AnthropicWorkspace] {
        let headers = anthropicHeaders(adminKey: adminKey)
        var all: [AnthropicWorkspace] = []
        let listURL = URL(string: "\(baseURL)/organizations/workspaces")!

        struct Page: Decodable {
            let data: [AnthropicWorkspace]
            let hasMore: Bool
            let lastID: String?

            enum CodingKeys: String, CodingKey {
                case data
                case hasMore = "has_more"
                case lastID = "last_id"
            }
        }

        try await client.paginateCursor(
            baseURL: listURL,
            limit: 1000,
            cursorParam: "after_id",
            headers: headers,
            onPage: { (page: Page, _) in
                all.append(contentsOf: page.data)
                return (page.hasMore, page.lastID)
            },
            pageCallback: pageCallback
        )
        return all
    }

    public static func fetchUsageResponse(
        adminKey: String,
        startDate: String,
        endDate: String?,
        workspaceID: String?,
        pageCallback: ((Int) -> Void)? = nil
    ) async throws -> AnthropicUsageResponse {
        let startingAt = try DateRange.startToRFC3339(start: startDate)
        var params = "starting_at=\(startingAt)&group_by[]=model&group_by[]=workspace_id"
        if let endDate {
            let endingAt = try DateRange.inclusiveEndToRFC3339(end: endDate)
            params += "&ending_at=\(endingAt)"
        }

        let baseURLString = "\(baseURL)/organizations/usage_report/messages?\(params)"
        let headers = anthropicHeaders(adminKey: adminKey)

        struct UsageResult: Decodable {
            let model: String?
            let workspaceID: String?
            let uncachedInputTokens: UInt64
            let outputTokens: UInt64
            let cacheReadInputTokens: UInt64
            let cacheCreation: CacheCreation?

            enum CodingKeys: String, CodingKey {
                case model
                case workspaceID = "workspace_id"
                case uncachedInputTokens = "uncached_input_tokens"
                case outputTokens = "output_tokens"
                case cacheReadInputTokens = "cache_read_input_tokens"
                case cacheCreation = "cache_creation"
            }
        }

        struct CacheCreation: Decodable {
            let ephemeral5mInputTokens: UInt64
            let ephemeral1hInputTokens: UInt64

            enum CodingKeys: String, CodingKey {
                case ephemeral5mInputTokens = "ephemeral_5m_input_tokens"
                case ephemeral1hInputTokens = "ephemeral_1h_input_tokens"
            }
        }

        struct Bucket: Decodable {
            let startingAt: String
            let endingAt: String
            let results: [UsageResult]

            enum CodingKeys: String, CodingKey {
                case startingAt = "starting_at"
                case endingAt = "ending_at"
                case results
            }
        }

        struct Page: Decodable {
            let data: [Bucket]
            let hasMore: Bool
            let nextPage: String?

            enum CodingKeys: String, CodingKey {
                case data
                case hasMore = "has_more"
                case nextPage = "next_page"
            }
        }

        var rows: [OrgUsageRow] = []
        try await client.paginateNextToken(
            urlBuilder: { token in
                var url = baseURLString
                if let token {
                    url += "&page=\(token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? token)"
                }
                return URL(string: url)!
            },
            headers: headers,
            onPage: { (page: Page, _) in
                for bucket in page.data {
                    let period = "\(DateRange.rfc3339DatePart(bucket.startingAt)) to \(DateRange.rfc3339DatePart(bucket.endingAt))"
                    for row in bucket.results {
                        let cacheCreate = (row.cacheCreation?.ephemeral5mInputTokens ?? 0) + (row.cacheCreation?.ephemeral1hInputTokens ?? 0)
                        let total = row.uncachedInputTokens + row.outputTokens + cacheCreate + row.cacheReadInputTokens
                        rows.append(
                            OrgUsageRow(
                                timePeriod: period,
                                model: row.model,
                                workspaceID: row.workspaceID,
                                inputTokens: row.uncachedInputTokens,
                                outputTokens: row.outputTokens,
                                cacheCreationTokens: cacheCreate,
                                cacheReadTokens: row.cacheReadInputTokens,
                                totalTokens: total
                            ))
                    }
                }
                return (page.hasMore, page.nextPage)
            },
            pageCallback: pageCallback
        )

        let filtered = filterUsageRows(rows, workspaceID: workspaceID)
        return AnthropicUsageResponse(rows: filtered)
    }

    public static func fetchOrgReport(
        adminKey: String,
        startDate: String,
        endDate: String?,
        workspaceID: String?,
        pageCallback: ((Int) -> Void)? = nil
    ) async throws -> OrgUsageReport {
        let scope = workspaceID ?? "organization"
        var report = OrgUsageReport(provider: "Anthropic", scopeLabel: scope, startDate: startDate, endDate: endDate)
        let usage = try await fetchUsageResponse(
            adminKey: adminKey,
            startDate: startDate,
            endDate: endDate,
            workspaceID: workspaceID,
            pageCallback: pageCallback
        )

        var modelTotals: [String: (input: UInt64, output: UInt64, cacheCreate: UInt64, cacheRead: UInt64)] = [:]
        for row in usage.rows {
            let model = ScopeFilter.displayModel(row.model)
            var entry = modelTotals[model] ?? (0, 0, 0, 0)
            entry.input += row.inputTokens
            entry.output += row.outputTokens
            entry.cacheCreate += row.cacheCreationTokens
            entry.cacheRead += row.cacheReadTokens
            modelTotals[model] = entry
        }

        var grandEUR = 0.0
        for (model, totals) in modelTotals.sorted(by: { $0.key < $1.key }) {
            let pricing = Pricing.modelPricing(for: model)
            let eur = pricing.calculateCostEUR(
                input: totals.input,
                output: totals.output,
                cacheCreation: totals.cacheCreate,
                cacheRead: totals.cacheRead
            )
            grandEUR += eur
            report.usageRows.append(
                OrgUsageRow(
                    model: model == "unknown" ? nil : model,
                    workspaceID: nil,
                    inputTokens: totals.input,
                    outputTokens: totals.output,
                    cacheCreationTokens: totals.cacheCreate,
                    cacheReadTokens: totals.cacheRead,
                    totalTokens: totals.input + totals.output + totals.cacheCreate + totals.cacheRead
                ))
            report.costRows.append(OrgCostRow(label: model, costUSD: eur / Pricing.usdToEUR, costEUR: eur))
        }
        report.grandTotalEUR = grandEUR
        report.grandTotalUSD = grandEUR / Pricing.usdToEUR
        return report
    }

    private static func anthropicHeaders(adminKey: String) -> [String: String] {
        [
            "x-api-key": adminKey,
            "anthropic-version": "2023-06-01",
            "Content-Type": "application/json"
        ]
    }

    private static func filterUsageRows(_ rows: [OrgUsageRow], workspaceID: String?) -> [OrgUsageRow] {
        guard let workspaceID else { return rows }
        if let filter = ScopeFilter.fromCLIID(workspaceID) {
            return rows.filter { $0.workspaceID == filter }
        }
        return rows.filter { $0.workspaceID == nil }
    }
}
