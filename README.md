# burn

macOS-native **burn** — shared `BurnCore` library, `burn-cli` terminal CLI, and `burn-app` menu bar app for LLM provider usage and subscription quotas.

## Requirements

- macOS 14+
- Xcode 16+ / Swift 6 toolchain

## Build

```bash
swift build
swift test
```

Binaries:

- `.build/debug/burn-cli` — CLI (Swift Package)
- `Sources/burn-app/.build/Products/Debug/burn-app.app` — menu bar app (Xcode)

## Architecture

| Target | Role |
|--------|------|
| **BurnCore** | Domain models, vendor OAuth (read-only import + burn-owned copy), app Keychain, HTTP, quota + org providers, `UsageOrchestrator`. No terminal output. |
| **burn-cli** | ArgumentParser CLI — fetches via BurnCore; terminal formatting in `Sources/burn-cli/` |
| **burn-app** | macOS menu bar app (Xcode project in `Sources/burn-app/`); links **BurnCore** |

UI targets never call vendor URLs directly — only `UsageOrchestrator` and settings stores. All CLI stdout/stderr formatting lives in the **`burn-cli` executable target**, not BurnCore (menu bar uses its own SwiftUI).

### Credential stores

| Store | Purpose |
|-------|---------|
| `VendorCredentialsReader` / `VendorCredentialImporter` | Subscription quota OAuth: **read-only** import from vendor files/Keychain; menu bar stores a copy in burn Keychain |
| `BurnVendorCredentialStore` | burn-owned OAuth copies (`com.burn.vendor.*`) for silent menu bar refresh |
| `AppKeychainStore` | User-entered Admin keys (`com.burn.keys.<provider>.adminKey`) |

### Settings (menu bar)

`Settings` → tab per provider:

- **General** — refresh interval
- **Claude / Codex** — subscription quota + org billing toggles; API + Admin key fields
- **Cursor** — subscription quota toggle only (no org billing)

## CLI examples

```bash
# Subscription quotas (vendor OAuth)
.build/debug/burn-cli anthropic --quota
.build/debug/burn-cli codex --quota
.build/debug/burn-cli cursor --quota

# Org billing (Admin key: -a, env, or app Keychain)
.build/debug/burn-cli anthropic -a "$ANTHROPIC_ADMIN_KEY"
.build/debug/burn-cli openai -a "$OPENAI_ADMIN_KEY"

# List workspaces / projects
.build/debug/burn-cli anthropic --list-workspaces
.build/debug/burn-cli openai --list-projects
```

## burn-app

The menu bar app is an **Xcode project** (proper `.app` bundle, code signing, `LSUIElement` for menu-bar-only).

```bash
# Open in Xcode (recommended)
open Sources/burn-app/burn-app.xcodeproj

# Command line
cd Sources/burn-app
xcodebuild -scheme burn-app -configuration Debug build
open .build/Products/Debug/burn-app.app
```

Set your **Development Team** in the target’s Signing & Capabilities before distributing. Bundle ID: `com.panjas.burn`.

Open **Settings** from the menu to configure per-provider toggles and save keys to burn’s Keychain.

## Tests

```bash
swift test
```

Mapper and date/redaction tests run offline; live quota tests require macOS vendor logins.
