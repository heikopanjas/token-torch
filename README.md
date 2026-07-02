# Token Torch

macOS-native **Token Torch** helps you see where your LLM usage goes — before the invoice or rate limit does. It unifies **organization billing** (Anthropic and OpenAI Admin APIs) and **personal subscription quotas** (Claude Code, Codex, Cursor, GitHub Copilot) in one menu bar app.

Credentials stay on your Mac. Token Torch reads vendor OAuth and Admin keys **read-only** and never writes back to Claude Code, Codex, Cursor, or GitHub.

## What it does

| Provider | Org billing (Admin API) | Personal subscription quota |
|----------|-------------------------|----------------------------|
| **Anthropic** | Token usage + model costs from pricing docs | Claude Code rate limits and plan usage |
| **OpenAI** | Completions usage + native billed costs aggregated by model | Codex / ChatGPT subscription limits |
| **Cursor** | Not available | Plan usage (Auto, API, total meters) |
| **GitHub Copilot** | Not available | AI Credits and monthly quotas via fine-grained PAT |

Org-wide usage is the default in Settings. Scope Anthropic org billing to a workspace or OpenAI org billing to a project from the provider settings tabs.

Display currency (USD/EUR), VAT deduction, provider order, and enable/disable are configured in **Settings → General**.

## Requirements

- macOS 15+ (Apple Silicon)
- Xcode 16+ with Swift 6.2 toolchain (full Xcode required for `./build.sh` release builds)

## Build

From the repository root:

```bash
./build.sh                  # debug build → .build/Products/Debug/
./build.sh --release        # clean, archive + export to .build/export/
./build.sh --release --notarize   # clean, submit and staple (requires notarytool profile)
```

Or open the Xcode project:

```bash
open token-torch.xcodeproj
xcodebuild -scheme token-torch -configuration Debug build
```

The release version lives in `VERSION` at the repository root. Local release builds and CI pass that value into the app `MARKETING_VERSION`.

If `xcodebuild` is missing, `./build.sh` prints how to point `xcode-select` at Xcode. `--notarize` requires `--release`.

### GitHub Actions

- `.github/workflows/build.yml` runs signed release builds on pushes and pull requests for `develop` and `feature/**`, uploads the exported app zip, and creates a GitHub prerelease on non-PR runs.
- `.github/workflows/release.yml` runs signed release builds, Apple notarization, stapling, verification, and artifact upload on pull requests to `main`. On pushes to `main`, it creates the `v$(cat VERSION)` GitHub release after notarization succeeds.
- Both workflows generate `CHANGELOG.md` and `BILL_OF_MATERIALS.md` and include them inside the release zip.
- Both workflows use the `macos-26` GitHub runner image for the current Xcode/Swift toolchain.

Required repository secrets: `APPLE_CERTIFICATE_P12_BASE64`, `APPLE_CERTIFICATE_PASSWORD`, `APPLE_SIGNING_IDENTITY`, `APPLE_TEAM_ID`, `APPLE_ID`, and `APPLE_ID_PASSWORD`.

## Token Torch (menu bar app)

Menu bar app (Xcode): `Token Torch.app`, code signing, `LSUIElement` for menu-bar-only UI. Bundle ID: `com.panjas.tokentorch`.

**Settings** toolbar:

- **General** — **Start at login**, refresh interval, display currency (USD/EUR), **VAT rate (%)**, **Automatically deduct VAT**, **Menu bar icon**, and a **Providers** table for the six menu views (Claude Code, Anthropic API, Codex, OpenAI Platform, Cursor, Copilot): drag rows to reorder, use **Enabled** to turn each view on or off
- **Claude / Codex / Cursor** — reset imported subscription credentials; Claude repair can ask Claude Code to update its own login, then re-import the updated token into Token Torch; Claude and Codex tabs also include an Admin API key field
- **Codex** — optional **Show additional model usage** (e.g. Codex Spark)
- **Cursor** — optional **Hide Total usage value and Bonus** to suppress Cursor's opaque value-framing rows while keeping quota meters and Credits visible
- **Copilot** — GitHub Personal Access Token field with setup guidance
- **Advanced** — **Reset Keychain…** deletes all Token Torch-owned Keychain items (`com.tokentorch.*`); vendor logins are not touched
- **Info** — metadata-only view of the vendor source recorded when each enabled subscription credential was imported; Keychain secret values are never displayed

The app imports vendor OAuth into Token Torch-owned Keychain (`com.tokentorch.vendor.*`) once per provider so routine refresh does not re-prompt macOS for vendor Keychain access. User-initiated Claude Code repair first checks no-prompt Claude sources, including credentials files and a timeout-bound Claude-only `/usr/bin/security` read, to avoid extra Keychain prompts when Claude Code has already refreshed its own login. On first launch after upgrading from **burn**, `CredentialStoreMigration` copies legacy `com.burn.*` Keychain entries.

### Quota credential sources (macOS)

| Tool | Where Token Torch looks (read-only) |
|------|-------------------------------------|
| Claude Code | Keychain `Claude Code-credentials`, then `~/.claude/.credentials.json` |
| Codex | `~/.codex/auth.json`, `CODEX_HOME`, `~/.config/codex`, Keychain `Codex Auth` |
| Cursor | `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`, Keychain `cursor-access-token` |
| GitHub Copilot | Fine-grained PAT pasted in Settings |

**Copilot PAT:** create a fine-grained personal access token at [github.com/settings/personal-access-tokens](https://github.com/settings/personal-access-tokens) with Account permission **Copilot requests (Read-only)**. Classic `ghp_` tokens are rejected (HTTP 401).

Quota APIs are undocumented and may change. Reference: [OpenUsage provider docs](https://github.com/robinebers/openusage/tree/main/docs/providers).

## Architecture

| Target | Role |
|--------|------|
| **Token Torch** | AppKit menu bar app; includes Core sources (providers, credentials, orchestration) and AppKit UI |

UI code never calls vendor URLs directly — only `UsageOrchestrator` and settings stores.

### Repository layout

```
token-torch/               # App UI + Core/ (domain logic)
token-torch-tests/
token-torch.xcodeproj
pictures/                  # Provider icon PDFs
exportOptions.plist        # Developer ID export (release builds)
VERSION                    # Release version source of truth
```

### Credential stores

| Store | Purpose |
|-------|---------|
| `VendorCredentialsReader` / `VendorCredentialImporter` | Read-only import from vendor Keychain/files for subscription quota |
| `TokenTorchVendorCredentialStore` | Token Torch-owned OAuth copies (`com.tokentorch.vendor.*`) for silent menu bar refresh |
| `AppKeychainStore` | User-entered Admin keys (`com.tokentorch.keys.<provider>.adminKey`); Copilot PAT |

## Tests

```bash
xcodebuild test -scheme token-torch -configuration Debug -destination 'platform=macOS,arch=arm64'
```

Offline unit tests cover mappers, dates, redaction, credential guards, and Keychain round-trips. Live quota tests require macOS vendor logins and a Copilot PAT.

## Security

- Never commit API keys, OAuth tokens, or PATs
- User-visible errors are redacted via `Redaction`
- Quota mode does not refresh or write vendor credentials; on 401/403, re-login in the vendor tool (or replace the Copilot PAT)
- Keychain access uses Security framework APIs by default. The only subprocess exception is Claude Code repair, which may read the Claude Code Keychain item with `/usr/bin/security` after an explicit user action; Token Torch still never writes vendor-owned credentials.

## Development

See [AGENTS.md](AGENTS.md) for architecture details, conventions, and agent workflow.
