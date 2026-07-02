import Foundation
import Security

enum KeychainReader {
    /// Reads a generic password via `SecItemCopyMatching`.
    static func readGenericPassword(
        service: String,
        account: String? = nil,
        allowUI: Bool = false
    ) throws -> String? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        if allowUI == false {
            query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip
        }

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
            case errSecSuccess:
                guard let data = item as? Data,
                    let value = String(data: data, encoding: .utf8)
                else {
                    throw TokenTorchError.message("Keychain read failed for \"\(service)\"")
                }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            case errSecItemNotFound:
                return nil
            case errSecAuthFailed, errSecUserCanceled, errSecInteractionNotAllowed:
                return nil
            default:
                throw TokenTorchError.message("Keychain read failed for \"\(service)\"")
        }
    }

    /// Reads every generic password matching `service` (across all accounts), picking up each item.
    ///
    /// A vendor service can hold more than one item — e.g. Claude Code's live login (account = the
    /// macOS user) plus a stale copy left by another app/account. `kSecMatchLimitOne` returns an
    /// arbitrary one, and a single `kSecReturnData` + `kSecMatchLimitAll` read fails outright when the
    /// matches have different access ACLs. So: enumerate accounts via an attributes-only query (which
    /// never triggers an ACL prompt), then read each item individually so a protected item prompts or
    /// skips on its own without failing the rest.
    static func readAllGenericPasswords(service: String, allowUI: Bool = false) -> [String] {
        var attrQuery = baseQuery(service: service, account: nil)
        attrQuery[kSecReturnAttributes as String] = true
        attrQuery[kSecMatchLimit as String] = kSecMatchLimitAll
        attrQuery[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip

        var result: CFTypeRef?
        let status = SecItemCopyMatching(attrQuery as CFDictionary, &result)

        let accounts: [String]
        switch status {
            case errSecSuccess:
                let items = (result as? [[String: Any]]) ?? []
                accounts = items.compactMap { $0[kSecAttrAccount as String] as? String }
            case errSecItemNotFound:
                return []
            default:
                accounts = []
        }

        if accounts.isEmpty {
            if let value = try? readGenericPassword(service: service, account: nil, allowUI: allowUI) {
                return [value]
            }
            return []
        }
        return accounts.compactMap { account in
            try? readGenericPassword(service: service, account: account, allowUI: allowUI)
        }
    }

    /// Enumerates generic-password attributes only. This never requests secret data and never prompts.
    static func genericPasswordMetadata(service: String) -> KeychainMetadataQueryResult {
        var query = baseQuery(service: service, account: nil)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            return KeychainMetadataQueryResult(status: status, items: [])
        }

        let items = (result as? [[String: Any]] ?? []).map { item in
            KeychainGenericPasswordMetadata(
                service: stringAttribute(item, kSecAttrService) ?? service,
                account: stringAttribute(item, kSecAttrAccount),
                label: stringAttribute(item, kSecAttrLabel),
                itemDescription: stringAttribute(item, kSecAttrDescription),
                comment: stringAttribute(item, kSecAttrComment),
                createdAt: item[kSecAttrCreationDate as String] as? Date,
                modifiedAt: item[kSecAttrModificationDate as String] as? Date,
                accessible: stringAttribute(item, kSecAttrAccessible),
                accessGroup: stringAttribute(item, kSecAttrAccessGroup),
                synchronizable: boolAttribute(item, kSecAttrSynchronizable)
            )
        }
        return KeychainMetadataQueryResult(status: status, items: items)
    }

    static func saveGenericPassword(service: String, account: String, value: String) throws {
        try deleteGenericPassword(service: service, account: account)
        guard let data = value.data(using: .utf8) else {
            throw TokenTorchError.message("Invalid key encoding")
        }

        var query = baseQuery(service: service, account: account)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw TokenTorchError.message("Keychain save failed for \"\(service)\"")
        }
    }

    static func deleteGenericPassword(service: String, account: String) throws {
        let query = baseQuery(service: service, account: account)
        SecItemDelete(query as CFDictionary)
    }

    /// Deletes every generic password whose service begins with `prefix`, returning the deleted count.
    ///
    /// Safety: enumerates items via an attributes-only query (no secret data, no ACL prompt), filters
    /// strictly by service prefix, and deletes each match by its exact `(service, account)`. Items that
    /// do not match the prefix — including all vendor-owned credentials — are never touched.
    @discardableResult
    static func deleteItems(withServicePrefix prefix: String) -> Int {
        precondition(prefix.isEmpty == false, "Refusing to delete with an empty service prefix")

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUISkip
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let items = result as? [[String: Any]] else { return 0 }

        var deleted = 0
        for item in items {
            guard
                let service = item[kSecAttrService as String] as? String,
                service.hasPrefix(prefix)
            else { continue }

            var delete: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service
            ]
            if let account = item[kSecAttrAccount as String] as? String {
                delete[kSecAttrAccount as String] = account
            }
            if SecItemDelete(delete as CFDictionary) == errSecSuccess {
                deleted += 1
            }
        }
        return deleted
    }

    private static func baseQuery(service: String, account: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        if let account {
            query[kSecAttrAccount as String] = account
        }
        return query
    }

    private static func stringAttribute(_ item: [String: Any], _ key: CFString) -> String? {
        if let value = item[key as String] as? String {
            return value.isEmpty ? nil : value
        }
        guard let value = item[key as String] else { return nil }
        let string = String(describing: value)
        return string.isEmpty ? nil : string
    }

    private static func boolAttribute(_ item: [String: Any], _ key: CFString) -> Bool? {
        if let value = item[key as String] as? Bool {
            return value
        }
        if let value = item[key as String] as? NSNumber {
            return value.boolValue
        }
        return nil
    }
}
