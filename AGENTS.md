# Token Torch — Development Guide

Last updated: 2026-05-31 (read all Keychain items per vendor service; freshest wins)

This file provides comprehensive guidance to Claude Code and developers when working with this repository.

## Before You Start

Run `/init-session` at the beginning of each new session, OR read this entire file before proceeding.

**DO NOT** make code changes or commits until you have done one of the above.

## Project Overview

**Token Torch** is a macOS Swift application for monitoring **Anthropic** and **OpenAI** organization usage, plus **personal subscription quotas** for Claude Code, ChatGPT/Codex, and Cursor. Anthropic uses `--list-workspaces` / `--workspace`; OpenAI uses `--list-projects` / `--project` (or `default` for null scope). Org-wide usage is the default when no scope flag is set.

- **Anthropic**: token usage from Admin API; costs calculated from pricing docs.
- **OpenAI**: completions token usage + native billed costs from `/organization/costs`.
- **Personal subscriptions** (`--quota` on `claude`, `codex`, or `cursor`): rate limits and plan usage from reverse-engineered OAuth APIs; reads local Keychain / auth files / Cursor SQLite on macOS (no Admin API key).

## Mission Statement

**Token Torch** helps you see where your LLM usage goes — before the invoice or rate limit does. It unifies org billing (Anthropic and OpenAI Admin APIs) and personal plan quotas (Claude Code, Codex, Cursor) into one native macOS experience: query from the terminal with **token-torch-cli**, or glance from the menu bar with **Token Torch**. Credentials stay on your Mac; Token Torch reads them read-only and never writes back to vendor tools.

## Technology Stack

- **Language:** Swift 6
- **Platforms:** macOS 14+
- **CLI:** ArgumentParser (`token-torch-cli`)
- **App:** AppKit menu bar app (Xcode, `Token Torch.app`, bundle `com.panjas.tokentorch`) — `NSStatusItem` + `NSMenu` with custom-view usage items
- **Package manager:** Swift Package Manager (`Package.swift` at repo root)
- **Version Control:** Git

## Session Protocol

When starting a new session, read this entire file and confirm you have understood the project instructions before proceeding. Summarize the project purpose and key conventions briefly. Do not make changes until you have confirmed your understanding.

## Build and Development Commands

Binary output: `.build/debug/token-torch-cli` (SPM) and `Sources/token-torch-app/.build/Products/Debug/Token Torch.app` (Xcode).

```bash
# Swift Package (TokenTorchCore + token-torch-cli)
swift build
swift test
.build/debug/token-torch-cli anthropic --quota

# Menu bar app
open Sources/token-torch-app/token-torch.xcodeproj
cd Sources/token-torch-app && xcodebuild -scheme token-torch -configuration Debug build

# Release archive + Developer ID export (from Sources/token-torch-app/)
cd Sources/token-torch-app && ./build.sh
cd Sources/token-torch-app && ./build.sh --clean --notarize   # requires ExportOptions.plist + notarytool profile TokenTorch-Notarize
```

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

These APIs are undocumented and may change; reference: [OpenUsage provider docs](https://github.com/robinebers/openusage/tree/main/docs/providers). GitHub Copilot subscription quota is deferred until after the June 2026 billing migration.

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
| **token-torch-cli** | ArgumentParser CLI; terminal formatting in `Sources/token-torch-cli/` |
| **Token Torch** | AppKit menu bar app (Xcode, `Sources/token-torch-app/`); links **TokenTorchCore** local package |

UI targets never call vendor URLs directly — only `UsageOrchestrator` and settings stores. All CLI stdout/stderr formatting lives in the **`token-torch-cli` executable target**, not TokenTorchCore (menu bar UI is AppKit under `Sources/token-torch-app/token-torch/`).

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
├── token-torch-cli/       # TokenTorchCLI, TerminalDisplay, TableRenderer, PageProgress
└── token-torch-app/       # Xcode project + menu bar app sources
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
| `AppKeychainStore` | User-entered Admin keys (`com.tokentorch.keys.<provider>.adminKey`) |

**Strategies** (`VendorCredentialStrategy`):

- `directVendorRead` — **token-torch-cli** reads vendor Keychain/files directly
- `tokenTorchOwnedCopy` — **Token Torch** reads Token Torch-owned Keychain copy after one-time import

### CLI structure (`TokenTorchCLI.swift`)

- Top-level `--version` / `-V` (version in `CommandConfiguration`)
- Subcommands: `anthropic` (alias `claude`), `openai` (alias `codex`), `cursor`
- Anthropic: `-a`, `--quota`, `--list-workspaces`, `--workspace`, `-s`, `-e`
- OpenAI: `-a`, `--quota`, `--list-projects`, `--project`, `-s`, `-e`
- Cursor: `--quota` only (no org Admin API; default prints unavailability notice)
- All subcommands: `-c/--currency` (USD/EUR; defaults to system locale) via shared `CurrencyOptions` `@OptionGroup`
- Modes: org usage (default + Admin key), personal subscription quota (`--quota`)

### Key TokenTorchCore modules

- `AnthropicOrgProvider` / `OpenAIOrgProvider` — Admin API usage, workspaces/projects, pagination
- `ClaudeQuotaProvider` / `CodexQuotaProvider` / `CursorQuotaProvider` — subscription quota APIs
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

### Display Currency

- `DisplayCurrency` (USD/EUR) + `CurrencyConverter` in `TokenTorchCore/Utilities/DisplayCurrency.swift` (pure; USD<->EUR via `Pricing.usdToEUR`, native passthrough for other source currencies).
- Default = `Locale.current.currency` mapped to USD/EUR (`.systemDefault`, USD fallback).
- Menu bar: General tab popup, persisted in `ProviderPreferences.displayCurrency`; changing it posts `tokenTorchDisplayChanged` to rebuild the menu (no refetch).
- CLI: `-c/--currency` per subcommand (the CLI can't read the app's `UserDefaults`, so it defaults to system locale).
- Source currencies fed to the converter: USD for Cursor / Anthropic org / OpenAI org / ChatGPT credits; `extra_usage.currency` for Claude credits.

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

- Swift 6, macOS 14+ APIs
- Prefer `Sendable` and actor isolation where appropriate
- Public APIs documented with `///` when non-obvious
- Match existing naming and file organization under `Sources/TokenTorchCore/`

## Commit Protocol

Load the `git-workflow` skill before committing.

## Semantic Versioning

Automatically bump **`token-torch-cli`** version in `TokenTorchCLI.swift` (`CommandConfiguration.version`) after every code change and include it in the same commit. Load the `semantic-versioning` skill for PATCH/MINOR/MAJOR rules.

## Recent Updates & Decisions

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
