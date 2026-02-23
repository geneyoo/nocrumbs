#!/usr/bin/env bash
set -euo pipefail

# NoCrumbs Release Pipeline (fully automated)
# Usage: ./scripts/release.sh [version] [--minor] [--major] [--team-id <id>] [--password <keychain-profile>]
#
# Version is optional — defaults to patch bump (e.g. 0.4.1 → 0.4.2).
# Use --minor for minor bump (0.4.1 → 0.5.0) or --major for major bump (0.4.1 → 1.0.0).
# Or pass an explicit version: ./scripts/release.sh 1.0.0
#
# Secrets are loaded from scripts/.env.local (gitignored).
# See scripts/RUNBOOK.local.md for setup instructions.

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

# Read current version from Info.plist
CURRENT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
    "${PROJECT_DIR}/NoCrumbs/Resources/Info.plist")

# Parse semver components
IFS='.' read -r CUR_MAJOR CUR_MINOR CUR_PATCH <<< "$CURRENT_VERSION"

# Parse arguments
BUMP_TYPE="patch"
VERSION=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --major) BUMP_TYPE="major"; shift ;;
        --minor) BUMP_TYPE="minor"; shift ;;
        --patch) BUMP_TYPE="patch"; shift ;;
        --team-id) TEAM_ID="$2"; shift 2 ;;
        --password) KEYCHAIN_PROFILE="$2"; shift 2 ;;
        -*)  echo "Unknown option: $1"; exit 1 ;;
        *)
            # Positional arg = explicit version
            if [[ -z "$VERSION" ]]; then
                VERSION="$1"; shift
            else
                echo "Unknown argument: $1"; exit 1
            fi
            ;;
    esac
done

# Compute version if not explicitly provided
if [[ -z "$VERSION" ]]; then
    case "$BUMP_TYPE" in
        major) VERSION="$((CUR_MAJOR + 1)).0.0" ;;
        minor) VERSION="${CUR_MAJOR}.$((CUR_MINOR + 1)).0" ;;
        patch) VERSION="${CUR_MAJOR}.${CUR_MINOR}.$((CUR_PATCH + 1))" ;;
    esac
fi

echo "Current version: ${CURRENT_VERSION}"
echo "New version:     ${VERSION}"
echo ""

if [[ -z "$TEAM_ID" ]]; then
    echo "❌ TEAM_ID not set. Either:"
    echo "   1. Create scripts/.env.local with: NOCRUMBS_TEAM_ID=<your-team-id>"
    echo "   2. Pass --team-id <id>"
    exit 1
fi

# === Pre-flight checks ===
echo "→ Pre-flight checks..."

if [[ -n "$(git -C "$PROJECT_DIR" status --porcelain)" ]]; then
    echo "❌ Working tree is dirty. Commit or stash changes first."
    git -C "$PROJECT_DIR" status --short
    exit 1
fi

if git -C "$PROJECT_DIR" rev-parse "v${VERSION}" >/dev/null 2>&1; then
    echo "❌ Tag v${VERSION} already exists."
    exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
    echo "❌ GitHub CLI not authenticated. Run: gh auth login"
    exit 1
fi

echo "✓ Pre-flight checks passed"

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

# Step 1: Bump version in Info.plist
echo "→ Bumping Info.plist version to ${VERSION}..."
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" \
    "${PROJECT_DIR}/NoCrumbs/Resources/Info.plist"

# Increment build number (use date-based)
BUILD_NUMBER=$(date +%Y%m%d%H%M)
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" \
    "${PROJECT_DIR}/NoCrumbs/Resources/Info.plist"
echo "   Version: ${VERSION} (${BUILD_NUMBER})"

# Step 2: Bump CLI version
echo "→ Bumping CLI version to ${VERSION}..."
CLI_MAIN="${PROJECT_DIR}/CLI/Sources/nocrumbs/main.swift"
sed -i '' "s/^let version = \".*\"/let version = \"${VERSION}\"/" "$CLI_MAIN"
echo "✓ CLI version bumped"

