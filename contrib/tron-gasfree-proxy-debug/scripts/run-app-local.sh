#!/usr/bin/env bash
# Launch a local build of the wallet pointed at the LOCAL gas-free proxy.
#
# Default device is macOS (native): native KDF sends no browser `Origin`, so it avoids
# the Cloudflare/CORS wall on forwarded open.gasfree.io responses that a web build hits.
# Requests to localhost are treated as same-network by the proxy, so its libp2p
# healthcheck gate is BYPASSED locally — this validates creds + forwarding + the gasless
# flow/UX end-to-end (the healthcheck path itself is proven separately by prove.sh).
#
# Usage:
#   ./scripts/run-app-local.sh             # macOS (recommended)
#   ./scripts/run-app-local.sh chrome      # web (faithful to prod; see CORS caveat below)
#
# Credentials: none needed here. The GasFree api_key/secret live only in ./.env (the
# proxy holds them); this app only needs the proxy base_url + service_provider.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"      # contrib/tron-gasfree-proxy-debug
REPO="$(cd "$HERE/../.." && pwd)"             # repo root
DEVICE="${1:-macos}"
# Default to the NGINX edge (6160), which handles browser CORS + (locally) bypasses the
# proxy gate. Use http://localhost:6150/gasfree/tron to hit the proxy directly.
PROXY_BASE="${TRON_GASLESS_BASE_URL:-http://localhost:6160/gasfree/tron}"
SERVICE_PROVIDER="${TRON_GASLESS_SERVICE_PROVIDER:-TLyqzVGLV1srkB7dToTAEqgDSfPtXRJZYH}"

echo "Preflight: checking GasFree creds via the proxy ..."
if ! TRON_GASLESS_BASE_URL="$PROXY_BASE" "$HERE/scripts/check-creds.sh"; then
  echo "  Fix the creds in $HERE/.env, then: (cd \"$HERE\" && docker compose up -d --force-recreate proxy)"
  exit 1
fi

# Auto-detect the provider registered for THIS GasFree account (the value the permit must
# name) unless the caller pinned TRON_GASLESS_SERVICE_PROVIDER explicitly. This avoids the
# wallet's hardcoded default being wrong for the account behind the proxy.
if [ -z "${TRON_GASLESS_SERVICE_PROVIDER:-}" ]; then
  PAYLOAD=$(python3 -c "import json;print(json.dumps({'signature_bytes':[0]*64,'address':'12D3KooWQffrAQimALi3gA1zWG2wnK3v9aJZoZdBFGcCfXNnTSEh','raw_message':{'uri':'https://x/','body_size':0,'public_key_encoded':[0]*38,'expires_at':9999999999}}))")
  detected=$(curl -s -m 25 -H "X-Forwarded-For: 127.0.0.1" -H "x-auth-payload: $PAYLOAD" "${PROXY_BASE}/api/v1/config/provider/all" \
    | python3 -c 'import sys,json;
try:
 print(json.load(sys.stdin)["data"]["providers"][0]["address"])
except Exception: pass' 2>/dev/null || true)
  if [ -n "$detected" ]; then
    SERVICE_PROVIDER="$detected"
    echo "  Using provider from account: $SERVICE_PROVIDER"
  fi
fi
echo

echo "Launching '$DEVICE' build against $PROXY_BASE (service_provider $SERVICE_PROVIDER)"
cd "$REPO"
exec flutter run -d "$DEVICE" \
  --dart-define=TRON_GASLESS_BASE_URL="$PROXY_BASE" \
  --dart-define=TRON_GASLESS_SERVICE_PROVIDER="$SERVICE_PROVIDER"
