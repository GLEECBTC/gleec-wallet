# GLEEC Wallet Branding Migration Summary

This document summarizes the GLEEC branding migration work completed and outlines the remaining actions required for a full cross-platform release.

---

## Migration Status Overview

| Category                 | Status      |
| ------------------------ | ----------- |
| App Configuration        | ✅ Complete |
| Theme Colors             | ✅ Complete |
| Android Icons            | ✅ Complete |
| iOS Icons                | ✅ Complete |
| macOS Icons              | ✅ Complete |
| Windows Icons & Metadata | ✅ Complete |
| Linux Icons & Metadata   | ✅ Complete |
| Web Icons & Metadata     | ✅ Complete |
| Flutter Assets           | ✅ Complete |
| Bundle/App Identifiers   | ✅ Complete |

---

## Completed Changes

### 1. App Configuration (`lib/app_config/app_config.dart`)

| Setting                    | New Value                                               |
| -------------------------- | ------------------------------------------------------- |
| `appTitle`                 | `GLEEC Wallet \| Non-Custodial Multi-Coin Wallet & DEX` |
| `appShortTitle`            | `GLEEC Wallet`                                          |
| `appFolder`                | `GleecWallet`                                           |
| `discordSupportChannelUrl` | `https://discord.gg/gleec`                              |
| `discordInviteUrl`         | `https://discord.gg/gleec`                              |
| Priority coin              | `GLEEC` added with priority 1000                        |
| Default enabled coins      | `GLEEC`, `KMD`, `BTC-segwit`                            |

### 2. Theme Colors (GLEEC Brand Palette)

| Color                 | Hex Value | Usage                              |
| --------------------- | --------- | ---------------------------------- |
| Primary Blue          | `#4986EA` | Primary actions, links, highlights |
| Secondary Purple-Blue | `#5A68E6` | Secondary elements, gradients      |
| Background            | `#202337` | Main dark background               |
| Secondary Background  | `#24273D` | Cards, elevated surfaces           |
| Deep Background       | `#171A2C` | Deepest background layer           |
| Success/OK            | `#00C058` | Positive states, buy actions       |
| Error/Warning         | `#E52167` | Errors, sell actions, warnings     |

Files updated:

- `app_theme/lib/src/new_theme/new_theme_dark.dart`
- `app_theme/lib/src/new_theme/new_theme_light.dart`
- `app_theme/lib/src/dark/theme_custom_dark.dart`

### 3. Platform Assets Updated

#### Android (`android/`)

- All `mipmap-*/ic_launcher.png` icons
- All `mipmap-*/ic_launcher_round.png` icons
- All `mipmap-*/launcher_icon_foreground.png` icons
- `res/values/colors.xml` - Updated with GLEEC colors
- `res/values/ic_launcher_background.xml` - Background color `#202337`

#### iOS (`ios/`)

- All `Assets.xcassets/AppIcon.appiconset/Icon-App-*.png` icons (16 sizes)
- `Assets.xcassets/AppLogo.imageset/` images

#### macOS (`macos/`)

- All `Assets.xcassets/AppIcon.appiconset/app_icon_*.png` icons (7 sizes)
- `Runner/Configs/AppInfo.xcconfig`:
  - `PRODUCT_NAME` = `GLEEC Wallet`
  - `PRODUCT_BUNDLE_IDENTIFIER` = `com.gleec.wallet`
  - `PRODUCT_COPYRIGHT` = `Copyright © 2024 GLEEC. All rights reserved.`

#### Windows (`windows/`)

- `runner/resources/app_icon.ico` - Replaced with GLEEC icon
- `runner/Runner.rc`:
  - `CompanyName` = `GLEEC`
  - `FileDescription` = `GLEEC Wallet`
  - `InternalName` = `gleecwallet`
  - `OriginalFilename` = `gleecwallet.exe`
  - `ProductName` = `GLEEC Wallet`
  - `LegalCopyright` = `Copyright (C) 2024 GLEEC. All rights reserved.`

#### Linux (`linux/`)

- Renamed `KomodoWallet.png` → `GleecWallet.png`
- Renamed `KomodoWallet.desktop` → `GleecWallet.desktop`
- `CMakeLists.txt`:
  - `BINARY_NAME` = `GleecWallet`
  - `APPLICATION_ID` = `com.gleec.GleecWallet`
- `GleecWallet.desktop`:
  - `Name` = `GLEEC Wallet`
  - `Exec` = `./GleecWallet`
  - `Icon` = `./GleecWallet.png`

#### Web (`web/`)

