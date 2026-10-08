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
    /// Last usage band each capped row alerted at (`UsageAlertState`), so a relaunch doesn't re-notify.
    public static let usageAlertStateKey = "tokentorch.usageAlertState"
    /// User-Agent required by Anthropic's undocumented `/api/oauth/usage` endpoint, in Claude Code's own
    /// `claude-cli/<version> (external, cli)` format. Requests without a Claude Code agent are routed to an
    /// aggressive rate-limit bucket (persistent 429s), and reset grants (`cedar_ember`) are only offered to
    /// a recognized Claude Code surface — anything else comes back `eligible: false`.
    public static let claudeUsageUserAgent = "claude-cli/2.1.280 (external, cli)"
}
