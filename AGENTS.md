# burn — Development Guide

Last updated: 2026-05-26 (README expanded for user-facing docs)

This file provides comprehensive guidance to Claude Code and developers when working with this repository.

## Before You Start

Run `/init-session` at the beginning of each new session, OR read this entire file before proceeding.

**DO NOT** make code changes or commits until you have done one of the above.

## Project Overview

**burn** is a macOS Swift application for monitoring **Anthropic** and **OpenAI** organization usage, plus **personal subscription quotas** for Claude Code, ChatGPT/Codex, and Cursor. Anthropic uses `--list-workspaces` / `--workspace`; OpenAI uses `--list-projects` / `--project` (or `default` for null scope). Org-wide usage is the default when no scope flag is set.

- **Anthropic**: token usage from Admin API; costs calculated from pricing docs.
- **OpenAI**: completions token usage + native billed costs from `/organization/costs`.
- **Personal subscriptions** (`--quota` on `claude`, `codex`, or `cursor`): rate limits and plan usage from reverse-engineered OAuth APIs; reads local Keychain / auth files / Cursor SQLite on macOS (no Admin API key).

## Mission Statement

**burn** helps you see where your LLM usage goes — before the invoice or rate limit does. It unifies org billing (Anthropic and OpenAI Admin APIs) and personal plan quotas (Claude Code, Codex, Cursor) into one native macOS experience: query from the terminal with **burn-cli**, or glance from the menu bar with **burn-app**. Credentials stay on your Mac; burn reads them read-only and never writes back to vendor tools.

## Technology Stack

- **Language:** Swift 6
- **Platforms:** macOS 14+
- **CLI:** ArgumentParser (`burn-cli`)
- **App:** SwiftUI menu bar app (Xcode, `burn-app`)
- **Package manager:** Swift Package Manager (`Package.swift` at repo root)
- **Version Control:** Git

## Session Protocol

When starting a new session, read this entire file and confirm you have understood the project instructions before proceeding. Summarize the project purpose and key conventions briefly. Do not make changes until you have confirmed your understanding.

## Build and Development Commands

Binary output: `.build/debug/burn-cli` (SPM) and `Sources/burn-app/.build/Products/Debug/burn-app.app` (Xcode).

```bash
# Swift Package (BurnCore + burn-cli)
swift build
swift test
.build/debug/burn-cli anthropic --quota

# Menu bar app
open Sources/burn-app/burn-app.xcodeproj
cd Sources/burn-app && xcodebuild -scheme burn-app -configuration Debug build
```

### Project-specific run examples

```bash
# Anthropic org usage (defaults to current month)
.build/debug/burn-cli anthropic

# OpenAI org usage
.build/debug/burn-cli openai

# List workspaces / projects
.build/debug/burn-cli anthropic --list-workspaces
.build/debug/burn-cli openai --list-projects

# Workspace-scoped usage
.build/debug/burn-cli anthropic --workspace default
.build/debug/burn-cli openai --project proj_abc

# With Admin API key flag
.build/debug/burn-cli anthropic -a YOUR_ADMIN_API_KEY -s 2026-05

# Personal subscription quotas (macOS local OAuth; no Admin key)
.build/debug/burn-cli claude --quota
.build/debug/burn-cli codex --quota
.build/debug/burn-cli cursor --quota
```

## Configuration

**Important**: Org billing requires an **Anthropic Admin API key** (not a regular API key). Admin API keys can be generated from the Anthropic Console at **Settings → Organization → API Keys**.

### API Keys

**Admin API Key** (required for org billing only):

- Anthropic: `-a` / `ANTHROPIC_ADMIN_KEY` on `burn-cli anthropic` (not needed with `--quota`)
- OpenAI: `-a` / `OPENAI_ADMIN_KEY` on `burn-cli openai` (not needed with `--quota`)
- Menu bar: saved via Settings → `AppKeychainStore` (`com.burn.keys.<provider>.adminKey`)

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
| **BurnCore** | Domain models, HTTP, credentials, quota + org providers, `UsageOrchestrator`. No terminal output. |
| **burn-cli** | ArgumentParser CLI; terminal formatting in `Sources/burn-cli/` |
| **burn-app** | SwiftUI menu bar app (Xcode); links **BurnCore** local package |

UI targets never call vendor URLs directly — only `UsageOrchestrator` and settings stores. All CLI stdout/stderr formatting lives in the **`burn-cli` executable target**, not BurnCore (menu bar uses its own SwiftUI).

### Directory layout

```
Package.swift
Sources/
├── BurnCore/
│   ├── Credentials/       # Keychain, vendor import, burn-owned copies
│   ├── HTTP/              # Shared HTTP client
│   ├── Models/            # Quota, org usage, preferences, reports
│   ├── Providers/         # Anthropic, OpenAI, Claude, Codex, Cursor
│   ├── Services/          # UsageOrchestrator
│   └── Utilities/         # DateRange, Redaction, BurnError
├── burn-cli/              # BurnCLI, TerminalDisplay, TableRenderer, PageProgress
└── burn-app/              # Xcode project + menu bar app sources
    ├── burn-app.xcodeproj
    └── burn-app/          # BurnApp.swift, assets, entitlements
Tests/BurnCoreTests/
Pictures/                  # Provider icon PDFs (referenced by Xcode)
```

### Credential stores

| Store | Purpose |
|-------|---------|
| `VendorCredentialsReader` / `VendorCredentialImporter` | Subscription quota OAuth: **read-only** import from vendor files/Keychain; menu bar stores a copy in burn Keychain |
| `BurnVendorCredentialStore` | burn-owned OAuth copies (`com.burn.vendor.*`) for silent menu bar refresh |
| `AppKeychainStore` | User-entered Admin keys (`com.burn.keys.<provider>.adminKey`) |