# Step 2b: Bump local cask template
CASK_TEMPLATE="${PROJECT_DIR}/homebrew-tap/Casks/nocrumbs.rb"
if [[ -f "$CASK_TEMPLATE" ]]; then
    sed -i '' "s/version \".*\"/version \"${VERSION}\"/" "$CASK_TEMPLATE"
    echo "✓ Cask template version bumped"
fi

# Step 3: Commit version bumps
echo "→ Committing version bumps..."
git -C "$PROJECT_DIR" add \
    "NoCrumbs/Resources/Info.plist" \
    "CLI/Sources/nocrumbs/main.swift" \
    "homebrew-tap/Casks/nocrumbs.rb"
git -C "$PROJECT_DIR" commit -m "chore: bump version to ${VERSION}"
echo "✓ Version bump committed"

# Step 4: Clean build with Developer ID signing + hardened runtime
# The Xcode build phase "Build & Embed CLI" builds the CLI and copies it into
# NoCrumbs.app/Contents/Resources/nocrumbs automatically.
echo "→ Building Release configuration (app + embedded CLI)..."
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

# Verify CLI is embedded in app bundle
CLI_IN_BUNDLE="${APP_PATH}/Contents/Resources/nocrumbs"
if [[ ! -x "$CLI_IN_BUNDLE" ]]; then
    echo "❌ CLI binary not found in app bundle at ${CLI_IN_BUNDLE}"
    exit 1
fi
echo "✓ CLI embedded: ${CLI_IN_BUNDLE}"
"$CLI_IN_BUNDLE" --version

# Step 4b: Sign embedded CLI binary with Developer ID + hardened runtime
SIGN_ID="Developer ID Application: Gene Yoo (${TEAM_ID})"
echo "→ Signing embedded CLI binary..."
codesign --force --sign "$SIGN_ID" --timestamp --options runtime "$CLI_IN_BUNDLE"
echo "✓ CLI binary signed"

# Step 5: Re-sign Sparkle embedded binaries with Developer ID + timestamp
echo "→ Re-signing Sparkle framework binaries..."
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

# Step 6: Re-sign the main app (picks up re-signed framework)
echo "→ Re-signing app bundle..."
codesign --force --sign "$SIGN_ID" --timestamp --options runtime \
    --entitlements "${PROJECT_DIR}/NoCrumbs/Resources/NoCrumbs.entitlements" \
    "$APP_PATH"
echo "✓ App re-signed"

# Step 7: Verify code signing
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

# Step 8: Create zip for notarization
echo "→ Creating zip for notarization..."
ZIP_PATH="${BUILD_DIR}/${APP_NAME}-${VERSION}.zip"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
echo "✓ Zip created: ${ZIP_PATH}"

# Step 9: Notarize
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

# Step 10: Staple
echo "→ Stapling notarization ticket..."
xcrun stapler staple "$APP_PATH"
echo "✓ Stapled"

# Step 11: Re-zip after stapling (final distributable)
echo "→ Creating final distributable zip..."
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
ZIP_SIZE=$(stat -f%z "$ZIP_PATH")
echo "✓ Final zip: ${ZIP_PATH} ($(( ZIP_SIZE / 1048576 )) MB)"

# Step 12: Sign zip with Sparkle EdDSA
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

# Step 13: Generate appcast
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

# Step 14: Copy appcast to docs-site for GitHub Pages
if [[ -f "${APPCAST_DIR}/appcast.xml" ]]; then
    echo "→ Copying appcast to docs-site..."
    cp "${APPCAST_DIR}/appcast.xml" "${PROJECT_DIR}/docs-site/static/appcast.xml"
    echo "✓ Appcast copied to docs-site/static/appcast.xml"
fi

