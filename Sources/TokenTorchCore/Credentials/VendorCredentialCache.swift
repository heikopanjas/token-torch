import Foundation

/// In-process cache for vendor OAuth sessions so menu bar refresh does not re-read Token Torch-owned Keychain.
enum VendorCredentialCache: @unchecked Sendable {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var claude: OAuthSession?
    private nonisolated(unsafe) static var codex: OAuthSession?
    private nonisolated(unsafe) static var cursor: OAuthSession?

    static func session(for provider: ProviderID) -> OAuthSession? {
        lock.lock()
        defer { lock.unlock() }
        switch provider {
            case .claude: return claude
            case .codex: return codex
            case .cursor: return cursor
        }
    }

    static func claudeSession() -> OAuthSession? {
        session(for: .claude)
    }

    static func codexSession() -> OAuthSession? {
        session(for: .codex)
    }

    static func cursorSession() -> OAuthSession? {
        session(for: .cursor)
    }

    static func store(_ session: OAuthSession, for provider: ProviderID) {
        lock.lock()
        defer { lock.unlock() }
        switch provider {
            case .claude: claude = session
            case .codex: codex = session
            case .cursor: cursor = session
        }
    }

    static func storeClaude(_ session: OAuthSession) {
        store(session, for: .claude)
    }

    static func storeCodex(_ session: OAuthSession) {
        store(session, for: .codex)
    }

    static func storeCursor(_ session: OAuthSession) {
        store(session, for: .cursor)
    }

    static func invalidate(provider: ProviderID) {
        lock.lock()
        defer { lock.unlock() }
        switch provider {
            case .claude: claude = nil
            case .codex: codex = nil
            case .cursor: cursor = nil
        }
    }

    static func invalidateAll() {
        lock.lock()
        defer { lock.unlock() }
        claude = nil
        codex = nil
        cursor = nil
    }
}
