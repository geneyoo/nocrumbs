#!/usr/bin/env bash
set -euo pipefail

# Sync all version sources from the single VERSION file.
# Called by: Xcode build phase, release script, or manually.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION_FILE="${PROJECT_DIR}/VERSION"

if [[ ! -f "$VERSION_FILE" ]]; then
    echo "error: VERSION file not found at $VERSION_FILE"
    exit 1
fi

VERSION=$(tr -d '[:space:]' < "$VERSION_FILE")

if [[ -z "$VERSION" ]]; then
    echo "error: VERSION file is empty"
    exit 1
fi

echo "Syncing version: ${VERSION}"

# 1. Info.plist
PLIST="${PROJECT_DIR}/NoCrumbs/Resources/Info.plist"
if [[ -f "$PLIST" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "$PLIST"
    echo "  ✓ Info.plist"
fi

# 2. CLI Version.swift
CLI_VERSION="${PROJECT_DIR}/CLI/Sources/nocrumbs/Version.swift"
cat > "$CLI_VERSION" <<EOF
// Auto-generated from VERSION file — do not edit manually.
// Updated by: Xcode build phase, release script, or \`scripts/sync-version.sh\`
let version = "${VERSION}"
EOF
echo "  ✓ CLI Version.swift"

# 3. Homebrew cask template
CASK="${PROJECT_DIR}/homebrew-tap/Casks/nocrumbs.rb"
if [[ -f "$CASK" ]]; then
    sed -i '' "s/version \".*\"/version \"${VERSION}\"/" "$CASK"
    echo "  ✓ Cask template"
fi
