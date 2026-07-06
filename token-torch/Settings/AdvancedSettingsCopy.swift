enum AdvancedSettingsCopy {
    static var resetKeychainHint: String {
        "Permanently deletes every Keychain item \(AppBrand.displayName) created — the admin API keys you entered and the imported subscription OAuth copies (services starting with \"com.tokentorch.\"). \(SettingsCopy.vendorCredentialPolicy) After resetting, re-enter admin keys and re-import subscription credentials from each provider tab."
    }
}
