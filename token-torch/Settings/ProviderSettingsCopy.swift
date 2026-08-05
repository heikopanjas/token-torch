/// Provider-tab explanatory copy for subscription reset and org Admin API keys.
enum ProviderSettingsCopy {
    static func resetHint(for provider: ProviderID) -> String {
        switch provider {
            case .claude:
                return Self.resetHint(
                    vendorName: "Claude Code OAuth session",
                    reimportSource: "Claude Code",
                    loginAction: "signing in again in Claude Code (/login)",
                    viewName: "Claude Code view"
                )
            case .codex:
                return Self.resetHint(
                    vendorName: "Codex OAuth session",
                    reimportSource: "the Codex CLI",
                    loginAction: "running `codex login`",
                    viewName: "Codex menu view"
                )
            case .cursor:
                return Self.resetHint(
                    vendorName: "Cursor OAuth session",
                    reimportSource: "Cursor",
                    loginAction: "signing in again in the Cursor IDE",
                    viewName: "Cursor view"
                )
            case .copilot:
                return ""
        }
    }

    static func adminKeyHint(for provider: ProviderID) -> String? {
        switch provider {
            case .claude:
                return Self.adminKeyHint(
                    viewName: "Anthropic API org-billing menu view",
                    createInstructions:
                        "Create an Admin API key in the Anthropic Console under Settings → Organization → API Keys.",
                    invalidKeyNote: "Regular API keys return 401."
                )
            case .codex:
                return Self.adminKeyHint(
                    viewName: "OpenAI Platform org-billing menu view",
                    createInstructions:
                        "Create an Admin API key at platform.openai.com under Settings → Organization → Admin keys.",
                    invalidKeyNote:
                        "Regular project API keys cannot access organization usage and return 401."
                )
            case .cursor, .copilot:
                return nil
        }
    }

    private static func resetHint(
        vendorName: String,
        reimportSource: String,
        loginAction: String,
        viewName: String
    ) -> String {
        return
            "Clears \(AppBrand.displayName)'s Keychain copy of your \(vendorName) and re-imports from \(reimportSource). \(reimportSource.capitalized) itself is not modified. Use after \(loginAction) if the \(viewName) shows expired credentials."
    }

    private static func adminKeyHint(
        viewName: String,
        createInstructions: String,
        invalidKeyNote: String
    ) -> String {
        return
            "Required for the \(viewName). \(createInstructions) \(invalidKeyNote) \(SettingsCopy.keychainStorageNote)"
    }

    static func additionalModelUsageHint() -> String {
        "When enabled, shows extra per-model rate limits (e.g. Codex Spark) in the Codex menu view. Off by default to keep the menu concise."
    }

    static func cursorValueRowsHint() -> String {
        "When enabled, shows Cursor's estimated Total usage value and Bonus rows. Off by default; the quota meters and Credits row are always visible."
    }

    static func claudeBackgroundRepairSectionTitle() -> String {
        "Background credential repair"
    }

    static func claudeAutomaticRepairHint() -> String {
        "When enabled, \(AppBrand.displayName) may run `ANTHROPIC_API_KEY=\"\" claude -p \"/usage\"` in one pseudo-terminal shell process during automatic refreshes so Claude Code refreshes its subscription credentials. On repair failure, command output appears in the copyable menu error but is never used as usage data. This may prompt for Keychain access. Off by default; manual Refresh always repairs on authentication failure."
    }

    static func claudeRepairFailureNotificationHint() -> String {
        "When enabled, \(AppBrand.displayName) posts a desktop notification if background Claude Code credential repair fails during startup or timer refreshes. On by default; manual Refresh still shows the error in the menu only."
    }

    static func claudeCLIPathHint() -> String {
        "Optional. Absolute path to the `claude` CLI used by the repair step. Menu bar apps launched at login inherit a minimal PATH, so `claude` may not be found automatically. Leave blank to auto-detect on PATH (e.g. /opt/homebrew/bin/claude)."
    }

    static func personalAccessTokenHint() -> String {
        "Required for the Copilot subscription menu view. Create a fine-grained GitHub Personal Access Token on your personal account with Account permission “Copilot requests” (Read-only) at github.com/settings/personal-access-tokens. Under Repository access, choose Public repositories only (or the most restrictive option available). Classic tokens (ghp_…) return HTTP 401. \(SettingsCopy.keychainStorageNote) Token Torch only reads Copilot usage."
    }
}
