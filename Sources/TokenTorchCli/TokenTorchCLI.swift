import ArgumentParser
import Foundation
import TokenTorchCore

@main
struct TokenTorchCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "token-torch-cli",
        abstract: "Monitor Anthropic, OpenAI, Cursor, and Copilot usage (org billing and personal subscription quotas)",
        version: "4.1.2",
        subcommands: [AnthropicCommand.self, OpenAICommand.self, CursorCommand.self, CopilotCommand.self]
    )

}

extension DisplayCurrency: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(rawValue: argument.uppercased())
    }

    public static var allValueStrings: [String] { allCases.map(\.rawValue) }
}

struct CurrencyOptions: ParsableArguments {
    @Option(name: [.short, .long], help: "Display currency: USD or EUR (defaults to your system locale).")
    var currency: DisplayCurrency = .systemDefault
}

struct AnthropicCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "anthropic", aliases: ["claude"])

    @Option(name: [.short, .long], help: "Anthropic Admin API key")
    var apiKey: String?

    @Flag(name: .long, help: "Show Claude Code personal subscription quota")
    var quota: Bool = false

    @Flag(name: .long, help: "List available workspaces and their IDs")
    var listWorkspaces: Bool = false

    @Option(name: .long, help: "Workspace ID or `default` for the org default workspace")
    var workspace: String?

    @Option(name: [.short, .long], help: "Start date (YYYY, YYYY-MM, or YYYY-MM-DD; defaults to current month)")
    var startDate: String?

    @Option(name: [.short, .long], help: "End date (YYYY-MM-DD; auto-calculated for year/month ranges)")
    var endDate: String?

    @OptionGroup var currencyOptions: CurrencyOptions

    mutating func validate() throws {
        if quota, listWorkspaces || workspace != nil || startDate != nil || endDate != nil {
            throw ValidationError("--quota cannot be used with workspace/date/list flags.")
        }
        if listWorkspaces, workspace != nil {
            throw ValidationError("--list-workspaces cannot be used with --workspace.")
        }
    }

    func run() async throws {
        TerminalDisplay.displayCurrency = currencyOptions.currency
        CredentialStoreMigration.migrateFromBurnIfNeeded()
        if quota {
            try await runQuota(label: "Claude") { try await ClaudeQuotaProvider.fetch() }
            return
        }

        let key = try resolveAdminKey(flag: apiKey, provider: .claude)
        let progress = PageProgress()
        defer { progress.finish() }
        let onPage = { progress.update(page: $0) }

        if listWorkspaces {
            print(ANSIColor.brightCyan("Fetching workspaces..."))
            let workspaces = try await AnthropicOrgProvider.listWorkspaces(adminKey: key, pageCallback: onPage)
            TerminalDisplay.displayAnthropicWorkspaces(workspaces)
            return
        }

        let (start, end) = try DateRange.parseDateRange(startInput: startDate, endInput: endDate)

        if let workspace {
            let pricingMap = await loadPricingMap()
            print(ANSIColor.brightCyan(ScopeFormatting.formatWorkspaceFetchBanner(workspaceID: workspace, start: start, end: end)))
            let usage = try await AnthropicOrgProvider.fetchUsageResponse(
                adminKey: key, startDate: start, endDate: end, workspaceID: workspace, pageCallback: onPage
            )
            let emptyHint = ScopeFilter.fromCLIID(workspace) != nil ? ScopeFilter.emptyScopeHint(flagName: "--workspace") : nil
            TerminalDisplay.displayAnthropicUsage(usage, pricingMap: pricingMap, emptyHint: emptyHint)
        }
        else {
            let pricingMap = await loadPricingMap()
            print(ANSIColor.brightCyan(ScopeFormatting.formatFetchBanner(scope: "organization", start: start, end: end)))
            let usage = try await AnthropicOrgProvider.fetchUsageResponse(
                adminKey: key, startDate: start, endDate: end, workspaceID: nil, pageCallback: onPage
            )
            TerminalDisplay.displayAnthropicUsage(usage, pricingMap: pricingMap)
        }
    }
}

