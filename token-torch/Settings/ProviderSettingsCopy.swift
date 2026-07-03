/// Provider-tab explanatory copy for subscription reset and org Admin API keys.
enum ProviderSettingsCopy {
    static func resetHint(for provider: ProviderID) -> String {
        switch provider {
            case .claude:
                return
                    "Clears \(AppBrand.displayName)'s Keychain copy of your Claude Code OAuth session and re-imports from Claude Code. Claude Code itself is not modified. Use after signing in again in Claude Code (/login) if the Claude Code view shows expired credentials."
            case .codex:
                return
                    "Clears \(AppBrand.displayName)'s Keychain copy of your Codex OAuth session and re-imports from the Codex CLI. The Codex CLI login is not modified. Use after running `codex login` if the Codex menu view shows expired credentials."
            case .cursor:
                return
                    "Clears \(AppBrand.displayName)'s Keychain copy of your Cursor OAuth session and re-imports from Cursor. Your Cursor login is not modified. Use after signing in again in the Cursor IDE if the Cursor view shows expired credentials."
            case .copilot:
                return ""
        }
    }

    static func adminKeyHint(for provider: ProviderID) -> String? {
        switch provider {
            case .claude:
                return
                    "Required for the Anthropic API org-billing menu view. Create an Admin API key in the Anthropic Console under Settings → Organization → API Keys. Regular API keys return 401. Stored only in \(AppBrand.displayName)'s Keychain."
            case .codex:
                return
                    "Required for the OpenAI Platform org-billing menu view. Create an Admin API key at platform.openai.com under Settings → Organization → Admin keys. Regular project API keys cannot access organization usage and return 401. Stored only in \(AppBrand.displayName)'s Keychain."
            case .cursor, .copilot:
                return nil
        }
    }

    static func additionalModelUsageHint() -> String {
        "When enabled, shows extra per-model rate limits (e.g. Codex Spark) in the Codex menu view. Off by default to keep the menu concise."
    }

    static func cursorValueRowsHint() -> String {
        "When enabled, shows Cursor's estimated Total usage value and Bonus rows. Off by default; the quota meters and Credits row are always visible."
    }

    static func claudeAutomaticRepairHint() -> String {
        "When enabled, \(AppBrand.displayName) may repair the Claude Code credential copy during automatic (startup and timer) refreshes. This can launch the `claude` CLI in the background and prompt for Keychain access. Off by default; manual Refresh always repairs on authentication failure."
    }

    static func claudeCLIPathHint() -> String {
        "Optional. Absolute path to the `claude` CLI used by the repair step. Menu bar apps launched at login inherit a minimal PATH, so `claude` may not be found automatically. Leave blank to auto-detect on PATH (e.g. /opt/homebrew/bin/claude)."
    }

    static func personalAccessTokenHint() -> String {
        "Required for the Copilot subscription menu view. Create a fine-grained GitHub Personal Access Token on your personal account with Account permission “Copilot requests” (Read-only) at github.com/settings/personal-access-tokens. Under Repository access, choose Public repositories only (or the most restrictive option available). Classic tokens (ghp_…) return HTTP 401. Stored only in \(AppBrand.displayName)'s Keychain; Token Torch only reads Copilot usage."
    }
}
