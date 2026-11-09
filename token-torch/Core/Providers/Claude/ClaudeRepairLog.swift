import Foundation

/// Append-only diagnostics file for Claude Code credential repair (`~/Library/Logs/Token Torch/claude-repair.log`).
/// Off by default in every build configuration; `enableCommand` turns it on to analyze a failing repair.
/// Entries never contain token values: a session appears only as a short SHA-256 fingerprint plus its expiry.
enum ClaudeRepairLog {
    static let enableCommand = "defaults write \(AppBrand.bundleIdentifier) \(AppBrand.claudeRepairLogEnabledKey) -bool true"

    private static let maximumFileSize: UInt64 = 1_048_576
    private static let fingerprintLength = 12
    private static let timestampStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        return defaults.bool(forKey: AppBrand.claudeRepairLogEnabledKey)
    }

    /// The `repair log:` diagnostics value. A failed repair's error row is the one place a user learns the log exists.
    static func statusLabel(defaults: UserDefaults = .standard) -> String {
        if Self.isEnabled(defaults: defaults) == true {
            return Self.fileURL().path
        }
        return "off (enable with `\(Self.enableCommand)`)"
    }

    static func fileURL() -> URL {
        let fileManager = FileManager.default
        let library =
            fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library", isDirectory: true)
        return
            library
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent(AppBrand.displayName, isDirectory: true)
            .appendingPathComponent("claude-repair.log")
    }

    static func makeAttemptID() -> String {
        return String(UUID().uuidString.prefix(8)).lowercased()
    }

    /// Appends one redacted entry when the log is on; continuation lines are indented. Write failures are ignored so logging never breaks repair.
    /// The message is an autoclosure so a disabled log doesn't hash tokens to build it.
    static func write(
        _ message: @autoclosure () -> String,
        attemptID: String,
        now: Date = Date(),
        fileURL: URL = Self.fileURL(),
        defaults: UserDefaults = .standard
    ) -> Void {
        guard Self.isEnabled(defaults: defaults) == true else {
            return
        }
        let prefix = "\(now.formatted(Self.timestampStyle)) [\(attemptID)] "
        let body = Redaction.redactSecrets(message()).replacingOccurrences(of: "\n", with: "\n    ")
        Self.append(Data((prefix + body + "\n").utf8), to: fileURL)
    }

    static func describe(_ session: OAuthSession?, now: Date = Date()) -> String {
        guard let session else {
            return "none"
        }
        let fingerprint = ClaudeCredentialRepair.accessTokenFingerprint(session).map { String($0.prefix(Self.fingerprintLength)) } ?? "none"
        let expiry: String
        if let expiresAt = session.expiresAt ?? JWTHelper.expMs(session.accessToken) {
            let date = Date(timeIntervalSince1970: TimeInterval(expiresAt) / 1000)
            expiry = "\(date.formatted(Self.timestampStyle)) (\(Int(date.timeIntervalSince(now).rounded()))s from now)"
        }
        else {
            expiry = "unknown"
        }
        return
            "\(session.sourceLabel()), token sha256 \(fingerprint), expires \(expiry), usable \(VendorCredentialsReader.sessionIsUsable(session))"
    }

    private static func append(_ data: Data, to fileURL: URL) -> Void {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = (try? fileManager.attributesOfItem(atPath: fileURL.path))?[.size] as? NSNumber, size.uint64Value >= Self.maximumFileSize {
            let previous = fileURL.appendingPathExtension("1")
            try? fileManager.removeItem(at: previous)
            try? fileManager.moveItem(at: fileURL, to: previous)
        }
        // O_APPEND keeps concurrent repairs from overwriting each other's entries.
        let descriptor = open(fileURL.path, O_WRONLY | O_APPEND | O_CREAT, 0o600)
        guard descriptor >= 0 else {
            return
        }
        defer { close(descriptor) }
        data.withUnsafeBytes { buffer in
            _ = Darwin.write(descriptor, buffer.baseAddress, buffer.count)
        }
    }
}
