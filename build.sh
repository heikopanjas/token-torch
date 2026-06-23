#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PROJECT="${ROOT}/token-torch.xcodeproj"
SCHEME="token-torch"
APP_NAME="Token Torch"
BUILD_DIR="${ROOT}/.build"
DEBUG_DERIVED_DATA="${ROOT}/.build"
DEBUG_APP="${ROOT}/.build/Products/Debug/${APP_NAME}.app"
ARCHIVE_PATH="${BUILD_DIR}/${APP_NAME}.xcarchive"
EXPORT_PATH="${BUILD_DIR}/export"
EXPORT_PLIST="${ROOT}/exportOptions.plist"
VERSION_FILE="${ROOT}/VERSION"
NOTARIZE_PROFILE="${NOTARIZE_PROFILE:-TokenTorch-Notarize}"
# Apple Silicon only — not a universal/Intel build. Architecture comes from Xcode
# ARCHS=arm64 (project + target). Debug can pass arch= on -destination; release
# archive must use generic/platform=macOS (xcodebuild rejects arch on "Any Mac").
BUILD_ARCH="arm64"
DEBUG_DESTINATION="platform=macOS,arch=${BUILD_ARCH}"
RELEASE_DESTINATION="generic/platform=macOS"
TEAM_ID="8J2G689FCZ"

RELEASE=false
CLEAN=false
NOTARIZE=false

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Build the Token Torch menu bar app (Xcode). Run from the repository root.
Apple Silicon (arm64) only — not a universal binary.

Modes:
    (default)     Debug build → ${DEBUG_APP}
    --release     Release archive + Developer ID export → ${EXPORT_PATH}/${APP_NAME}.app

Options:
    --release     Clean, archive, export, and optionally notarize for distribution
    --clean       Clean build artifacts before a debug build (release always cleans)
    --notarize    Submit the exported release app for notarization and staple
                  (requires --release)
    -h, --help    Show this help message

Examples:
    $(basename "$0")                      # Debug build
    $(basename "$0") --clean              # Clean, then debug build
    $(basename "$0") --release            # Clean, archive, and export
    $(basename "$0") --release --notarize # Clean, archive, export, notarize, and staple

Release builds require exportOptions.plist at the repository root with Developer ID signing
configured for com.panjas.tokentorch.

Notarization (--notarize) requires a notarytool Keychain profile (default: ${NOTARIZE_PROFILE}).
Create it once (app-specific password from appleid.apple.com):

    xcrun notarytool store-credentials "${NOTARIZE_PROFILE}" \\
      --apple-id "you@example.com" \\
      --team-id ${TEAM_ID} \\
      --password "xxxx-xxxx-xxxx-xxxx"

Override profile name: NOTARIZE_PROFILE=my-profile $(basename "$0") --release --notarize
EOF
    exit 0
}

for arg in "$@"; do
    case "$arg" in
        --release)  RELEASE=true ;;
        --clean)    CLEAN=true ;;
        --notarize) NOTARIZE=true ;;
        -h|--help)  usage ;;
        *)          echo "Unknown option: $arg" >&2; usage ;;
    esac
done

if [ "$NOTARIZE" = true ] && [ "$RELEASE" = false ]; then
    echo "Error: --notarize requires --release." >&2
    exit 1
fi

if [ "$RELEASE" = true ]; then
    CLEAN=true
fi

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
    if [ ! -f "$VERSION_FILE" ]; then
        echo "Error: missing version file: ${VERSION_FILE}" >&2
        exit 1
    fi

    VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
    if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "Error: ${VERSION_FILE} must contain a semantic version like 4.2.15" >&2
        exit 1
    fi

    local settings
    if ! settings="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showBuildSettings 2>&1)"; then
        echo "Error: failed to read build settings from ${PROJECT}" >&2
        echo "$settings" >&2
        exit 1
    fi

    BUILD_NUMBER="$(echo "$settings" | awk '/CURRENT_PROJECT_VERSION/ { print $3; exit }')"

    if [ -z "$BUILD_NUMBER" ]; then
        echo "Error: could not read CURRENT_PROJECT_VERSION from ${PROJECT}" >&2
        exit 1
    fi
}

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

build_debug() {
    if [ "$CLEAN" = true ]; then
        echo "==> Cleaning (Debug)..."
        xcodebuild \
            -project "$PROJECT" \
            -scheme "$SCHEME" \
            -configuration Debug \
            -destination "$DEBUG_DESTINATION" \
            -derivedDataPath "$DEBUG_DERIVED_DATA" \
            clean -quiet
        echo "    Done."
        echo ""
    fi

    echo "==> Building (Debug)..."
    xcodebuild \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration Debug \
        -destination "$DEBUG_DESTINATION" \
        -derivedDataPath "$DEBUG_DERIVED_DATA" \
        MARKETING_VERSION="$VERSION" \
        build -quiet
    echo "    App: ${DEBUG_APP}"
    echo ""
    echo "==> Build complete: ${DEBUG_APP}"
}

build_release() {
    if [ "$CLEAN" = true ]; then
        echo "==> Cleaning (Release)..."
        xcodebuild \
            -project "$PROJECT" \
            -scheme "$SCHEME" \
            -destination "$RELEASE_DESTINATION" \
            clean -quiet
        rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH" "${BUILD_DIR}/TokenTorch.zip"
        echo "    Done."
        echo ""
    fi

    mkdir -p "$BUILD_DIR"

    echo "==> Archiving (Release)..."
    xcodebuild archive \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration Release \
        -destination "$RELEASE_DESTINATION" \
        -archivePath "$ARCHIVE_PATH" \
        MARKETING_VERSION="$VERSION" \
        -quiet
    echo "    Archive: ${ARCHIVE_PATH}"
    echo ""

    echo "==> Exporting with Developer ID signing..."
    rm -rf "$EXPORT_PATH"
    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE_PATH" \
        -exportPath "$EXPORT_PATH" \
        -exportOptionsPlist "$EXPORT_PLIST" \
        -quiet
    echo "    App: ${EXPORT_PATH}/${APP_NAME}.app"
    echo ""

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
        spctl -a -vvv "${EXPORT_PATH}/${APP_NAME}.app"
        echo ""

        rm -f "$ZIP_PATH"
    fi

    echo "==> Build complete: ${EXPORT_PATH}/${APP_NAME}.app"
}

require_xcode
read_build_version

echo "==> Token Torch ${VERSION} (${BUILD_NUMBER})"
echo ""

if [ "$RELEASE" = true ]; then
    build_release
else
    build_debug
fi
