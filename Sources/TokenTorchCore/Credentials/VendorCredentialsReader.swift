import CryptoKit
import Foundation
import SQLite3

public enum CredentialSource: Sendable, Equatable, Codable {
    case claudeKeychain(service: String)
    case claudeFile(URL)
    case codexFile(URL)
    case codexKeychain
    case cursorSqlite
    case cursorKeychain
    case tokenTorchCopy
}

public struct OAuthSession: Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Int64?
    public let accountID: String?
    public let subscriptionType: String?
    public let source: CredentialSource

    public func sourceLabel() -> String {
        switch source {
            case .claudeKeychain(let service):
                "Keychain \"\(service)\""
            case .claudeFile(let url), .codexFile(let url):
                "file \(url.path)"
            case .codexKeychain:
                "Keychain \"Codex Auth\""
            case .cursorSqlite:
                "Cursor state.vscdb"
            case .cursorKeychain:
                "Cursor Keychain"
            case .tokenTorchCopy:
                "Token Torch Keychain copy"
        }
    }
}

public enum VendorCredentialsReader {
    private static let claudeDefaultKeychain = "Claude Code-credentials"
    private static let codexKeychain = "Codex Auth"

    public static func quotaSessionExpired(provider: String, session: OAuthSession, vendorAction: String) -> TokenTorchError {
        .message(
            "\(provider) access token expired or invalid (read from \(session.sourceLabel())). \(vendorAction) Token Torch never writes to vendor credential stores."
        )
    }

    public static func loadClaudeSession(strategy: VendorCredentialStrategy = .directVendorRead) throws -> OAuthSession {
        switch strategy {
            case .directVendorRead:
                return try loadClaudeSessionDirect()
            case .tokenTorchOwnedCopy:
                return try loadTokenTorchCopySession(provider: .claude, missingMessage: claudeMissingMessage)
        }
    }

    public static func loadCodexSession(strategy: VendorCredentialStrategy = .directVendorRead) throws -> OAuthSession {
        switch strategy {
            case .directVendorRead:
                return try loadCodexSessionDirect()
            case .tokenTorchOwnedCopy:
                return try loadTokenTorchCopySession(provider: .codex, missingMessage: codexMissingMessage)
        }
    }

    public static func loadCursorSession(strategy: VendorCredentialStrategy = .directVendorRead) throws -> OAuthSession {
        switch strategy {
            case .directVendorRead:
                return try loadCursorSessionDirect()
            case .tokenTorchOwnedCopy:
                return try loadTokenTorchCopySession(provider: .cursor, missingMessage: cursorMissingMessage)
        }
    }

    // MARK: - Token Torch copy load path

    private static func loadTokenTorchCopySession(provider: ProviderID, missingMessage: String) throws -> OAuthSession {
        if let cached = VendorCredentialCache.session(for: provider) {
            return cached
        }
        guard let session = try TokenTorchVendorCredentialStore.load(provider: provider) else {
            throw TokenTorchError.missingCredentials(missingMessage)
        }
        VendorCredentialCache.store(session, for: provider)
        return session
    }

    // MARK: - Direct vendor read (CLI)

    private static func loadClaudeSessionDirect() throws -> OAuthSession {
        var candidates: [OAuthSession] = []
        for service in claudeKeychainServices() {
            if let json = try readVendorKeychain(service: service, allowUI: false),
                let session = try? parseClaudeJSON(json, source: .claudeKeychain(service: service))
            {
                candidates.append(session)
            }
        }
        for path in claudeCredentialPaths() {
            if let session = try loadClaudeFromFile(path) {
                candidates.append(session)
            }
        }
        guard let best = candidates.max(by: { freshness($0) < freshness($1) }) else {
            throw TokenTorchError.missingCredentials(claudeMissingMessage)
        }
        return best
    }

    private static func loadCodexSessionDirect() throws -> OAuthSession {
        for path in codexAuthPaths() {
            if let session = try loadCodexFromFile(path) {
                return session
            }
        }
        if let json = try readVendorKeychain(service: codexKeychain, allowUI: false),
            let session = try? parseCodexJSON(json, source: .codexKeychain)
        {
            return session
        }
        throw TokenTorchError.missingCredentials(codexMissingMessage)
    }

