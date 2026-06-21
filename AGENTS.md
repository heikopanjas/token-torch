# Token Torch — Development Guide

Last updated: 2026-06-21 (commit body bullet formatting)

This file provides comprehensive guidance to Claude Code and developers when working with this repository.

## Before You Start

Run `/init-session` at the beginning of each new session, OR read this entire file before proceeding.

**DO NOT** make code changes or commits until you have done one of the above.

## Project Overview

**Token Torch** is a macOS Swift application for monitoring **Anthropic** and **OpenAI** organization usage, plus **personal subscription quotas** for Claude Code, ChatGPT/Codex, Cursor, and GitHub Copilot. Anthropic uses `--list-workspaces` / `--workspace`; OpenAI uses `--list-projects` / `--project` (or `default` for null scope). Org-wide usage is the default when no scope flag is set.

- **Anthropic**: token usage from Admin API; costs calculated from pricing docs.
- **OpenAI**: completions token usage + native billed costs from `/organization/costs`, with input/output token cost line items aggregated into one model cost row.
- **Personal subscriptions** (`--quota` on `claude`, `codex`, `cursor`, or `copilot`): rate limits and plan usage from reverse-engineered OAuth APIs (Claude/Codex/Cursor read local Keychain / auth files / Cursor SQLite on macOS) or GitHub Copilot via fine-grained PAT (Account: **Copilot requests**).

## Mission Statement

**Token Torch** helps you see where your LLM usage goes — before the invoice or rate limit does. It unifies org billing (Anthropic and OpenAI Admin APIs) and personal plan quotas (Claude Code, Codex, Cursor, Copilot) into one native macOS experience: query from the terminal with **token-torch-cli**, or glance from the menu bar with **Token Torch**. Credentials stay on your Mac; Token Torch reads them read-only and never writes back to vendor tools.

## Technology Stack

- **Language:** Swift 6.2 (`swift-tools-version: 6.2` in `Package.swift`; Xcode `SWIFT_VERSION = 6.0` language mode)
- **Platforms:** macOS 15+ (Apple Silicon / arm64)
- **CLI:** ArgumentParser (`token-torch-cli`)
- **App:** AppKit menu bar app (Xcode, `Token Torch.app`, bundle `com.panjas.tokentorch`) — `NSStatusItem` + `NSMenu` with custom-view usage items
- **Package manager:** Swift Package Manager (`Package.swift` at repo root)
- **Version Control:** Git

## Session Protocol

When starting a new session, read this entire file and confirm you have understood the project instructions before proceeding. Summarize the project purpose and key conventions briefly. Do not make changes until you have confirmed your understanding.

## Build and Development Commands

Binary output: `.build/debug/token-torch-cli` (SPM), `./build.sh` → `Sources/TokenTorchApp/.build/Products/Debug/Token Torch.app` (Xcode Debug), and `./build.sh --release` → `.build/export/Token Torch.app`.

```bash
# Swift Package (TokenTorchCore + token-torch-cli)
swift build
swift test
.build/debug/token-torch-cli anthropic --quota

# Menu bar app
open Sources/TokenTorchApp/token-torch.xcodeproj
cd Sources/TokenTorchApp && xcodebuild -scheme token-torch -configuration Debug build

# Release archive + Developer ID export (from repo root)
./build.sh --release
./build.sh --release --notarize   # requires Sources/TokenTorchApp/exportOptions.plist + notarytool profile TokenTorch-Notarize (--release always cleans)
```

### CI release workflows

- `.github/workflows/build.yml`: signed Developer ID release build for pushes and pull requests on `develop` and `feature/**`; uploads the exported app zip.
- `.github/workflows/release.yml`: signed Developer ID release build + Apple notarization for pull requests to `main`; on pushes to `main`, creates `v$(cat VERSION)` only after notarization succeeds and refuses to overwrite an existing tag.
- Required GitHub repository secrets: `APPLE_CERTIFICATE_P12_BASE64`, `APPLE_CERTIFICATE_PASSWORD`, `APPLE_SIGNING_IDENTITY`, `APPLE_TEAM_ID`, `APPLE_ID`, and `APPLE_ID_PASSWORD`.
- CI imports the Developer ID `.p12` into a temporary keychain and runs the archive, export, notarize, staple, verify, package, and upload commands as separate workflow steps for debuggable logs.

### Project-specific run examples

```bash
# Anthropic org usage (defaults to current month)
.build/debug/token-torch-cli anthropic

# OpenAI org usage
.build/debug/token-torch-cli openai

# List workspaces / projects
.build/debug/token-torch-cli anthropic --list-workspaces
.build/debug/token-torch-cli openai --list-projects

# Workspace-scoped usage
.build/debug/token-torch-cli anthropic --workspace default
.build/debug/token-torch-cli openai --project proj_abc

# With Admin API key flag
.build/debug/token-torch-cli anthropic -a YOUR_ADMIN_API_KEY -s 2026-05

# Personal subscription quotas (macOS local OAuth; no Admin key)
.build/debug/token-torch-cli claude --quota
.build/debug/token-torch-cli codex --quota
.build/debug/token-torch-cli cursor --quota
.build/debug/token-torch-cli copilot --quota
```

## Configuration

**Important**: Org billing requires an **Anthropic Admin API key** (not a regular API key). Admin API keys can be generated from the Anthropic Console at **Settings → Organization → API Keys**.

### API Keys

**Admin API Key** (required for org billing only):

- Anthropic: `-a` / `ANTHROPIC_ADMIN_KEY` on `token-torch-cli anthropic` (not needed with `--quota`)
- OpenAI: `-a` / `OPENAI_ADMIN_KEY` on `token-torch-cli openai` (not needed with `--quota`)
- Menu bar: saved via Settings → `AppKeychainStore` (`com.tokentorch.keys.<provider>.adminKey`)

**Personal subscription quota** uses local OAuth credentials (macOS):

- Claude Code: Keychain `Claude Code-credentials` → `~/.claude/.credentials.json`
- ChatGPT/Codex: `~/.codex/auth.json` (or `CODEX_HOME`, `~/.config/codex`, Keychain `Codex Auth`)
- Cursor: `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb` → Keychain `cursor-access-token`
- GitHub Copilot: fine-grained PAT with Account **Copilot requests** permission, pasted in Settings → `AppKeychainStore` (`com.tokentorch.keys.copilot.personalAccessToken`); CLI `-t` / `GITHUB_TOKEN` / `COPILOT_TOKEN`. Classic `ghp_` / `read:user` tokens are rejected (HTTP 401).

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
- Add entries to the "Recent Updates & Decisions" log at the bottom with:
  - Date (with time if multiple updates per day)
  - Brief description
  - Reasoning for the change
- Preserve this structure: title header → timestamp → main instructions → "Recent Updates & Decisions" section

## Architecture

### Targets

| Target | Role |
|--------|------|
| **TokenTorchCore** | Domain models, HTTP, credentials, quota + org providers, `UsageOrchestrator`. No terminal output. |
| **token-torch-cli** | ArgumentParser CLI (target `TokenTorchCli`); terminal formatting in `Sources/TokenTorchCli/` |
| **Token Torch** | AppKit menu bar app (Xcode, `Sources/TokenTorchApp/`); links **TokenTorchCore** local package |

UI targets never call vendor URLs directly — only `UsageOrchestrator` and settings stores. All CLI stdout/stderr formatting lives in the **`token-torch-cli` executable target**, not TokenTorchCore (menu bar UI is AppKit under `Sources/TokenTorchApp/token-torch/`).

### Directory layout

```
Package.swift
Sources/
├── TokenTorchCore/
│   ├── Credentials/       # Keychain, vendor import, Token Torch-owned copies
│   ├── HTTP/              # Shared HTTP client
│   ├── Models/            # Quota, org usage, preferences, reports
│   ├── Providers/         # Anthropic, OpenAI, Claude, Codex, Cursor
│   ├── Services/          # UsageOrchestrator
│   └── Utilities/         # AppBrand, DateRange, Redaction, TokenTorchError, CredentialStoreMigration
├── TokenTorchCli/         # TokenTorchCLI, TerminalDisplay, TableRenderer, PageProgress
└── TokenTorchApp/         # Xcode project + menu bar app sources
    ├── token-torch.xcodeproj
    └── token-torch/       # main.swift, AppDelegate.swift, MenuBar/, Settings/, assets
Tests/TokenTorchCoreTests/
Pictures/                  # Provider icon PDFs (referenced by Xcode)
```

### Credential stores

| Store | Purpose |
|-------|---------|
| `VendorCredentialsReader` / `VendorCredentialImporter` | Subscription quota OAuth: **read-only** import from vendor files/Keychain; menu bar stores a copy in Token Torch Keychain |
| `TokenTorchVendorCredentialStore` | Token Torch-owned OAuth copies (`com.tokentorch.vendor.*`) for silent menu bar refresh |
| `AppKeychainStore` | User-entered Admin keys (`com.tokentorch.keys.<provider>.adminKey`); Copilot PAT (`com.tokentorch.keys.copilot.personalAccessToken`) |

**Strategies** (`VendorCredentialStrategy`):

- `directVendorRead` — **token-torch-cli** reads vendor Keychain/files directly
- `tokenTorchOwnedCopy` — **Token Torch** reads Token Torch-owned Keychain copy after one-time import

### CLI structure (`TokenTorchCLI.swift`)

