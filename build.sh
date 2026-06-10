#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="${ROOT}/Sources/TokenTorchApp"
PROJECT="${APP_DIR}/token-torch.xcodeproj"
SCHEME="token-torch"
APP_NAME="Token Torch"
BUILD_DIR="${ROOT}/.build"
ARCHIVE_PATH="${BUILD_DIR}/${APP_NAME}.xcarchive"
EXPORT_PATH="${BUILD_DIR}/export"
EXPORT_PLIST="${APP_DIR}/ExportOptions.plist"
NOTARIZE_PROFILE="${NOTARIZE_PROFILE:-TokenTorch-Notarize}"
DESTINATION="generic/platform=macOS"
TEAM_ID="8J2G689FCZ"

CLEAN=false
NOTARIZE=false

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Build, export, and optionally notarize Token Torch for direct distribution (Developer ID).

Run from the repository root. Requires ${APP_DIR}/ExportOptions.plist with a valid
Developer ID provisioning profile for com.panjas.tokentorch.

Options:
    --clean       Clean build artifacts before building
    --notarize    Submit the exported app for notarization and staple
    -h, --help    Show this help message

Examples:
    $(basename "$0")                  # Archive and export only
    $(basename "$0") --clean          # Clean first, then archive and export
    $(basename "$0") --notarize       # Archive, export, notarize, and staple
    $(basename "$0") --clean --notarize

Notarization (--notarize) requires a notarytool Keychain profile (default: ${NOTARIZE_PROFILE}).
Create it once (app-specific password from appleid.apple.com):

    xcrun notarytool store-credentials "${NOTARIZE_PROFILE}" \\
      --apple-id "you@example.com" \\
      --team-id ${TEAM_ID} \\
      --password "xxxx-xxxx-xxxx-xxxx"

Override profile name: NOTARIZE_PROFILE=my-profile $(basename "$0") --notarize
EOF
    exit 0
}

for arg in "$@"; do
    case "$arg" in
        --clean)    CLEAN=true ;;
        --notarize) NOTARIZE=true ;;
        -h|--help)  usage ;;
        *)          echo "Unknown option: $arg"; usage ;;
    esac
done

require_xcode() {
    if xcodebuild -version &>/dev/null; then
        return 0
    fi

    echo "Error: xcodebuild requires full Xcode.app, not Command Line Tools alone." >&2
    echo "" >&2

    local active_dir="(unknown)"
    if active_dir="$(xcode-select -p 2>/dev/null)"; then
        echo "Active developer directory: ${active_dir}" >&2
    fi

    local -a xcode_apps=()
    local candidate
    for candidate in /Applications/Xcode.app /Applications/Xcode-beta.app; do
        if [ -d "$candidate" ]; then
            xcode_apps+=("$candidate")
        fi
    done

    if [ "${#xcode_apps[@]}" -gt 0 ]; then
        echo "" >&2
        echo "Found Xcode installation(s). Point xcode-select at one of them:" >&2
        for candidate in "${xcode_apps[@]}"; do
            echo "  sudo xcode-select -s \"${candidate}/Contents/Developer\"" >&2
        done
        echo "" >&2
        echo "Or run this build once without changing the global setting:" >&2
        echo "  DEVELOPER_DIR=\"${xcode_apps[0]}/Contents/Developer\" $(basename "$0")" >&2
    else
        echo "" >&2
        echo "Install Xcode from the App Store, then run:" >&2
        echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
    fi

    exit 1
}

read_build_version() {
    local settings
    if ! settings="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showBuildSettings 2>&1)"; then
        echo "Error: failed to read build settings from ${PROJECT}" >&2
        echo "$settings" >&2
        exit 1
    fi

    VERSION="$(echo "$settings" | awk '/MARKETING_VERSION/ { print $3; exit }')"
    BUILD_NUMBER="$(echo "$settings" | awk '/CURRENT_PROJECT_VERSION/ { print $3; exit }')"

    if [ -z "$VERSION" ] || [ -z "$BUILD_NUMBER" ]; then
        echo "Error: could not read MARKETING_VERSION or CURRENT_PROJECT_VERSION from ${PROJECT}" >&2
        exit 1
    fi
}

require_xcode
read_build_version

echo "==> Token Torch ${VERSION} (${BUILD_NUMBER})"
echo ""

# Clean
if [ "$CLEAN" = true ]; then
    echo "==> Cleaning..."
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -destination "$DESTINATION" clean -quiet
    rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH" "${BUILD_DIR}/TokenTorch.zip"
    echo "    Done."
    echo ""
fi

mkdir -p "$BUILD_DIR"

# Archive
echo "==> Archiving (Release)..."
xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "$DESTINATION" \
    -archivePath "$ARCHIVE_PATH" \
    -quiet
echo "    Archive: ${ARCHIVE_PATH}"
echo ""

# Export
echo "==> Exporting with Developer ID signing..."
rm -rf "$EXPORT_PATH"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_PLIST" \
    -quiet
echo "    App: ${EXPORT_PATH}/${APP_NAME}.app"
echo ""

check_notary_profile() {
    if xcrun notarytool history --keychain-profile "$NOTARIZE_PROFILE" &>/dev/null; then
        return 0
    fi
    echo "Error: notarytool Keychain profile not found: ${NOTARIZE_PROFILE}" >&2
    echo "" >&2
    echo "Create credentials (one-time):" >&2
    echo "  xcrun notarytool store-credentials \"${NOTARIZE_PROFILE}\" \\" >&2
    echo "    --apple-id \"YOUR_APPLE_ID\" \\" >&2
    echo "    --team-id ${TEAM_ID} \\" >&2
    echo "    --password \"APP_SPECIFIC_PASSWORD\"" >&2
    echo "" >&2
    echo "App-specific password: https://account.apple.com/account/manage (Sign-In and Security)" >&2
    echo "Or set NOTARIZE_PROFILE to an existing profile name." >&2
    return 1
}

# Notarize
if [ "$NOTARIZE" = true ]; then
    check_notary_profile

    ZIP_PATH="${BUILD_DIR}/TokenTorch.zip"

    echo "==> Creating zip for notarization..."
    rm -f "$ZIP_PATH"
    ditto -c -k --keepParent "${EXPORT_PATH}/${APP_NAME}.app" "$ZIP_PATH"
    echo "    Zip: ${ZIP_PATH}"
    echo ""

    echo "==> Submitting for notarization (this may take a few minutes)..."
    xcrun notarytool submit "$ZIP_PATH" \
        --keychain-profile "$NOTARIZE_PROFILE" \
        --wait
    echo ""

    echo "==> Stapling notarization ticket..."
    xcrun stapler staple "${EXPORT_PATH}/${APP_NAME}.app"
    echo ""

    echo "==> Verifying..."
    spctl -a -vvv "${EXPORT_PATH}/${APP_NAME}.app" 2>&1 | head -5
    echo ""

    rm -f "$ZIP_PATH"
fi

echo "==> Build complete: ${EXPORT_PATH}/${APP_NAME}.app"
