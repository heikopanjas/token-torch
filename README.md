# Token Torch

macOS-native **Token Torch** helps you see where your LLM usage goes — before the invoice or rate limit does. It unifies **organization billing** (Anthropic and OpenAI Admin APIs) and **personal subscription quotas** (Claude Code, Codex, Cursor, GitHub Copilot) in one menu bar app.

Credentials stay on your Mac. Token Torch reads vendor OAuth and Admin keys **read-only** and never writes back to Claude Code, Codex, Cursor, or GitHub.

## What it does

| Provider | Org billing (Admin API) | Personal subscription quota |
| ---------- | ------------------------- | ---------------------------- |
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

Every row that states a percentage of a cap — the Claude Code and Codex limit windows, Cursor's three meters, Copilot's **Percent used**, and the credits rows that print `(x% used)` — carries a 2px usage bar underneath. The bar fills to the used share and changes color as it climbs: light green below 50%, dark green below 75%, orange below 87%, light red below 95%, dark red at or above 95%. Rows without a cap (Codex's credit balance, **Overage**, org billing costs) have no bar, and neither do rows below 1% used.

Token Torch can post a desktop notification when one of those rows climbs into the orange or red bands, so you don't have to keep the menu open to notice — **Notify when a usage limit runs high** on the Notifications settings tab (on by default), with a **Starting at** choice of Orange (75%) or Red (87%). It alerts once per band as usage climbs past the starting one, stays quiet while a row holds steady, and re-arms if the row falls back to a lower band (e.g. after its window resets). A row hidden by a display preference (Fable, additional model limits, Cursor's value rows) or a disabled provider never alerts.

**Settings** toolbar:

- **General** — **Start at login**, refresh interval, display currency (USD/EUR), **VAT rate (%)**, **Automatically deduct VAT**, **Menu bar icon**, and a **Providers** table for the six menu views (Claude Code, Anthropic API, Codex, OpenAI Platform, Cursor, Copilot): drag rows to reorder, use **Enabled** to turn each view on or off
- **Claude / Codex / Cursor** — reset imported subscription credentials; Claude repair can ask Claude Code to update its own login, then re-import the updated token into Token Torch; Claude and Codex tabs also include an Admin API key field
- **Claude** — optional **Automatically repair credentials in the background** (off by default; when on, repair also runs on startup/timer refreshes via `CLAUDE_CONFIG_DIR=… ANTHROPIC_API_KEY="" claude -p "/usage"` in a controlling terminal and may prompt for Keychain access — manual Refresh always repairs on auth failure), optional **Notify me when background credential repair fails** (on by default; desktop notification on automatic repair failure only), an optional **Claude CLI path** (point at the `claude` executable when it is not found on the login PATH; leave blank to auto-detect), and optional **Show Fable usage** (off by default) to reveal the weekly Fable sub-cap row
- **Codex** — optional **Show additional model usage** (e.g. Codex Spark); extra usage credits are shown as credit units with their fixed USD equivalent (`$0.04` per credit), and available rate-limit reset credits appear when the API reports them
- **Cursor** — optional **Show Total usage value and Bonus** (off by default) to reveal Cursor's opaque value-framing rows; quota meters and Credits are always shown
- **Copilot** — GitHub Personal Access Token field with setup guidance
- **Notifications** — **Notify when a usage limit runs high** (on by default) and a **Starting at** choice of Orange (75% used) or Red (87% used)
- **Advanced** — **Reset Keychain…** deletes all Token Torch-owned Keychain items (`com.tokentorch.*`); vendor logins are not touched
- **Info** — metadata-only view of the vendor source recorded when each enabled subscription credential was imported; Keychain secret values are never displayed

The app imports vendor OAuth into Token Torch-owned Keychain (`com.tokentorch.vendor.*`) once per provider, so routine refresh reads only Token Torch's copy. When a vendor Keychain fallback is needed, Token Torch invokes the timeout-bound `/usr/bin/security find-generic-password` tool for Claude Code, Codex, and Cursor secrets; file and SQLite sources remain preferred. This changes the requesting identity to Apple's `security` tool, but the tool cannot suppress authorization UI, so startup/timer imports may still show a Keychain dialog. Claude Code repair checks the same sources, then launches one `/bin/zsh` process in a controlling-terminal pseudo-terminal (PTY) that runs `CLAUDE_CONFIG_DIR="$2" ANTHROPIC_API_KEY="" exec "$1" -p "/usage"` so Claude Code refreshes the imported profile (not a different default config). The config directory, empty-key assignment, and Claude invocation therefore share the same process and environment. If repair fails, secret-safe diagnostics plus redacted terminal output are kept only with the in-memory error and shown in the menu's copyable error row; they are not added to desktop notifications, persisted, logged, parsed, or used for Token Torch usage display. Repair runs on manual Refresh always, and on automatic refreshes only when **Automatically repair credentials in the background** is enabled on the Claude tab. On first launch, Token Torch requests notification permission; when granted, a welcome notification confirms alerts are enabled. Background repair failures can post a desktop notification when **Notify me when background credential repair fails** is enabled, and usage-threshold alerts (above) can post one when **Notify when a usage limit runs high** is enabled. On first launch after upgrading from **burn**, `CredentialStoreMigration` copies legacy `com.burn.*` Keychain entries.