    private static func loadCursorSessionDirect() throws -> OAuthSession {
        if let session = try loadCursorFromSQLite() { return session }
        if let session = try loadCursorFromKeychain(allowUI: false) { return session }
        throw TokenTorchError.missingCredentials(cursorMissingMessage)
    }

    // MARK: - Vendor import (menu bar copy model; read-only vendor stores)

    static func importClaudeSessionFromVendor() throws -> OAuthSession {
        var fileCandidates: [OAuthSession] = []
        for path in claudeCredentialPaths() {
            if let session = try loadClaudeFromFile(path) {
                fileCandidates.append(session)
            }
        }
        if let bestFile = fileCandidates.max(by: { freshness($0) < freshness($1) }),
            sessionIsUsable(bestFile)
        {
            return bestFile
        }

        var keychainCandidates: [OAuthSession] = []
        for service in claudeKeychainServices() {
            if let json = try readVendorKeychain(service: service, allowUI: true),
                let session = try? parseClaudeJSON(json, source: .claudeKeychain(service: service))
            {
                keychainCandidates.append(session)
            }
        }

        let candidates = fileCandidates + keychainCandidates
        guard let best = candidates.max(by: { freshness($0) < freshness($1) }) else {
            throw TokenTorchError.missingCredentials(claudeMissingMessage)
        }
        return best
    }

    static func importCodexSessionFromVendor() throws -> OAuthSession {
        for path in codexAuthPaths() {
            if let session = try loadCodexFromFile(path) {
                return session
            }
        }
        if let json = try readVendorKeychain(service: codexKeychain, allowUI: true),
            let session = try? parseCodexJSON(json, source: .codexKeychain)
        {
            return session
        }
        throw TokenTorchError.missingCredentials(codexMissingMessage)
    }

    static func importCursorSessionFromVendor() throws -> OAuthSession {
        if let session = try loadCursorFromSQLite() { return session }
        if let session = try loadCursorFromKeychain(allowUI: true) { return session }
        throw TokenTorchError.missingCredentials(cursorMissingMessage)
    }

    static func sessionIsUsable(_ session: OAuthSession) -> Bool {
        guard let expiresAt = session.expiresAt ?? jwtExpMs(session.accessToken) else {
            return true
        }
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        return expiresAt > nowMs + 60_000
    }

    private static let claudeMissingMessage =
        "Claude Code credentials not found. Log in with Claude Code or create ~/.claude/.credentials.json."
    private static let codexMissingMessage =
        "Codex/ChatGPT credentials not found. Log in with the Codex CLI (`codex login`)."
    private static let cursorMissingMessage =
        "Cursor credentials not found. Log in via the Cursor IDE or run `cursor agent login`."

    // MARK: - Claude

    private static func claudeConfigDirs() -> [URL] {
        var dirs: [URL] = []
        if let config = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] {
            dirs.append(URL(fileURLWithPath: config))
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        dirs.append(home.appendingPathComponent(".config/claude"))
        dirs.append(home.appendingPathComponent(".claude"))
        var seen = Set<String>()
        return dirs.filter { seen.insert($0.path).inserted }
    }

    private static func claudeKeychainServices() -> [String] {
        var services: [String] = []
        for dir in claudeConfigDirs() {
            let hash = SHA256.hash(data: Data(dir.path.utf8))
            let hex = hash.map { String(format: "%02x", $0) }.joined()
            services.append("Claude Code-credentials-\(String(hex.prefix(8)))")
        }
        services.append(claudeDefaultKeychain)
        var seen = Set<String>()
        return services.filter { seen.insert($0).inserted }
    }

    private static func claudeCredentialPaths() -> [URL] {
        claudeConfigDirs().map { $0.appendingPathComponent(".credentials.json") }
    }

    private struct ClaudeCredentialsFile: Decodable {
        struct OAuth: Decodable {
            let accessToken: String
            let refreshToken: String
            let expiresAt: Int64?
            let subscriptionType: String?

            enum CodingKeys: String, CodingKey {
                case accessToken, refreshToken, expiresAt, subscriptionType
            }
        }

        let oauth: OAuth

        enum CodingKeys: String, CodingKey {
            case oauth = "claudeAiOauth"
        }
    }