# Step 15: Rebase on remote (in case PRs merged during build), tag, and push
echo "→ Rebasing on remote, tagging v${VERSION}, and pushing..."
# Stash appcast changes before rebase (Step 14 creates unstaged changes)
git -C "$PROJECT_DIR" stash --include-untracked
git -C "$PROJECT_DIR" pull --rebase origin main
git -C "$PROJECT_DIR" stash pop || true
git -C "$PROJECT_DIR" tag "v${VERSION}"
git -C "$PROJECT_DIR" push origin main --tags
echo "✓ Tag v${VERSION} pushed"

# Step 16: Create GitHub Release
echo "→ Creating GitHub Release v${VERSION}..."
gh release create "v${VERSION}" "$ZIP_PATH" \
    --repo geneyoo/nocrumbs \
    --title "v${VERSION}" \
    --generate-notes
echo "✓ GitHub Release v${VERSION} created"

# Step 17: Commit and push appcast (triggers GitHub Pages deploy)
if [[ -f "${PROJECT_DIR}/docs-site/static/appcast.xml" ]]; then
    echo "→ Committing appcast and pushing (triggers Pages deploy)..."
    git -C "$PROJECT_DIR" add "docs-site/static/appcast.xml"
    if git -C "$PROJECT_DIR" diff --cached --quiet; then
        echo "   Appcast unchanged, skipping commit"
    else
        git -C "$PROJECT_DIR" commit -m "chore: update appcast for v${VERSION}"
        git -C "$PROJECT_DIR" push origin main
        echo "✓ Appcast committed and pushed — GitHub Pages will deploy"
    fi
fi

# Step 18: Update Homebrew tap (cask)
echo "→ Updating Homebrew cask..."
TAP_REPO="geneyoo/homebrew-tap"
ZIP_URL="https://github.com/geneyoo/nocrumbs/releases/download/v${VERSION}/NoCrumbs-${VERSION}.zip"
ZIP_SHA=$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')

if [[ -n "$ZIP_SHA" ]]; then
    TAP_DIR=$(mktemp -d)
    gh repo clone "$TAP_REPO" "$TAP_DIR" -- --depth 1 2>/dev/null
    mkdir -p "${TAP_DIR}/Casks"
    cat > "${TAP_DIR}/Casks/nocrumbs.rb" <<CASK_EOF
cask "nocrumbs" do
  version "${VERSION}"
  sha256 "${ZIP_SHA}"

  url "https://github.com/geneyoo/nocrumbs/releases/download/v#{version}/NoCrumbs-#{version}.zip"
  name "NoCrumbs"
  desc "Catch every crumb your agent leaves behind"
  homepage "https://nocrumbs.ai"

  depends_on macos: ">= :sonoma"

  app "NoCrumbs.app"
  binary "#{appdir}/NoCrumbs.app/Contents/Resources/nocrumbs"

  zap trash: [
    "~/Library/Application Support/NoCrumbs",
  ]
end
CASK_EOF
    # Remove old formula if it exists
    rm -f "${TAP_DIR}/Formula/nocrumbs.rb"
    git -C "$TAP_DIR" add -A
    git -C "$TAP_DIR" commit -m "chore: bump nocrumbs cask to v${VERSION}"
    git -C "$TAP_DIR" push origin main
    echo "✓ Homebrew cask updated to v${VERSION}"
    rm -rf "$TAP_DIR"
else
    echo "⚠️  Failed to compute SHA256 — update Homebrew cask manually"
fi

# Summary
echo ""
echo "=== Release ${VERSION} Complete ==="
echo ""
echo "Artifacts:"
echo "  Zip:     ${ZIP_PATH}"
echo "  Appcast: ${APPCAST_DIR}/appcast.xml"
echo "  Release: https://github.com/geneyoo/nocrumbs/releases/tag/v${VERSION}"
echo "  Homebrew: brew install --cask geneyoo/tap/nocrumbs"
echo ""
echo "Appcast will be live at https://nocrumbs.ai/appcast.xml after Pages deploys."
