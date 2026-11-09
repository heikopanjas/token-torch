import CryptoKit
import Foundation

enum ClaudeCredentialRepair {
    static let usageRefreshShellPath = "/bin/zsh"
    /// An empty `$2` unsets `CLAUDE_CONFIG_DIR`: Claude Code reads some paths with `??`, so an empty value would put
    /// its settings, skills and agents relative to the working directory instead of `~/.claude`.
    /// An empty `$3` drops `--debug-file`, because only `ClaudeRepairLog` reads that output.
    static let usageRefreshShellScript =
        #"if [[ -n "$2" ]]; then export CLAUDE_CONFIG_DIR="$2"; else unset CLAUDE_CONFIG_DIR; fi; ANTHROPIC_API_KEY="" exec "$1" -p "/usage" ${3:+--debug-file} ${3:+"$3"}"#

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

    /// - Parameter trigger: why repair runs; recorded in `ClaudeRepairLog` only.
    static func repairAndImport(
        baseline: OAuthSession?,
        trigger: String,
        interactive: Bool = false,
        claudeExecutablePath: String? = nil,
        timeout: TimeInterval = repairTimeout,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async throws -> OAuthSession {
        let attemptID = ClaudeRepairLog.makeAttemptID()
        let started = Date()
        ClaudeRepairLog.write(
            "repair started: \(trigger) (interactive: \(interactive))\nToken Torch copy: \(ClaudeRepairLog.describe(baseline))",
            attemptID: attemptID
        )
        do {
            let session = try await Self.repair(
                baseline: baseline,
                interactive: interactive,
                claudeExecutablePath: claudeExecutablePath,
                timeout: timeout,
                environment: environment,
                attemptID: attemptID
            )
            ClaudeRepairLog.write(
                "repair succeeded after \(Self.elapsedSeconds(since: started)); imported \(ClaudeRepairLog.describe(session))",
                attemptID: attemptID
            )
            return session
        }
        catch {
            ClaudeRepairLog.write(
                "repair failed after \(Self.elapsedSeconds(since: started)): \(error.localizedDescription)",
                attemptID: attemptID
            )
            throw error
        }
    }

    private static func repair(
        baseline: OAuthSession?,
        interactive: Bool,
        claudeExecutablePath: String?,
        timeout: TimeInterval,
        environment: [String: String],
        attemptID: String
    ) async throws -> OAuthSession {
        let discovered = try await Self.currentNoPromptSession(interactive: interactive)
        ClaudeRepairLog.write("vendor session before running claude: \(ClaudeRepairLog.describe(discovered))", attemptID: attemptID)
        if let current = discovered, Self.shouldImport(current, comparedTo: baseline) == true {
            ClaudeRepairLog.write("vendor session is newer than the Token Torch copy; importing without running claude", attemptID: attemptID)
            try Self.saveTokenTorchCopy(current)
            return current
        }

        let configDir = Self.selectedRepairConfigDirEnvironmentValue(baseline: baseline, discovered: discovered)
        let claudePath = Self.resolvedExecutable(named: "claude", environment: environment, explicitPath: claudeExecutablePath)
        let diagnostics = Self.repairDiagnostics(
            configDir: configDir,
            baseline: baseline,
            environment: environment,
            claudePath: claudePath
        )
        guard let claudePath else {
            // Nothing can refresh the vendor session, so fail without polling for it.
            ClaudeRepairLog.write("claude not found\n\(diagnostics)", attemptID: attemptID)
            throw TokenTorchError.claudeRepairFailed(message: Self.claudeNotFoundMessage, commandOutput: diagnostics)
        }
        ClaudeRepairLog.write("running claude\n\(diagnostics)", attemptID: attemptID)
        let debugLogURL: URL?
        if ClaudeRepairLog.isEnabled() == true {
            debugLogURL = FileManager.default.temporaryDirectory.appendingPathComponent("token-torch-claude-repair-\(attemptID).log")
        }
        else {
            debugLogURL = nil
        }
        let commandStarted = Date()
        let touchResult: Result<String?, Error>
        do {
            let commandOutput = try await Self.refreshClaudeCLIAuthPath(
                claudePath: claudePath,
                timeout: min(timeout, Self.commandTimeout),
                environment: environment,
                configDir: configDir,
                debugLogPath: debugLogURL?.path ?? ""
            )
            touchResult = .success(commandOutput)
        }
        catch {
            touchResult = .failure(error)
        }

        let commandOutput: String?
        let commandOutcome: String
        switch touchResult {
            case .success(let output):
                commandOutput = output
                commandOutcome = "exited with status 0"
            case .failure(let error):
                if case TokenTorchError.claudeRepairFailed(_, let output) = error {
                    commandOutput = output
                }
                else {
                    commandOutput = nil
                }
                commandOutcome = "failed: \(error.localizedDescription)"
        }
        // Read outside the autoclosure, so the temporary file is deleted even if the log was turned off during the run.
        let debugLog = debugLogURL.map(Self.consumeDebugLog) ?? "(not requested)"
        ClaudeRepairLog.write(
            [
                "claude \(commandOutcome) after \(Self.elapsedSeconds(since: commandStarted))",
                "terminal output:",
                commandOutput ?? "(none)",
                "claude debug log:",
                debugLog
            ].joined(separator: "\n"),
            attemptID: attemptID
        )

        let deadline = Date().addingTimeInterval(timeout)
        let pollStarted = Date()
        var checks = 0
        var lastSeen = discovered
        while Date() < deadline {
            try Task.checkCancellation()
            checks += 1
            lastSeen = try await Self.currentNoPromptSession(interactive: interactive)
            if let current = lastSeen, Self.shouldImport(current, comparedTo: baseline) == true {
                ClaudeRepairLog.write(
                    "vendor session changed after \(checks) checks (\(Self.elapsedSeconds(since: pollStarted)))",
                    attemptID: attemptID
                )
                try Self.saveTokenTorchCopy(current)
                return current
            }
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
        ClaudeRepairLog.write(
            "vendor session unchanged after \(checks) checks (\(Self.elapsedSeconds(since: pollStarted))): \(ClaudeRepairLog.describe(lastSeen))",
            attemptID: attemptID
        )

        let manualCommand = Self.manualRefreshCommand(configDir: configDir)
        let combinedOutput = Self.combinedDiagnosticOutput(diagnostics: diagnostics, commandOutput: commandOutput)
        switch touchResult {
            case .success:
                throw TokenTorchError.claudeRepairFailed(
                    message:
                        "Claude Code repair ran, but the Keychain access token did not change. Run `\(manualCommand)` in a terminal, then retry Token Torch refresh.",
                    commandOutput: combinedOutput
                )
            case .failure(let error):
                throw TokenTorchError.claudeRepairFailed(
                    message:
                        "Claude Code repair did not update credentials: \(Self.sentence(error.localizedDescription)) Run `\(manualCommand)` in a terminal, then retry Token Torch refresh.",
                    commandOutput: combinedOutput
                )
        }
    }

    /// The command a user can run by hand to refresh the same profile repair targets.
    static func manualRefreshCommand(configDir: String) -> String {
        if configDir.isEmpty == true {
            return #"env -u CLAUDE_CONFIG_DIR ANTHROPIC_API_KEY="" claude -p "/usage""#
        }
        return #"CLAUDE_CONFIG_DIR="\#(configDir)" ANTHROPIC_API_KEY="" claude -p "/usage""#
    }

    static let claudeNotFoundMessage =
        "Claude Code repair could not find the claude CLI on PATH, in ~/.local/bin, ~/.claude/local, /opt/homebrew/bin or /usr/local/bin. Set the Claude CLI path in Settings > Claude."

    /// Ends `text` with a period unless it already ends with sentence punctuation.
    private static func sentence(_ text: String) -> String {
        guard let last = text.last, ".!?".contains(last) == false else { return text }
        return "\(text)."
    }

    private static func elapsedSeconds(since start: Date) -> String {
        return String(format: "%.1fs", Date().timeIntervalSince(start))
    }

    /// Reads and deletes Claude Code's `--debug-file` output for the repair log.
    private static func consumeDebugLog(at url: URL) -> String {
        defer { try? FileManager.default.removeItem(at: url) }
        guard let contents = try? String(contentsOf: url, encoding: .utf8), contents.isEmpty == false else {
            return "(not written)"
        }
        return contents.trimmingCharacters(in: .whitespacesAndNewlines)
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

    /// `CLAUDE_CONFIG_DIR` value for the repair command; empty means the shell unsets it for Claude Code's default profile.
    static func selectedRepairConfigDirEnvironmentValue(
        baseline: OAuthSession?,
        discovered: OAuthSession? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        if let baseline, let configDir = ClaudeCredentialPaths.configDirEnvironmentValue(for: baseline.source, environment: environment) {
            return configDir
        }
        if let discovered, let configDir = ClaudeCredentialPaths.configDirEnvironmentValue(for: discovered.source, environment: environment) {
            return configDir
        }
        if let stored = VendorCredentialImportSourceStore.load(provider: .claude),
            let configDir = ClaudeCredentialPaths.configDirEnvironmentValue(for: stored, environment: environment)
        {
            return configDir
        }
        return ClaudeCredentialPaths.preferredDefaultConfigDirEnvironmentValue()
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
        claudePath: String,
        timeout: TimeInterval,
        environment: [String: String],
        configDir: String,
        debugLogPath: String
    ) async throws -> String? {
        let result = try await ProcessRunner.runInPseudoTerminal(
            executablePath: Self.usageRefreshShellPath,
            arguments: Self.usageRefreshShellArguments(claudePath: claudePath, configDir: configDir, debugLogPath: debugLogPath),
            timeout: timeout,
            environment: environment,
            workingDirectory: Self.preparedProbeWorkingDirectory()
        )
        return try Self.validateUsageRefreshResult(result, executablePath: claudePath)
    }

    static func usageRefreshShellArguments(claudePath: String, configDir: String, debugLogPath: String) -> [String] {
        return [
            "-c",
            Self.usageRefreshShellScript,
            "token-torch-claude-repair",
            claudePath,
            configDir,
            debugLogPath
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
        configDir: String,
        baseline: OAuthSession?,
        environment: [String: String],
        claudePath: String?
    ) -> String {
        let configDirLabel: String
        if configDir.isEmpty == true {
            configDirLabel = "default (CLAUDE_CONFIG_DIR unset)"
        }
        else {
            configDirLabel = configDir
        }
        let sourceLabel =
            baseline?.sourceLabel()
            ?? VendorCredentialImportSourceStore.load(provider: .claude)?.sourceLabel()
            ?? "none"
        let executable = claudePath.map(Self.executableLabel) ?? "<not found>"
        let workingDirectory = Self.preparedProbeWorkingDirectory().path
        let authStates = Self.authenticationEnvironmentStates(environment: environment)
            .map { "\($0.key)=\($0.state)" }
            .joined(separator: ", ")
        return Redaction.redactSecrets(
            [
                "repair diagnostics:",
                "config directory: \(configDirLabel)",
                "credential source: \(sourceLabel)",
                "claude executable: \(executable)",
                "working directory: \(workingDirectory)",
                "auth selectors: \(authStates)",
                "repair log: \(ClaudeRepairLog.statusLabel())"
            ].joined(separator: "\n")
        )
    }

    /// The path plus its symlink target, which names the Claude Code version (`~/.local/bin/claude -> …/versions/2.1.311`).
    private static func executableLabel(_ path: String) -> String {
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        if resolved == path {
            return path
        }
        return "\(path) -> \(resolved)"
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

    /// Searched after `PATH`: apps launched from Finder or at login get launchd's minimal `PATH`, which misses
    /// Claude Code's native installer (`~/.local/bin`), its legacy local install (`~/.claude/local`), and Homebrew.
    static func fallbackExecutableDirectories(homeDirectory: URL) -> [String] {
        return [
            homeDirectory.appendingPathComponent(".local/bin").path,
            homeDirectory.appendingPathComponent(".claude/local").path,
            "/opt/homebrew/bin",
            "/usr/local/bin"
        ]
    }

    static func resolvedExecutable(
        named name: String,
        environment: [String: String],
        explicitPath: String? = nil,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
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

        let pathDirectories = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        for dir in pathDirectories + Self.fallbackExecutableDirectories(homeDirectory: homeDirectory) {
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
