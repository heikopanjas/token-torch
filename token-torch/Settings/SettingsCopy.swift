import Foundation

enum SettingsCopy {
    static let keychainStorageNote = "Stored only in \(AppBrand.displayName)'s Keychain."

    static let vendorCredentialPolicy =
        "Vendor logins and credential stores are read-only; \(AppBrand.displayName) never writes to them."
}
