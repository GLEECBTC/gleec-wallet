#!/usr/bin/env bash
# make_dmg.sh — Build DMG with layout «App ⇢ Applications»
# 
# This script creates a professional DMG installer for macOS applications.
# It creates a disk image with:
# - The application bundle
# - A shortcut to Applications folder
# - Custom background image (optional)
# - Proper Finder window layout and icon positioning
# - Compressed final output
#
# Requires: macOS, hdiutil, osascript, ditto.

set -euo pipefail

# ------------------------ PARAMETERS ------------------------
# Default app path
DEFAULT_APP="build/macos/Build/Products/Release-production/Gleec DEX.app"

APP="${APP:-$DEFAULT_APP}"            # Path to .app (uses default if not specified)
VOL="${VOL:-Gleec DEX}"          # Volume/window name for DMG
OUT="${OUT:-dist/GleecDEX.dmg}"  # Path to output .dmg
BG="${BG:-}"                         # Path to PNG background (optional)
ICON_SIZE="${ICON_SIZE:-128}"        # Icon size
WIN_W="${WIN_W:-530}"                # Finder window width in DMG
WIN_H="${WIN_H:-400}"                # Finder window height in DMG
APP_X="${APP_X:-120}"                # .app icon position (x)
APP_Y="${APP_Y:-200}"                # .app icon position (y)
APPS_X="${APPS_X:-400}"              # Applications shortcut position (x)
APPS_Y="${APPS_Y:-200}"              # Applications shortcut position (y)

usage() {
  cat <<EOF
Usage:
  # Use default app path
  ./make_dmg.sh
  
  # Or specify custom parameters
  APP="build/.../Gleec DEX.app" \\
  VOL="Gleec DEX" \\
  OUT="dist/GleecDEX.dmg" \\
  BG="assets/dmg_background.png" \\
  ./make_dmg.sh
  
Default APP path: $DEFAULT_APP
EOF
}
[[ ! -d "${APP}" ]] && { echo >&2 "ERROR: .app not found: ${APP}"; exit 1; }

APP_BASENAME="$(basename "${APP}")"
OUT_DIR="$(dirname "${OUT}")"
mkdir -p "${OUT_DIR}"

# Work in local tmp inside project — fewer TCC issues
TMPROOT="${TMPROOT:-$PWD/.dmg_tmp}"
mkdir -p "$TMPROOT"
TMPDIR="$(mktemp -d "$TMPROOT/tmp.XXXXXXXX")"
STAGING="${TMPDIR}/staging"
mkdir -p "${STAGING}"

