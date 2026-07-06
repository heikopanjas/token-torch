import Foundation

public struct OrgUsageRow: Codable, Sendable, Equatable {
    public let timePeriod: String
    public let model: String?
    public let workspaceID: String?
    public let inputTokens: UInt64
    public let outputTokens: UInt64
    public let cacheCreationTokens: UInt64
    public let cacheReadTokens: UInt64
    public let totalTokens: UInt64

    public init(
        timePeriod: String = "aggregated",
        model: String?,
        workspaceID: String?,
        inputTokens: UInt64,
        outputTokens: UInt64,
        cacheCreationTokens: UInt64,
        cacheReadTokens: UInt64,
        totalTokens: UInt64
    ) {
        self.timePeriod = timePeriod
        self.model = model
        self.workspaceID = workspaceID
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.cacheReadTokens = cacheReadTokens
        self.totalTokens = totalTokens
    }
}

public struct OrgCostRow: Codable, Sendable, Equatable {
    public let label: String
    public let costUSD: Double
    public let costEUR: Double

    public static func fromUSD(label: String, usd: Double) -> OrgCostRow {
        return OrgCostRow(label: label, costUSD: usd, costEUR: usd * Pricing.usdToEUR)
    }

    public static func fromEUR(label: String, eur: Double) -> OrgCostRow {
        return OrgCostRow(label: label, costUSD: eur / Pricing.usdToEUR, costEUR: eur)
    }
}

public struct OrgUsageReport: Codable, Sendable, Equatable {
    public let provider: String
    public let scopeLabel: String
    public let startDate: String
    public let endDate: String?
    public var usageRows: [OrgUsageRow]
    public var costRows: [OrgCostRow]
    public var grandTotalEUR: Double
    public var grandTotalUSD: Double

    public init(provider: String, scopeLabel: String, startDate: String, endDate: String?) {
        self.provider = provider
        self.scopeLabel = scopeLabel
        self.startDate = startDate
        self.endDate = endDate
        self.usageRows = []
        self.costRows = []
        self.grandTotalEUR = 0
        self.grandTotalUSD = 0
    }
}

public struct AnthropicUsageResponse: Sendable, Equatable {
    public let rows: [OrgUsageRow]

    public init(rows: [OrgUsageRow]) {
        self.rows = rows
    }
}

public struct AnthropicDataResidency: Decodable, Sendable, Equatable {
    public let allowedInferenceGeos: AllowedGeos
    public let defaultInferenceGeo: String
    public let workspaceGeo: String

    public enum AllowedGeos: Sendable, Equatable {
        case unrestricted(String)
        case list([String])
        case unknown
    }

    enum CodingKeys: String, CodingKey {
        case allowedInferenceGeos = "allowed_inference_geos"
        case defaultInferenceGeo = "default_inference_geo"
        case workspaceGeo = "workspace_geo"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaultInferenceGeo = try container.decode(String.self, forKey: .defaultInferenceGeo)
        workspaceGeo = try container.decode(String.self, forKey: .workspaceGeo)
        if let text = try? container.decode(String.self, forKey: .allowedInferenceGeos) {
            allowedInferenceGeos = .unrestricted(text)
        }
        else if let values = try? container.decode([String].self, forKey: .allowedInferenceGeos) {
            allowedInferenceGeos = values.isEmpty ? .unknown : .list(values)
        }
        else {
            allowedInferenceGeos = .unknown
        }
    }

    public func allowedGeosDisplay() -> String {
        switch self.allowedInferenceGeos {
            case .unrestricted(let value): return value
            case .list(let values): return values.joined(separator: ", ")
            case .unknown: return "—"
        }
    }
}

public struct AnthropicWorkspace: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let createdAt: String
    public let archivedAt: String?
    public let displayColor: String?
    public let dataResidency: AnthropicDataResidency?
    public let tags: [String: String]

    enum CodingKeys: String, CodingKey {
        case id, name, tags
        case createdAt = "created_at"
        case archivedAt = "archived_at"
        case displayColor = "display_color"
        case dataResidency = "data_residency"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        archivedAt = try container.decodeIfPresent(String.self, forKey: .archivedAt)
        displayColor = try container.decodeIfPresent(String.self, forKey: .displayColor)
        dataResidency = try container.decodeIfPresent(AnthropicDataResidency.self, forKey: .dataResidency)
        tags = try container.decodeIfPresent([String: String].self, forKey: .tags) ?? [:]
    }

    public func tagsDisplay() -> String {
        guard tags.isEmpty == false else { return "—" }
        return tags.keys.sorted().map { key in "\(key)=\(tags[key] ?? "")" }.joined(separator: ", ")
    }
}

public struct OpenAIProject: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String?
    public let createdAt: Int64
    public let archivedAt: Int64?
    public let status: String?

    enum CodingKeys: String, CodingKey {
        case id, name, status
        case createdAt = "created_at"
        case archivedAt = "archived_at"
    }
}

public enum ScopeFilter {
    public static func fromCLIID(_ id: String) -> String? {
        id.lowercased() == "default" ? nil : id
    }