- Top-level `--version` / `-V` (version in `CommandConfiguration`)
- Subcommands: `anthropic` (alias `claude`), `openai` (alias `codex`), `cursor`, `copilot`
- Anthropic: `-a`, `--quota`, `--list-workspaces`, `--workspace`, `-s`, `-e`
- OpenAI: `-a`, `--quota`, `--list-projects`, `--project`, `-s`, `-e`
- Cursor: `--quota` only (no org Admin API; default prints unavailability notice)
- Copilot: `-t`, `--quota` only (fine-grained GitHub PAT with Copilot requests; default prints unavailability notice)
- All subcommands: `-c/--currency` (USD/EUR; defaults to system locale) via shared `CurrencyOptions` `@OptionGroup`
- Modes: org usage (default + Admin key), personal subscription quota (`--quota`)

### Key TokenTorchCore modules

- `AnthropicOrgProvider` / `OpenAIOrgProvider` — Admin API usage, workspaces/projects, pagination
- `ClaudeQuotaProvider` / `CodexQuotaProvider` / `CursorQuotaProvider` / `CopilotQuotaProvider` — subscription quota APIs
- `UsageOrchestrator` — parallel fetch across enabled providers (menu bar)
- `DateRange` — flexible date parsing, RFC 3339, inclusive end boundaries
- `Redaction` — secret redaction for user-visible output
- `KeychainReader` — all Keychain I/O via Security framework (no `security` CLI subprocess)

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

### Display Currency

- `DisplayCurrency` (USD/EUR) + `CurrencyConverter` in `TokenTorchCore/Utilities/DisplayCurrency.swift` (pure; USD<->EUR via `Pricing.usdToEUR`, native passthrough for other source currencies).
- Default = `Locale.current.currency` mapped to USD/EUR (`.systemDefault`, USD fallback).
- Menu bar: General tab popup, persisted in `ProviderPreferences.displayCurrency`; changing it posts `tokenTorchDisplayChanged` to rebuild the menu (no refetch).
- Start at login: General tab **Start at login** checkbox; uses `SMAppService.mainApp` register/unregister (system-managed login item, not `ProviderPreferences`).
- VAT / gross vs net: General tab **VAT rate (%)** and **Automatically deduct VAT** toggle, persisted as `ProviderPreferences.vatRatePercent` and `automaticallyDeductVAT`. Entering a positive rate saves on field blur (not just Enter), auto-enables deduction, and applies to plan list prices (`$20/mo`) via `DisplayPriceOptions.formatPlanPrice`. Other menu amounts use `DisplayPriceOptions` (vendor gross incl. VAT; deduct divides by `1 + rate/100`). Posts `tokenTorchDisplayChanged` and repopulates the cached menu immediately.
- Menu bar icon: General tab **Menu bar icon** popup (`MenuBarIconProvider`: Anthropic, OpenAI, Cursor, Copilot); persisted in `ProviderPreferences.menuBarIcon` (default Cursor); posts `tokenTorchDisplayChanged` to update the status item.
- CLI: `-c/--currency` per subcommand (the CLI can't read the app's `UserDefaults`, so it defaults to system locale).
- Source currencies fed to the converter: USD for Cursor / Anthropic org / OpenAI org / ChatGPT credits; `extra_usage.currency` for Claude credits.

### Startup Network Readiness

- Menu bar startup/timer refreshes are gated by an app-only `NetworkManager` in `Sources/TokenTorchApp/token-torch/MenuBar/NetworkManager.swift`.
- The manager reuses the resilient `NWPathMonitor` / initial-status / connectivity-check pattern from Dashboard of Doom, but Token Torch provider requests still go through `TokenTorchCore/HTTP/HTTPClient.swift`.
- Non-interactive refreshes queue while the network is unavailable and run once connectivity is confirmed; manual refreshes still execute immediately.

### Date Handling

Flexible parsing via `DateRange.parseDateRange()`:

- `YYYY` → full year; `YYYY-MM` → full month; `YYYY-MM-DD` → specific date
- No date → current month
- Inclusive end dates advance by one day for API `ending_at` (avoids off-by-one bucket drop)

### Pagination

- Automatic paginated Admin API fetches
- In-place stderr braille spinner (`⠋ Fetching...`) via `PageProgress`, cleared on completion

### Cursor quota meters

Individual plans show `totalPercentUsed`, `autoPercentUsed`, and `apiPercentUsed` as separate non-additive pools. Subscription price (`$200/mo`) is separate from included usage credits.

## Dependencies

- **swift-argument-parser** (1.5+): CLI parsing
- **sqlite3** (system): read-only Cursor token lookup
- **TokenTorchCore** has no third-party HTTP dependency beyond Foundation URLSession

## Best Practices

### Development Guidelines

- Keep **TokenTorchCore** free of print/colors/tables — display belongs in `token-torch-cli` or Token Torch app
- Keep modules focused on single responsibilities
- Use `async`/`await` for network and orchestration
- Test mappers, dates, and redaction offline in `TokenTorchCoreTests`

### Security & Safety

- Never include API keys, tokens, or credentials in code
- Never print API keys in terminal output or error messages
- All user-visible errors pass through `Redaction.redactSecrets()`
- Use Anthropic Admin API keys only for org billing; regular API keys return 401
- **Quota credentials are read-only**: never write, refresh, or persist to vendor Keychain entries, auth files, or Cursor `state.vscdb`; token refresh is left to Claude Code, Codex CLI, and Cursor IDE
- Always require explicit human confirmation before commits

### Testing

```bash
swift test
```

- 15+ unit tests in `TokenTorchCoreTests` (dates, mappers, redaction, credential guards, Keychain round-trip)
- Live quota tests require macOS vendor logins
- No separate display snapshot test target

### Documentation

- Keep this file updated as the primary development guide
- Preserve the "Recent Updates & Decisions" section as an append-only history
- Update `README.md` when user-facing behavior changes

## Swift Coding Standards

- Swift 6.2, macOS 15+ APIs
- Prefer `Sendable` and actor isolation where appropriate
- Public APIs documented with `///` when non-obvious
- Match existing naming and file organization under `Sources/TokenTorchCore/`

## Commit Protocol

Load the `git-workflow` skill before committing. Commit message bodies are optional, but if a body is used, every body line must be a bullet point starting with `- `.

## Semantic Versioning

The root `VERSION` file is the release version and release tag source of truth (`v<version>`). `AppVersion.current` in `TokenTorchCore` must match `VERSION`; the CLI reads `AppVersion.current`, and app release builds pass `MARKETING_VERSION=$(cat VERSION)` to Xcode. Load the `semantic-versioning` skill before changing `VERSION` and keep version updates in the same commit as the behavior change.

## Recent Updates & Decisions

### 2026-06-21: Require bullet formatting for commit bodies

**What**: Commit message bodies remain optional, but if a body is used, every body line must be a bullet point starting with `- `. The `git-workflow` skill places this rule at the top of the commit protocol and updates examples accordingly.

**Why**: Bullet-only bodies make longer commit messages consistently structured and easier to review while preserving concise body-less commits for simple changes.

**How**: `AGENTS.md` and `.agents/skills/git-workflow/SKILL.md`.

### 2026-06-21: GitHub Actions signed and notarized release workflows

**What**: Added CI release conventions for `.github/workflows/build.yml` (signed Developer ID builds on `develop` / `feature/**`) and `.github/workflows/release.yml` (notarized builds for `main`, with `v$(cat VERSION)` tag creation after successful notarization on pushes to `main`). Added root `VERSION` as the shared release version source; CLI version flows through `AppVersion.current`, app release builds pass `MARKETING_VERSION` from `VERSION`, and `exportOptions.plist` no longer requires a provisioning profile.

**Why**: CI runners start without local signing state. Explicit workflow steps and repository secrets make certificate import, archive/export, notarization, stapling, verification, artifact upload, and release tag creation debuggable on first setup.

**How**: `.github/workflows/build.yml`, `.github/workflows/release.yml`, `VERSION`, `AppVersion.swift`, `TokenTorchCLI.swift`, `exportOptions.plist`, build scripts, Xcode project signing/version settings, README, and AGENTS.

### 2026-06-20: Defer startup refresh until network readiness

**What**: Menu bar startup and timer refreshes now wait for app-level network readiness before calling providers. Added an app `NetworkManager` using the resilient `NWPathMonitor` and actual-connectivity check pattern from Dashboard of Doom; manual refreshes still run immediately. CLI version `4.2.15`.

**Why**: Launch-at-login can run before macOS networking is ready, causing the initial provider fetch to fail even though the network appears moments later.

**How**: `NetworkManager.swift`, `MenuBarViewModel.swift`, `project.pbxproj`, `TokenTorchCLI.swift`, and `AGENTS.md`.

### 2026-06-18: Aggregate OpenAI input/output costs by model

**What**: OpenAI org billing now normalizes native `/organization/costs` line items such as `chat-latest, input` and `chat-latest, output` into one `chat-latest` cost row before summing. Non-token line items remain unchanged.

**Why**: OpenAI reports separate input/output token cost line items per model, but Token Torch should show the combined model price in the menu and CLI.

**How**: `OpenAIOrgProvider.costAggregationLabel(for:)`, `TokenTorchCLI.swift`, `README.md`, `AGENTS.md`, and focused tests. Version `4.2.14`.

### 2026-06-11: Pin Swift toolchain to 6.2

**What**: `Package.swift` `swift-tools-version` lowered from `6.4` to `6.2`. Docs require Swift 6.2 (not 6.3/6.4). No source changes needed — the codebase does not use newer-only language or PackageDescription APIs.

**Why**: Downstream builds must compile with Swift 6.2; avoid manifest or API drift tied to Xcode beta 6.4.

**How**: `Package.swift`, `AGENTS.md`, `README.md`. Version `4.2.13`.

### 2026-06-11: General tab providers table hint

