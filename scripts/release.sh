#!/usr/bin/env bash
set -euo pipefail

# NoCrumbs Release Pipeline
# Usage: ./scripts/release.sh <version> [--team-id <id>] [--password <keychain-profile>]
#
# Secrets are loaded from scripts/.env.local (gitignored).
# See scripts/RUNBOOK.local.md for setup instructions.

VERSION="${1:?Usage: $0 <version> [--team-id <id>] [--password <keychain-profile>]}"

# Load local secrets (not tracked in git)
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${PROJECT_DIR}/scripts/.env.local"
if [[ -f "$ENV_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$ENV_FILE"
fi

# Defaults (secrets must come from .env.local or flags)
TEAM_ID="${NOCRUMBS_TEAM_ID:-}"
KEYCHAIN_PROFILE="${NOCRUMBS_KEYCHAIN_PROFILE:-nocrumbs-notary}"
BUILD_DIR="${PROJECT_DIR}/build-release"
APP_NAME="NoCrumbs"

# Parse optional flags
shift
while [[ $# -gt 0 ]]; do
    case "$1" in
        --team-id) TEAM_ID="$2"; shift 2 ;;
        --password) KEYCHAIN_PROFILE="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [[ -z "$TEAM_ID" ]]; then
    echo "❌ TEAM_ID not set. Either:"
    echo "   1. Create scripts/.env.local with: NOCRUMBS_TEAM_ID=<your-team-id>"
    echo "   2. Pass --team-id <id>"
    exit 1
fi

# Resolve Sparkle tools from SPM build
SPARKLE_BIN="${PROJECT_DIR}/build/SourcePackages/artifacts/sparkle/Sparkle/bin"
if [[ ! -d "$SPARKLE_BIN" ]]; then
    # Try DerivedData SPM checkout
    SPARKLE_BIN=$(find "${BUILD_DIR}" -path "*/artifacts/sparkle/Sparkle/bin" -type d 2>/dev/null | head -1)
fi
if [[ ! -d "$SPARKLE_BIN" ]]; then
    echo "⚠️  Sparkle bin tools not found. Build the project first to download SPM packages."
    echo "   Looking for sign_update and generate_appcast in SPM artifacts."
    SPARKLE_BIN=""
fi

echo "=== NoCrumbs Release ${VERSION} ==="
echo "Team ID: ${TEAM_ID}"
echo "Project: ${PROJECT_DIR}"
echo ""

# Step 1: Update version in Info.plist
echo "→ Setting version to ${VERSION}..."
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" \
    "${PROJECT_DIR}/NoCrumbs/Resources/Info.plist"

# Increment build number (use date-based)
BUILD_NUMBER=$(date +%Y%m%d%H%M)
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" \
    "${PROJECT_DIR}/NoCrumbs/Resources/Info.plist"
echo "   Version: ${VERSION} (${BUILD_NUMBER})"

# Step 2: Clean build with Developer ID signing + hardened runtime
echo "→ Building Release configuration..."
xcodebuild -project "${PROJECT_DIR}/NoCrumbs.xcodeproj" \
    -scheme "${APP_NAME}" \
    -configuration Release \
    -sdk macosx \
    -derivedDataPath "${BUILD_DIR}" \
    ARCHS="arm64 x86_64" \
    DEVELOPMENT_TEAM="${TEAM_ID}" \
    CODE_SIGN_IDENTITY="Developer ID Application" \
    CODE_SIGN_STYLE="Manual" \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime" \
    clean build 2>&1 | tail -5

APP_PATH="${BUILD_DIR}/Build/Products/Release/${APP_NAME}.app"
if [[ ! -d "$APP_PATH" ]]; then
    echo "❌ Build failed — app not found at ${APP_PATH}"
    exit 1
fi
echo "✓ Built: ${APP_PATH}"

# Step 3: Re-sign Sparkle embedded binaries with Developer ID + timestamp
echo "→ Re-signing Sparkle framework binaries..."
SIGN_ID="Developer ID Application: Gene Yoo (${TEAM_ID})"
find "$APP_PATH/Contents/Frameworks/Sparkle.framework" -type f -perm +111 | while read -r binary; do
    codesign --force --sign "$SIGN_ID" --timestamp --options runtime "$binary" 2>/dev/null || true
done
# Re-sign XPC services and nested apps
find "$APP_PATH/Contents/Frameworks/Sparkle.framework" -name "*.xpc" -o -name "*.app" | while read -r bundle; do
    codesign --force --deep --sign "$SIGN_ID" --timestamp --options runtime "$bundle"
done
# Re-sign the framework itself
codesign --force --sign "$SIGN_ID" --timestamp --options runtime \
    "$APP_PATH/Contents/Frameworks/Sparkle.framework"
echo "✓ Sparkle binaries re-signed"

# Step 4: Re-sign the main app (picks up re-signed framework)
echo "→ Re-signing app bundle..."
codesign --force --sign "$SIGN_ID" --timestamp --options runtime \
    --entitlements "${PROJECT_DIR}/NoCrumbs/Resources/NoCrumbs.entitlements" \
    "$APP_PATH"
echo "✓ App re-signed"

# Step 5: Verify code signing
echo "→ Verifying code signature..."
codesign -dv --verbose=2 "$APP_PATH" 2>&1 | grep -E "(Authority|Runtime|Identifier)"
codesign --verify --strict --deep "$APP_PATH"
echo "✓ Code signature valid"

# Verify no get-task-allow (Apple rejects this)
if codesign -d --entitlements - "$APP_PATH" 2>&1 | grep -q "get-task-allow"; then
    echo "❌ get-task-allow entitlement found — notarization will fail"
    exit 1
fi
echo "✓ No debug entitlements"

# Step 6: Create zip for notarization
echo "→ Creating zip for notarization..."
ZIP_PATH="${BUILD_DIR}/${APP_NAME}-${VERSION}.zip"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
echo "✓ Zip created: ${ZIP_PATH}"

# Step 7: Notarize
echo "→ Submitting for notarization (this may take a few minutes)..."
xcrun notarytool submit "$ZIP_PATH" \
    --keychain-profile "${KEYCHAIN_PROFILE}" \
    --wait 2>&1 | tee "${BUILD_DIR}/notarization.log"

if ! grep -q "status: Accepted" "${BUILD_DIR}/notarization.log"; then
    echo "❌ Notarization failed. Check ${BUILD_DIR}/notarization.log"
    echo "   Run: xcrun notarytool log <submission-id> --keychain-profile ${KEYCHAIN_PROFILE}"
    exit 1
fi
echo "✓ Notarization accepted"

# Step 8: Staple
echo "→ Stapling notarization ticket..."
xcrun stapler staple "$APP_PATH"
echo "✓ Stapled"

# Step 9: Re-zip after stapling (final distributable)
echo "→ Creating final distributable zip..."
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
ZIP_SIZE=$(stat -f%z "$ZIP_PATH")
echo "✓ Final zip: ${ZIP_PATH} ($(( ZIP_SIZE / 1048576 )) MB)"

# Step 10: Sign zip with Sparkle EdDSA
if [[ -n "$SPARKLE_BIN" && -x "${SPARKLE_BIN}/sign_update" ]]; then
    echo "→ Signing zip with Sparkle EdDSA..."
    EDDSA_SIG=$("${SPARKLE_BIN}/sign_update" "$ZIP_PATH")
    echo "✓ EdDSA signature:"
    echo "   ${EDDSA_SIG}"
else
    echo "⚠️  Skipping Sparkle signing — sign_update not found"
    echo "   Run manually: <sparkle-bin>/sign_update ${ZIP_PATH}"
    EDDSA_SIG="(manual signing required)"
fi

# Step 11: Generate appcast
APPCAST_DIR="${BUILD_DIR}/appcast"
mkdir -p "$APPCAST_DIR"
cp "$ZIP_PATH" "$APPCAST_DIR/"

if [[ -n "$SPARKLE_BIN" && -x "${SPARKLE_BIN}/generate_appcast" ]]; then
    echo "→ Generating appcast.xml..."
    "${SPARKLE_BIN}/generate_appcast" "$APPCAST_DIR" \
        --download-url-prefix "https://github.com/geneyoo/nocrumbs/releases/download/v${VERSION}/"
    echo "✓ Appcast generated: ${APPCAST_DIR}/appcast.xml"
else
    echo "⚠️  Skipping appcast generation — generate_appcast not found"
fi

# Summary
echo ""
echo "=== Release ${VERSION} Complete ==="
echo ""
echo "Artifacts:"
echo "  Zip:     ${ZIP_PATH}"
echo "  Appcast: ${APPCAST_DIR}/appcast.xml"
echo ""
echo "Next steps:"
echo "  1. Upload zip to GitHub Release v${VERSION}"
echo "  2. Upload appcast.xml to https://nocrumbs.ai/appcast.xml"
echo "  3. Tag: git tag v${VERSION} && git push --tags"
echo ""
if [[ "$EDDSA_SIG" != "(manual signing required)" ]]; then
    echo "Sparkle signature (for manual appcast editing):"
    echo "  ${EDDSA_SIG}"
fi
