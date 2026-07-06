import CryptoKit
import Darwin
import Foundation

enum ClaudeCredentialRepair {
    static let doctorTouchArguments = ["doctor"]

    private static let securityPath = "/usr/bin/security"
    private static let securityTimeout: TimeInterval = 1.5
    private static let repairTimeout: TimeInterval = 20
    private static let pollInterval: TimeInterval = 0.5
    private static let defaultKeychainService = "Claude Code-credentials"

    static func repairAndImport(
        baseline: OAuthSession?,
        claudeExecutablePath: String? = nil,
        timeout: TimeInterval = repairTimeout,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async throws -> OAuthSession {
        if let current = try await currentNoPromptSession(),
            shouldImport(current, comparedTo: baseline)
        {
            try saveTokenTorchCopy(current)
            return current
        }

        let touchResult: Result<Void, Error>
        do {
            try await touchClaudeCLIAuthPath(
                timeout: min(timeout, 12),
                environment: environment,
                claudeExecutablePath: claudeExecutablePath
            )
            touchResult = .success(())
        }
        catch {
            touchResult = .failure(error)
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try Task.checkCancellation()
            if let current = try await currentNoPromptSession(),
                shouldImport(current, comparedTo: baseline)
            {
                try saveTokenTorchCopy(current)
                return current
            }
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }

        switch touchResult {
            case .success:
                throw TokenTorchError.claudeRepairFailed(
                    "Claude Code repair ran, but the Keychain access token did not change. Run `claude doctor` in a terminal (or launch Claude Code), then retry Token Torch refresh."
                )
            case .failure(let error):
                throw TokenTorchError.claudeRepairFailed(
                    "Claude Code repair did not update credentials: \(error.localizedDescription). Run `claude doctor` in a terminal, then retry Token Torch refresh."
                )
        }
    }

    static func currentNoPromptSession() async throws -> OAuthSession? {
        var candidates = fileCandidates()
        if let keychain = try await currentSecurityCLISession() {
            candidates.append(keychain)
        }
        return VendorCredentialsReader.freshest(candidates)
    }

    static func currentSecurityCLISession() async throws -> OAuthSession? {
        var candidates: [OAuthSession] = []
        for service in ClaudeCredentialPaths.keychainServices(defaultService: defaultKeychainService) {
            for account in accountCandidates(for: service) {
                guard let json = try? await readSecurityCLI(service: service, account: account) else { continue }
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

    private static func readSecurityCLI(service: String, account: String?) async throws -> String {
        var arguments = ["find-generic-password", "-s", service]
        if let account, account.isEmpty == false {
            arguments.append(contentsOf: ["-a", account])
        }
        arguments.append("-w")

        let data = try await runCommand(
            executablePath: securityPath,
            arguments: arguments,
            timeout: securityTimeout
        )
        let value = String(data: data, encoding: .utf8) ?? ""
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw TokenTorchError.missingCredentials("Claude Code Keychain item was empty.")
        }
        return trimmed
    }

    private static func touchClaudeCLIAuthPath(
        timeout: TimeInterval,
        environment: [String: String],
        claudeExecutablePath: String?
    ) async throws {
        guard
            let claudePath = resolvedExecutable(
                named: "claude",
                environment: environment,
                explicitPath: claudeExecutablePath
            )
        else {
            throw TokenTorchError.message(
                "Claude CLI is not installed or not on PATH. Set the Claude CLI path in Settings > Claude."
            )
        }

        _ = try await runCommand(
            executablePath: claudePath,
            arguments: Self.doctorTouchArguments,
            input: "\n",
            timeout: timeout,
            environment: environment,
            workingDirectory: preparedProbeWorkingDirectory()
        )
    }

    private static func runCommand(
        executablePath: String,
        arguments: [String],
        input: String? = nil,
        timeout: TimeInterval,
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil
    ) async throws -> Data {
        try await Task.detached(priority: .utility) {
            try runCommandSynchronously(
                executablePath: executablePath,
                arguments: arguments,
                input: input,
                timeout: timeout,
                environment: environment,
                workingDirectory: workingDirectory
            )
        }.value
    }

    private static func runCommandSynchronously(
        executablePath: String,
        arguments: [String],
        input: String?,
        timeout: TimeInterval,
        environment: [String: String]?,
        workingDirectory: URL?
    ) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = workingDirectory

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let inputPipe: Pipe?
        if input != nil {
            let pipe = Pipe()
            process.standardInput = pipe
            inputPipe = pipe
        }
        else {
            inputPipe = nil
        }

        do {
            try process.run()
        }
        catch {
            throw TokenTorchError.message("Failed to launch \(executablePath): \(error.localizedDescription)")
        }

        var processGroup: pid_t?
        let pid = process.processIdentifier
        if setpgid(pid, pid) == 0 {
            processGroup = pid
        }

        if let input, let inputPipe {
            if let data = input.data(using: .utf8) {
                inputPipe.fileHandleForWriting.write(data)
            }
            try? inputPipe.fileHandleForWriting.close()
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }

        if process.isRunning == true {
            terminate(process: process, processGroup: processGroup)
            throw TokenTorchError.message("\(URL(fileURLWithPath: executablePath).lastPathComponent) timed out.")
        }

        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = errorPipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let message = String(data: errorOutput, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let fallback = "\(executablePath) exited with status \(process.terminationStatus)."
            throw TokenTorchError.message(message?.isEmpty == false ? message ?? fallback : fallback)
        }
        return output
    }

    private static func terminate(process: Process, processGroup: pid_t?) {
        guard process.isRunning == true else { return }
        process.terminate()
        if let processGroup {
            kill(-processGroup, SIGTERM)
        }

        let deadline = Date().addingTimeInterval(0.4)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning == true {
            if let processGroup {
                kill(-processGroup, SIGKILL)
            }
            kill(process.processIdentifier, SIGKILL)
        }
    }

    private static func accountCandidates(for service: String) -> [String?] {
        let accounts = KeychainReader.genericPasswordMetadata(service: service)
            .items
            .compactMap(\.account)
            .filter { !$0.isEmpty }

        var seen = Set<String>()
        let uniqueAccounts = accounts.filter { seen.insert($0).inserted }
        return uniqueAccounts.map(Optional.some) + [nil]
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
