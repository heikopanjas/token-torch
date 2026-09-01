# Token Torch — Development Guide

Last updated: 2026-09-01 (full updates log moved to `UPDATES.md`; Claude Fable share row from the usage `limits` array)

This file provides comprehensive guidance to Claude Code and developers when working with this repository.

## Before You Start

Run `/init-session` at the beginning of each new session, OR read this entire file before proceeding.

**DO NOT** make code changes or commits until you have done one of the above.

## Project Overview

**Token Torch** is a macOS Swift application for monitoring **Anthropic** and **OpenAI** organization usage, plus **personal subscription quotas** for Claude Code, ChatGPT/Codex, Cursor, and GitHub Copilot. Anthropic uses `--list-workspaces` / `--workspace`; OpenAI uses `--list-projects` / `--project` (or `default` for null scope). Org-wide usage is the default when no scope flag is set.

- **Anthropic**: token usage from Admin API; costs calculated from pricing docs.
- **OpenAI**: completions token usage + native billed costs from `/organization/costs`, with input/output token cost line items aggregated into one model cost row.
- **Personal subscriptions**: rate limits and plan usage from reverse-engineered OAuth APIs (Claude/Codex/Cursor read local Keychain / auth files / Cursor SQLite on macOS) or GitHub Copilot via fine-grained PAT (Account: **Copilot requests**). Configured and viewed in the menu bar app only.

## Mission Statement

**Token Torch** helps you see where your LLM usage goes — before the invoice or rate limit does. It unifies org billing (Anthropic and OpenAI Admin APIs) and personal plan quotas (Claude Code, Codex, Cursor, Copilot) into one native macOS menu bar app. Credentials stay on your Mac; Token Torch reads them read-only and never writes back to vendor tools.

## Technology Stack

- **Language:** Swift 6.2 (Xcode `SWIFT_VERSION = 6.0` language mode)
- **Platforms:** macOS 15+ (Apple Silicon / arm64)
- **App:** AppKit menu bar app (Xcode, `Token Torch.app`, bundle `com.panjas.tokentorch`) — `NSStatusItem` + `NSMenu` with custom-view usage items; domain logic lives under `token-torch/Core/`
- **Build system:** Xcode (`token-torch.xcodeproj`)
- **Version Control:** Git

## Session Protocol

When starting a new session, read this entire file and confirm you have understood the project instructions before proceeding. Summarize the project purpose and key conventions briefly. Do not make changes until you have confirmed your understanding.

## Build and Development Commands

Binary output: `./build.sh` → `.build/Products/Debug/Token Torch.app` (Xcode Debug), and `./build.sh --release` → `.build/export/Token Torch.app`.

`build.sh` passes `SYMROOT` explicitly on the Debug build and fails if no app exists at the advertised path afterwards. Both are load-bearing: Xcode's global build-location preference (`IDEBuildLocationStyle=Custom`, e.g. `Build/Products` relative to the workspace) overrides `-derivedDataPath` for the products directory, so without the override the script silently reports a path it never wrote to and a stale app can be launched from it. A command-line build setting outranks that preference. Bare `xcodebuild test` still honors the user's preference, which is fine because it ships nothing.

```bash
# Menu bar app
open token-torch.xcodeproj
xcodebuild -scheme token-torch -configuration Debug build

# Unit tests
xcodebuild test -scheme token-torch -configuration Debug -destination 'platform=macOS,arch=arm64'

# Release archive + Developer ID export (from repo root)
./build.sh --release
./build.sh --release --notarize   # requires exportOptions.plist + notarytool profile TokenTorch-Notarize (--release always cleans)
```

### CI release workflows

