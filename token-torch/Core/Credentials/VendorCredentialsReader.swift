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

    public func sourceLabel() -> String {
        switch self {
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

public struct OAuthSession: Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Int64?
    public let accountID: String?
    public let subscriptionType: String?
    public let rateLimitTier: String?
    public let source: CredentialSource

    public func sourceLabel() -> String {
        return self.source.sourceLabel()
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

    public static func loadClaudeSession() throws -> OAuthSession {
        try loadTokenTorchCopySession(provider: .claude, missingMessage: claudeMissingMessage)
    }

    public static func loadCodexSession() throws -> OAuthSession {
        try loadTokenTorchCopySession(provider: .codex, missingMessage: codexMissingMessage)
    }

    public static func loadCursorSession() throws -> OAuthSession {
        try loadTokenTorchCopySession(provider: .cursor, missingMessage: cursorMissingMessage)
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

    // MARK: - Vendor import (menu bar copy model; read-only vendor stores)

    static func importClaudeSessionFromVendor(interactive: Bool) async throws -> OAuthSession {
        var fileCandidates: [OAuthSession] = []
        for path in Self.claudeCredentialPaths() {
            if let session = try Self.loadClaudeFromFile(path) {
                fileCandidates.append(session)
            }
        }
        if let bestFile = Self.freshest(fileCandidates), Self.sessionIsUsable(bestFile) {
            return bestFile
        }

        let candidates = fileCandidates + (try await Self.claudeKeychainCandidates(interactive: interactive))
        guard let best = Self.freshest(candidates) else {
            throw TokenTorchError.missingCredentials(Self.claudeMissingMessage)
        }
        return best
    }

    /// All Claude sessions found across the candidate Keychain services. A service may hold several
    /// items (e.g. Claude Code's live login under the user account plus a stale copy from another
    /// app/account), so every item is parsed and the freshest is chosen by the caller.
    private static func claudeKeychainCandidates(interactive: Bool) async throws -> [OAuthSession] {
        var sessions: [OAuthSession] = []
        for service in Self.claudeKeychainServices() {
            for json in try await SecurityCLIReader.readAllGenericPasswords(
                service: service,
                timeout: SecurityCLIReader.timeout(interactive: interactive)
            ) {
                if let session = try? Self.parseClaudeJSON(json, source: .claudeKeychain(service: service)) {
                    sessions.append(session)
                }
            }
        }
        return sessions
    }

    static func importCodexSessionFromVendor(interactive: Bool) async throws -> OAuthSession {
        for path in Self.codexAuthPaths() {
            if let session = try Self.loadCodexFromFile(path) {
                return session
            }
        }
        if let json = try await SecurityCLIReader.readGenericPassword(
            service: Self.codexKeychain,
            timeout: SecurityCLIReader.timeout(interactive: interactive)
        ),
            let session = try? Self.parseCodexJSON(json, source: .codexKeychain)
        {
            return session
        }
        throw TokenTorchError.missingCredentials(Self.codexMissingMessage)
    }

    static func importCursorSessionFromVendor(interactive: Bool) async throws -> OAuthSession {
        if let session = try Self.loadCursorFromSQLite() { return session }
        if let session = try await Self.loadCursorFromKeychain(interactive: interactive) { return session }
        throw TokenTorchError.missingCredentials(Self.cursorMissingMessage)
    }

    static func sessionIsUsable(_ session: OAuthSession) -> Bool {
        guard let expiresAt = session.expiresAt ?? JWTHelper.expMs(session.accessToken) else {
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
        return ClaudeCredentialPaths.configDirs()
    }

    private static func claudeKeychainServices() -> [String] {
        return ClaudeCredentialPaths.keychainServices(defaultService: claudeDefaultKeychain)
    }

    private static func claudeCredentialPaths() -> [URL] {
        return ClaudeCredentialPaths.credentialPaths()
    }

    private static func parseClaudeJSON(_ json: String, source: CredentialSource) throws -> OAuthSession {
        return try ClaudeOAuthParser.parse(json, source: source)
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
            expiresAt: JWTHelper.expMs(parsed.tokens.accessToken),
            accountID: parsed.tokens.accountID,
            subscriptionType: nil,
            rateLimitTier: nil,
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
            expiresAt: JWTHelper.expMs(access),
            accountID: nil,
            subscriptionType: membership,
            rateLimitTier: nil,
            source: .cursorSqlite
        )
    }

    private static func loadCursorFromKeychain(interactive: Bool) async throws -> OAuthSession? {
        let timeout = SecurityCLIReader.timeout(interactive: interactive)
        let access = try await SecurityCLIReader.readGenericPassword(service: "cursor-access-token", timeout: timeout)
        let refresh = try await SecurityCLIReader.readGenericPassword(service: "cursor-refresh-token", timeout: timeout)
        guard let access, let refresh else { return nil }
        return OAuthSession(
            accessToken: access,
            refreshToken: refresh,
            expiresAt: JWTHelper.expMs(access),
            accountID: nil,
            subscriptionType: nil,
            rateLimitTier: nil,
            source: .cursorKeychain
        )
    }

    // MARK: - Helpers

    private static func freshness(_ session: OAuthSession) -> Int64 {
        return session.expiresAt ?? JWTHelper.expMs(session.accessToken) ?? 0
    }

    /// The session with the latest expiry. Used to prefer a live login over a stale same-service item.
    static func freshest(_ sessions: [OAuthSession]) -> OAuthSession? {
        return sessions.max(by: { freshness($0) < freshness($1) })
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