- All favicon files (`favicon.ico`, `favicon.png`, `favicon-16x16.png`, `favicon-32x32.png`)
- `icons/android-chrome-*.png`
- `icons/apple-touch-icon.png`
- `icons/mstile-150x150.png`
- `icons/logo_icon.webp`
- `manifest.json`:
  - `name` = `GLEEC Wallet`
  - `short_name` = `GLEEC Wallet`
  - `background_color` = `#202337`
  - `theme_color` = `#4986EA`
- `index.html`:
  - Page title and meta descriptions
  - Open Graph and Twitter Card metadata
  - Schema.org structured data
  - Theme colors and background colors

#### Flutter Assets (`assets/`)

- `app_icon/logo_icon.webp`
- `logo/logo.svg`
- `logo/logo_dark.svg`
- `logo/dark_theme.png`
- `logo/light_theme.png`
- `logo/update_logo.png`

---

## Current Bundle/App Identifier Status ✅

### Identifier Comparison Table

| Platform    | File                           | Value                   | Status     |
| ----------- | ------------------------------ | ----------------------- | ---------- |
| **Android** | `build.gradle` (namespace)     | `com.gleec.gleecdex`    | ✅ Updated |
| **Android** | `build.gradle` (applicationId) | `com.gleec.gleecdex`    | ✅ Updated |
| **iOS**     | `project.pbxproj`              | `com.gleec.gleecdex`    | ✅ Updated |
| **iOS**     | `Info.plist` (CFBundleName)    | `GLEEC Wallet`          | ✅ Updated |
| **macOS**   | `AppInfo.xcconfig`             | `com.gleec.gleecdex`    | ✅ Updated |
| **macOS**   | `project.pbxproj`              | `com.gleec.gleecdex`    | ✅ Updated |
| **Linux**   | `CMakeLists.txt`               | `com.gleec.GleecWallet` | ✅         |
| **Windows** | `Runner.rc`                    | `GLEEC`                 | ✅         |

**Note:** All bundle IDs have been unified to `com.gleec.gleecdex` to match the existing Play Store and App Store apps.

---

## Required Follow-Up Actions

### ✅ Bundle Identifier Updates - COMPLETED

All bundle identifiers have been updated to `com.gleec.gleecdex` to match the existing GLEEC apps on Play Store and App Store:

| File                                     | Old Value                      | New Value               |
| ---------------------------------------- | ------------------------------ | ----------------------- |
| `android/app/build.gradle`               | `com.komodoplatform.atomicdex` | ✅ `com.gleec.gleecdex` |
| `ios/Runner.xcodeproj/project.pbxproj`   | `com.komodo.wallet`            | ✅ `com.gleec.gleecdex` |
| `ios/Runner/Info.plist`                  | `Komodo Wallet`                | ✅ `GLEEC Wallet`       |
| `macos/Runner.xcodeproj/project.pbxproj` | `com.komodo.wallet`            | ✅ `com.gleec.gleecdex` |
| `macos/Runner/Configs/AppInfo.xcconfig`  | `com.gleec.wallet`             | ✅ `com.gleec.gleecdex` |

---

### ✅ Found Contact Information (Updated)

The following official GLEEC contact information was found and applied:

| Item               | Value                       | Source                                                           |
| ------------------ | --------------------------- | ---------------------------------------------------------------- |
| **Website**        | `https://www.gleec.com`     | Official website                                                 |
| **Web Wallet URL** | `https://dex.gleec.com/dex` | User provided                                                    |
| **Twitter/X**      | `@GleecOfficial`            | https://x.com/GleecOfficial                                      |
| **Instagram**      | `@gleecofficial`            | https://www.instagram.com/gleecofficial/                         |
| **LinkedIn**       | `/company/gleec/`           | https://www.linkedin.com/company/gleec/                          |
| **Email**          | `info@gleec.com`            | Contact page                                                     |
| **Play Store**     | `com.gleec.gleecdex`        | https://play.google.com/store/apps/details?id=com.gleec.gleecdex |

**Note:** GLEEC does not appear to have a public Discord server. The support URLs have been updated to point to the contact page and email.

#### iOS App Store (Verified)

| Field                | Value                                                        |
| -------------------- | ------------------------------------------------------------ |
| **App Name**         | GleecDEX wallet                                              |
| **App Store ID**     | `1563795528`                                                 |
| **App Store URL**    | `https://apps.apple.com/us/app/gleecdex-wallet/id1563795528` |
| **Developer/Seller** | Gleec-BTC OU                                                 |
| **Legal Entity**     | Gleec-BTC OU (Estonian company)                              |

#### All Bundle IDs Updated ✅

iOS Bundle ID has been set to `com.gleec.gleecdex` matching the App Store app.

#### ✅ Completed Additional Items

| Item            | Value                                                        |
| --------------- | ------------------------------------------------------------ |
| Thumbnail Image | `web/thumbnail.jpg` (1200x630) - Created with GLEEC branding |

