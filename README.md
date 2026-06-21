# Token Torch

macOS-native **Token Torch** helps you see where your LLM usage goes — before the invoice or rate limit does. It unifies **organization billing** (Anthropic and OpenAI Admin APIs) and **personal subscription quotas** (Claude Code, Codex, Cursor, GitHub Copilot) into one Swift stack: shared **TokenTorchCore**, terminal **token-torch-cli**, and menu bar **Token Torch**.

Credentials stay on your Mac. Token Torch reads vendor OAuth and Admin keys **read-only** and never writes back to Claude Code, Codex, Cursor, or GitHub.

## What it does

| Provider | Org billing (Admin API) | Personal quota (`--quota`) |
|----------|-------------------------|----------------------------|
| **Anthropic** (`anthropic`, alias `claude`) | Token usage + model costs from pricing docs | Claude Code rate limits and plan usage |
| **OpenAI** (`openai`, alias `codex`) | Completions usage + native billed costs aggregated by model | Codex / ChatGPT subscription limits |
| **Cursor** (`cursor`) | Not available | Plan usage (Auto, API, total meters) |
| **GitHub Copilot** (`copilot`) | Not available | AI Credits and monthly quotas via fine-grained PAT |

Org-wide usage is the default. Scope with `--workspace` (Anthropic) or `--project` (OpenAI; use `default` for unscoped usage).

All subcommands accept `-c` / `--currency` (`USD` or `EUR`; defaults to your system locale).

## Requirements

- macOS 15+ (Apple Silicon)
- Xcode 16+ with **Swift 6.2** toolchain (full Xcode required for the menu bar app and `./build.sh` release builds; do not require Swift 6.3/6.4)

## Build

```bash
# Swift Package (TokenTorchCore + token-torch-cli)
swift build
swift test
```

Binaries:

- `.build/debug/token-torch-cli` — CLI (Swift Package)
- `Sources/TokenTorchApp/.build/Products/Debug/Token Torch.app` — menu bar app (Xcode)

### Release (Developer ID export)

The release version lives in `VERSION` at the repository root. Local release builds and CI pass that value into the app `MARKETING_VERSION`; the CLI exposes the same value through `AppVersion.current`.

From the repository root:

```bash
./build.sh                  # debug build → Sources/TokenTorchApp/.build/Products/Debug/
./build.sh --release        # clean, archive + export to .build/export/
./build.sh --release --notarize   # clean, submit and staple (requires notarytool profile)
```

If `xcodebuild` is missing, the script prints how to point `xcode-select` at Xcode (or use `DEVELOPER_DIR=… ./build.sh` once). `--notarize` requires `--release`.

### GitHub Actions

- `.github/workflows/build.yml` runs signed release builds on pushes and pull requests for `develop` and `feature/**`, then uploads the exported app zip.
- `.github/workflows/release.yml` runs signed release builds, Apple notarization, stapling, verification, and artifact upload on pull requests to `main`. On pushes to `main`, it creates `v$(cat VERSION)` after notarization succeeds and refuses to overwrite an existing tag.

Required repository secrets:

- `APPLE_CERTIFICATE_P12_BASE64` — base64 encoded Developer ID Application `.p12`.
- `APPLE_CERTIFICATE_PASSWORD` — password for that `.p12`.
- `APPLE_SIGNING_IDENTITY` — full Developer ID Application signing identity.
- `APPLE_TEAM_ID` — Apple Developer Team ID.
- `APPLE_ID` — Apple ID for notarization.
- `APPLE_ID_PASSWORD` — app-specific password for `notarytool`.

The workflows use `Sources/TokenTorchApp/exportOptions.plist` and import the certificate into a temporary keychain on the GitHub-hosted macOS runner.

## CLI

Command name: `token-torch-cli`. Top-level flags: `--version` / `-V`.

### Subscription quotas

Reads local OAuth on macOS (Claude, Codex, Cursor) or a user-pasted GitHub PAT (Copilot). No Admin API key required:

```bash
.build/debug/token-torch-cli anthropic --quota   # alias: claude
.build/debug/token-torch-cli openai --quota      # alias: codex
.build/debug/token-torch-cli cursor --quota
.build/debug/token-torch-cli copilot --quota
```

Copilot also accepts `-t` / `GITHUB_TOKEN` / `COPILOT_TOKEN` for the fine-grained PAT.

### Organization billing

Requires an **Admin API key** (not a regular API key):