### Quota credential sources (macOS)

| Tool | Where Token Torch looks (read-only) |
| ------ | ------------------------------------- |
| Claude Code | `$CLAUDE_CONFIG_DIR/.credentials.json`, `~/.config/claude/.credentials.json`, `~/.claude/.credentials.json`, then Keychain `Claude Code-credentials-<hash>` / `Claude Code-credentials` |
| Codex | `~/.codex/auth.json`, `CODEX_HOME`, `~/.config/codex`, Keychain `Codex Auth` |
| Cursor | `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`, Keychain `cursor-access-token` |
| GitHub Copilot | Fine-grained PAT pasted in Settings |

**Copilot PAT:** create a fine-grained personal access token at [github.com/settings/personal-access-tokens](https://github.com/settings/personal-access-tokens) with Account permission **Copilot requests (Read-only)**. Classic `ghp_` tokens are rejected (HTTP 401).

Quota APIs are undocumented and may change. Reference: [OpenUsage provider docs](https://github.com/robinebers/openusage/tree/main/docs/providers).

Codex 5-hour and 7-day windows are classified from each `/wham/usage` window's `limit_window_seconds` (`18000` and `604800`) rather than assuming `primary_window` and `secondary_window` always have fixed meanings. This keeps weekly-only responses correct when Codex moves the remaining weekly limit into the primary slot; payloads without a recognized duration retain the historical positional fallback.

Claude Code's weekly **Fable** limit has no top-level `seven_day_*` key. The `/api/oauth/usage` response reports it only as a `weekly_scoped` entry in the `limits` array, identified by `scope.model.display_name`; the array's `session` and `weekly_all` entries restate `five_hour` and `seven_day` and are ignored. The **Fable share of 7-day limit** row is off by default; enable **Show Fable usage** on the Claude tab to display it. It then sits directly below the 7-day window and stays visible before the window starts, when Anthropic reports `percent` 0 with a null reset. Fable is not a separate allowance: it draws from the same weekly limit as every other model (on Max, up to half of it), so the row reports how much of that scoped share is spent rather than an additional pool. The label says so explicitly because two stacked percentages otherwise read as independent budgets.

Copilot reports the next monthly quota reset, not a subscription billing-cycle start. Token Torch derives the displayed **Quota period** as the preceding UTC calendar month and does not use Copilot's persistent `assigned_date` seat-assignment timestamp.

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
| ------- | --------- |
| `VendorCredentialsReader` / `VendorCredentialImporter` | Read-only import from vendor Keychain/files for subscription quota |
| `TokenTorchVendorCredentialStore` | Token Torch-owned OAuth copies (`com.tokentorch.vendor.*`) for silent menu bar refresh |
| `AppKeychainStore` | User-entered Admin keys (`com.tokentorch.keys.<provider>.adminKey`); Copilot PAT |

## Tests

```bash
xcodebuild test -scheme token-torch -configuration Debug -destination 'platform=macOS,arch=arm64'
```

Offline unit tests cover mappers, dates, redaction, credential guards, in-memory credential-store round trips, and subprocess timeout/cancellation/output handling. Live quota tests require macOS vendor logins and a Copilot PAT.

## Security

- Never commit API keys, OAuth tokens, or PATs
- User-visible errors are redacted via `Redaction`
- Quota mode does not refresh or write vendor credentials; on 401/403, re-login in the vendor tool (or replace the Copilot PAT)
- Vendor-owned Keychain secret reads use timeout-bound `/usr/bin/security` subprocesses during automatic and interactive imports. Security.framework remains responsible for Token Torch-owned reads, all writes/deletes, and metadata-only enumeration. Token Torch never writes vendor-owned credentials.

## Development

See [AGENTS.md](AGENTS.md) for architecture details, conventions, and agent workflow.