**Strategies** (`VendorCredentialStrategy`):

- `directVendorRead` — **burn-cli** reads vendor Keychain/files directly
- `burnOwnedCopy` — **burn-app** reads burn-owned Keychain copy after one-time import

### CLI structure (`BurnCLI.swift`)

- Top-level `--version` / `-V` (version in `CommandConfiguration`)
- Subcommands: `anthropic` (alias `claude`), `openai` (alias `codex`), `cursor`
- Anthropic: `-a`, `--quota`, `--list-workspaces`, `--workspace`, `-s`, `-e`
- OpenAI: `-a`, `--quota`, `--list-projects`, `--project`, `-s`, `-e`
- Cursor: `--quota` only (no org Admin API; default prints unavailability notice)
- Modes: org usage (default + Admin key), personal subscription quota (`--quota`)

### Key BurnCore modules

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

Costs summed per model, sorted descending:

```
€X.XX ($Y.YY USD) → claude-opus-4-6
...
Grand Total: €Z.ZZ ($W.WW USD)
```

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
- **BurnCore** has no third-party HTTP dependency beyond Foundation URLSession

## Best Practices

### Development Guidelines

- Keep **BurnCore** free of print/colors/tables — display belongs in `burn-cli` or `burn-app`
- Keep modules focused on single responsibilities
- Use `async`/`await` for network and orchestration
- Test mappers, dates, and redaction offline in `BurnCoreTests`

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

- 15+ unit tests in `BurnCoreTests` (dates, mappers, redaction, credential guards, Keychain round-trip)
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
- Match existing naming and file organization under `Sources/BurnCore/`

## Commit Protocol

Load the `git-workflow` skill before committing.

## Semantic Versioning

Automatically bump **`burn-cli`** version in `BurnCLI.swift` (`CommandConfiguration.version`) after every code change and include it in the same commit. Load the `semantic-versioning` skill for PATCH/MINOR/MAJOR rules.

## Recent Updates & Decisions

### 2026-05-26: Expand README for end users

**What**: Rewrote `README.md` with mission statement, provider matrix, full CLI examples (aliases, dates, scope), quota credential sources, repo layout, security notes, and link to `AGENTS.md`.

**Why**: Initial README was sparse; user-facing docs should stand alone without reading AGENTS.md.

**How**: `README.md` only (no version bump).

### 2026-05-26: Move burn-app to Sources/

**What**: Relocated `burn-app/` → `Sources/burn-app/`. Updated Xcode local package reference (`../..`), Pictures PDF paths (`../../Pictures/`), and docs.

**Why**: Consolidate all source targets under `Sources/` alongside BurnCore and burn-cli.

**How**: `project.pbxproj`, `README.md`, `AGENTS.md`. Version bump to `3.2.11`.

### 2026-05-26: Swift-only workspace documentation

**What**: Rewrote `AGENTS.md` and `README.md` for the Swift-only repo layout (`Package.swift` at root). Removed legacy dual-language and parity-diff documentation. Updated `VendorCredentialStrategy` comment.

**Why**: Project is fully Swift; documentation should match the codebase.

**How**: Docs rewrite; version bump to `3.2.10`.

### 2026-05-26: Quota-enabled guard before subscription credential import

**What**: `VendorCredentialImporter.ensureImported(provider:quotaEnabled:)` returns immediately when subscription quota is disabled for that vendor. Menu bar import runs inside `UsageOrchestrator.fetchProvider` only in the subscription-quota branch.

**Why**: Disabled providers must not trigger vendor Keychain/file reads or burn copy checks on refresh.

**How**: `VendorCredentialImporter.swift`, `UsageOrchestrator.swift`; tests in `BurnCoreTests`. Version `3.2.9`.

### 2026-05-26: Subscription credential copy model

**What**: Menu bar app imports vendor OAuth into burn-owned Keychain (`com.burn.vendor.*`) once per provider; routine quota refresh reads only burn's copy. CLI uses `VendorCredentialStrategy.directVendorRead`.

**Why**: Cross-app vendor Keychain reads triggered macOS login prompts on every menu refresh.

**How**: `BurnVendorCredentialStore`, `VendorCredentialImporter`, `VendorCredentialStrategy`; `UsageOrchestrator(credentialStrategy: .burnOwnedCopy)` in burn-app. Version `3.2.8`.

### 2026-05-26: Vendor Keychain via SecItemCopyMatching

**What**: **BurnCore** reads and writes all Keychain data via `KeychainReader` — no `/usr/bin/security` subprocess.

**Why**: Shelling out to the `security` CLI is a security concern and often triggers repeated macOS password prompts.

**How**: `Sources/BurnCore/Credentials/KeychainReader.swift`. Version `3.2.8`.

### 2026-05-26: burn-app Xcode project

**What**: macOS app target (`com.panjas.burn`, `LSUIElement`, entitlements). Links local **BurnCore** from `Package.swift`.

**How**: `Sources/burn-app/burn-app.xcodeproj`; `xcodebuild -scheme burn-app build`.

### 2026-05-26: Rename CLI target to burn-cli

**What**: Executable target and ArgumentParser `commandName` is `burn-cli`.

**How**: `Sources/burn-cli/`, `Package.swift`.

### 2026-05-26: Collapse BurnDisplay into burn-cli

**What**: Terminal formatting in `Sources/burn-cli/` only (`TerminalDisplay`, `TableRenderer`, `PageProgress`, `ScopeFormatting`, `ANSIColor`).

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
