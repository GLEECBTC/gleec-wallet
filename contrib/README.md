# Contrib Scripts

This directory contains utility scripts for building, packaging, and testing the Gleec Wallet application.

## Scripts Overview

### `make-dmg.sh`

Creates a professional DMG installer for macOS applications.

**Purpose:** Builds a disk image (.dmg) file with proper layout for distributing macOS applications.

**Features:**

- Creates a disk image with the application bundle
- Adds a shortcut to the Applications folder
- Supports custom background images
- Configures proper Finder window layout and icon positioning
- Compresses the final output

**Usage:**

```bash
# Use default app path
./make-dmg.sh

# Or specify custom parameters
APP="build/.../Gleec DEX.app" \
VOL="Gleec DEX" \
OUT="dist/GleecDEX.dmg" \
BG="assets/dmg_background.png" \
./make-dmg.sh
```

**Default Parameters:**

- `APP`: `build/macos/Build/Products/Release-production/Gleec DEX.app`
- `VOL`: `Gleec DEX`
- `OUT`: `dist/GleecDEX.dmg`
- `BG`: (optional background image)
- `ICON_SIZE`: `128`
- `WIN_W`: `530` (Finder window width)
- `WIN_H`: `400` (Finder window height)

**Requirements:** macOS, hdiutil, osascript, ditto

---

### `test-sign-timestamp.sh`

Checks code signing and timestamping for macOS applications.

**Purpose:** Verifies that all executable Mach-O files in the app bundle are properly signed and timestamped.

**Features:**

- Scans all executable files in the app bundle
- Checks for valid code signatures
- Verifies timestamping (Apple's timestamp authority)
- Provides colored output for easy reading
- Reports missing timestamps

**Usage:**

```bash
# Use default app path
./test-sign-timestamp.sh

# Or specify custom app path
./test-sign-timestamp.sh "path/to/your/app.app"
```

**Default App Path:** `build/macos/Build/Products/Release-production/Gleec DEX.app`

**Requirements:** macOS, codesign utility

## Release Build and Notarization Process for macOS (Non-App Store Distribution)

To build and notarize the macOS app for release (for distribution outside the Mac App Store), follow these steps.  
Note: The `--flavor production` flag is mandatory in the build command to ensure correct provisioning for signing with a Developer ID Application certificate and for proper notarization/distribution outside the App Store.

```bash
# 1. Clean the project and fetch dependencies
flutter clean
flutter pub get --enforce-lockfile
pushd macos; pod deintegrate; pod install; popd    # Generating Pods project

# 2. Fetch all required artifacts (this runs komodo_wallet_build_transformer)
flutter build web --no-pub -v

# 3. Build the macOS release application (ensure --flavor production is present)
flutter build macos --no-pub --release -v \
  --dart-define=COMMIT_HASH=<hash> \
  --dart-define=FEEDBACK_API_KEY=<key> \
  --dart-define=FEEDBACK_PRODUCTION_URL=<url> \
  --dart-define=TRELLO_BOARD_ID=<id> \
  --dart-define=TRELLO_LIST_ID=<id> \
  --dart-define=MATOMO_URL=<url> \
  --dart-define=MATOMO_SITE_ID=<id> \
  --flavor production
```

Replace the `<...>` placeholders above with your actual values.

To view app entitlements used in the resulting .app:

```bash
codesign -d --entitlements :- "build/macos/Build/Products/Release-production/Gleec DEX.app" | plutil -p -
```

Package the application bundle as a ZIP archive (required by notary service):

```bash
APP="build/macos/Build/Products/Release-production/Gleec DEX.app"
ZIP="GleecDEX.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
```

Submit the ZIP archive to Apple Notary Service:

```bash
xcrun notarytool submit "$ZIP" --keychain-profile "AC_NOTARY" --wait
```

Check notarization status for a specific request:

```bash
xcrun notarytool info <REQUEST_ID> \
  --apple-id "<apple_id_email>" \
  --team-id "<TEAM_ID>" \
  --password "<app-specific-password>"
```

Download notarization log:

```bash
xcrun notarytool log <REQUEST_ID> --keychain-profile AC_NOTARY > notarization_errors.json
```

If there were no errors and the submission status was `Accepted`, you can proceed with the following steps to staple and validate the app:

```bash
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute -vv "$APP"   # now the status should be accepted
```