---

### 🟡 Firebase Configuration

If Firebase services are to be used:

1. Create new Firebase project for GLEEC Wallet
2. Register apps with new bundle identifiers:
   - Android: `com.gleec.gleecdex`
   - iOS: `com.gleec.gleecdex`
   - macOS: `com.gleec.gleecdex`
   - Web: Configure with GLEEC domain
3. Download and replace configuration files:
   - `android/app/google-services.json`
   - `ios/Runner/GoogleService-Info.plist`
   - `macos/Runner/GoogleService-Info.plist`
   - `lib/firebase_options.dart`

---

### 🟡 Code Signing & Provisioning

#### iOS/macOS

- Create new App IDs in Apple Developer Portal for `com.gleec.gleecdex`
- Generate new provisioning profiles
- Update Xcode signing settings

#### Android

- Create new keystore for GLEEC Wallet
- Configure signing in `android/app/build.gradle`
- Register new app in Google Play Console

#### Windows

- Obtain code signing certificate for GLEEC
- Configure signing in build process

#### macOS

- Notarization with new bundle ID
- Update entitlements if needed

---

### 🟢 Optional Improvements

#### pubspec.yaml Package Name

```yaml
# Current:
name: web_dex

# Consider changing to:
name: gleec_wallet
```

Note: This requires updating all import statements throughout the codebase.

#### Web Thumbnail

Create and add `web/thumbnail.jpg` with GLEEC branding for social media previews.

---

## Important Warnings

### ⚠️ App Store Impact

Changing bundle identifiers will result in:

- **New app listings** on App Store and Play Store
- Users must download a new app (cannot update existing Komodo Wallet)
- Review process required for new apps
- Existing ratings/reviews will not transfer

### ⚠️ User Data Migration

- Keychain/Secure Storage data is tied to bundle ID
- Users may need to re-enter credentials or restore wallets
- Consider implementing a data migration guide for users

### ⚠️ Deep Links & URL Schemes

If using custom URL schemes or universal links, these must be updated:

- iOS: Update Associated Domains
- Android: Update intent filters in `AndroidManifest.xml`

---

## Verification Checklist

Before release, verify:

- [x] All bundle IDs updated to `com.gleec.gleecdex`
- [ ] App displays "GLEEC Wallet" on all platforms
- [ ] Icons display correctly on all platforms
- [ ] Theme colors match GLEEC brand guidelines
- [ ] Firebase configured (if used)
- [ ] Code signing configured for all platforms
- [ ] Placeholder URLs replaced with official GLEEC URLs
- [x] Web thumbnail image created
- [ ] App store listings prepared
- [ ] User migration documentation prepared

---

## File Quick Reference

Files modified during this migration:

```
lib/app_config/app_config.dart
app_theme/lib/src/new_theme/new_theme_dark.dart
app_theme/lib/src/new_theme/new_theme_light.dart
app_theme/lib/src/dark/theme_custom_dark.dart
android/app/src/main/res/values/colors.xml
android/app/src/main/res/values/ic_launcher_background.xml
android/app/src/main/res/mipmap-*/ic_launcher.png
android/app/src/main/res/mipmap-*/ic_launcher_round.png
android/app/src/main/res/mipmap-*/launcher_icon_foreground.png
ios/Runner/Assets.xcassets/AppIcon.appiconset/*
ios/Runner/Assets.xcassets/AppLogo.imageset/*
macos/Runner/Assets.xcassets/AppIcon.appiconset/*
macos/Runner/Configs/AppInfo.xcconfig
windows/runner/resources/app_icon.ico
windows/runner/Runner.rc
linux/CMakeLists.txt
linux/GleecWallet.desktop
linux/GleecWallet.png
web/favicon*.png
web/icons/*
web/manifest.json
web/index.html
assets/app_icon/logo_icon.webp
assets/logo/logo.svg
assets/logo/logo_dark.svg
assets/logo/dark_theme.png
assets/logo/light_theme.png
assets/logo/update_logo.png
```

Files updated for bundle IDs:

```
android/app/build.gradle                 # ✅ Updated to com.gleec.gleecdex
ios/Runner.xcodeproj/project.pbxproj     # ✅ Updated to com.gleec.gleecdex
ios/Runner/Info.plist                    # ✅ CFBundleName = GLEEC Wallet
macos/Runner.xcodeproj/project.pbxproj   # ✅ Updated to com.gleec.gleecdex
macos/Runner/Configs/AppInfo.xcconfig    # ✅ Updated to com.gleec.gleecdex
```

---

_Document generated: December 2024_
_Migration performed on branch: `chore/gleec-migration`_
