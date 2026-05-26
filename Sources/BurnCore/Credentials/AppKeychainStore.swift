import Foundation

public protocol AppKeychainStoring: Sendable {
    func load(provider: ProviderID, kind: AppKeyKind) throws -> String?
    func save(provider: ProviderID, kind: AppKeyKind, value: String) throws
    func delete(provider: ProviderID, kind: AppKeyKind) throws
    func hasKey(provider: ProviderID, kind: AppKeyKind) throws -> Bool
}

/// Persists burn admin keys in the macOS Keychain (`com.burn.keys.*`).
public final class AppKeychainStore: AppKeychainStoring, @unchecked Sendable {
    public static let shared = AppKeychainStore()
    private let account = "burn"

    public init() {}

    public func load(provider: ProviderID, kind: AppKeyKind) throws -> String? {
        try KeychainReader.readGenericPassword(service: kind.service(for: provider), account: account)
    }

    public func save(provider: ProviderID, kind: AppKeyKind, value: String) throws {
        try KeychainReader.saveGenericPassword(
            service: kind.service(for: provider),
            account: account,
            value: value
        )
    }

    public func delete(provider: ProviderID, kind: AppKeyKind) throws {
        try KeychainReader.deleteGenericPassword(service: kind.service(for: provider), account: account)
    }

    public func hasKey(provider: ProviderID, kind: AppKeyKind) throws -> Bool {
        try load(provider: provider, kind: kind) != nil
    }
}

public final class InMemoryAppKeychainStore: AppKeychainStoring, @unchecked Sendable {
    private var storage: [String: String] = [:]
    private let lock = NSLock()

    public init() {}

    private func key(provider: ProviderID, kind: AppKeyKind) -> String {
        kind.service(for: provider)
    }

    public func load(provider: ProviderID, kind: AppKeyKind) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key(provider: provider, kind: kind)]
    }

    public func save(provider: ProviderID, kind: AppKeyKind, value: String) throws {
        lock.lock()
        defer { lock.unlock() }
        storage[key(provider: provider, kind: kind)] = value
    }

    public func delete(provider: ProviderID, kind: AppKeyKind) throws {
        lock.lock()
        defer { lock.unlock() }
        storage.removeValue(forKey: key(provider: provider, kind: kind))
    }

    public func hasKey(provider: ProviderID, kind: AppKeyKind) throws -> Bool {
        try load(provider: provider, kind: kind) != nil
    }
}
