# burn

macOS-native **burn** helps you see where your LLM usage goes — before the invoice or rate limit does. It unifies **organization billing** (Anthropic and OpenAI Admin APIs) and **personal subscription quotas** (Claude Code, ChatGPT/Codex, Cursor) into one Swift stack: shared **BurnCore**, terminal **burn-cli**, and menu bar **burn-app**.

Credentials stay on your Mac. burn reads vendor OAuth and Admin keys **read-only** and never writes back to Claude Code, Codex, or Cursor.

## What it does

| Provider | Org billing (Admin API) | Personal quota (`--quota`) |
|----------|-------------------------|----------------------------|
| **Anthropic** (`anthropic`, alias `claude`) | Token usage + model costs from pricing docs | Claude Code rate limits and plan usage |
| **OpenAI** (`openai`, alias `codex`) | Completions usage + native billed costs | ChatGPT/Codex subscription limits |
| **Cursor** (`cursor`) | Not available | Plan usage (Auto, API, total meters) |

Org-wide usage is the default. Scope with `--workspace` (Anthropic) or `--project` (OpenAI; use `default` for unscoped usage).

## Requirements

- macOS 14+
- Xcode 16+ / Swift 6 toolchain

## Build

```bash
# Swift Package (BurnCore + burn-cli)
swift build
swift test
```

Binaries:

- `.build/debug/burn-cli` — CLI (Swift Package)
- `Sources/burn-app/.build/Products/Debug/burn-app.app` — menu bar app (Xcode)

## CLI

Command name: `burn-cli`. Top-level flags: `--version` / `-V`.

### Subscription quotas

Reads local OAuth on macOS (no Admin API key):

```bash
.build/debug/burn-cli anthropic --quota   # alias: claude
.build/debug/burn-cli openai --quota      # alias: codex
.build/debug/burn-cli cursor --quota
```

### Organization billing

Requires an **Admin API key** (not a regular API key):

- Anthropic: `-a` / `ANTHROPIC_ADMIN_KEY` — create at **Settings → Organization → API Keys** in the Anthropic Console
- OpenAI: `-a` / `OPENAI_ADMIN_KEY`
- CLI also reads keys saved by **burn-app** in burn Keychain (`com.burn.keys.<provider>.adminKey`)

```bash
# Current month (default date range)
.build/debug/burn-cli anthropic
.build/debug/burn-cli openai

# Explicit range: YYYY, YYYY-MM, or YYYY-MM-DD
.build/debug/burn-cli anthropic -s 2026-05
.build/debug/burn-cli openai -s 2026-05-01 -e 2026-05-15

# List workspaces / projects
.build/debug/burn-cli anthropic --list-workspaces
.build/debug/burn-cli openai --list-projects

# Scoped usage
.build/debug/burn-cli anthropic --workspace default
.build/debug/burn-cli openai --project proj_abc
```

`cursor` without `--quota` prints a notice that org billing is not supported.

### Quota credential sources (macOS)

| Tool | Where burn looks (read-only) |
|------|------------------------------|
| Claude Code | Keychain `Claude Code-credentials`, then `~/.claude/.credentials.json` |
| Codex | `~/.codex/auth.json`, `CODEX_HOME`, `~/.config/codex`, Keychain `Codex Auth` |
| Cursor | `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`, Keychain `cursor-access-token` |

Quota APIs are undocumented and may change. Reference: [OpenUsage provider docs](https://github.com/robinebers/openusage/tree/main/docs/providers).

## burn-app

Menu bar app (Xcode): proper `.app` bundle, code signing, `LSUIElement` for menu-bar-only UI.

```bash
# Open in Xcode (recommended)
open Sources/burn-app/burn-app.xcodeproj

# Command line
cd Sources/burn-app
xcodebuild -scheme burn-app -configuration Debug build
open .build/Products/Debug/burn-app.app
```

Set your **Development Team** in the target’s Signing & Capabilities before distributing. Bundle ID: `com.panjas.burn`.

**Settings** (per provider):

- **General** — refresh interval
- **Claude / Codex** — subscription quota and org billing toggles; API and Admin key fields
- **Cursor** — subscription quota only (no org billing)

The app imports vendor OAuth into burn-owned Keychain (`com.burn.vendor.*`) once per provider so routine refresh does not re-prompt macOS for vendor Keychain access. **burn-cli** reads vendor stores directly.

## Architecture

| Target | Role |
|--------|------|
| **BurnCore** | Domain models, HTTP, credentials, quota and org providers, `UsageOrchestrator`. No terminal output. |
| **burn-cli** | ArgumentParser CLI; terminal formatting in `Sources/burn-cli/` |
| **burn-app** | SwiftUI menu bar app (`Sources/burn-app/`); links **BurnCore** |

UI targets never call vendor URLs directly — only `UsageOrchestrator` and settings stores.

### Repository layout

```
Package.swift
Sources/
├── BurnCore/          # Library: providers, credentials, orchestration
├── burn-cli/          # Terminal CLI
└── burn-app/          # Xcode menu bar project
Tests/BurnCoreTests/
Pictures/              # Provider icons (PDF/SVG)
```

### Credential stores

| Store | Purpose |
|-------|---------|
| `VendorCredentialsReader` / `VendorCredentialImporter` | Read-only import from vendor Keychain/files for subscription quota |
| `BurnVendorCredentialStore` | burn-owned OAuth copies (`com.burn.vendor.*`) for silent menu bar refresh |
| `AppKeychainStore` | User-entered Admin keys (`com.burn.keys.<provider>.adminKey`) |

## Tests

```bash
swift test
```

Mapper, date, redaction, and credential-guard tests run offline. Live quota tests require macOS vendor logins.

## Security

- Never commit API keys or OAuth tokens
- User-visible errors are redacted via `Redaction`
- Quota mode does not refresh or write vendor credentials; on 401/403, re-login in the vendor tool
- Keychain access uses Security framework APIs in **BurnCore** (no `security` CLI subprocess)

## Development

See [AGENTS.md](AGENTS.md) for architecture details, conventions, and agent workflow.