**What**: Replaced the outdated hint below the General **Providers** table (which incorrectly said “Admin keys below”). New copy in `GeneralSettingsCopy.providersTableHint` explains drag-reorder, Enabled toggles, and that credentials/Admin keys live on provider tabs; uses `SettingsLayout.makeHintLabel` with measured height.

**Why**: Admin keys are on provider tabs, not the General tab; table now also covers enable/order for all six menu views including Copilot.

### 2026-06-11: arm64-only app builds

**What**: Xcode target and project `ARCHS = arm64`; scheme `buildArchitectures = ARM64`. Root `build.sh` debug destination is `platform=macOS,arch=arm64`; release archive uses `generic/platform=macOS` (xcodebuild rejects `arch` on generic "Any Mac" — arm64-only still enforced by `ARCHS`). Drops Intel (x86_64) slices from app/release builds.

**Why**: Apple Silicon-only; avoids dual-destination xcodebuild warnings and unnecessary universal binaries.

**How**: `project.pbxproj`, `token-torch.xcscheme`, `build.sh`. Version `4.2.9`.

### 2026-06-11: Advanced settings tab visual parity

**What**: Advanced tab matches provider layout: **Reset Keychain** section label, measured hint, destructive button (8pt gap). Shared hint helpers in `SettingsLayout.swift`; copy in `AdvancedSettingsCopy.swift`.

**Why**: Advanced used a bold header and fixed 88pt hint block above the button; other tabs group label, hint, and control.

**How**: `AdvancedSettingsViewController`, `SettingsLayout`, `ProviderSettingsViewController` refactor. Version `4.2.8`.

### 2026-06-11: Copilot settings tab visual parity

**What**: Copilot tab matches Anthropic/OpenAI layout: section label, measured hint, token field (8pt gap), Save/Clear. Copy moved to `ProviderSettingsCopy.personalAccessTokenHint()`.

**Why**: Copilot used a fixed-height intro block above the label; other provider tabs group explanatory text with their inputs.

**How**: `ProviderSettingsViewController`, `SettingsStyle.copilotPaneHeight`. Version `4.2.7`.

### 2026-06-11: OpenAI provider tab settings copy

**What**: OpenAI (Codex) settings tab matches Anthropic: Codex-specific reset hint under the button, Admin API key guidance (platform.openai.com Admin keys, regular keys return 401), and explanatory text grouped under the additional-model-usage toggle.

**Why**: Parity with the Anthropic tab; OpenAI org billing needs the same explicit Admin key instructions.

**How**: `ProviderSettingsCopy` codex strings, `ProviderSettingsViewController` toggle hint. Version `4.2.3`.

### 2026-06-11: Anthropic provider tab settings copy

**What**: Claude settings tab groups **Reset subscription credentials** with Claude Code-specific explanatory text directly beneath the button. Admin API key field adds guidance (Anthropic Console Admin key, not regular API key). Codex/Cursor reset and Codex admin hints use the same layout via `ProviderSettingsCopy`.

**Why**: Generic multi-vendor reset text was unclear on the Anthropic tab; org billing needs explicit Admin key setup instructions.

**How**: `ProviderSettingsCopy.swift`, `ProviderSettingsViewController` layout. Version `4.2.2`.

### 2026-06-11: Start at login

**What**: General tab adds **Start at login**. Checked state registers Token Torch via `SMAppService.mainApp`; unchecked unregisters. If macOS requires approval, an alert offers to open Login Items in System Settings.

**Why**: Menu bar utilities should launch automatically after sign-in without manual setup.

**How**: `LoginItemRegistration.swift`, `GeneralSettingsViewController`. Version `4.2.0`.

### 2026-06-11: Fix VAT not applied in menu

**What**: VAT rate now saves when the field loses focus (not only on Enter). Entering a positive rate auto-enables **Automatically deduct VAT**. Plan list prices (`Pro · $20/mo`) go through `DisplayPriceOptions.formatPlanPrice`. Display-only changes repopulate the cached menu even when closed.

**Why**: Users entered a rate and still saw gross prices because the rate was not persisted until Enter, plan prices bypassed VAT, and deduction required manually enabling the toggle.

**How**: `GeneralSettingsViewController` (`NSTextFieldDelegate`, `viewWillDisappear`), `ReportLabels.planSummary(pricing:)`, `StatusItemController.displayChanged`, `DisplayPriceOptions.formatPlanPrice`. Version `4.1.10`.

### 2026-06-10: VAT rate and gross/net price display

**What**: General tab adds **VAT rate (%)** and **Automatically deduct VAT**. Persisted in `ProviderPreferences`; menu prices use `DisplayPriceOptions` (vendor amounts are gross incl. VAT; deduct applies `/ (1 + VAT/100)` after currency conversion).

**Why**: Users see vendor gross prices by default and can optionally show net ex-VAT for bookkeeping.

### 2026-06-10: build.sh defaults to Debug

**What**: Root `build.sh` with no flags runs an Xcode Debug build to `Sources/TokenTorchApp/.build/Products/Debug/Token Torch.app`. Release archive/export/notarize requires `--release` (`--notarize` implies release). `--release` always cleans release artifacts first.

**Why**: Local development should be the default; distribution builds are opt-in.

### 2026-06-10: Configurable menu bar icon

**What**: General tab adds **Menu bar icon** picker (Anthropic, OpenAI, Cursor, Copilot). Persisted as `ProviderPreferences.menuBarIcon` (`MenuBarIconProvider` in Core); `MenuBarStatusIcon` loads the matching PDF; changing posts `tokenTorchDisplayChanged`.

**Why**: Users want the status item to reflect their primary provider without editing code.

### 2026-06-10: macOS 15 minimum deployment target

**What**: Lowered the Token Torch app and TokenTorchCore SPM platform minimum from macOS 27 to macOS 15 (`MACOSX_DEPLOYMENT_TARGET` in `project.pbxproj`, `Package.swift` `.macOS(.v15)`).

**Why**: macOS 27 was too restrictive; macOS 15 (Sequoia) is the intended floor for current builds.

### 2026-06-10: Remove Claude long-lived token

**What**: Reverted the optional Claude Code long-lived token (`claude setup-token`) Settings field, Keychain storage (`AppKeyKind.longLivedToken`), orchestrator bypass, and OAuth fallback path. Claude subscription quota again uses vendor OAuth credentials only.

**Why**: Setup-tokens lack OAuth scopes for `/api/oauth/usage` (HTTP 403); the feature did not work reliably and added complexity.

### 2026-06-10: Copilot PAT permission docs — Read-only is correct

**What**: Settings/CLI/error copy now says Account **Copilot requests (Read-only)** instead of “Read and write”. Repository access guidance uses GitHub’s real options (e.g. Public repositories only), not a nonexistent “No repositories” setting.

**Why**: GitHub’s fine-grained PAT UI only exposes Read-only for Copilot requests when reading quota; write is for making Copilot API calls Token Torch does not perform.

### 2026-06-10: Copilot fine-grained PAT auth + logging

**What**: GitHub Copilot quota now requires a fine-grained PAT (`github_pat_…`) with Account permission **Copilot requests**; classic `ghp_` / `read:user` tokens are rejected up front with a clear error. Auth header switched from `Authorization: token` to `Bearer`. Added `GitHubPersonalAccessToken` validation, `TokenTorchLog.copilot` os.Logger diagnostics (token kind/length prefix, HTTP status, plan on success), and richer 401 messages parsing GitHub's JSON `message`. Settings/CLI copy updated.

**Why**: Users pasting classic PATs per old docs got silent HTTP 401; GitHub Copilot CLI docs confirm classic tokens are rejected by `/copilot_internal/user`.

### 2026-06-10: macOS 27 minimum deployment target

**What**: Raised the Token Torch app and TokenTorchCore SPM platform minimum from macOS 14 to macOS 27 (`MACOSX_DEPLOYMENT_TARGET` in `project.pbxproj`, `Package.swift` `.macOS(.v27)` with `swift-tools-version: 6.4`). CLI version bumped to `4.0.0` (breaking platform requirement).

**Why**: Target the current macOS 27 SDK/Xcode beta toolchain the project is built with.

### 2026-06-10: build.sh fails loudly when Xcode is missing

**What**: Root `build.sh` now calls `require_xcode` before any build steps. If `xcodebuild` is unavailable (e.g. `xcode-select` points at Command Line Tools only), the script prints the active developer directory, suggests `sudo xcode-select -s …` for any installed `Xcode.app` / `Xcode-beta.app`, and shows a one-off `DEVELOPER_DIR=… ./build.sh` alternative. Version lookup uses a single `-showBuildSettings` pass with explicit errors instead of `2>/dev/null` + silent `set -e` exit.

**Why**: Archive/export requires full Xcode; the old script exited immediately with no output when CLT was active.

### 2026-06-10: Release build output under .build

**What**: Root `build.sh` now writes archive, export, and notarization zip under `.build/` (same directory tree as SPM), instead of `./build/`. `--clean` removes only release artifacts (`.xcarchive`, `export/`, `TokenTorch.zip`), not the whole `.build/` tree.

**Why**: One ignored build directory at the repo root; avoids a separate `build/` folder.

### 2026-06-02: Repo-root build.sh for Token Torch release

**What**: Replaced the copied Senor Particle `build.sh` at the repository root with a Token Torch release script. It archives `token-torch` (Release), exports with `Sources/TokenTorchApp/ExportOptions.plist` (Developer ID, `com.panjas.tokentorch`), and optionally notarizes via `TokenTorch-Notarize` (override with `NOTARIZE_PROFILE`). Build output goes to `.build/` at the repo root (alongside SPM artifacts).

