import Foundation

public enum AppBrand {
    public static let displayName = "Token Torch"
    public static let keychainAccount = "tokentorch"
    /// Service prefix for every Keychain item Token Torch creates (admin keys + vendor OAuth copies).
    /// Vendor-owned items (e.g. `Claude Code-credentials-*`) never carry this prefix.
    public static let keychainServicePrefix = "com.tokentorch."
    public static let bundleIdentifier = "com.panjas.tokentorch"
    public static let preferencesKey = "tokentorch.providerPreferences"
    public static let migrationFlagKey = "tokentorch.migratedFromBurn"
}