- Anthropic: `-a` / `ANTHROPIC_ADMIN_KEY` — create at **Settings → Organization → API Keys** in the Anthropic Console
- OpenAI: `-a` / `OPENAI_ADMIN_KEY`
- CLI also reads keys saved by **Token Torch** in Keychain (`com.tokentorch.keys.<provider>.adminKey`)

OpenAI native cost line items such as `chat-latest, input` and `chat-latest, output` are aggregated into one model cost row.

```bash
# Current month (default date range)
.build/debug/token-torch-cli anthropic
.build/debug/token-torch-cli openai

# Explicit range: YYYY, YYYY-MM, or YYYY-MM-DD
.build/debug/token-torch-cli anthropic -s 2026-05
.build/debug/token-torch-cli openai -s 2026-05-01 -e 2026-05-15

# Display in EUR
.build/debug/token-torch-cli anthropic -c EUR

# List workspaces / projects
.build/debug/token-torch-cli anthropic --list-workspaces
.build/debug/token-torch-cli openai --list-projects

# Scoped usage
.build/debug/token-torch-cli anthropic --workspace default
.build/debug/token-torch-cli openai --project proj_abc
```

`cursor` and `copilot` without `--quota` print a notice that org billing is not supported.

### Quota credential sources (macOS)

| Tool | Where Token Torch looks (read-only) |
|------|-------------------------------------|
| Claude Code | Keychain `Claude Code-credentials`, then `~/.claude/.credentials.json` |
| Codex | `~/.codex/auth.json`, `CODEX_HOME`, `~/.config/codex`, Keychain `Codex Auth` |
| Cursor | `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`, Keychain `cursor-access-token` |
| GitHub Copilot | Fine-grained PAT pasted in Settings or passed via `-t` / env (see below) |

**Copilot PAT:** create a fine-grained personal access token at [github.com/settings/personal-access-tokens](https://github.com/settings/personal-access-tokens) with Account permission **Copilot requests (Read-only)**. Classic `ghp_` tokens are rejected (HTTP 401).

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

**Settings** toolbar:

- **General** — **Start at login**, refresh interval, display currency (USD/EUR), **VAT rate (%)**, **Automatically deduct VAT**, **Menu bar icon** (Anthropic, OpenAI, Cursor, Copilot), and a **Providers** table listing the six menu views (Claude Code, Anthropic API, Codex, OpenAI Platform, Cursor, Copilot): drag rows to reorder, use **Enabled** to turn each view on or off (enabling triggers a refresh; disabling is instant)
- **Claude / Codex / Cursor** — reset imported subscription credentials (button with explanatory text); Claude and Codex tabs also include an Admin API key field with setup guidance
- **Codex** — optional **Show additional model usage** (e.g. Codex Spark)
- **Copilot** — GitHub Personal Access Token field with setup guidance (same grouped layout as Admin API keys on Claude/OpenAI)
- **Advanced** — **Reset Keychain…** with explanatory text (same grouped layout as provider tabs); deletes all Token Torch-owned Keychain items (`com.tokentorch.*`); vendor logins are not touched

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
├── TokenTorchCli/           # Terminal CLI
└── TokenTorchApp/           # Xcode menu bar project (Token Torch.app)
Tests/TokenTorchCoreTests/
Pictures/                    # Provider icon PDFs (referenced by Xcode)
```

### Credential stores

| Store | Purpose |
|-------|---------|
| `VendorCredentialsReader` / `VendorCredentialImporter` | Read-only import from vendor Keychain/files for subscription quota |
| `TokenTorchVendorCredentialStore` | Token Torch-owned OAuth copies (`com.tokentorch.vendor.*`) for silent menu bar refresh |
| `AppKeychainStore` | User-entered Admin keys (`com.tokentorch.keys.<provider>.adminKey`); Copilot PAT (`com.tokentorch.keys.copilot.personalAccessToken`) |

## Tests

```bash
swift test
```

Offline unit tests cover mappers, dates, redaction, credential guards, and Keychain round-trips. Live quota tests require macOS vendor logins and a Copilot PAT.

## Security

- Never commit API keys, OAuth tokens, or PATs
- User-visible errors are redacted via `Redaction`
- Quota mode does not refresh or write vendor credentials; on 401/403, re-login in the vendor tool (or replace the Copilot PAT)
- Keychain access uses Security framework APIs in **TokenTorchCore** (no `security` CLI subprocess)

## Development

See [AGENTS.md](AGENTS.md) for architecture details, conventions, and agent workflow.