- `.github/workflows/build.yml`: signed Developer ID release build for pushes and pull requests on `develop` and `feature/**`; uploads the exported app zip and creates a GitHub prerelease on non-PR runs. Prerelease tags and zip files use `token-torch-build-<run>-<yyyymmdd-hhmmss>`.
- `.github/workflows/release.yml`: signed Developer ID release build + Apple notarization for pull requests to `main`; on pushes to `main`, creates the `v$(cat VERSION)` GitHub release only after notarization succeeds and refuses to overwrite an existing tag or release. Release zip files use `token-torch-v<version>`.
- Both workflows generate `CHANGELOG.md` and `BILL_OF_MATERIALS.md` and include them inside the release zip.
- Both workflows run `xcodebuild test` on the `token-torchTests` target before archiving.
- Both workflows use the `macos-26` GitHub runner image for the current Xcode/Swift toolchain.
- Standard GitHub actions in these workflows use Node 24 compatible major versions (`actions/checkout@v6`, `actions/upload-artifact@v6`) to avoid runner deprecation warnings.
- Required GitHub repository secrets: `APPLE_CERTIFICATE_P12_BASE64`, `APPLE_CERTIFICATE_PASSWORD`, `APPLE_SIGNING_IDENTITY`, `APPLE_TEAM_ID`, `APPLE_ID`, and `APPLE_ID_PASSWORD`.
- CI imports the Developer ID `.p12` into a temporary keychain and runs the archive, export, notarize, staple, verify, package, and upload commands as separate workflow steps for debuggable logs.

### Project-specific run examples

Org billing and subscription quota are configured in **Settings** (Admin API keys on provider tabs; Copilot PAT on Copilot tab). Usage is shown in the menu bar app only.

## Configuration

**Important**: Org billing requires an **Anthropic Admin API key** (not a regular API key). Admin API keys can be generated from the Anthropic Console at **Settings → Organization → API Keys**.

### API Keys

**Admin API Key** (required for org billing only):

- Anthropic: Settings → Claude tab Admin API key (`com.tokentorch.keys.anthropic.adminKey`)
- OpenAI: Settings → Codex tab Admin API key (`com.tokentorch.keys.openai.adminKey`)

**Personal subscription quota** uses local OAuth credentials (macOS):

- Claude Code: `$CLAUDE_CONFIG_DIR` / `~/.config/claude` / `~/.claude` credentials files, then Keychain `Claude Code-credentials-<hash>` / `Claude Code-credentials`
- ChatGPT/Codex: `~/.codex/auth.json` (or `CODEX_HOME`, `~/.config/codex`, Keychain `Codex Auth`)
- Cursor: `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb` → Keychain `cursor-access-token`
- GitHub Copilot: fine-grained PAT with Account **Copilot requests** permission, pasted in Settings → `AppKeychainStore` (`com.tokentorch.keys.copilot.personalAccessToken`). Classic `ghp_` / `read:user` tokens are rejected (HTTP 401).

