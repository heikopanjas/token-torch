import CryptoKit
import Foundation

enum ClaudeCredentialRepair {
    static let usageRefreshShellPath = "/bin/zsh"
    static let usageRefreshShellScript = #"ANTHROPIC_API_KEY="" exec "$1" -p "/usage""#

    private static let repairTimeout: TimeInterval = 20
    private static let pollInterval: TimeInterval = 0.5
    private static let defaultKeychainService = "Claude Code-credentials"

    static func repairAndImport(
        baseline: OAuthSession?,
        interactive: Bool = false,
        claudeExecutablePath: String? = nil,
        timeout: TimeInterval = repairTimeout,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async throws -> OAuthSession {
        if let current = try await Self.currentNoPromptSession(interactive: interactive),
            shouldImport(current, comparedTo: baseline)
        {
            try saveTokenTorchCopy(current)
            return current
        }

        let touchResult: Result<String?, Error>
        do {
            let commandOutput = try await Self.refreshClaudeCLIAuthPath(
                timeout: min(timeout, 12),
                environment: environment,
                claudeExecutablePath: claudeExecutablePath
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
                shouldImport(current, comparedTo: baseline)
            {
                try saveTokenTorchCopy(current)
                return current
            }
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }

        switch touchResult {
            case .success(let commandOutput):
                throw TokenTorchError.claudeRepairFailed(
                    message:
                        "Claude Code repair ran, but the Keychain access token did not change. Run `ANTHROPIC_API_KEY=\"\" claude -p \"/usage\"` in a terminal, then retry Token Torch refresh.",
                    commandOutput: commandOutput
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
                        "Claude Code repair did not update credentials: \(error.localizedDescription). Run `ANTHROPIC_API_KEY=\"\" claude -p \"/usage\"` in a terminal, then retry Token Torch refresh.",
                    commandOutput: commandOutput
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
        claudeExecutablePath: String?
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
            arguments: Self.usageRefreshShellArguments(claudePath: claudePath),
            timeout: timeout,
            environment: environment,
            workingDirectory: Self.preparedProbeWorkingDirectory()
        )
        return try Self.validateUsageRefreshResult(result, executablePath: claudePath)
    }

    static func usageRefreshShellArguments(claudePath: String) -> [String] {
        return ["-c", Self.usageRefreshShellScript, "token-torch-claude-repair", claudePath]
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