struct OpenAICommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "openai", aliases: ["codex"])

    @Option(name: [.short, .long], help: "OpenAI Admin API key")
    var apiKey: String?

    @Flag(name: .long, help: "Show ChatGPT/Codex personal subscription quota")
    var quota: Bool = false

    @Flag(name: .long, help: "List available projects and their IDs")
    var listProjects: Bool = false

    @Option(name: .long, help: "Project ID or `default` for unscoped usage")
    var project: String?

    @Option(name: [.short, .long], help: "Start date (YYYY, YYYY-MM, or YYYY-MM-DD; defaults to current month)")
    var startDate: String?

    @Option(name: [.short, .long], help: "End date (YYYY-MM-DD; auto-calculated for year/month ranges)")
    var endDate: String?

    @OptionGroup var currencyOptions: CurrencyOptions

    mutating func validate() throws {
        if quota, listProjects || project != nil || startDate != nil || endDate != nil {
            throw ValidationError("--quota cannot be used with project/date/list flags.")
        }
        if listProjects, project != nil {
            throw ValidationError("--list-projects cannot be used with --project.")
        }
    }

    func run() async throws {
        TerminalDisplay.displayCurrency = currencyOptions.currency
        CredentialStoreMigration.migrateFromBurnIfNeeded()
        if quota {
            try await runQuota(label: "ChatGPT/Codex") { try await CodexQuotaProvider.fetch() }
            return
        }

        let key = try resolveAdminKey(flag: apiKey, provider: .codex)
        let progress = PageProgress()
        defer { progress.finish() }
        let onPage = { progress.update(page: $0) }

        if listProjects {
            print(ANSIColor.brightCyan("Fetching projects..."))
            let projects = try await OpenAIOrgProvider.listProjects(adminKey: key, pageCallback: onPage)
            TerminalDisplay.displayOpenAIProjects(projects)
            return
        }

        let (start, end) = try DateRange.parseDateRange(startInput: startDate, endInput: endDate)
        let scopeLabel = project ?? "organization"
        print(ANSIColor.brightCyan(ScopeFormatting.formatFetchBanner(scope: scopeLabel, start: start, end: end)))

        let report = try await OpenAIOrgProvider.fetchOrgReport(
            adminKey: key, startDate: start, endDate: end, projectID: project, pageCallback: onPage
        )

        let emptyHint: String? = {
            guard let project, ScopeFilter.fromCLIID(project) != nil else { return nil }
            return ScopeFilter.emptyScopeHint(flagName: "--project")
        }()
        TerminalDisplay.displayOpenAIReport(report, emptyHint: emptyHint)
    }
}

struct CursorCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "cursor")

    @Flag(name: .long, help: "Show Cursor personal subscription plan usage")
    var quota: Bool = false

    @OptionGroup var currencyOptions: CurrencyOptions

    func run() async throws {
        TerminalDisplay.displayCurrency = currencyOptions.currency
        CredentialStoreMigration.migrateFromBurnIfNeeded()
        if quota {
            try await runQuota(label: "Cursor") { try await CursorQuotaProvider.fetch() }
        }
        else {
            TerminalDisplay.displayCursorOrgUnavailable()
        }
    }
}

struct CopilotCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "copilot")

    @Option(name: .shortAndLong, help: "Fine-grained GitHub PAT (Account: Copilot requests, Read-only)")
    var token: String?

    @Flag(name: .long, help: "Show GitHub Copilot personal subscription quota")
    var quota: Bool = false

    @OptionGroup var currencyOptions: CurrencyOptions

    func run() async throws {
        TerminalDisplay.displayCurrency = currencyOptions.currency
        CredentialStoreMigration.migrateFromBurnIfNeeded()
        if quota {
            let pat = try resolvePersonalAccessToken(flag: token)
            try await runQuota(label: "Copilot") {
                try await CopilotQuotaProvider.fetch(personalAccessToken: pat)
            }
        }
        else {
            TerminalDisplay.displayCopilotOrgUnavailable()
        }
    }
}

private func runQuota(label: String, fetch: () async throws -> SubscriptionQuotaReport) async throws {
    print(ANSIColor.brightCyan("Fetching \(label) subscription quota..."))
    let report = try await fetch()
    TerminalDisplay.displaySubscriptionQuota(report)
}

private func loadPricingMap() async -> [String: Pricing.ModelPricing] {
    TerminalDisplay.printPricingFetchBanner()
    switch await AnthropicPricing.fetchPricingMap() {
        case .success(let map):
            TerminalDisplay.printPricingLoaded()
            return map
        case .fallbackWarning(let message):
            TerminalDisplay.printPricingWarning(message)
            return Pricing.fallbackPricingMap()
    }
}

private func resolveAdminKey(flag: String?, provider: ProviderID) throws -> String {
    if let flag, !flag.isEmpty { return flag }
    let envName = provider == .claude ? "ANTHROPIC_ADMIN_KEY" : "OPENAI_ADMIN_KEY"
    if let env = ProcessInfo.processInfo.environment[envName], !env.isEmpty { return env }
    if let stored = try? AppKeychainStore.shared.load(provider: provider, kind: .adminKey), !stored.isEmpty {
        return stored
    }
    let providerName = provider == .claude ? "Anthropic" : "OpenAI"
    throw TokenTorchError.message("\(providerName) Admin API key required for org billing (use --quota for personal subscription limits)")
}

private func resolvePersonalAccessToken(flag: String?) throws -> String {
    if let flag, !flag.isEmpty { return GitHubPersonalAccessToken.normalize(flag) }
    let env = ProcessInfo.processInfo.environment
    if let github = env["GITHUB_TOKEN"], !github.isEmpty { return GitHubPersonalAccessToken.normalize(github) }
    if let copilot = env["COPILOT_TOKEN"], !copilot.isEmpty { return GitHubPersonalAccessToken.normalize(copilot) }
    if let stored = try? AppKeychainStore.shared.load(provider: .copilot, kind: .personalAccessToken), !stored.isEmpty {
        return GitHubPersonalAccessToken.normalize(stored)
    }
    throw TokenTorchError.missingPersonalAccessToken(provider: .copilot)
}