These APIs are undocumented and may change; reference: [OpenUsage provider docs](https://github.com/robinebers/openusage/tree/main/docs/providers).

## Primary Instructions

- Avoid making assumptions. If you need additional context to accurately answer the user, ask the user for the missing information. Be specific about which context you need.
- Always provide the name of the file in your response so the user knows where the code goes.
- Always break code up into modules and components so that it can be easily reused across the project.
- All code you write MUST be fully optimized. ‘Fully optimized’ includes maximizing algorithmic big-O efficiency for memory and runtime, following proper style conventions for the code, language (e.g. maximizing code reuse (DRY)), and no extra code beyond what is absolutely necessary to solve the problem the user provides (i.e. no technical debt). If the code is not fully optimized, you will be fined $100.

### Working Together

This file (`AGENTS.md`) is the primary instructions file for AI coding assistants working on this project. Agent-specific instruction files (such as `.github/copilot-instructions.md`, `CLAUDE.md`) reference this document, maintaining a single source of truth.

When initializing a session or analyzing the workspace, refer to instruction files in this order:

1. `AGENTS.md` (this file - primary instructions and single source of truth)
2. Agent-specific reference file (if present - points back to AGENTS.md)

### Update Protocol (CRITICAL)

**PROACTIVELY update this file (`AGENTS.md`) as we work together.** Whenever you make a decision, choose a technology, establish a convention, or define a standard, you MUST update AGENTS.md immediately in the same response.

**Update ONLY this file (`AGENTS.md`)** when coding standards, conventions, or project decisions evolve. Do not modify agent-specific reference files unless the reference mechanism itself needs changes.

**When to update** (do this automatically, without being asked):

- Technology choices (build tools, languages, frameworks)
- Directory structure decisions
- Coding conventions and style guidelines
- Architecture decisions
- Naming conventions
- Build/test/deployment procedures

**How to update AGENTS.md:**

- Maintain the "Last updated" timestamp at the top
- Add content to the relevant section (Project Overview, Coding Standards, etc.)
- Add entries to the "Recent Updates & Decisions" log in `UPDATES.md`, not to this file — load the `recent-updates` skill for the entry format and the append-only rules
- Preserve this structure: title header → timestamp → main instructions

## Architecture

### Targets

| Target | Role |
|--------|------|
| **Token Torch** | AppKit menu bar app; compiles AppKit UI and **Core** sources (domain models, HTTP, credentials, quota + org providers, `UsageOrchestrator`) in one target |
| **token-torchTests** | Xcode unit tests (`token-torch-tests/`) |

UI code never calls vendor URLs directly — only `UsageOrchestrator` and settings stores. Menu bar UI is AppKit under `token-torch/`; Core logic lives under `token-torch/Core/`.

### Directory layout

```
token-torch/
├── Core/                  # Credentials, HTTP, Models, Providers, Services, Utilities
├── MenuBar/
└── Settings/
token-torch-tests/
token-torch.xcodeproj
pictures/                  # Provider icon PDFs (referenced by Xcode)
exportOptions.plist        # Developer ID export (release builds)
VERSION                    # Release version source of truth
```

### Credential stores

| Store | Purpose |
| ------- | --------- |
| `VendorCredentialsReader` / `VendorCredentialImporter` | Subscription quota OAuth: **read-only** import from vendor files/Keychain; menu bar stores a copy in Token Torch Keychain |
| `TokenTorchVendorCredentialStore` | Token Torch-owned OAuth copies (`com.tokentorch.vendor.*`) for silent menu bar refresh |
| `AppKeychainStore` | User-entered Admin keys (`com.tokentorch.keys.<provider>.adminKey`); Copilot PAT (`com.tokentorch.keys.copilot.personalAccessToken`) |

**Strategies** (`VendorCredentialImporter`):

- Menu bar app imports vendor OAuth into Token Torch-owned Keychain (`com.tokentorch.vendor.*`) once per provider; routine quota refresh reads only the Token Torch copy
- Settings **Info** tab lists vendor credential source metadata for transparency. It shows enabled subscription providers that have a Token Torch-owned credential copy and the non-secret vendor source recorded at import time; it must never display raw token/API-key values.
- Vendor-owned Keychain secret fallbacks for Claude Code, Codex, and Cursor run the timeout-bound `/usr/bin/security find-generic-password` tool during both automatic and interactive imports. File/SQLite sources remain preferred. Security.framework still performs metadata-only account enumeration, Token Torch-owned reads, and all writes/deletes. The CLI changes the requesting identity but has no equivalent to `kSecUseAuthenticationUISkip`, so startup/timer imports may still show an authorization dialog.
- Claude Code repair checks the shared file/Keychain sources, selects the config directory for the imported credential source (`CLAUDE_CONFIG_DIR`), then launches one `/bin/zsh` process in a controlling-terminal pseudo-terminal (PTY) that runs `CLAUDE_CONFIG_DIR="$2" ANTHROPIC_API_KEY="" exec "$1" -p "/usage"` when a newer usable session is unavailable, and saves only Token Torch's own credential copy. The config directory, empty-key assignment, and Claude invocation must share that process and environment; do not replace this with parent-side environment filtering or separate subprocesses. Claude must see a real controlling terminal (`ProcessRunner.runInPseudoTerminal` via `PseudoTerminalChildBootstrap` with `POSIX_SPAWN_SETSID` + `TIOCSCTTY`); ordinary pipes or TTY-without-session are insufficient for credential refresh. The command exists solely to trigger Claude Code's subscription credential refresh: secret-safe diagnostics and redacted terminal output may be retained only in the in-memory repair error and shown in the menu's copyable error row when repair fails; they must never be parsed, mapped, persisted, logged, used for app usage display, or included in desktop notifications. Manual Refresh always attempts repair on auth failure. Automatic repair runs only if `ProviderPreferences.claudeAutomaticRepair` is enabled (default off; Claude Settings tab). When that opt-in is enabled and the silent importer cannot authorize, the orchestrator falls through to the repair provider instead of returning a needs-authorization notice. Repair must never print token values or consume Claude Code's `refreshToken` directly. The `claude` executable is located via `ProviderPreferences.claudeCLIPath` when set, else PATH. Background repair failures can post a desktop notification when `ProviderPreferences.notifyOnRepairFailure` is enabled (default on).

### Key Core modules (`token-torch/Core/`)

- `AnthropicOrgProvider` / `OpenAIOrgProvider` — Admin API usage, workspaces/projects, pagination
- `ClaudeQuotaProvider` / `CodexQuotaProvider` / `CursorQuotaProvider` / `CopilotQuotaProvider` — subscription quota APIs
- `ClaudeCredentialRepair` — Claude Code repair path; checks credential files and vendor Keychain items through the shared security CLI reader, maps the imported source to `CLAUDE_CONFIG_DIR`, uses one `/bin/zsh` controlling-terminal PTY process for `CLAUDE_CONFIG_DIR="$2" ANTHROPIC_API_KEY="" exec "$1" -p "/usage"` solely to trigger credential refresh, attaches secret-safe diagnostics plus redacted command output only to an in-memory repair failure for the copyable menu error, and stores only the refreshed Token Torch-owned credential copy. Runs on manual Refresh always; automatic repair runs only when `ProviderPreferences.claudeAutomaticRepair` is enabled
- `SecurityCLIReader` / `ProcessRunner` / `PseudoTerminalChildBootstrap` — exact vendor Keychain secret reads through hard-coded `/usr/bin/security` (pipe-backed); Claude repair uses `ProcessRunner.runInPseudoTerminal` (`openpty`, self-exec bootstrap with `POSIX_SPAWN_SETSID` + `TIOCSCTTY`, merged terminal output). Both paths share async timeout/cancellation, bounded output draining, and process-group cleanup. Claude account discovery remains a metadata-only Security.framework query.
- `AppNotification` / `NotificationService` — general desktop notification content model (`AppNotification` factories per use case) and app-layer poster (`NotificationService.bootstrap()` requests authorization on first launch and posts a welcome notification on grant; `post(_:)` delivers any notification). First consumer: Claude repair failure on automatic refreshes, gated by `ProviderPreferences.notifyOnRepairFailure` (default on). Designed for future alerts (e.g. budget warnings) by adding new `AppNotification` factories only
- `UsageOrchestrator` — parallel fetch across enabled providers (menu bar)
- `DateRange` — flexible date parsing, RFC 3339, inclusive end boundaries
- `Redaction` — secret redaction for user-visible output
- `KeychainReader` — Security.framework access for Token Torch-owned secrets, metadata-only enumeration, writes, exact deletes, and prefix reset; never reads vendor-owned secret data
- `VendorCredentialSourceInfo` / `VendorCredentialImportSourceStore` / `VendorCredentialsReader.vendorCredentialSourceInfo()` — metadata-only source inventory for Settings Info tab; filters to enabled providers with Token Torch-owned credential copies, reads non-secret import-source metadata, and uses Keychain attributes-only queries with UI skipped. Advanced Keychain reset must clear both `VendorCredentialCache` and `VendorCredentialImportSourceStore` so the following interactive refresh truly re-imports vendor credentials.

Anthropic usage requests pass `group_by[]=model&group_by[]=workspace_id` for per-model cost calculation.

## Features

### Dynamic Pricing (Anthropic)

- Fetches current pricing from Anthropic documentation at startup (with fallback tiers)
- Pattern-based model name matching (Opus current vs legacy, Sonnet, Haiku)
- `USD_TO_EUR`: 0.8546 (ECB reference rate as of 2026-04-30)

### Cost Display

Costs summed per model, sorted descending. The primary amount is the user's **display currency** (USD/EUR), with the other shown in parentheses:

```
€X.XX ($Y.YY) → claude-opus-4-6
...
Grand Total: €Z.ZZ ($W.WW)
```

OpenAI native cost line items such as `chat-latest, input` and `chat-latest, output` are aggregated into one model cost row before display.

Claude `/api/oauth/usage` reports the weekly **Fable** limit only inside the `limits` array, never as a top-level `seven_day_*` key. `ClaudeQuotaProvider.fableWindow(in:)` selects the entry whose `kind` is `weekly_scoped` and whose `scope.model.display_name` (or `scope.model.id`) contains `fable` case-insensitively — a substring match, so a versioned name such as `Fable 5` still resolves — and `mapUsage` pushes it as **Fable share of 7-day limit** directly after the 7-day window with `skipIfEmpty: false`. That label is deliberate: `weekly_scoped` is a sub-cap carved out of the weekly limit (on Max, up to 50% of it), not an independent pool, so a sibling row named like a separate window misreads as additive. Do not put the 50% figure in the label — the share is plan-dependent, and on Pro, Fable runs on usage credits instead of the weekly limit. Both details are load-bearing: an unstarted Fable window returns `percent` 0 with a null `resets_at`, which `QuotaHelpers.pushWindow` would otherwise drop. The array's `session` and `weekly_all` entries duplicate `five_hour` / `seven_day` and must stay ignored so those rows are not rendered twice. Only Fable is read from `limits`; Opus and Sonnet keep their top-level keys.

Codex `/wham/usage` windows are classified by `limit_window_seconds`: `18000` is the 5-hour window and `604800` is the 7-day window. Do not assume `primary_window` is always 5-hour or `secondary_window` is always weekly because Codex can move a temporarily sole weekly limit into the primary slot. Missing or unknown durations retain the historical positional fallback. Apply the same classification to core, code-review, and additional/model limits, and use it for `rate_limit_reached_type` labels.

Codex `/wham/usage` `credits.balance` is a credit-unit balance, not dollars. Display Codex extra usage as the fixed USD equivalent at `$0.04` per credit plus the whole credit count (for example `$10.00 · 250 credits`), and surface `rate_limit_reset_credits.available_count` as available rate-limit resets when nonzero.

Copilot `/copilot_internal/user` returns the next monthly quota reset, not a subscription billing-cycle start. Derive the displayed **Quota period** by subtracting one UTC calendar month from that reset boundary; never use the persistent `assigned_date` seat-assignment timestamp as a current-period start.

### Display Currency

- `DisplayCurrency` (USD/EUR) + `CurrencyConverter` in `token-torch/Core/Utilities/DisplayCurrency.swift` (pure; USD<->EUR via `Pricing.usdToEUR`, native passthrough for other source currencies).
- Default = `Locale.current.currency` mapped to USD/EUR (`.systemDefault`, USD fallback).
- Menu bar: General tab popup, persisted in `ProviderPreferences.displayCurrency`; changing it posts `tokenTorchDisplayChanged` to rebuild the menu (no refetch).
- Start at login: General tab **Start at login** checkbox; uses `SMAppService.mainApp` register/unregister (system-managed login item, not `ProviderPreferences`).
- VAT / gross vs net: General tab **VAT rate (%)** and **Automatically deduct VAT** toggle, persisted as `ProviderPreferences.vatRatePercent` and `automaticallyDeductVAT`. Entering a positive rate saves on field blur (not just Enter), auto-enables deduction, and applies to plan list prices (`$20/mo`) via `DisplayPriceOptions.formatPlanPrice`. Other menu amounts use `DisplayPriceOptions` (vendor gross incl. VAT; deduct divides by `1 + rate/100`). Posts `tokenTorchDisplayChanged` and repopulates the cached menu immediately.
- Menu bar icon: General tab **Menu bar icon** popup (`MenuBarIconProvider`: `<automatic>`, Anthropic, Claude Code, Codex, OpenAI, Cursor, Copilot); **`<automatic>`** uses the PDF for the first **enabled** row in the Providers table; persisted in `ProviderPreferences.menuBarIcon` (default Cursor); posts `tokenTorchDisplayChanged` to update the status item (including when provider order or enable state changes while that option is selected).
- Source currencies fed to the converter: USD for Cursor / Anthropic org / OpenAI org / ChatGPT credits; `extra_usage.currency` for Claude credits.

### Startup Network Readiness

- Menu bar startup/timer refreshes are gated by an app-only `NetworkManager` in `token-torch/MenuBar/NetworkManager.swift`.
- The manager reuses the resilient `NWPathMonitor` / initial-status / connectivity-check pattern from Dashboard of Doom, but Token Torch provider requests still go through `token-torch/Core/HTTP/HTTPClient.swift`.
- Non-interactive refreshes queue while the network is unavailable and run once connectivity is confirmed; manual refreshes still execute immediately.

### Date Handling

Flexible parsing via `DateRange.parseDateRange()`:

- `YYYY` → full year; `YYYY-MM` → full month; `YYYY-MM-DD` → specific date
- No date → current month
- Inclusive end dates advance by one day for API `ending_at` (avoids off-by-one bucket drop)

### Pagination

- Automatic paginated Admin API fetches in org providers

### Cursor quota meters

Individual plans show `totalPercentUsed`, `autoPercentUsed`, and `apiPercentUsed` as separate non-additive pools. Subscription price (`$200/mo`) is separate from included usage credits.

Cursor's `Total usage value` and `Bonus` rows are display-only value-framing fields from Cursor's private usage API. They are hidden by default; users can reveal both from the Cursor Settings tab via `ProviderPreferences.showCursorUsageValueAndBonus` (default off); toggling it posts `tokenTorchDisplayChanged` and must not refetch or discard the raw decoded values.

### About panel

- **About…** lives in the status menu (`MenuBuilder.appendCommandItems`) and the app menu (`AppDelegate.setupMainMenu`), not in Settings.
- Uses the standard macOS About panel via `AppActions.showAbout()` → `NSApplication.orderFrontStandardAboutPanel`; version/copyright come from `Info.plist` (`MARKETING_VERSION`, `NSHumanReadableCopyright`).
- Status-menu About temporarily switches activation to `.regular` so the panel is key while the app is otherwise an accessory (`LSUIElement`); closing the About panel restores `.accessory` unless Settings is still visible (same helper as Settings close).

## Dependencies

- **sqlite3** (system): read-only Cursor token lookup; linked via `OTHER_LDFLAGS = -lsqlite3` on the app target
- Core code has no third-party HTTP dependency beyond Foundation URLSession

## Best Practices

### Development Guidelines

- Keep **Core** free of AppKit — UI belongs in `token-torch/MenuBar/` and `token-torch/Settings/`
- Keep modules focused on single responsibilities
- Use `async`/`await` for network and orchestration
- Test mappers, dates, and redaction offline in `token-torch-tests`

### Security & Safety

- Never include API keys, tokens, or credentials in code
- Never print API keys in terminal output or error messages
- All user-visible errors pass through `Redaction.redactSecrets()`
- Use Anthropic Admin API keys only for org billing; regular API keys return 401
- **Quota credentials are read-only**: never write, refresh, or persist to vendor Keychain entries, auth files, or Cursor `state.vscdb`; token refresh is left to Claude Code, Codex CLI, and Cursor IDE. Vendor Keychain secret reads use `/usr/bin/security` in automatic and interactive imports, but must never print secret output, write vendor storage, or consume a vendor refresh token.
- Always require explicit human confirmation before commits

### Testing

```bash
xcodebuild test -scheme token-torch -configuration Debug -destination 'platform=macOS,arch=arm64'
```

- 55+ unit tests in `token-torch-tests` (dates, mappers, redaction, credential guards, Keychain round-trip)
- Live quota tests require macOS vendor logins
- No separate display snapshot test target

### Documentation

- Keep this file updated as the primary development guide
- `UPDATES.md` holds the append-only "Recent Updates & Decisions" history; never edit or reorder existing entries there
- Update `README.md` when user-facing behavior changes

## Swift Coding Standards

- Swift 6.2, macOS 15+ APIs
- Prefer `Sendable` and actor isolation where appropriate
- Public APIs documented with `///` when non-obvious
- Match existing naming and file organization under `token-torch/Core/`
- Boolean conditions use explicit literals: `if condition == true` / `if condition == false` (not bare `if condition` or `if !condition`); qualify member access with `Self.` / `self.` when touching code (see `.claude/skills/swift-coding-conventions/SKILL.md`)

## Commit Protocol

Load the `git-workflow` skill before committing. Commit message bodies are mandatory, every body line must be a bullet point starting with `-`.

## Semantic Versioning

The root `VERSION` file is the release version and release tag source of truth (`v<version>`). `AppVersion.current` in `token-torch/Core/Utilities/AppVersion.swift` must match `VERSION`; app release builds pass `MARKETING_VERSION=$(cat VERSION)` to Xcode. Load the `semantic-versioning` skill before changing `VERSION` and keep version updates in the same commit as the behavior change.
