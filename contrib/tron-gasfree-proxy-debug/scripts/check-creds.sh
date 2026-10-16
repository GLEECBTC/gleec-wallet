#!/usr/bin/env bash
# Check the GasFree creds in .env by calling provider/all THROUGH the local proxy.
# (We go through the proxy because open.gasfree.io is behind Cloudflare, which bot-blocks
# naive direct clients with "error code: 1010" — the proxy's client gets through.)
#
# Interprets GasFree's response:
#   HTTP 200                      -> creds OK
#   "Apikey not found"            -> GASFREE_API_KEY wrong / not applied
#   "Authorization hash not match"-> GASFREE_API_SECRET doesn't match the key
# Never prints the secret.
set -euo pipefail
cd "$(dirname "$0")/.."
PROXY_BASE="${TRON_GASLESS_BASE_URL:-http://localhost:6150/gasfree/tron}"
PAYLOAD=$(python3 -c "import json;print(json.dumps({'signature_bytes':[0]*64,'address':'12D3KooWQffrAQimALi3gA1zWG2wnK3v9aJZoZdBFGcCfXNnTSEh','raw_message':{'uri':'https://x/','body_size':0,'public_key_encoded':[0]*38,'expires_at':9999999999}}))")

# Force the proxy's private-IP bypass via X-Forwarded-For (this host may otherwise
# present a public source IP to the published port, making validation run and reject
# the dummy payload). The bypass still forwards to GasFree, so creds are exercised.
resp=$(curl -s -m 25 -w $'\n%{http_code}' \
  -H "X-Forwarded-For: 127.0.0.1" -H "x-auth-payload: $PAYLOAD" \
  "${PROXY_BASE}/api/v1/config/provider/all" 2>/dev/null || true)
body=$(printf '%s' "$resp" | sed '$d')
code=$(printf '%s' "$resp" | tail -n1)

echo "provider/all via proxy -> HTTP $code"
case "$code:$body" in
  200:*)                          echo "✅ creds OK"; echo "$body" | head -c 500; echo; exit 0 ;;
  *"Apikey not found"*)           echo "❌ GASFREE_API_KEY not recognized — wrong key, or proxy not recreated after editing .env." ;;
  *"hash not match"*)             echo "❌ GASFREE_API_SECRET does not match the key — re-copy the secret paired with this api_key." ;;
  *"error code: 1010"*)           echo "⚠️  Cloudflare blocked the request (1010) — unusual via the proxy; retry." ;;
  *)                              echo "⚠️  Unexpected response:"; echo "$body" | head -c 400 ;;
esac
exit 1