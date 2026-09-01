import CryptoKit
import Foundation

enum ClaudeCredentialRepair {
    static let usageRefreshShellPath = "/bin/zsh"
    static let usageRefreshShellScript = #"CLAUDE_CONFIG_DIR="$2" ANTHROPIC_API_KEY="" exec "$1" -p "/usage""#

    private static let repairTimeout: TimeInterval = 45
    private static let commandTimeout: TimeInterval = 30
    private static let pollInterval: TimeInterval = 0.5
    private static let defaultKeychainService = "Claude Code-credentials"
    private static let authenticationSelectorKeys = [
        "ANTHROPIC_API_KEY",
        "ANTHROPIC_AUTH_TOKEN",
        "CLAUDE_CODE_OAUTH_TOKEN",
        "CLAUDE_CODE_USE_BEDROCK",
        "CLAUDE_CODE_USE_VERTEX",
        "CLAUDE_CODE_USE_FOUNDRY",
        "CLAUDE_CONFIG_DIR"
    ]

    static func repairAndImport(
        baseline: OAuthSession?,
        interactive: Bool = false,
        claudeExecutablePath: String? = nil,
        timeout: TimeInterval = repairTimeout,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async throws -> OAuthSession {
        let discovered = try await Self.currentNoPromptSession(interactive: interactive)
        if let current = discovered, Self.shouldImport(current, comparedTo: baseline) == true {
            try Self.saveTokenTorchCopy(current)
            return current
        }

        let configDirectory = Self.selectedRepairConfigDirectory(baseline: baseline, discovered: discovered)
        let touchResult: Result<String?, Error>
        do {
            let commandOutput = try await Self.refreshClaudeCLIAuthPath(
                timeout: min(timeout, Self.commandTimeout),
                environment: environment,
                claudeExecutablePath: claudeExecutablePath,
                configDirectory: configDirectory
            )
            touchResult = .success(commandOutput)
        }
        catch {
            touchResult = .failure(error)
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try Task.checkCancellation()
            if let current = try await Self.currentNoPromptSession(interactive: interactive),
                Self.shouldImport(current, comparedTo: baseline) == true
            {
                try Self.saveTokenTorchCopy(current)
                return current
            }
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }

        let diagnostics = Self.repairDiagnostics(
            configDirectory: configDirectory,
            baseline: baseline,
            environment: environment,
            claudeExecutablePath: claudeExecutablePath
        )
        switch touchResult {
            case .success(let commandOutput):
                throw TokenTorchError.claudeRepairFailed(
                    message:
                        "Claude Code repair ran, but the Keychain access token did not change. Run `CLAUDE_CONFIG_DIR=\"\(configDirectory.path)\" ANTHROPIC_API_KEY=\"\" claude -p \"/usage\"` in a terminal, then retry Token Torch refresh.",
                    commandOutput: Self.combinedDiagnosticOutput(diagnostics: diagnostics, commandOutput: commandOutput)
                )
            case .failure(let error):
                let commandOutput: String?
                if case TokenTorchError.claudeRepairFailed(_, let output) = error {
                    commandOutput = output
                }
                else {
                    commandOutput = nil
                }
                throw TokenTorchError.claudeRepairFailed(
                    message:
                        "Claude Code repair did not update credentials: \(error.localizedDescription). Run `CLAUDE_CONFIG_DIR=\"\(configDirectory.path)\" ANTHROPIC_API_KEY=\"\" claude -p \"/usage\"` in a terminal, then retry Token Torch refresh.",
                    commandOutput: Self.combinedDiagnosticOutput(diagnostics: diagnostics, commandOutput: commandOutput)
                )
        }
    }

    static func currentNoPromptSession(interactive: Bool = false) async throws -> OAuthSession? {
        var candidates = Self.fileCandidates()
        if let keychain = try await Self.currentSecurityCLISession(interactive: interactive) {
            candidates.append(keychain)
        }
        return VendorCredentialsReader.freshest(candidates)
    }

    static func currentSecurityCLISession(interactive: Bool = false) async throws -> OAuthSession? {
        var candidates: [OAuthSession] = []
        for service in ClaudeCredentialPaths.keychainServices(defaultService: defaultKeychainService) {
            for json in try await SecurityCLIReader.readAllGenericPasswords(
                service: service,
                timeout: SecurityCLIReader.timeout(interactive: interactive)
            ) {
                if let session = try? ClaudeOAuthParser.parse(json, source: .claudeKeychain(service: service)) {
                    candidates.append(session)
                }
            }
        }
        return VendorCredentialsReader.freshest(candidates)
    }

    static func parseClaudeCredentialJSON(_ json: String, service: String) throws -> OAuthSession {
        return try Self.parseClaudeCredentialJSON(json, source: .claudeKeychain(service: service))
    }

    static func parseClaudeCredentialJSON(_ json: String, source: CredentialSource) throws -> OAuthSession {
        return try ClaudeOAuthParser.parse(json, source: source)
    }

    static func accessTokenFingerprint(_ session: OAuthSession?) -> String? {
        guard let token = session?.accessToken else { return nil }
        return SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func selectedRepairConfigDirectory(
        baseline: OAuthSession?,
        discovered: OAuthSession? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let baseline, let directory = ClaudeCredentialPaths.configDir(for: baseline.source, environment: environment) {
            return directory
        }
        if let discovered, let directory = ClaudeCredentialPaths.configDir(for: discovered.source, environment: environment) {
            return directory
        }
        if let stored = VendorCredentialImportSourceStore.load(provider: .claude),
            let directory = ClaudeCredentialPaths.configDir(for: stored, environment: environment)
        {
            return directory
        }
        return ClaudeCredentialPaths.preferredDefaultConfigDir()
    }

    private static func shouldImport(_ session: OAuthSession, comparedTo baseline: OAuthSession?) -> Bool {
        guard VendorCredentialsReader.sessionIsUsable(session) else { return false }
        guard let baseline else { return true }
        return accessTokenFingerprint(session) != accessTokenFingerprint(baseline)
            || VendorCredentialsReader.sessionIsUsable(baseline) == false
    }

    private static func saveTokenTorchCopy(_ session: OAuthSession) throws {
        try TokenTorchVendorCredentialStore.save(provider: .claude, session: session)
        VendorCredentialImportSourceStore.save(session.source, provider: .claude)
        VendorCredentialCache.store(session, for: .claude)
    }

    private static func refreshClaudeCLIAuthPath(
        timeout: TimeInterval,
        environment: [String: String],
        claudeExecutablePath: String?,
        configDirectory: URL
    ) async throws -> String? {
        guard
            let claudePath = Self.resolvedExecutable(
                named: "claude",
                environment: environment,
                explicitPath: claudeExecutablePath
            )
        else {
            throw TokenTorchError.message(
                "Claude CLI is not installed or not on PATH. Set the Claude CLI path in Settings > Claude."
            )
        }

        let result = try await ProcessRunner.runInPseudoTerminal(
            executablePath: Self.usageRefreshShellPath,
            arguments: Self.usageRefreshShellArguments(claudePath: claudePath, configDirectory: configDirectory),
            timeout: timeout,
            environment: environment,
            workingDirectory: Self.preparedProbeWorkingDirectory()
        )
        return try Self.validateUsageRefreshResult(result, executablePath: claudePath)
    }

    static func usageRefreshShellArguments(claudePath: String, configDirectory: URL) -> [String] {
        return [
            "-c",
            Self.usageRefreshShellScript,
            "token-torch-claude-repair",
            claudePath,
            configDirectory.path
        ]
    }

    static func validateUsageRefreshResult(_ result: ProcessRunner.Result, executablePath: String) throws -> String? {
        let commandOutput = Self.commandOutput(from: result)
        guard result.terminationStatus == 0 else {
            let fallback = "\(executablePath) exited with status \(result.terminationStatus)."
            let message = Self.failureMessage(from: result) ?? fallback
            throw TokenTorchError.claudeRepairFailed(
                message: Redaction.redactSecrets(message),
                commandOutput: commandOutput
            )
        }
        return commandOutput
    }

    static func authenticationEnvironmentStates(environment: [String: String]) -> [(key: String, state: String)] {
        return Self.authenticationSelectorKeys.map { key in
            guard let value = environment[key] else {
                return (key: key, state: "unset")
            }
            if value.isEmpty == true {
                return (key: key, state: "empty")
            }
            return (key: key, state: "nonempty")
        }
    }

    private static func failureMessage(from result: ProcessRunner.Result) -> String? {
        let standardError = String(data: result.standardError, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let standardError, standardError.isEmpty == false {
            return standardError
        }
        let standardOutput = String(data: result.standardOutput, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let standardOutput, standardOutput.isEmpty == false {
            return standardOutput
        }
        return nil
    }

    private static func commandOutput(from result: ProcessRunner.Result) -> String? {
        let standardOutput = String(data: result.standardOutput, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let standardError = String(data: result.standardError, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var sections: [String] = []
        if let standardOutput, standardOutput.isEmpty == false {
            sections.append(standardOutput)
        }
        if let standardError, standardError.isEmpty == false {
            sections.append("stderr:\n\(standardError)")
        }
        guard sections.isEmpty == false else { return nil }
        return Redaction.redactSecrets(sections.joined(separator: "\n\n"))
    }

    private static func repairDiagnostics(
        configDirectory: URL,
        baseline: OAuthSession?,
        environment: [String: String],
        claudeExecutablePath: String?
    ) -> String {
        let sourceLabel =
            baseline?.sourceLabel()
            ?? VendorCredentialImportSourceStore.load(provider: .claude)?.sourceLabel()
            ?? "none"
        let executable =
            Self.resolvedExecutable(
                named: "claude",
                environment: environment,
                explicitPath: claudeExecutablePath
            ) ?? "<not found>"
        let workingDirectory = Self.preparedProbeWorkingDirectory().path
        let authStates = Self.authenticationEnvironmentStates(environment: environment)
            .map { "\($0.key)=\($0.state)" }
            .joined(separator: ", ")
        return Redaction.redactSecrets(
            [
                "repair diagnostics:",
                "config directory: \(configDirectory.path)",
                "credential source: \(sourceLabel)",
                "claude executable: \(executable)",
                "working directory: \(workingDirectory)",
                "auth selectors: \(authStates)"
            ].joined(separator: "\n")
        )
    }

    private static func combinedDiagnosticOutput(diagnostics: String, commandOutput: String?) -> String {
        guard let commandOutput, commandOutput.isEmpty == false else {
            return diagnostics
        }
        return "\(diagnostics)\n\n\(commandOutput)"
    }

    private static func fileCandidates() -> [OAuthSession] {
        var sessions: [OAuthSession] = []
        for url in ClaudeCredentialPaths.credentialPaths() {
            guard
                FileManager.default.fileExists(atPath: url.path),
                let json = try? String(contentsOf: url, encoding: .utf8),
                let session = try? ClaudeOAuthParser.parse(json, source: .claudeFile(url))
            else {
                continue
            }
            sessions.append(session)
        }
        return sessions
    }

    static func resolvedExecutable(
        named name: String,
        environment: [String: String],
        explicitPath: String? = nil
    ) -> String? {
        if let explicitPath = explicitPath?.trimmingCharacters(in: .whitespacesAndNewlines),
            explicitPath.isEmpty == false,
            FileManager.default.isExecutableFile(atPath: explicitPath)
        {
            return explicitPath
        }

        if name.contains("/") {
            return FileManager.default.isExecutableFile(atPath: name) ? name : nil
        }

        let path = environment["PATH"] ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        for dir in path.split(separator: ":").map(String.init) {
            let candidate = URL(fileURLWithPath: dir).appendingPathComponent(name).path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func preparedProbeWorkingDirectory() -> URL {
        let fileManager = FileManager.default
        let base =
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directory =
            base
            .appendingPathComponent(AppBrand.displayName, isDirectory: true)
            .appendingPathComponent("ClaudeRepair", isDirectory: true)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let claudeDirectory = directory.appendingPathComponent(".claude", isDirectory: true)
            try fileManager.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)
            let settingsURL = claudeDirectory.appendingPathComponent("settings.local.json")
            let settings = ["disableDeepLinkRegistration": "disable"]
            let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: settingsURL, options: .atomic)
            return directory
        }
        catch {
            return fileManager.temporaryDirectory
        }
    }
}
