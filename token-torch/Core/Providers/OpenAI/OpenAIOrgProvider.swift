import Foundation

public enum OpenAIOrgProvider {
    private static let baseURL = "https://api.openai.com/v1"
    private static let client = HTTPClient()

    /// OpenAI returns `amount.value` as a decimal string (sometimes scientific notation).
    public struct CostAmount: Decodable {
        public let value: Double

        enum CodingKeys: String, CodingKey {
            case value
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let number = try? container.decode(Double.self, forKey: .value) {
                value = number
            }
            else if let text = try? container.decode(String.self, forKey: .value),
                let parsed = Double(text)
            {
                value = parsed
            }
            else {
                throw DecodingError.dataCorruptedError(
                    forKey: .value,
                    in: container,
                    debugDescription: "invalid cost amount"
                )
            }
        }
    }

    public static func listProjects(
        adminKey: String,
        pageCallback: ((Int) -> Void)? = nil
    ) async throws -> [OpenAIProject] {
        let headers = ["Authorization": "Bearer \(adminKey)"]
        var all: [OpenAIProject] = []
        let listURL = URL(string: "\(baseURL)/organization/projects")!

        struct Page: Decodable {
            let data: [OpenAIProject]
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
            limit: 100,
            cursorParam: "after",
            headers: headers,
            onPage: { (page: Page, _) in
                all.append(contentsOf: page.data)
                return (page.hasMore, page.lastID)
            },
            pageCallback: pageCallback
        )
        return all
    }

    public static func fetchOrgReport(
        adminKey: String,
        startDate: String,
        endDate: String?,
        projectID: String?,
        pageCallback: ((Int) -> Void)? = nil
    ) async throws -> OrgUsageReport {
        let scope = projectID ?? "organization"
        var report = OrgUsageReport(provider: "OpenAI", scopeLabel: scope, startDate: startDate, endDate: endDate)
        let (startUnix, endUnix) = try DateRange.dateRangeToUnix(start: startDate, end: endDate)
        let headers = ["Authorization": "Bearer \(adminKey)"]

        struct CompletionsResult: Decodable {
            let inputTokens: UInt64
            let outputTokens: UInt64
            let inputCachedTokens: UInt64
            let projectID: String?
            let model: String?

            enum CodingKeys: String, CodingKey {
                case inputTokens = "input_tokens"
                case outputTokens = "output_tokens"
                case inputCachedTokens = "input_cached_tokens"
                case projectID = "project_id"
                case model
            }
        }

        struct CostResult: Decodable {
            let amount: CostAmount?
            let lineItem: String?
            let projectID: String?

            enum CodingKeys: String, CodingKey {
                case amount
                case lineItem = "line_item"
                case projectID = "project_id"
            }
        }

        struct Bucket<T: Decodable>: Decodable {
            let results: [T]
        }

        struct Page<T: Decodable>: Decodable {
            let data: [Bucket<T>]
            let hasMore: Bool
            let nextPage: String?

            enum CodingKeys: String, CodingKey {
                case data
                case hasMore = "has_more"
                case nextPage = "next_page"
            }
        }

        let filterProject = projectID.flatMap { ScopeFilter.fromCLIID($0) }
        let matches: (String?) -> Bool = { pid in
            guard projectID != nil else { return true }
            if let filterProject {
                return pid == filterProject
            }
            return pid == nil
        }

        var usageURL =
            "\(baseURL)/organization/usage/completions?start_time=\(startUnix)&bucket_width=1d&group_by=project_id&group_by=model&limit=31"
        if let endUnix { usageURL += "&end_time=\(endUnix)" }
        if let filterProject {
            usageURL += "&project_ids[]=\(filterProject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? filterProject)"
        }

        var mergedUsage: [String: OrgUsageRow] = [:]
        try await client.paginateNextToken(
            urlBuilder: { token in
                var url = usageURL
                if let token { url += "&page=\(token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? token)" }
                return URL(string: url)!
            },
            headers: headers,
            onPage: { (page: Page<CompletionsResult>, _) in
                for bucket in page.data {
                    for row in bucket.results where matches(row.projectID) {
                        let key = "\(row.projectID ?? "default")|\(row.model ?? "unknown")"
                        var entry =
                            mergedUsage[key]
                            ?? OrgUsageRow(
                                timePeriod: "aggregated",
                                model: row.model,
                                workspaceID: row.projectID,
                                inputTokens: 0,
                                outputTokens: 0,
                                cacheCreationTokens: 0,
                                cacheReadTokens: 0,
                                totalTokens: 0
                            )
                        entry = OrgUsageRow(
                            timePeriod: "aggregated",
                            model: row.model,
                            workspaceID: row.projectID,
                            inputTokens: entry.inputTokens + row.inputTokens,
                            outputTokens: entry.outputTokens + row.outputTokens,
                            cacheCreationTokens: 0,
                            cacheReadTokens: entry.cacheReadTokens + row.inputCachedTokens,
                            totalTokens: entry.totalTokens + row.inputTokens + row.outputTokens
                        )
                        mergedUsage[key] = entry
                    }
                }
                return (page.hasMore, page.nextPage)
            },
            pageCallback: pageCallback
        )
        report.usageRows = Array(mergedUsage.values)

        var costURL = "\(baseURL)/organization/costs?start_time=\(startUnix)&bucket_width=1d&group_by=line_item&limit=180"
        if let endUnix { costURL += "&end_time=\(endUnix)" }
        if let filterProject {
            costURL += "&project_ids[]=\(filterProject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? filterProject)"
        }

        var costTotals: [String: Double] = [:]
        try await client.paginateNextToken(
            urlBuilder: { token in
                var url = costURL
                if let token { url += "&page=\(token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? token)" }
                return URL(string: url)!
            },
            headers: headers,
            onPage: { (page: Page<CostResult>, _) in
                for bucket in page.data {
                    for row in bucket.results where matches(row.projectID) {
                        let usd = row.amount?.value ?? 0
                        guard usd > 0, let line = row.lineItem else { continue }
                        costTotals[costAggregationLabel(for: line), default: 0] += usd
                    }
                }
                return (page.hasMore, page.nextPage)
            },
            pageCallback: pageCallback
        )

        var grandUSD = 0.0
        for (line, usd) in costTotals.sorted(by: { $0.value > $1.value }) {
            grandUSD += usd
            report.costRows.append(
                OrgCostRow(
                    label: line,
                    costUSD: usd,
                    costEUR: usd * Pricing.usdToEUR
                ))
        }
        report.grandTotalUSD = grandUSD
        report.grandTotalEUR = grandUSD * Pricing.usdToEUR
        return report
    }

    static func costAggregationLabel(for lineItem: String) -> String {
        let trimmed = lineItem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let comma = trimmed.lastIndex(of: ",") else { return trimmed }

        let model = String(trimmed[..<comma]).trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = String(trimmed[trimmed.index(after: comma)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")

        guard model.isEmpty == false else { return trimmed }
        let parts = suffix.split(separator: " ").map(String.init)
        let tokenCostWords: Set<String> = ["audio", "cache", "cached", "input", "output", "text", "token", "tokens"]
        let isTokenCost =
            parts.contains { $0 == "input" || $0 == "output" }
            && parts.allSatisfy { tokenCostWords.contains($0) }
        return isTokenCost ? String(model) : trimmed
    }
}