    private static func parseClaudeJSON(_ json: String, source: CredentialSource) throws -> OAuthSession {
        let data = Data(json.utf8)
        let parsed = try JSONDecoder().decode(ClaudeCredentialsFile.self, from: data)
        return OAuthSession(
            accessToken: parsed.oauth.accessToken,
            refreshToken: parsed.oauth.refreshToken,
            expiresAt: parsed.oauth.expiresAt,
            accountID: nil,
            subscriptionType: parsed.oauth.subscriptionType,
            source: source
        )
    }

    private static func loadClaudeFromFile(_ url: URL) throws -> OAuthSession? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let json = try String(contentsOf: url, encoding: .utf8)
        return try parseClaudeJSON(json, source: .claudeFile(url))
    }

    // MARK: - Codex

    private static func codexAuthPaths() -> [URL] {
        var paths: [URL] = []
        if let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"] {
            paths.append(URL(fileURLWithPath: codexHome).appendingPathComponent("auth.json"))
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        paths.append(home.appendingPathComponent(".config/codex/auth.json"))
        paths.append(home.appendingPathComponent(".codex/auth.json"))
        return paths
    }

    private struct CodexAuthFile: Decodable {
        struct Tokens: Decodable {
            let accessToken: String
            let refreshToken: String
            let accountID: String?

            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
                case refreshToken = "refresh_token"
                case accountID = "account_id"
            }
        }

        let tokens: Tokens
    }

    private static func parseCodexJSON(_ json: String, source: CredentialSource) throws -> OAuthSession {
        let parsed = try JSONDecoder().decode(CodexAuthFile.self, from: Data(json.utf8))
        return OAuthSession(
            accessToken: parsed.tokens.accessToken,
            refreshToken: parsed.tokens.refreshToken,
            expiresAt: jwtExpMs(parsed.tokens.accessToken),
            accountID: parsed.tokens.accountID,
            subscriptionType: nil,
            source: source
        )
    }

    private static func loadCodexFromFile(_ url: URL) throws -> OAuthSession? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let json = try String(contentsOf: url, encoding: .utf8)
        return try parseCodexJSON(json, source: .codexFile(url))
    }

    // MARK: - Cursor

    private static func cursorStateDBPath() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
    }

    private static func loadCursorFromSQLite() throws -> OAuthSession? {
        let path = cursorStateDBPath()
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        let access = try readSQLiteValue(dbPath: path, key: "cursorAuth/accessToken")
        let refresh = try readSQLiteValue(dbPath: path, key: "cursorAuth/refreshToken")
        let membership = try readSQLiteValue(dbPath: path, key: "cursorAuth/stripeMembershipType")
        guard let access, let refresh else { return nil }
        return OAuthSession(
            accessToken: access,
            refreshToken: refresh,
            expiresAt: jwtExpMs(access),
            accountID: nil,
            subscriptionType: membership,
            source: .cursorSqlite
        )
    }

    private static func loadCursorFromKeychain(allowUI: Bool) throws -> OAuthSession? {
        let access = try readVendorKeychain(service: "cursor-access-token", allowUI: allowUI)
        let refresh = try readVendorKeychain(service: "cursor-refresh-token", allowUI: allowUI)
        guard let access, let refresh else { return nil }
        return OAuthSession(
            accessToken: access,
            refreshToken: refresh,
            expiresAt: jwtExpMs(access),
            accountID: nil,
            subscriptionType: nil,
            source: .cursorKeychain
        )
    }

    // MARK: - Helpers

    private static func freshness(_ session: OAuthSession) -> Int64 {
        session.expiresAt ?? jwtExpMs(session.accessToken) ?? 0
    }

    private static func jwtExpMs(_ token: String) -> Int64? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1])
        base64 = base64.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let padding = (4 - base64.count % 4) % 4
        base64 += String(repeating: "=", count: padding)
        guard let data = Data(base64Encoded: base64),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let exp = json["exp"] as? Int64
        else { return nil }
        return exp * 1000
    }

    private static func readVendorKeychain(service: String, allowUI: Bool) throws -> String? {
        try KeychainReader.readGenericPassword(service: service, allowUI: allowUI)
    }

    private static func readSQLiteValue(dbPath: URL, key: String) throws -> String? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            throw TokenTorchError.message("Failed to open Cursor state database at \(dbPath.path). Close Cursor and retry.")
        }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        let sql = "SELECT value FROM ItemTable WHERE key = ?1"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, key, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        guard let cString = sqlite3_column_text(stmt, 0) else { return nil }
        let value = String(cString: cString)
        return value.isEmpty ? nil : value
    }
}
