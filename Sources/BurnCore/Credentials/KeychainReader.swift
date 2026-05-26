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
                    throw BurnError.message("Keychain read failed for \"\(service)\"")
                }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            case errSecItemNotFound:
                return nil
            case errSecAuthFailed, errSecUserCanceled, errSecInteractionNotAllowed:
                return nil
            default:
                throw BurnError.message("Keychain read failed for \"\(service)\"")
        }
    }

    static func saveGenericPassword(service: String, account: String, value: String) throws {
        try deleteGenericPassword(service: service, account: account)
        guard let data = value.data(using: .utf8) else {
            throw BurnError.message("Invalid key encoding")
        }

        var query = baseQuery(service: service, account: account)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw BurnError.message("Keychain save failed for \"\(service)\"")
        }
    }

    static func deleteGenericPassword(service: String, account: String) throws {
        let query = baseQuery(service: service, account: account)
        SecItemDelete(query as CFDictionary)
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
}
