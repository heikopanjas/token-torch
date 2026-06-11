#!/usr/bin/env bash
set -euo pipefail

PROJECT="token-torch.xcodeproj"
SCHEME="token-torch"
APP_NAME="Token Torch"
BUILD_DIR="./build"
ARCHIVE_PATH="${BUILD_DIR}/${APP_NAME}.xcarchive"
EXPORT_PATH="${BUILD_DIR}/export"
EXPORT_PLIST="ExportOptions.plist"
NOTARIZE_PROFILE="${NOTARIZE_PROFILE:-TokenTorch-Notarize}"
# Apple Silicon only — not a universal/Intel build. Architecture comes from Xcode
# ARCHS=arm64 (project + target). generic/platform=macOS is required for archive
# (xcodebuild rejects arch= on "Any Mac").
BUILD_ARCH="arm64"
DESTINATION="generic/platform=macOS"
TEAM_ID="8J2G689FCZ"

CLEAN=false
NOTARIZE=false

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Build, export, and optionally notarize Token Torch for direct distribution (Developer ID).
Apple Silicon (arm64) only — not a universal binary.

Run from Sources/TokenTorchApp/. Requires ExportOptions.plist with a valid Developer ID
provisioning profile for com.panjas.tokentorch.

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

VERSION=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showBuildSettings 2>/dev/null \
    | awk '/MARKETING_VERSION/ { print $3; exit }')
BUILD_NUMBER=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showBuildSettings 2>/dev/null \
    | awk '/CURRENT_PROJECT_VERSION/ { print $3; exit }')

echo "==> Token Torch ${VERSION} (${BUILD_NUMBER})"
echo ""

# Clean
if [ "$CLEAN" = true ]; then
    echo "==> Cleaning..."
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -destination "$DESTINATION" clean -quiet
    rm -rf "$BUILD_DIR"
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
