#!/bin/bash
# test-sign-timestamp.sh — Check code signing and timestamping for macOS app
# Usage: ./contrib/test-sign-timestamp.sh [APP_PATH]
# If APP_PATH is not provided, uses default build path

set -euo pipefail

# Default app path
DEFAULT_APP="build/macos/Build/Products/Release-production/Gleec DEX.app"

# Parse command line arguments
APP="${1:-$DEFAULT_APP}"

# Color codes for output
RED='\033[0;31m'; GRN='\033[0;32m'; YEL='\033[0;33m'; BLU='\033[0;34m'; NC='\033[0m'

# Welcome message
echo -e "${BLU}========================================${NC}"
echo -e "${BLU}  Code Signing & Timestamp Checker${NC}"
echo -e "${BLU}========================================${NC}"
echo ""
echo -e "Checking app: ${YEL}$APP${NC}"
echo ""

# Check if app exists
if [[ ! -d "$APP" ]]; then
  echo -e "${RED}ERROR: App not found at: $APP${NC}"
  echo ""
  echo "Usage: $0 [APP_PATH]"
  echo "  APP_PATH - Path to the .app bundle to check"
  echo "  If not provided, uses: $DEFAULT_APP"
  exit 1
fi

# Searching for all executable Mach-O files (+x)
while IFS= read -r -d '' f; do
  if file -b "$f" | grep -q 'Mach-O'; then
    echo "==> $f"
    INFO="$(LC_ALL=C /usr/bin/codesign -d --verbose=4 "$f" 2>&1 || true)"
    if echo "$INFO" | grep -q '^[[:space:]]*Timestamp='; then
      TS="$(echo "$INFO" | sed -n 's/^[[:space:]]*Timestamp=//p' | head -n1)"
      echo -e "   ${GRN}✔ Signed + timestamp${NC} ($TS)"

      # On newer systems, the 'Timestamp Authority=' line is often missing.
      # If you really need to check the TSA, look for 'Apple' in the certificate chain.
      if echo "$INFO" | grep -q 'Authority=.*Apple'; then
        : # All good, timestamp is most likely from Apple
      else
        echo -e "   ${YEL}▲ Timestamp present, but TSA line not shown by 'codesign' (this is normal).${NC}"
      fi
    else
      echo -e "   ${RED}✖ Signed, but NO timestamp${NC}"
    fi
  fi
done < <(find "$APP" -type f -perm -111 -print0)
# Additional verification for the entire .app bundle:
echo ""
echo -e "${BLU}Performing deep signature verification of the .app bundle...${NC}"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"

echo ""
echo -e "${BLU}Gatekeeper assessment (spctl) for the .app bundle...${NC}"
/usr/sbin/spctl --assess --type execute -vv "$APP"

echo ""
echo -e "${BLU}========================================${NC}"
echo -e "${BLU}  Check completed${NC}"
echo -e "${BLU}========================================${NC}"