**Why**: Root-level release workflow should match the product; paths are anchored to the script location so it runs from anywhere.

**How**: `build.sh` at repo root (same options as `Sources/TokenTorchApp/build.sh`: `--clean`, `--notarize`, notary profile check). AGENTS build commands updated to use `./build.sh`.

### 2026-06-02: Match Settings toolbar provider icons to SF Symbol size

**What**: The provider PDF toolbar icons (Anthropic/OpenAI/Cursor/Copilot) in the Settings window rendered much larger (~25-35pt ink) and inconsistently versus the neighboring SF Symbol items (General `gearshape`, Advanced `wrench.and.screwdriver`, ~17-19pt). They now render at the SF Symbol size.

**Why**: Visual consistency across the toolbar; the provider bitmaps should match the symbols' displayed size.

**How**: A `.preference`-style `NSToolbar` **upscales** non-symbol (PDF/bitmap) item images to fill its icon slot (~35pt) while leaving SF Symbols at their configured point size — so setting `NSImage.size` on the PDFs has no effect (confirmed: PDFs created at 16pt still rendered 25-35pt; measured from app screenshots since `screencapture`/`cacheDisplay` readback was unavailable). Fix: `ProviderIcons.paddedToolbarImage(named:)` composites each logo into a transparent square canvas (`SettingsStyle.toolbarProviderCanvasSide` = 40, wider than the slot so the toolbar stops upscaling) with the logo aspect-fitted into a centered `toolbarProviderLogoBox` (23) box; the toolbar then downscales the canvas to its slot, landing logos at ~20pt to match the symbols. Verified composited boxes offscreen (anthropic 23x17, openai 23x23, cursor 21x23, copilot 23x20). Version `3.20.7`.

### 2026-06-02: GitHub Copilot subscription quota provider

**What**: Added GitHub Copilot as the sixth menu view (subscription-only). Users paste a classic GitHub PAT with `read:user` scope in Settings (Admin-key UX via `AppKeychainStore.personalAccessToken`); CLI adds `copilot --quota` with `-t` / `GITHUB_TOKEN` / `COPILOT_TOKEN`. Maps `GET /copilot_internal/user` into `SubscriptionQuotaReport`: **AI Credits** row from `premium_interactions`, free-tier Chat/Completions from `monthly_quotas`/`limited_user_quotas`, plan header via `PlanBranding.copilot`/`copilotPrice`, billing cycle from `assigned_date`/`quota_reset_date_utc`. Skips `unlimited: true` snapshots (not 0% used). Icon: `Pictures/githubcopilot.pdf`.

**Why**: Post–June 2026 AI Credits migration; spike validated `read:user` PAT on Copilot Max.

**How**: `CopilotQuotaProvider`, `ProviderID.copilot`, `UsageOrchestrator` PAT path (no `VendorCredentialImporter`), Copilot Settings tab, `ReportLabels`/`MenuBuilder`/`TerminalDisplay` AI Credits label, tests with `individual_max` fixture. Version `3.20.0`.

### 2026-06-02: Rename subscription captions to Claude Code / Codex

**What**: The two subscription menu/CLI captions were renamed: Claude `Claude` -> `Claude Code`, and Codex/ChatGPT `ChatGPT` -> `Codex`. The org-billing captions (`Anthropic API`, `OpenAI Platform`) and Cursor are unchanged. This reverts the earlier 2026-05-31 shortenings ("Claude Code" -> "Claude", "ChatGPT" -> "Codex"... see those entries).

**How**: Menu source of truth `ReportLabels.heading(provider:kind:)` (`.claude` subscription -> "Claude Code"; `.codex` subscription -> "Codex"). For CLI parity the underlying `SubscriptionQuotaReport.forProvider(...)` strings were also updated (`ClaudeQuotaProvider` -> "Claude Code", `CodexQuotaProvider` -> "Codex"), which flows into `TerminalDisplay.subscriptionTitle`. No comparison logic keys off these strings (only `== "Cursor"`/`"OpenAI"` are used), so no behavior change. Version `3.19.3`.

### 2026-06-01: Enable refetches, disable is display-only

**What**: Toggling a provider's Enabled checkbox now behaves asymmetrically: enabling (off->on) posts `tokenTorchRefreshRequested` (interactive refetch, since the last fetch omitted that view), while disabling (on->off) posts `tokenTorchDisplayChanged` (no network call). To make the display-only path drop a disabled view, `MenuBuilder.populate` now filters the flattened sections by `prefs.isSectionEnabled(...)` so a still-cached but now-disabled report is not rendered.

**Why**: Disabling should be instant and free; only enabling needs data.

**How**: `GeneralSettingsViewController.enabledToggled(_:)` branches on the new state; `MenuBuilder.populate` adds the `isSectionEnabled` filter. Version `3.19.2`.

### 2026-06-01: Rename Providers table "Menu View" column to "Provider"

**What**: Renamed the first column header of the General-tab Providers table from "Menu View" to "Provider". Display-only; `viewColumn.title` in `GeneralSettingsViewController`. Version `3.19.1`.

### 2026-06-01: Providers table in Settings (enable + order in one place)

**What**: The General-tab provider list is now a proper headered `NSTableView` titled "Providers" with three columns — **Provider** (icon + caption), **Type** (Subscription / API billing), and **Enabled** (checkbox) — over the five menu-view rows. The per-provider enable toggles ("Enable subscription quota" / "Enable API billing") were removed from the provider tabs and replaced by the table's Enabled checkboxes; rows stay drag-reorderable. Toggling a checkbox saves and posts `tokenTorchRefreshRequested` so the menu updates immediately (enabling a subscription view may show a one-time Keychain prompt). Provider tabs now hold only reset-credentials, the Codex "Show additional model usage" checkbox, and the Admin API key field; their pane heights shrank accordingly (`providerPaneHeight` 700->380, `providerQuotaOnlyPaneHeight` 520->240).

**Why**: Centralizing enable/disable next to ordering makes turning views on and off far more convenient than hunting through provider tabs.

**How**: Core `ProviderPreferences.isSectionEnabled(_:)`/`setSection(_:enabled:)` map a `ProviderSection` to the correct `ProviderModeFlags` bit (subscription vs org). `GeneralSettingsViewController` builds the three columns with per-column cell factories (`makeViewCell`/`makeTypeCell`/`makeEnabledCell`) and an `enabledToggled(_:)` handler that resolves the live row via `tableView.row(for:)`. `ReportLabels.typeLabel(_:)` provides the Type strings (display stays out of Core). `ProviderSettingsViewController` dropped `subscriptionToggle`/`orgToggle`/`toggleChanged`/`saveFlags`; `resetCredentials` reads the flag locally. Added a Core test for the enable mapping. Version `3.19.0`.

### 2026-06-01: Reorder all five menu views (per section, not per provider)

**What**: The Settings -> General order list now arranges the **five** menu views independently — Claude, Anthropic API, ChatGPT, OpenAI Platform, Cursor — instead of the three providers. Each row uses the exact caption shown in the menu, and the menu renders the sections in that order (subscription and org-billing views of the same provider can now be separated and interleaved with others).

**Why**: A provider can contribute two distinct menu sections (subscription + org billing); users want to arrange those five sections freely.

**How**: New Core model `ProviderSection` (`provider` + `ProviderSectionKind` {`subscription`, `orgBilling`}) with `ProviderSection.allSections` (the five valid combos; Cursor has no org). `ProviderPreferences.providerOrder: [ProviderID]` was replaced by `sectionOrder: [ProviderSection]` (default `allSections`, backward-compatible `decodeIfPresent`) with `orderedSections()` (drops invalid, appends missing), `setSectionOrder(_:)`, `sectionOrderIndex(of:)`, and `providerOrderIndex(of:)` (earliest section index, for ordering orchestrator fetch results). `ProviderReport.sectionKind` maps a report to its view. `MenuBuilder.populate` now flattens every present `(provider, report)` into sections and sorts by `sectionOrderIndex` (dropping the old per-provider grouping); `appendProviderSection` was removed. Caption is a single source of truth: `ReportLabels.heading(provider:kind:)` (the `report` overload delegates to it) is used by both the menu header and the Settings list, with matching icons via `ProviderIcons.image(for:section:)`. Settings list (`GeneralSettingsViewController`) now lists `[ProviderSection]`. Tests updated/added for `allSections`, legacy decode default, normalization, and coding round-trip. Version `3.18.0`.

### 2026-06-01: Provider order reorder lives in Settings only

**What**: Kept the Settings -> General drag-reorderable provider list and removed the in-menu up/down reorder chevrons. The menu still renders providers in the saved order; it just no longer offers reordering controls inline.

**Why**: After comparing the two reorder UIs, the Settings list is the keeper; the in-menu chevrons (a workaround for NSMenu not supporting reliable drag) were redundant.

**How**: Reverted `UsageMenuItemViews.providerHeader` to its plain (no-chevron) form and deleted `ProviderHeaderView`; reverted `MenuBuilder.appendProviderSection`/`appendReport` signatures and removed `moveProvider(_:by:among:)`. The order-based sort in `MenuBuilder.populate` and `UsageOrchestrator.fetchAll`, plus all `ProviderPreferences.providerOrder` plumbing and tests, are unchanged. Version `3.17.1`.

### 2026-06-01: User-configurable provider order

**What**: Users can arrange the order of provider sections in the menu bar. Two reorder UIs were added (to be compared, then one kept): a drag-reorderable provider list in Settings -> General, and per-section move up/down chevrons on each provider header in the menu. The Settings provider tabs (Claude/Codex/Cursor toolbar) stay in fixed order.

