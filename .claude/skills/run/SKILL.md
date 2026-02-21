---
name: run
description: Build and run the NoCrumbs Mac app. Use when the user says "run", "build and run", "launch", or uses /run.
version: 1.0.0
---

# Run NoCrumbs

Build and run the NoCrumbs macOS menu bar app.

## Project Details
- Bundle ID: `com.geneyoo.nocrumbs`
- Development Team: `H32EKFDL92`
- Scheme: `NoCrumbs`
- Project: `NoCrumbs.xcodeproj`
- Build output: `build/` (local to project)

## Instructions

### 1. Parse Arguments
- `clean` → clean build
- `release` → Release configuration
- `signed` → build with code signing
- No args → incremental Debug build, no signing

### 2. Build

```bash
# Incremental build (default — fast)
xcodebuild -project NoCrumbs.xcodeproj \
  -scheme NoCrumbs \
  -configuration Debug \
  -sdk macosx \
  -derivedDataPath build \
  build \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO \
  | tail -20

# Clean build (if args contain "clean")
# Add "clean" before "build" in the xcodebuild command

# Signed build (if args contain "signed")
# Replace CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO with:
# CODE_SIGN_IDENTITY="Apple Development" DEVELOPMENT_TEAM=H32EKFDL92
```

### 3. Kill Old Instance and Launch

```bash
# Kill any running instance
pkill -x NoCrumbs 2>/dev/null || true

# Launch fresh build
open build/Build/Products/Debug/NoCrumbs.app
```

### 4. Error Handling
- **Build fails**: Show last 30 lines of build output with errors
- **App not found**: Check if build succeeded, show path

### 5. Success Output
```
✅ NoCrumbs running
🔧 Debug | unsigned
```

## Examples
```
/run                # Incremental debug build, launch
/run clean          # Clean debug build, launch
/run signed         # Incremental signed build, launch
/run clean signed   # Clean signed build, launch
```
