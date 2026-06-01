# Token Torch

macOS-native **Token Torch** helps you see where your LLM usage goes — before the invoice or rate limit does. It unifies **organization billing** (Anthropic and OpenAI Admin APIs) and **personal subscription quotas** (Claude Code, ChatGPT/Codex, Cursor) into one Swift stack: shared **TokenTorchCore**, terminal **token-torch-cli**, and menu bar **Token Torch**.

Credentials stay on your Mac. Token Torch reads vendor OAuth and Admin keys **read-only** and never writes back to Claude Code, Codex, or Cursor.

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
# Swift Package (TokenTorchCore + token-torch-cli)
swift build
swift test
```

Binaries:

- `.build/debug/token-torch-cli` — CLI (Swift Package)
- `Sources/TokenTorchApp/.build/Products/Debug/Token Torch.app` — menu bar app (Xcode)

## CLI

Command name: `token-torch-cli`. Top-level flags: `--version` / `-V`.

### Subscription quotas

Reads local OAuth on macOS (no Admin API key):

```bash
.build/debug/token-torch-cli anthropic --quota   # alias: claude
.build/debug/token-torch-cli openai --quota      # alias: codex
.build/debug/token-torch-cli cursor --quota
```

### Organization billing

Requires an **Admin API key** (not a regular API key):

- Anthropic: `-a` / `ANTHROPIC_ADMIN_KEY` — create at **Settings → Organization → API Keys** in the Anthropic Console
- OpenAI: `-a` / `OPENAI_ADMIN_KEY`
- CLI also reads keys saved by **Token Torch** in Keychain (`com.tokentorch.keys.<provider>.adminKey`)

```bash
# Current month (default date range)
.build/debug/token-torch-cli anthropic
.build/debug/token-torch-cli openai

# Explicit range: YYYY, YYYY-MM, or YYYY-MM-DD
.build/debug/token-torch-cli anthropic -s 2026-05
.build/debug/token-torch-cli openai -s 2026-05-01 -e 2026-05-15

# List workspaces / projects
.build/debug/token-torch-cli anthropic --list-workspaces
.build/debug/token-torch-cli openai --list-projects

# Scoped usage
.build/debug/token-torch-cli anthropic --workspace default
.build/debug/token-torch-cli openai --project proj_abc
```

`cursor` without `--quota` prints a notice that org billing is not supported.

### Quota credential sources (macOS)

| Tool | Where Token Torch looks (read-only) |
|------|------------------------------|
| Claude Code | Keychain `Claude Code-credentials`, then `~/.claude/.credentials.json` |
| Codex | `~/.codex/auth.json`, `CODEX_HOME`, `~/.config/codex`, Keychain `Codex Auth` |
| Cursor | `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`, Keychain `cursor-access-token` |

Quota APIs are undocumented and may change. Reference: [OpenUsage provider docs](https://github.com/robinebers/openusage/tree/main/docs/providers).

## Token Torch (menu bar app)

Menu bar app (Xcode): `Token Torch.app`, code signing, `LSUIElement` for menu-bar-only UI.

```bash
# Open in Xcode (recommended)
open Sources/TokenTorchApp/token-torch.xcodeproj

# Command line
cd Sources/TokenTorchApp
xcodebuild -scheme token-torch -configuration Debug build
open .build/Products/Debug/Token\ Torch.app
```

Set your **Development Team** in the target’s Signing & Capabilities before distributing. Bundle ID: `com.panjas.tokentorch`.

**Settings** (per provider):

- **General** — refresh interval
- **Claude / Codex** — subscription quota and org billing toggles; API and Admin key fields
- **Cursor** — subscription quota only (no org billing)

The app imports vendor OAuth into Token Torch-owned Keychain (`com.tokentorch.vendor.*`) once per provider so routine refresh does not re-prompt macOS for vendor Keychain access. On first launch after upgrading from **burn**, `CredentialStoreMigration` copies legacy `com.burn.*` Keychain entries. **token-torch-cli** reads vendor stores directly (also runs migration on startup).


## Architecture

| Target | Role |
|--------|------|
| **TokenTorchCore** | Domain models, HTTP, credentials, quota and org providers, `UsageOrchestrator`. No terminal output. |
| **token-torch-cli** | ArgumentParser CLI (target `TokenTorchCli`); terminal formatting in `Sources/TokenTorchCli/` |
| **Token Torch** | AppKit menu bar app (`Sources/TokenTorchApp/`); `NSMenu` + settings window; links **TokenTorchCore** |

UI targets never call vendor URLs directly — only `UsageOrchestrator` and settings stores.

### Repository layout

```
Package.swift
Sources/
├── TokenTorchCore/          # Library: providers, credentials, orchestration
├── TokenTorchCli/          # Terminal CLI
└── TokenTorchApp/      # Xcode menu bar project (Token Torch.app)
Tests/TokenTorchCoreTests/
Pictures/              # Provider icons (PDF/SVG)
```

### Credential stores

| Store | Purpose |
|-------|---------|
| `VendorCredentialsReader` / `VendorCredentialImporter` | Read-only import from vendor Keychain/files for subscription quota |
| `TokenTorchVendorCredentialStore` | Token Torch-owned OAuth copies (`com.tokentorch.vendor.*`) for silent menu bar refresh |
| `AppKeychainStore` | User-entered Admin keys (`com.tokentorch.keys.<provider>.adminKey`) |

## Tests

```bash
swift test
```

Mapper, date, redaction, and credential-guard tests run offline. Live quota tests require macOS vendor logins.

## Security

- Never commit API keys or OAuth tokens
- User-visible errors are redacted via `Redaction`
- Quota mode does not refresh or write vendor credentials; on 401/403, re-login in the vendor tool
- Keychain access uses Security framework APIs in **TokenTorchCore** (no `security` CLI subprocess)

## Development

See [AGENTS.md](AGENTS.md) for architecture details, conventions, and agent workflow.
