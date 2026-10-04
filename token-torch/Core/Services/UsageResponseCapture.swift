import Foundation
import Synchronization

/// Headless `--capture-usage-responses <directory>` mode: fetches each subscription usage endpoint
/// through the regular provider path and writes the raw response body, re-indented but otherwise
/// unmodified, plus its response headers (minus `Set-Cookie`) to the reference file names used in
/// `docs/`. Output contains account identifiers (email, user/account IDs) and must be scrubbed by hand
/// before it is committed.
public enum UsageResponseCapture {
    public static let invocationArgument = "--capture-usage-responses"

    private struct Target: Sendable {
        let provider: ProviderID
        let usageURL: URL
        let baseName: String
    }

    private struct RecordedResponse: Sendable {
        let headers: [String: String]
        let body: Data
    }

    private static let targets = [
        Target(provider: .claude, usageURL: ClaudeQuotaProvider.usageURL, baseName: "claude-code-usage-response"),
        Target(provider: .codex, usageURL: CodexQuotaProvider.usageURL, baseName: "codex-usage-response"),
        Target(provider: .copilot, usageURL: CopilotQuotaProvider.usageURL, baseName: "copilot-usage-response")
    ]

    /// Session cookies are credentials, so they never reach the output even though the capture is unredacted.
    private static let excludedHeader = "set-cookie"

    /// Keeps the last successful response received from one usage URL.
    private final class ResponseRecorder: Sendable {
        private let usageURL: URL
        private let response = Mutex<RecordedResponse?>(nil)

        init(usageURL: URL) {
            self.usageURL = usageURL
        }

        var recordedResponse: RecordedResponse? {
            return self.response.withLock { $0 }
        }

        func record(url: URL, statusCode: Int, headers: [String: String], body: Data) -> Void {
            guard url == self.usageURL else {
                return
            }
            guard (200 ..< 300).contains(statusCode) == true else {
                return
            }
            self.response.withLock { $0 = RecordedResponse(headers: headers, body: body) }
        }
    }

    /// If launched with the capture argument, runs the capture and exits; otherwise returns normally.
    public static func runIfRequested(arguments: [String] = CommandLine.arguments) -> Void {
        guard let markerIndex = arguments.firstIndex(of: Self.invocationArgument) else {
            return
        }
        guard markerIndex + 1 < arguments.count else {
            Self.writeError("Usage: \(Self.invocationArgument) <directory>")
            exit(EX_USAGE)
        }
        let directory = URL(fileURLWithPath: arguments[markerIndex + 1], isDirectory: true)
        Task {
            let succeeded = await Self.capture(into: directory)
            exit((succeeded == true) ? EXIT_SUCCESS : EXIT_FAILURE)
        }
        dispatchMain()
    }

    private static func capture(into directory: URL) async -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        catch {
            Self.writeError("Cannot create \(directory.path): \(error.localizedDescription)")
            return false
        }
        let orchestrator = UsageOrchestrator()
        var succeeded = true
        // Sequential so any Keychain authorization dialogs appear one at a time.
        for target in Self.targets {
            let name = target.provider.quotaDisplayName
            do {
                let files = try await Self.capture(target, into: directory, orchestrator: orchestrator)
                for file in files {
                    print("\(name): wrote \(file.path)")
                }
            }
            catch {
                succeeded = false
                Self.writeError("\(name): \(Redaction.redactSecrets(error.localizedDescription))")
            }
        }
        return succeeded
    }

    private static func capture(_ target: Target, into directory: URL, orchestrator: UsageOrchestrator) async throws -> [URL] {
        let recorder = ResponseRecorder(usageURL: target.usageURL)
        let report = await HTTPClient.$responseRecorder.withValue({ url, statusCode, headers, body in
            recorder.record(url: url, statusCode: statusCode, headers: headers, body: body)
        }) {
            return await orchestrator.fetchSubscription(provider: target.provider)
        }
        switch report {
            case .subscription:
                guard let response = recorder.recordedResponse else {
                    throw TokenTorchError.message("no response received from \(target.usageURL.absoluteString)")
                }
                let bodyFile = directory.appendingPathComponent("\(target.baseName).json")
                try JSONPrettyPrinter.prettyPrinted(response.body).write(to: bodyFile, options: .atomic)
                let headers = response.headers.filter { $0.key.lowercased() != Self.excludedHeader }
                var headerData = try JSONSerialization.data(withJSONObject: headers, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
                headerData.append(Data("\n".utf8))
                let headersFile = directory.appendingPathComponent("\(target.baseName).headers.json")
                try headerData.write(to: headersFile, options: .atomic)
                return [bodyFile, headersFile]
            case .needsAuthorization:
                throw TokenTorchError.message("needs authorization; open Token Torch and choose Refresh once, then retry")
            case .error(_, _, let message, _, _):
                throw TokenTorchError.message(message)
            case .org:
                throw TokenTorchError.message("unexpected org billing report")
        }
    }

    private static func writeError(_ message: String) -> Void {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
    }
}