**Why**: Let users prioritize the providers they care about most at the top of the menu.

**How**: New `ProviderPreferences.providerOrder: [ProviderID]` (default `ProviderID.allCases`, backward-compatible `decodeIfPresent`), normalized via `orderedProviders()` (drops unknown ids, appends any missing case) with `setProviderOrder(_:)`/`orderIndex(of:)` helpers. `UsageOrchestrator.fetchAll` now sorts results by `orderIndex`; `MenuBuilder.populate` also sorts the cached `result.results` by the current order so a display-only rebuild reorders instantly. Settings list is an `NSTableView` with row drag-reordering in `GeneralSettingsViewController`; on drop it saves and posts `tokenTorchDisplayChanged`. In-menu reorder: `UsageMenuItemViews.providerHeader` gained optional up/down chevrons backed by `ProviderHeaderView` (a custom `NSView` that hit-tests `mouseUp` itself, because `NSMenu`'s tracking loop makes native drag unreliable and a mid-drag rebuild would destroy the dragged view); `MenuBuilder.moveProvider(_:by:among:)` swaps adjacent displayed providers in the persisted order (hidden providers keep their slots) and posts `tokenTorchDisplayChanged`. CLI is single-provider per invocation, so no CLI change. Tests added for legacy decode default, `orderedProviders()` normalization, and coding round-trip. Version `3.17.0`.

### 2026-06-01: Rename CLI folder/target to TokenTorchCli

**What**: Renamed `Sources/token-torch-cli/` to `Sources/TokenTorchCli/` and the SPM target `token-torch-cli` -> `TokenTorchCli`. The executable **product** name stays `token-torch-cli`, so the CLI command and binary path (`.build/debug/token-torch-cli`) are unchanged.

**Why**: Consistent PascalCase target/folder naming alongside `TokenTorchCore` / `TokenTorchApp`.

**How**: Moved the folder; in `Package.swift` the `.executable(name: "token-torch-cli", targets: ["TokenTorchCli"])` product keeps the command name while the target/folder match by convention (no `path:` override). Updated doc references. Verified `swift build` (binary still `token-torch-cli`) and `swift test` (35 pass). Version `3.16.2`.

### 2026-06-01: Rename app folder to TokenTorchApp

**What**: Renamed `Sources/token-torch-app/` to `Sources/TokenTorchApp/`. The Xcode project (`token-torch.xcodeproj`) and scheme (`token-torch`) names are unchanged.

**Why**: Consistent PascalCase naming alongside `TokenTorchCore`.

**How**: Moved the folder (same depth, so the project's relative paths `../..` package ref and `../../Pictures/*` icons stay valid); updated the absolute paths in local `buildServer.json` and all doc references (README, AGENTS, build.sh comment). Verified clean Xcode build and `swift build`. Version `3.16.1`.

### 2026-06-01: Refresh interval options up to 1 day

**What**: The Settings refresh-interval picker now offers 5, 10, 15, 30, 60 minutes and 3, 6, 12 hours, 1 day (instead of every 5 minutes from 5-120). A saved interval that is no longer offered snaps to the nearest available option on open.

**How**: `GeneralSettingsViewController.intervalOptions` (title + minutes; hours stored as minutes, 1 day = 1440); `viewWillAppear` migrates legacy values via nearest-minutes match. Version `3.16.0`.

### 2026-06-01: Fix off-by-one org billing cycle dates

**What**: The Anthropic/OpenAI org billing cycle showed dates one day early (e.g. `2026-05-31 -> 2026-06-29` instead of `2026-06-01 -> 2026-06-30`) on machines with a positive UTC offset.

**Why**: `DateRange.firstDay` / `lastDayOfMonth` (and the parse calendar) constructed month-boundary `Date`s with a calendar in the local time zone, but formatted them with a UTC `DateFormatter`. At UTC+2, `2026-06-01 00:00` local is `2026-05-31 22:00` UTC, so it printed as the previous day.

**How**: Set `TimeZone(secondsFromGMT: 0)` on every calendar used to build month-boundary dates in `DateRange`. Added `parseDateRangeMonthIsNotOffByOne` test. Version `3.15.9`.

### 2026-06-01: New app icon

**What**: Replaced the `AppIcon.appiconset` artwork with a new torch/dollar-flame icon. Generated all ten macOS sizes (16-512 @1x/@2x) from `Pictures/Icon-macOS-Default-1024x1024@1x.png` via `sips`.

**How**: Resized into the existing filenames referenced by `Contents.json`; no `Contents.json` change needed. Version `3.15.8`.

### 2026-05-31: Compact caption-less rows

**What**: The wider inter-item spacing now applies only to rows that have an attached caption. Rows without a caption are compact again (smaller padding), so the menu stays short for the screen when many providers are enabled, while caption groups still read as distinct.

**How**: `UsageMenuItemViews.twoColumnRow` adds `rowSpacing` below the item only when a caption is present; caption-less rows use a small symmetric `topPad` (3pt). Version `3.15.7`.

### 2026-05-31: Wider gaps between menu items

**What**: Increased the vertical spacing between distinct menu rows so that each row and its attached caption read as one group, clearly separated from the next item. The row->caption gap stays tight (~2pt); the item->item gap is larger.

**How**: `UsageMenuItemViews` adds a uniform `rowSpacing` (7pt) bottom padding to every `twoColumnRow` (cost rows, captions, bold rows); attached captions are positioned above that padding so they stay glued to their row. Version `3.15.6`.

### 2026-05-31: Captions hug the row they describe

**What**: Sub-row captions (the Cursor "Bonus" caption, and the reset/"resets once the window starts" captions under the Claude/ChatGPT 5-hour and 7-day windows) now visually attach to the row directly above them instead of floating midway between rows. Reduces ambiguity about which row a caption belongs to.

**How**: `UsageMenuItemViews.costRow` / `twoColumnRow` gained an optional `caption:` parameter that renders the caption *inside the same menu item*, directly beneath the main row with a ~2pt gap, so there is no inter-item padding between a row and its caption. Used for the Claude/ChatGPT window reset captions in `MenuBuilder` (non-Cursor branch) and the Cursor Bonus caption. The standalone `caption` style (billing cycle, headers) is unchanged. Menu-only; CLI lines are already adjacent. Iterated `3.15.3` (separate 16pt caption, too dense) -> `3.15.4` (full-height top-aligned) -> `3.15.5` (caption merged into the row item for the tightest attachment).

### 2026-05-31: Clarify Cursor "Total usage value" / "Bonus" / "Credits"

**What**: Renamed the Cursor "Total spend" row to "Total usage value" (it's `includedSpend + bonusSpend` = the total dollar-value of usage at provider rates, which can exceed the included limit). Added a static caption under Bonus: "Free usage beyond what you've purchased". Reordered the rows so the order is now Total usage value -> Bonus (+ caption) -> Credits (the Credits/"API allowance" row moved to the bottom). The three percentage meters are unchanged — they faithfully mirror Cursor's own dashboard, and the API meter is the correct basis for the Credits value.

**How**: `MenuBuilder.appendCursorSubscription` (rename, caption, move Credits block below Bonus); `TerminalDisplay` (rename, caption, move the `apiAllowance`/"API allowance" block below Total/Bonus). Display-only; no model changes. Version `3.15.2`.

### 2026-05-31: Swap Claude "Extra usage" / "On-demand credits" order

**What**: In the Claude subscription view, "Extra usage" (notes) now renders before "On-demand credits" (credits) in both the menu and the CLI. No effect on other providers (ChatGPT has no on-demand credits row).

**How**: Reordered the notes loop ahead of the credits row in `MenuBuilder` (non-Cursor branch); swapped `printSubscriptionNotes`/`printSubscriptionCredits` order in `TerminalDisplay`. Version `3.15.1`.

### 2026-05-31: Cursor "Total spend" + "Bonus" rows

**What**: The Cursor subscription view now shows two new rows below "Credits": **Total spend** (`planUsage.totalSpend`, the real usage including bonus, e.g. `$573.18`) and **Bonus** (`planUsage.bonusSpend`, free provider usage beyond purchased, shown only when > 0, e.g. `$173.18`). Surfaces fields that were already in the `GetCurrentPeriodUsage` response but previously unused. The `bonusTooltip`/`displayMessage` text is intentionally not surfaced in the menu.

**How**: Decoded `totalSpend`/`bonusSpend` in `CursorQuotaProvider.CursorPlanUsage`; added `totalSpendCents`/`bonusSpendCents` to `SubscriptionQuotaReport` and set them in `mapUsage`; rendered rows in `MenuBuilder.appendCursorSubscription` and CLI lines in `TerminalDisplay`. Test fixture updated in `mapCursorIndividualUsage`. Version `3.15.0`.

### 2026-05-31: Shorten Cursor caption to provider name

**What**: Cursor subscription heading changed from "Cursor Plan" to "Cursor" (matching the "Claude"/"ChatGPT" caption style). Org caption unchanged.

**How**: `ReportLabels.heading`. Version `3.14.6`.

### 2026-05-31: Placeholder caption for windows with no reset time

**What**: Windows whose `resets_at` is null (e.g. an idle Claude 5-hour window — the API only sets a reset time once the window is active) now show "resets once the window starts" instead of nothing (menu) / "resets unknown" (CLI). Confirmed against the raw `/api/oauth/usage` response: idle `five_hour` returns `utilization: 0, resets_at: null`.

**How**: `MenuFormat.noResetCaption` + an else branch in `MenuBuilder` window loop; `TerminalDisplay.printQuotaWindow` placeholder text. Version `3.14.5`.

### 2026-05-31: Always show Claude 5-hour and 7-day windows

**What**: The Claude 5-hour window disappeared when it had no recent activity (0% used, no active reset) because `skipIfEmpty` dropped empty windows. The primary 5-hour and 7-day windows now always show; the optional windows (Opus/Sonnet/Cowork/Design/OAuth apps/Tangelo/Iguana/promo) still hide when empty.

**How**: `ClaudeQuotaProvider.pushWindow` gained a `skipIfEmpty` parameter (default true); the 5-hour and 7-day calls pass `false`. Version `3.14.4`.

### 2026-05-31: Menu rows size value column to content

**What**: Long two-column values (e.g. the Cursor "Credits" row `$339.97/$400.00 (85% used)`) were truncated by a fixed 40%-width value column. The value column now sizes to its natural width and the label takes the remainder (reserving a label minimum), so long values fit.

**How**: Rewrote `UsageMenuItemViews.twoColumnRow` layout (measure value/label via `sizeToFit`, cap label at 45% of available width). Version `3.14.3`.

### 2026-05-31: Fix Cursor Credits used amount

**What**: The Cursor "Credits" row was showing `$400.00/$400.00` because it preferred `periodSpendCents` (which equals the included allowance for this plan). It now uses the same source as the old Grand Total — `apiAllowance` (or `dollarUsage` for team) — so the used amount is the real spend, e.g. `$333.51/$400.00 (83% used)`.

**How**: `ReportLabels.cursorCreditsLabel` now reads used/limit/percent from `apiAllowance ?? dollarUsage`. Version `3.14.2`.

### 2026-05-31: Cursor Credits row spacing + "used" suffix

**What**: Removed the blank spacer between "Included API usage" and the Cursor "Credits" row, and the credits percentage now reads "(NN% used)" to match Claude's on-demand credits.

**How**: `MenuBuilder.appendCursorSubscription` (dropped the `menuSpacer`), `ReportLabels.cursorCreditsLabel` (percent suffix). Version `3.14.1`.

### 2026-05-31: Cursor "Credits" row replaces menu Grand Total

**What**: The Cursor menu section no longer shows a "Grand Total" row. Instead a "Credits" row shows spend against the included allowance, styled like Claude's on-demand credits, e.g. `$333.51/$400.00 (83%)`.

**How**: New `ReportLabels.cursorCreditsLabel` (used = `periodSpendCents` ?? `apiAllowance.usedCents` ?? `dollarUsage.usedCents`; limit = `includedAllowanceCents` ?? `dollarUsage.limitCents`; self-consistent percent from those). `MenuBuilder.appendCursorSubscription` renders it via `costRow(label: "Credits", …)`; removed the now-unused `cursorGrandTotalLabel`. `grandTotalRow` is retained for org billing. CLI Cursor output (separate "API allowance" line) is unchanged. Version `3.14.0`.

### 2026-05-31: Empty state only when no provider is enabled

**What**: "No enabled providers. Configure in Settings." now shows only when no provider has subscription quota or org billing enabled (previously it appeared whenever there was no result). When at least one provider is enabled, the menu shows data or the "Fetching data…" spinner instead.

**How**: Added `ProviderPreferences.hasAnyEnabledProvider`; `MenuBuilder.populate` short-circuits to the empty state (plus command items) only when it's false. Reworded the row. Version `3.13.3`.

### 2026-05-31: "Fetching data…" loading state replaces empty state

**What**: While a fetch is running (including the initial load at app start), the menu shows a single spinner row reading "Fetching data…" instead of "No enabled providers. Open Settings." The empty-state row now only appears when not loading and there is no result. The header reads "Fetching data…" whenever `isLoading`, otherwise "Updated <time>".

**How**: `UsageMenuItemViews.header` now picks its text from loading/result state; `MenuBuilder.populate` skips the empty state while loading and omits the leading separator when there are no provider rows. Version `3.13.2`.

### 2026-05-31: Live menu updates while the menu is open

**What**: The menu bar dropdown now updates in place when a refresh finishes while the menu is open (previously the on-screen menu stayed frozen until dismissed and reopened).

**Why**: The status item showed a *cached* `NSMenu` via `popUp`, so `rebuildMenu()` only swapped the cached instance and never touched the visible one; additionally, fetch completions delivered on the default run loop mode are starved while AppKit runs its nested menu-tracking loop. Same root cause/fix as Señor Particle.

**How**: `StatusItemController` now owns a persistent `NSMenu` assigned to `statusItem.menu`, conforms to `NSMenuDelegate` (tracks open state via `menuWillOpen`/`menuDidClose`), and repopulates that live instance in place. `MenuBuilder.populate(_:model:)` rebuilds menu contents in place (`buildMenu` is a thin wrapper). New `MenuTrackingRefresh.perform` schedules updates on `RunLoop.main` `.common` modes (with `MainActor.assumeIsolated`) so they apply during tracking; `MenuBarViewModel.refresh` delivers its completion through it. Version `3.13.1`.

### 2026-05-31: Subscription monthly price next to plan tier

**What**: Claude and ChatGPT subscriptions now show a fixed monthly USD list price next to the plan tier (like Cursor already did), e.g. `Pro · $20/mo`, `Pro Lite · $100/mo`, `Max 20x · $200/mo`. ChatGPT `plan_type`: go=$8, plus=$20, prolite=$100 (Pro 5x), pro=$200 (Pro 20x); Claude: pro=$20, max 5x=$100, max 20x=$200. Free/per-seat/custom/enterprise tiers and Max with unknown multiplier show no price.

**Why**: No provider API returns a price, so this is a hardcoded USD map keyed off the same plan codes as the brand names. These are list prices and do not reflect annual/regional/mobile/tax billing.

**How**: `PlanBranding.chatGPTPrice` / `PlanBranding.claudePrice`; wired into `CodexQuotaProvider.mapUsage` and `ClaudeQuotaProvider.mapUsage` via `report.planPrice`. Display layers (`ReportLabels.planSummary`, `TerminalDisplay.subscriptionTitle`) already render `tier · price`. Version `3.13.0`.

### 2026-05-31: Tighten On-demand credits separator

**What**: Removed the spaces around `/` in the Claude "On-demand credits" menu row (`used / limit` -> `used/limit`).

**How**: `ReportLabels.creditsLabel`. Version `3.12.2`.

### 2026-05-31: Shorten subscription captions to provider name

**What**: Menu subscription headings shortened: "Claude & Claude Code" -> "Claude", "ChatGPT & Codex" -> "ChatGPT". Org captions ("Anthropic API", "OpenAI Platform") unchanged.

**How**: `ReportLabels.heading`. Version `3.12.1`.

### 2026-05-31: Plan brand-name mapping

**What**: Raw plan codes now render as official brand names. ChatGPT `plan_type` -> Go / Plus / Pro / Pro Lite (`prolite`) / Team / Business / Enterprise / Education; Claude `subscriptionType` -> Pro / Max, with the Max usage multiplier (`Max 5x` / `Max 20x`) parsed from `rateLimitTier`. Unknown codes fall back to a capitalized form. No provider API returns brand names directly, so this is a client-side map (same approach as Codex CLI / CodexBar).

**Why**: The menu header and CLI title previously showed internal codes (`prolite`, `pro`, `max`) instead of the user-facing tier names.

**How**: New `PlanBranding` utility (`Sources/TokenTorchCore/Utilities/PlanBranding.swift`); wired in `CodexQuotaProvider.mapUsage` and `ClaudeQuotaProvider.mapUsage`. Added `rateLimitTier` to `OAuthSession`, the Claude credentials parse, `TokenTorchVendorCredentialStore` copy, and `VendorCredentialImporter` (old Token Torch-owned copies decode `rateLimitTier` as nil and show plain "Max" until re-import). Version `3.12.0`.

### 2026-05-31: Show plan tier for all subscriptions in menu header

**What**: The plan/subscription tier (e.g. Claude "pro", ChatGPT "prolite") now appears as the trailing summary next to the provider caption in the menu, like the Cursor plan already did. Generalized `ReportLabels.cursorPlanSummary` -> `planSummary` and applied it to every subscription report (not just Cursor).

**How**: `ReportLabels.swift`, `MenuBuilder.swift`. Version `3.11.2`.

### 2026-05-31: Menu window row restyle + Spark setting moved to OpenAI tab

**What**: Menu subscription window rows now use the `costRow` style (matching "On-demand credits"/"Extra usage") with the percent in `.labelColor` instead of the red/yellow/green meter color. Removed the now-unused `UsageMenuItemViews.quotaRow` and `MenuFormat.percentColor`. Moved the `showAdditionalModelUsage` checkbox from the General tab to the OpenAI (codex) provider tab, since it only affects ChatGPT/Codex.

**How**: `MenuBuilder.swift`, `UsageMenuItemViews.swift`, `MenuFormat.swift`, `GeneralSettingsViewController.swift` (reverted), `ProviderSettingsViewController.swift` (codex-only checkbox). Version `3.11.1`.

### 2026-05-31: Opt-in additional model usage (Codex Spark)

**What**: ChatGPT `additional_rate_limits` (e.g. `GPT-5.3-Codex-Spark`) now populate a separate `SubscriptionQuotaReport.additionalWindows` instead of the main `windows`. New General-tab setting `showAdditionalModelUsage` (`ProviderPreferences`, default off, backward-compatible decode) gates whether the menu lists these windows. The CLI always prints `additionalWindows` after the main windows. Toggling posts `tokenTorchDisplayChanged` (display-only rebuild, no refetch).

**Why**: Per-model extra windows are noise for most users; opt-in keeps the menu clean by default while preserving the data.

**How**: `QuotaModels.swift` (`additionalWindows`), `CodexQuotaProvider.swift`, `ProviderPreferences.swift`, `GeneralSettingsViewController.swift` (checkbox), `MenuBuilder.swift` (threads `showAdditional`), `TerminalDisplay.swift`. Test updated to assert Spark lands in `additionalWindows`. Version `3.11.0`.

### 2026-05-31: Reset dates in menu, Claude User-Agent, provider rename, meaningful-only notes

**What**: (1) Menu bar now shows each subscription window's reset date as a dimmed caption beneath the percent row (styled like org "Billing cycle"), with absolute UTC time + relative countdown (`MenuFormat.resetCaption`/`relativeReset`); previously only the CLI showed resets. (2) `ClaudeQuotaProvider` sends `User-Agent: claude-code/*` (`AppBrand.claudeUsageUserAgent`) — the undocumented `/api/oauth/usage` endpoint 429s non-`claude-code` agents, so this protects reset-date/usage visibility. (3) Renamed the Claude subscription report label `Claude Code` -> `Claude` (the unified limits cover chat, Code, Cowork, design; not just Code). (4) ChatGPT `code_review_rate_limit` re-added as windows when non-null (D1). (5) `rate_limit_reached_type` mapped to friendly labels (`primary`->"5-hour limit", `secondary`->"weekly limit") (D4). (6) ChatGPT boolean status notes (`allowed`/`limit_reached`/`unlimited`/`overage_limit_reached`/`spend_control.reached`) now appear only when meaningful (limited/capped/positive), removing healthy-state noise like "Allowed yes" (D7).

**Why**: Reset dates are a primary user need and were missing from the menu; the missing User-Agent was the likely root cause of earlier Claude 429s; the old label undersold the subscription scope; the always-on boolean rows were noise.

**How**: `AppBrand.swift`, `ClaudeQuotaProvider.swift`, `CodexQuotaProvider.swift`, `MenuFormat.swift`, `MenuBuilder.swift`, `TokenTorchCLI.swift`. Tests: ChatGPT healthy-vs-limited notes, code-review windows. Version `3.10.0`.

### 2026-05-31: Full subscription field display (ChatGPT + Claude)

**What**: New shared `QuotaNote` (label/value) on `SubscriptionQuotaReport` plus a recursive `JSONValue` (`TokenTorchCore/Utilities/JSONValue.swift`) for undocumented nested fields. ChatGPT/Codex now surfaces everything from `/wham/usage` except the user-excluded fields (`user_id`, `account_id`, `email`, `code_review_rate_limit`, `referral_beacon`, `rate_limit_reset_credits`, `approx_local_messages`, `approx_cloud_messages`): `additional_rate_limits[]` become per-model windows (`<limit_name> (5h)/(7d)`), and `rate_limit.allowed`/`limit_reached`, `credits.unlimited`/`overage_limit_reached`, `spend_control.{reached,individual_limit}`, `rate_limit_reached_type`, and `promo` (flattened) become notes. Claude surfaces `extra_usage.is_enabled` as a note (still excluding `disabled_reason`/`currency`). Notes render in both the menu (`costRow`) and CLI.

**Why**: Complete the subscription field display for both providers per the user's keep/exclude lists.

**How**: `QuotaModels.swift` (`QuotaNote`, `notes`), `JSONValue.swift`, `CodexQuotaProvider.swift` (removed `code_review_rate_limit` window per exclusion), `ClaudeQuotaProvider.swift`, `MenuBuilder.swift`, `TerminalDisplay.swift`. Also fixed two Claude reset-time bugs: `ClaudeUsageWindow` lacked a `resets_at` CodingKey (always nil → "resets unknown"), and `QuotaHelpers.parseRFC3339UTC` now handles fractional/microsecond precision (strips sub-second digits as a fallback). Tests added for ChatGPT notes/windows, Claude notes/exclusions, and fractional-seconds parsing. Version `3.9.0`.

### 2026-05-31: Display currency + expanded Claude usage fields

**What**: New `DisplayCurrency` (USD/EUR) + `CurrencyConverter` (`TokenTorchCore/Utilities/DisplayCurrency.swift`). General-tab popup persists `ProviderPreferences.displayCurrency` (default = locale currency, USD fallback); CLI gains `-c/--currency`. All monetary output in the menu and CLI converts via the built-in USD<->EUR rate (native passthrough otherwise). Claude `mapUsage` now surfaces every window the API returns (`seven_day_sonnet`, `seven_day_cowork`, `seven_day_oauth_apps`, and codenames) plus `extra_usage.utilization`; `extra_usage.disabled_reason` and the standalone `currency` are not displayed (currency is kept internally for conversion). Added a non-Cursor credits row to the menu. `CreditsInfo.utilizationPercent` added.

**Why**: Users in non-USD regions need amounts in their own currency, and the Claude API exposes more meters than were shown. Confirmed source currencies: USD for Cursor/Anthropic org/OpenAI org/ChatGPT credits; EUR (account-dependent) for Claude credits.

**How**: `DisplayCurrency.swift`, `ProviderPreferences.swift` (backward-compatible decode), `QuotaModels.swift`, `ClaudeQuotaProvider.swift`, `GeneralSettingsViewController.swift`, `MenuFormat.swift`, `ReportLabels.swift`, `MenuBuilder.swift`, `StatusItemController.swift`, `AppActions.swift` (`tokenTorchDisplayChanged`), `TerminalDisplay.swift`, `TokenTorchCLI.swift`. Tests for converter/format/legacy-prefs/Claude windows. Version `3.8.0`.

### 2026-05-31: Advanced settings — Reset Keychain

**What**: New **Advanced** tab in Settings with a destructive **Reset Keychain…** button (confirmation alert) that deletes every Token Torch-owned Keychain item. `TokenTorchKeychainMaintenance.resetTokenTorchKeychain()` → `KeychainReader.deleteItems(withServicePrefix:)` enumerates generic passwords attributes-only (no ACL prompt) and deletes only those whose service starts with `AppBrand.keychainServicePrefix` (`com.tokentorch.`) — i.e. admin keys (`com.tokentorch.keys.*`) and imported vendor OAuth copies (`com.tokentorch.vendor.*`).

**Why**: Users need a safe escape hatch to clear stale/broken stored credentials (e.g. an expired imported copy) in one action. Strict service-prefix filtering guarantees vendor-owned logins (Claude Code, Codex, Cursor) are never touched.

**How**: `AppBrand.swift` (`keychainServicePrefix`), `KeychainReader.deleteItems`, `TokenTorchKeychainMaintenance.swift`, `AdvancedSettingsViewController.swift`, `SettingsWindowController.swift` (+`SettingsStyle`), `project.pbxproj`; test `keychainResetTargetsOnlyTokenTorchServices`. Version `3.7.0`.

### 2026-05-31: Read all Keychain items per vendor service (freshest wins)

**What**: `KeychainReader.readAllGenericPasswords(service:allowUI:)` returns every item for a service by first enumerating accounts via an **attributes-only** query (no ACL prompt), then reading each item individually. Claude vendor reads (`importClaudeSessionFromVendor`, `loadClaudeSessionDirect`) gather all candidates across services/accounts and pick the freshest via `VendorCredentialsReader.freshest(_:)`.

**Why**: Claude Code stores its OAuth under account = the macOS username, and a stale leftover item from the old *burn* app sat under the **same** vendor service (`Claude Code-credentials-<hash>` / account `burn`). The old single-item read (`kSecMatchLimitOne`, service only) returned an arbitrary match — the stale one — so even after a fresh `claude /login`, Reset kept importing the expired token into Token Torch's copy. A single `kSecMatchLimitAll` + `kSecReturnData` read fails outright ("Keychain read failed") when the matches have different access ACLs (the live item is owned by Claude Code, the leftover by burn), so the read must enumerate then fetch per item. Choosing the latest expiry fixes it without requiring the user to delete the leftover. (No current code writes to vendor services; the `burn` item is a legacy artifact.)

**How**: `KeychainReader.swift`, `VendorCredentialsReader.swift`; test `freshestPrefersLaterExpiryOverStaleSameServiceItem`. Version `3.6.3`.

### 2026-05-31: Fail fast on expired vendor tokens

**What**: `QuotaHTTP.requireUsableSession(_:provider:vendorAction:)` throws the precise `quotaSessionExpired` ("Re-login…") message when the loaded access token is already expired. Each quota provider (`Claude`/`Codex`/`Cursor`) calls it right after loading the session, before any API request.

**Why**: Token Torch is read-only and never refreshes vendor tokens. With an expired token (e.g. Claude Code's Keychain token left stale because Claude Code hasn't run), the usage call returned 401 and the retry churn then tripped a 429 — surfacing a confusing dual "rate limit / login" error. **Reset** only re-copies the same expired token, so it can't help; the user must refresh the vendor app (run Claude Code / `/login`) first. Short-circuiting avoids the doomed call and shows a single accurate message.

**How**: `HTTPClient.swift` (`QuotaHTTP`), `Claude/Codex/CursorQuotaProvider.swift`; tests in `TokenTorchCoreTests`. Version `3.6.1`.

### 2026-05-31: Non-interactive startup + settings-gated credential access

**What**: Startup and timer refreshes are now non-interactive: vendor Keychain imports only prompt on explicit user action (manual Refresh, Settings → Reset credentials). An `interactive` flag threads through `VendorCredentialsReader.import*FromVendor(allowUI:)`, `VendorCredentialImporter` (`ensureImported`/`importAndSave`/`importFromVendor`/`resetAndReimport`/`reimportAfterAuthFailure`/`ensureImportedForEnabledProviders`), `UsageOrchestrator.fetchAll/fetchProvider`, the three quota providers' `fetch`, and `MenuBarViewModel.refresh(interactive:)`. When a non-interactive import has no silent source, it surfaces `TokenTorchError.needsAuthorization` → new `ProviderReport.needsAuthorization` → a "Click Refresh to authorize Keychain access." notice row (not a red error). `CredentialStoreMigration.migrateFromBurnIfNeeded` now migrates preferences first, then only migrates vendor OAuth for `subscriptionQuotaEnabled` providers and admin keys for `orgBillingEnabled` providers. `ensureImported` dedupes the copy read to a single `load` + usability check.

**Why**: Debug rebuilds change the app signature, invalidating the saved copy's Keychain ACL and triggering a re-import prompt per enabled provider on every launch. Background reads must never prompt, and only credentials for enabled providers should ever be touched.

**Note**: Repeated debug-time prompts stem from ad-hoc signing changing app identity. Use a stable signing identity (consistent Development Team) for Debug builds so the Token Torch copy persists across rebuilds.

**How**: `TokenTorchError.swift`, `VendorCredentialsReader.swift`, `VendorCredentialImporter.swift`, `UsageOrchestrator.swift`, `ProviderReport.swift`, `Claude/Codex/CursorQuotaProvider.swift`, `CredentialStoreMigration.swift`, `MenuBuilder.swift`, `UsageMenuItemViews.swift`, `ReportLabels.swift`, `ProviderIcons.swift`, `MenuBarViewModel.swift`, `ProviderSettingsViewController.swift`; tests in `TokenTorchCoreTests`. Version `3.6.0`.

### 2026-05-26: Rebrand burn → Token Torch

**What**: Full product rebrand: `BurnCore` → `TokenTorchCore`, `burn-cli` → `token-torch-cli`, bundle ID `com.panjas.tokentorch`, Keychain `com.tokentorch.*`, app `Token Torch.app`, `AppBrand` constants, `CredentialStoreMigration` from legacy `com.burn.*`.

**Why**: New product name and identity; preserve existing Keychain data via one-time migration.

**How**: SPM/Xcode/docs rename; CLI version `3.5.0`. Repo folder `burn-swift` unchanged.

### 2026-05-26: token-torch release build script

**What**: `Sources/token-torch-app/build.sh` archives `token-torch` (Release), exports with `ExportOptions.plist` (Developer ID, `com.panjas.tokentorch`), optional `--notarize` via `TokenTorch-Notarize` keychain profile.

**Why**: Port senor-particle direct-distribution workflow; replace senor-particle names in copied scripts.

**How**: `build.sh`, `ExportOptions.plist`. Docs in AGENTS.md build section.

### 2026-05-26: token-torch startup wiring

**What**: `main.swift` top-level entry retains `AppDelegate` strongly (`nonisolated(unsafe)` global), sets `.accessory` activation policy before `run()`, and drops `@MainActor` on `AppDelegate` so `NSApplicationDelegate` callbacks run. Debug builds set `ENABLE_DEBUG_DYLIB = NO` so `_main` lives in the app executable (avoids blank debug stub). Status icon falls back to `flame.fill` SF Symbol like SwiftUI.

**Why**: Weak delegate + debug dylib stub could prevent `applicationDidFinishLaunching` from installing `NSStatusItem`; menu bar showed nothing.

**How**: `main.swift`, `AppDelegate.swift`, `ProviderIcons.swift`, `project.pbxproj`. Version `3.3.2`.

### 2026-05-26: token-torch AppKit NSMenu migration

**What**: Replaced SwiftUI `MenuBarExtra` with `NSApplicationDelegate`, `NSStatusItem.menu`, and custom-view `NSMenuItem`s for usage (`MenuBuilder`, `UsageMenuItemViews`). Settings use `NSTabView` + AppKit view controllers. No SwiftUI in token-torch.

**How**: Split `BurnApp.swift` into `AppDelegate.swift`, `MenuBar/`, `Settings/`. Version `3.3.0`.

### 2026-05-26: Menu bar Refresh command row

**What**: Removed the header refresh toolbar button; added a **Refresh** row (⌘R) above **Settings…** in the menu bar panel. Disabled while loading.

**How**: `BurnApp.swift`. Version `3.2.15`.

### 2026-05-26: Menu bar status icon uses cursor.pdf

**What**: `MenuBarIcon` loads `Pictures/cursor.pdf` for the menu bar extra label; falls back to `flame.fill` if missing.

**How**: `BurnApp.swift`. Version `3.2.14`.

### 2026-05-26: Menu bar status icon uses brain SF Symbol

**What**: `MenuBarStatusIcon` used `Image(systemName: "brain")` briefly; reverted to cursor.pdf.

**How**: `BurnApp.swift`. Version `3.2.13`.

### 2026-05-26: Expand README for end users

**What**: Rewrote `README.md` with mission statement, provider matrix, full CLI examples (aliases, dates, scope), quota credential sources, repo layout, security notes, and link to `AGENTS.md`.

**Why**: Initial README was sparse; user-facing docs should stand alone without reading AGENTS.md.

**How**: `README.md` only (no version bump).

### 2026-05-26: Move token-torch to Sources/

**What**: Relocated `token-torch/` → `Sources/token-torch/`. Updated Xcode local package reference (`../..`), Pictures PDF paths (`../../Pictures/`), and docs.

**Why**: Consolidate all source targets under `Sources/` alongside TokenTorchCore and token-torch-cli.

**How**: `project.pbxproj`, `README.md`, `AGENTS.md`. Version bump to `3.2.11`.

### 2026-05-26: Swift-only workspace documentation

**What**: Rewrote `AGENTS.md` and `README.md` for the Swift-only repo layout (`Package.swift` at root). Removed legacy dual-language and parity-diff documentation. Updated `VendorCredentialStrategy` comment.

**Why**: Project is fully Swift; documentation should match the codebase.

**How**: Docs rewrite; version bump to `3.2.10`.

### 2026-05-26: Quota-enabled guard before subscription credential import

**What**: `VendorCredentialImporter.ensureImported(provider:quotaEnabled:)` returns immediately when subscription quota is disabled for that vendor. Menu bar import runs inside `UsageOrchestrator.fetchProvider` only in the subscription-quota branch.

**Why**: Disabled providers must not trigger vendor Keychain/file reads or burn copy checks on refresh.

**How**: `VendorCredentialImporter.swift`, `UsageOrchestrator.swift`; tests in `TokenTorchCoreTests`. Version `3.2.9`.

### 2026-05-26: Subscription credential copy model

**What**: Menu bar app imports vendor OAuth into Token Torch-owned Keychain (`com.tokentorch.vendor.*`) once per provider; routine quota refresh reads only burn's copy. CLI uses `VendorCredentialStrategy.directVendorRead`.

**Why**: Cross-app vendor Keychain reads triggered macOS login prompts on every menu refresh.

**How**: `TokenTorchVendorCredentialStore`, `VendorCredentialImporter`, `VendorCredentialStrategy`; `UsageOrchestrator(credentialStrategy: .tokenTorchOwnedCopy)` in token-torch. Version `3.2.8`.

### 2026-05-26: Vendor Keychain via SecItemCopyMatching

**What**: **TokenTorchCore** reads and writes all Keychain data via `KeychainReader` — no `/usr/bin/security` subprocess.

**Why**: Shelling out to the `security` CLI is a security concern and often triggers repeated macOS password prompts.

**How**: `Sources/TokenTorchCore/Credentials/KeychainReader.swift`. Version `3.2.8`.

### 2026-05-26: token-torch Xcode project

**What**: macOS app target (`com.panjas.tokentorch`, `LSUIElement`, entitlements). Links local **TokenTorchCore** from `Package.swift`.

**How**: `Sources/token-torch/token-torch.xcodeproj`; `xcodebuild -scheme token-torch build`.

### 2026-05-26: Rename CLI target to token-torch-cli

**What**: Executable target and ArgumentParser `commandName` is `token-torch-cli`.

**How**: `Sources/token-torch-cli/`, `Package.swift`.

### 2026-05-26: Collapse BurnDisplay into token-torch-cli

**What**: Terminal formatting in `Sources/token-torch-cli/` only (`TerminalDisplay`, `TableRenderer`, `PageProgress`, `ScopeFormatting`, `ANSIColor`).

**Why**: Display is CLI-only UI, not a reusable library.

### 2026-05-26: Read-only quota credentials

**What**: No OAuth token refresh or writes to vendor credential stores. On 401/403, burn tells the user to re-login in the vendor tool.

**Why**: Writing back to shared Keychain/files/SQLite can rotate refresh tokens and break vendor tools.

### 2026-05-26: Personal subscription quota (`--quota`)

**What**: Claude Code, ChatGPT/Codex, and Cursor subscription quota reporting via local OAuth on macOS.

**Why**: Users need rate-limit windows and plan consumption alongside org billing.

**How**: `ClaudeQuotaProvider`, `CodexQuotaProvider`, `CursorQuotaProvider`; undocumented APIs per [OpenUsage docs](https://github.com/robinebers/openusage). Version `3.1.0`.

### 2026-05-26: Cursor separate Auto vs API quota meters

**What**: Individual plans display `totalPercentUsed`, `autoPercentUsed`, and `apiPercentUsed` as separate non-additive pools.

**Why**: Cursor bills Auto + Composer and API agent usage separately.

### 2025-11-11: AGENTS.md as Primary Instructions

**What**: Established AGENTS.md as the main development guide for humans and AI agents.

**How**: Single source of truth for architecture, features, and development guidelines.