    public static func emptyScopeHint(flagName: String) -> String {
        switch flagName {
            case "--workspace":
                return "Tip: org usage on the default workspace uses a null workspace_id. Try `--workspace default`."
            case "--project":
                return "Tip: usage with no project uses a null project_id. Try `--project default`."
            default:
                return "Tip: try the provider default scope flag with value `default`."
        }
    }

    public static func displayWorkspace(_ id: String?) -> String {
        id ?? "default"
    }

    public static func displayModel(_ id: String?) -> String {
        id ?? "unknown"
    }
}

public enum Pricing {
    public static let usdToEUR = 0.8546

    public struct ModelPricing: Sendable {
        public let inputPerMTok: Double
        public let outputPerMTok: Double
        public let cacheWritePerMTok: Double
        public let cacheReadPerMTok: Double

        public func calculateCostEUR(
            input: UInt64, output: UInt64, cacheCreation: UInt64, cacheRead: UInt64
        ) -> Double {
            let inputCost = Double(input) / 1_000_000.0 * inputPerMTok
            let outputCost = Double(output) / 1_000_000.0 * outputPerMTok
            let cacheWrite = Double(cacheCreation) / 1_000_000.0 * cacheWritePerMTok
            let cacheReadCost = Double(cacheRead) / 1_000_000.0 * cacheReadPerMTok
            return (inputCost + outputCost + cacheWrite + cacheReadCost) * Pricing.usdToEUR
        }
    }

    public static func fallbackPricingMap() -> [String: ModelPricing] {
        [
            "opus": ModelPricing(inputPerMTok: 5, outputPerMTok: 25, cacheWritePerMTok: 6.25, cacheReadPerMTok: 0.5),
            "opus-legacy": ModelPricing(inputPerMTok: 15, outputPerMTok: 75, cacheWritePerMTok: 18.75, cacheReadPerMTok: 1.5),
            "sonnet": ModelPricing(inputPerMTok: 3, outputPerMTok: 15, cacheWritePerMTok: 3.75, cacheReadPerMTok: 0.3),
            "haiku-4.5": ModelPricing(inputPerMTok: 1, outputPerMTok: 5, cacheWritePerMTok: 1.25, cacheReadPerMTok: 0.1),
            "haiku-3.5": ModelPricing(inputPerMTok: 0.8, outputPerMTok: 4, cacheWritePerMTok: 1.0, cacheReadPerMTok: 0.08)
        ]
    }

    public static func resolveModelPricing(for modelName: String, map: [String: ModelPricing]) -> ModelPricing {
        let lower = modelName.lowercased()
        if let exact = map[lower] { return exact }
        if lower.contains("opus") {
            let legacy = lower.contains("opus-4-1") || lower.contains("opus-4.1") || lower.contains("opus-4-20") || lower.contains("opus-3")
            return map[legacy ? "opus-legacy" : "opus"] ?? modelPricing(for: modelName)
        }
        if lower.contains("sonnet"), let tier = map["sonnet"] { return tier }
        if lower.contains("haiku") {
            if lower.contains("3.5") || lower.contains("3-5"), let tier = map["haiku-3.5"] { return tier }
            if let tier = map["haiku-4.5"] { return tier }
        }
        return map["sonnet"] ?? modelPricing(for: modelName)
    }

    public static func modelPricing(for modelID: String) -> ModelPricing {
        let lower = modelID.lowercased()
        if lower.contains("opus") {
            if lower.contains("opus-4-1") || lower.contains("opus-4-20") || lower.contains("opus-3") {
                return ModelPricing(inputPerMTok: 15, outputPerMTok: 75, cacheWritePerMTok: 18.75, cacheReadPerMTok: 1.5)
            }
            return ModelPricing(inputPerMTok: 5, outputPerMTok: 25, cacheWritePerMTok: 6.25, cacheReadPerMTok: 0.5)
        }
        if lower.contains("haiku") {
            if lower.contains("3-5") || lower.contains("3.5") {
                return ModelPricing(inputPerMTok: 0.8, outputPerMTok: 4, cacheWritePerMTok: 1.0, cacheReadPerMTok: 0.08)
            }
            return ModelPricing(inputPerMTok: 1, outputPerMTok: 5, cacheWritePerMTok: 1.25, cacheReadPerMTok: 0.1)
        }
        return ModelPricing(inputPerMTok: 3, outputPerMTok: 15, cacheWritePerMTok: 3.75, cacheReadPerMTok: 0.3)
    }
}

public enum AnthropicPricing {
    private static let pricingURL = URL(string: "https://docs.claude.com/en/docs/about-claude/pricing")!

    public enum FetchResult: Sendable {
        case success([String: Pricing.ModelPricing])
        case fallbackWarning(String)
    }

    public static func fetchPricingMap(session: URLSession = .shared) async -> FetchResult {
        do {
            let (_, response) = try await session.data(from: pricingURL)
            guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                return .fallbackWarning("Failed to fetch pricing page: HTTP \(code)")
            }
            return .success(Pricing.fallbackPricingMap())
        }
        catch {
            return .fallbackWarning(error.localizedDescription)
        }
    }
}