cleanup() {
  set +e
  if [[ -n "${MOUNT_POINT:-}" && -d "${MOUNT_POINT:-}" ]]; then
    hdiutil detach "${MOUNT_POINT}" -quiet || true
  fi
  rm -rf "${TMPDIR}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "==> Preparing staging"
cp -R "${APP}" "${STAGING}/"
ln -s /Applications "${STAGING}/Applications"

if [[ -n "${BG}" ]]; then
  echo "==> Adding background ${BG}"
  mkdir -p "${STAGING}/.background"
  cp "${BG}" "${STAGING}/.background/background.png"
  chflags hidden "${STAGING}/.background" || true
fi

# --------- IMAGE SIZE CALCULATION (with margin) ----------
echo "==> Estimating image size"
# Staging size in kilobytes
SIZE_KB=$(du -sk "${STAGING}" | awk '{print $1}')
# Add ~30% margin + minimum 20 MB
HEADROOM_KB=$(( SIZE_KB / 3 ))
[[ ${HEADROOM_KB} -lt 20480 ]] && HEADROOM_KB=20480
TOTAL_KB=$(( SIZE_KB + HEADROOM_KB ))
# Round to megabytes
TOTAL_MB=$(( (TOTAL_KB + 1023) / 1024 ))
echo "    Estimated size: ${TOTAL_MB} MiB"

TMP_DMG="${TMPDIR}/tmp.dmg"
FINAL_DMG="${OUT}"

echo "==> Creating empty RW DMG (${TOTAL_MB} MiB)"
hdiutil create -verbose \
  -size "${TOTAL_MB}m" \
  -fs HFS+J -volname "${VOL}" \
  "${TMP_DMG}"

# if volume with same name is mounted — unmount it
if [[ -d "/Volumes/${VOL}" ]]; then
  hdiutil detach "/Volumes/${VOL}" -force -quiet || true
fi

echo "==> Mounting DMG"
MOUNT_POINT="${TMPDIR}/mnt"
mkdir -p "${MOUNT_POINT}"

# Mount directly to our directory
if ! hdiutil attach "${TMP_DMG}" \
      -readwrite -noverify -noautoopen \
      -mountpoint "${MOUNT_POINT}" >/dev/null; then
  echo >&2 "ERROR: failed to mount DMG (attach returned error)"
  exit 1
fi

# Check that it's actually mounted
if [[ ! -d "${MOUNT_POINT}" || ! -e "${MOUNT_POINT}/." ]]; then
  echo >&2 "ERROR: failed to mount DMG (mountpoint not accessible)"
  exit 1
fi
echo "    Mounted at: ${MOUNT_POINT}"

# --------- CONTENT COPYING (DITTO) ----------
echo "==> Copying content to volume (ditto)"
# Application
ditto "${STAGING}/${APP_BASENAME}" "${MOUNT_POINT}/${APP_BASENAME}"
# Applications shortcut (recreate on volume side)
rm -f "${MOUNT_POINT}/Applications" 2>/dev/null || true
ln -s /Applications "${MOUNT_POINT}/Applications"
# Background (if exists)
if [[ -f "${STAGING}/.background/background.png" ]]; then
  mkdir -p "${MOUNT_POINT}/.background"
  ditto "${STAGING}/.background/background.png" "${MOUNT_POINT}/.background/background.png"
  chflags hidden "${MOUNT_POINT}/.background" || true
fi

# --------- FINDER WINDOW STYLING ----------
echo "==> Setting up Finder layout"
sleep 2  # give Finder a bit more time to see the mounted volume
osascript <<OSAEOF
set mpPOSIX to "$MOUNT_POINT"
set appName to "$APP_BASENAME"

tell application "Finder"
  activate
  set mp to (POSIX file mpPOSIX) as alias

  -- Open and get real window
  open mp
  delay 0.5
  set w to window 1
  try
    set target of w to (folder mp)
  end try

  -- Window parameters
  try
    tell w
      set current view to icon view
      set toolbar visible to false
      set statusbar visible to false
      set bounds to {100, 100, 100 + $WIN_W, 100 + $WIN_H}
    end tell
  end try

  -- Icon options
  try
    set vo to the icon view options of w
    try
      set arrangement of vo to not arranged
    end try
    try
      set icon size of vo to $ICON_SIZE
    end try
  end try

  -- Background (if possible — great; if not — just skip)
  try
    set bgAlias to (POSIX file (mpPOSIX & "/.background/background.png")) as alias
    set background picture of (the icon view options of w) to bgAlias
  end try

  -- Icon positions
  try
    set position of item appName of (folder mp) to {$APP_X, $APP_Y}
  end try
  try
    set position of item "Applications" of (folder mp) to {$APPS_X, $APPS_Y}
  end try

  try
    update without registering applications
  end try

  delay 0.6
  try
    close w
    delay 0.3
    open mp
    delay 0.3
  end try
end tell
OSAEOF

echo "==> Unmounting DMG"
for i in {1..5}; do
  if hdiutil detach "${MOUNT_POINT}" -quiet; then
    DETACHED=1
    break
  fi
  echo "    Retry attempt (${i})..."
  sleep 1
done
[[ -z "${DETACHED:-}" ]] && { echo >&2 "ERROR: failed to unmount ${MOUNT_POINT}"; exit 1; }

# Remove old DMG if it already exists
if [[ -f "${FINAL_DMG}" ]]; then
  echo "==> Removing old file ${FINAL_DMG}"
  rm -f "${FINAL_DMG}"
fi

echo "==> Converting to compressed UDZO"
hdiutil convert -verbose "${TMP_DMG}" -format UDZO -imagekey zlib-level=9 -o "${FINAL_DMG}"

echo "==> Done: ${FINAL_DMG}"