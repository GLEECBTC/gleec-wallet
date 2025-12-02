# GLEEC Branding Asset Issues Analysis

## Executive Summary

After comparing the modified branding assets with the original files and the GLEEC reference repositories, several critical issues have been identified:

| Platform | Status | Issue |
|----------|--------|-------|
| **iOS** | ✅ Correct | Icons match GLEEC mobile repo exactly |
| **Android** | ✅ **FIXED** | Correct RGBA assets from GLEEC mobile repo applied |
| **macOS** | ℹ️ Design Change | New solid-background design (intentional) |
| **Windows** | ✅ Correct | Icon matches desktop repo |
| **Web** | ⚠️ Minor | Icons work but lack transparency |
| **Linux** | ✅ Added | New icon added |

---

## Critical Issues Identified

### 1. Android Icons - CRITICAL ❌

**Problem**: All Android launcher icons have incorrect format and design:

| Issue | Local Files | GLEEC Mobile Repo |
|-------|-------------|-------------------|
| **Format** | RGB (no alpha) | RGBA (with alpha) |
| **ic_launcher_round.png** | Square shape | Circular with transparent corners |
| **launcher_icon_foreground.png** | 432x432 with dark bg | 192x192 with transparent bg |
| **Adaptive icon** | Broken | Correctly configured |

**Visual Comparison**:

**Local ic_launcher_round.png (WRONG)**:
- Square icon with solid dark background
- No transparency
- Will display incorrectly on devices with circular icon masks

**GLEEC repo ic_launcher_round.png (CORRECT)**:
- Circular icon with transparent corners
- RGBA format
- Proper adaptive icon support

**Local launcher_icon_foreground.png (WRONG)**:
- 432x432 pixels (oversized)
- Contains dark background baked into the image
- Will cause double-background effect in adaptive icons

**GLEEC repo launcher_icon_foreground.png (CORRECT)**:
- 192x192 pixels (correct for xxxhdpi)
- Transparent background with rounded rectangle containing logo
- Works properly with adaptive icon background layer

**File Size Comparison** (xxxhdpi):

| File | Local Size | GLEEC Repo Size |
|------|------------|-----------------|
| ic_launcher_round.png | 7,232 bytes | 11,387 bytes |
| launcher_icon_foreground.png | 18,037 bytes | 5,550 bytes |

### 2. macOS Icons - ℹ️ Design Change (Intentional)

**Note**: This is an intentional design change, not a bug.

| Aspect | Original (Komodo) | Current (GLEEC) |
|--------|-------------------|-----------------|
| **Background** | Transparent | Solid dark (#202337) |
| **Format** | RGBA | RGB |
| **Design Philosophy** | Logo floats, OS applies shape | Full icon with background |

**Original Komodo Icon**: Blue/purple gradient infinity symbol on transparent background. macOS would apply its own rounded rectangle shape.

**New GLEEC Icon**: Cyan "G" logo on solid dark background (matching iOS). macOS Big Sur+ will apply its own rounded corner mask over the solid background.

**This is acceptable** for modern macOS (Big Sur and later) which applies consistent rounded-rectangle masks to all app icons regardless of their original transparency.

### 3. Web Icons - Minor Issues

Web icons are functional but could benefit from RGBA format for better display on various backgrounds.

---

## Reference Repositories

### GLEEC Mobile (for mobile-specific assets)
- **Repo**: `GLEECBTC/komodo-wallet-mobile`
- **Branch**: `white-label/dev/gleecdex`
- **Key paths**:
  - `android/app/src/main/res/mipmap-*/` - Android icons (RGBA with proper adaptive icon support)
  - `ios/Runner/Assets.xcassets/AppIcon.appiconset/` - iOS icons (match local)
  - `assets/branding/` - Source branding assets

### GleecDEX Desktop (for desktop-specific assets)
- **Repo**: `GLEECBTC/GleecDEX-Desktop`
- **Key paths**:
  - `assets/logo/dex-logo.ico` - Windows icon (177,289 bytes - matches local)
  - `assets/logo/dex-logo.icns` - macOS icon set (68,226 bytes)
  - `assets/logo/dex-logo*.png` - Various PNG sizes

**Note**: The GleecDEX Desktop repo contains a **different logo design** (purple "G" with dollar marks) which is the GleecDEX brand, not the GLEEC Wallet brand. The current cyan "G" logo is the correct GLEEC Wallet branding.

---

## Applied Fixes

### ✅ Fix 1: Android Icons - COMPLETED

The correct assets were copied from the GLEEC mobile repo (`GLEECBTC/komodo-wallet-mobile`, branch `white-label/dev/gleecdex`):

- `ic_launcher_round.png` - All densities (hdpi, mdpi, xhdpi, xxhdpi, xxxhdpi)
- `launcher_icon_foreground.png` - All densities

These files now have:
- ✅ RGBA format with proper transparency
- ✅ Correct circular shape for round icons
- ✅ Proper sizes for adaptive icons (48px to 192px depending on density)

### ℹ️ macOS Icons - No Action Required

The macOS icons use a different design philosophy than the original Komodo icons:
- **Original**: Transparent background (logo floats)
- **Current**: Solid dark background (full icon)

This is acceptable for macOS Big Sur and later, which applies uniform rounded-rectangle masks to all app icons.

### ✅ Verify Android Adaptive Icon Configuration

Ensure `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml` correctly references the foreground:

```xml
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/launcher_icon_foreground"/>
</adaptive-icon>
```

And ensure `ic_launcher_background` is set to `#202337`.

---

## Files Updated

### ✅ Android (FIXED - copied from GLEEC mobile repo)
```
android/app/src/main/res/mipmap-hdpi/ic_launcher_round.png      ✅ RGBA, 72x72
android/app/src/main/res/mipmap-hdpi/launcher_icon_foreground.png     ✅ RGBA, 72x72
android/app/src/main/res/mipmap-mdpi/ic_launcher_round.png      ✅ RGBA, 48x48
android/app/src/main/res/mipmap-mdpi/launcher_icon_foreground.png     ✅ RGBA, 48x48
android/app/src/main/res/mipmap-xhdpi/ic_launcher_round.png     ✅ RGBA, 96x96
android/app/src/main/res/mipmap-xhdpi/launcher_icon_foreground.png    ✅ RGBA, 96x96
android/app/src/main/res/mipmap-xxhdpi/ic_launcher_round.png    ✅ RGBA, 144x144
android/app/src/main/res/mipmap-xxhdpi/launcher_icon_foreground.png   ✅ RGBA, 144x144
android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_round.png   ✅ RGBA, 192x192
android/app/src/main/res/mipmap-xxxhdpi/launcher_icon_foreground.png  ✅ RGBA, 192x192
```

### ℹ️ macOS (No change required - design intentional)
The solid-background design is acceptable for macOS Big Sur+.

---

## Verification Checklist

After applying fixes, verify:

- [x] Android: `ic_launcher_round.png` files have RGBA format and circular shape
- [x] Android: `launcher_icon_foreground.png` files have RGBA format and proper size
- [ ] Android: Adaptive icons display correctly in emulator (test circular and squircle masks)
- [x] macOS: Solid-background design acceptable for Big Sur+
- [x] All icons visually match the GLEEC Wallet brand (cyan "G" on dark background)

---

*Analysis performed: December 2024*
*Reference repos checked: GLEECBTC/komodo-wallet-mobile, GLEECBTC/GleecDEX-Desktop*

