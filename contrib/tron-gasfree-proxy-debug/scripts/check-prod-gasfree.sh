#!/usr/bin/env bash
# Smoke-check the production GasFree proxy edge and, when given a real wallet PeerId,
# the proxy host's KDF healthcheck path. Does not print secrets.
set -euo pipefail

PROXY_BASE="${PROXY_BASE:-https://quicknode.gleec.com/gasfree/tron}"
ORIGIN="${ORIGIN:-https://wallet.gleec.com}"
PROD_KDF_RPC_URL="${PROD_KDF_RPC_URL:-}"
PROD_KDF_RPC_PASSWORD="${PROD_KDF_RPC_PASSWORD:-}"
WALLET_PEER_ID="${WALLET_PEER_ID:-}"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

header_value() {
  awk -v name="$1" '
    BEGIN { IGNORECASE = 1 }
    index($0, name ":") == 1 {
      sub("^[^:]+:[[:space:]]*", "")
      sub("\r$", "")
      print
      exit
    }
  ' "$2"
}

check_cors_header() {
  local headers="$1"
  local label="$2"
  local acao
  acao="$(header_value "Access-Control-Allow-Origin" "$headers")"
  if [ -z "$acao" ]; then
    echo "FAIL $label: missing Access-Control-Allow-Origin" >&2
    return 1
  fi
  echo "OK   $label: Access-Control-Allow-Origin: $acao"
}

echo "== Production GasFree edge: $PROXY_BASE =="

options_headers="$tmpdir/options.headers"
options_body="$tmpdir/options.body"
options_code="$(curl -sS -m 20 -D "$options_headers" -o "$options_body" \
  -X OPTIONS "${PROXY_BASE}/api/v1/config/token/all" \
  -H "Origin: $ORIGIN" \
  -H "Access-Control-Request-Method: GET" \
  -w '%{http_code}')"
echo "OPTIONS /api/v1/config/token/all -> HTTP $options_code"
check_cors_header "$options_headers" "preflight"

get_headers="$tmpdir/get.headers"
get_body="$tmpdir/get.body"
get_code="$(curl -sS -m 20 -D "$get_headers" -o "$get_body" \
  "${PROXY_BASE}/api/v1/config/token/all" \
  -H "Origin: $ORIGIN" \
  -w '%{http_code}')"
echo "GET /api/v1/config/token/all without X-Auth-Payload -> HTTP $get_code"
check_cors_header "$get_headers" "unauthorized route response"

if [ -n "$PROD_KDF_RPC_URL" ] || [ -n "$PROD_KDF_RPC_PASSWORD" ] || [ -n "$WALLET_PEER_ID" ]; then
  : "${PROD_KDF_RPC_URL:?set PROD_KDF_RPC_URL to the proxy host KDF RPC URL}"
  : "${PROD_KDF_RPC_PASSWORD:?set PROD_KDF_RPC_PASSWORD}"
  : "${WALLET_PEER_ID:?set WALLET_PEER_ID to a real wallet KDF PeerId}"

  echo
  echo "== KDF peer_connection_healthcheck =="
  # Feed the authenticated request over stdin so the RPC password never
  # appears in curl's process arguments.
  resp="$(printf '{"userpass":"%s","mmrpc":"2.0","method":"peer_connection_healthcheck","params":{"peer_address":"%s"},"id":0}' \
    "$PROD_KDF_RPC_PASSWORD" "$WALLET_PEER_ID" | \
    curl -sS -m 35 "$PROD_KDF_RPC_URL" --data-binary @-)"
  echo "$resp"
  if ! printf '%s' "$resp" | grep -q '"result"[[:space:]]*:[[:space:]]*true'; then
    echo "FAIL healthcheck did not return result:true" >&2
    exit 1
  fi
fi

echo
echo "Manual staging check still required: send X-Forwarded-For: 127.0.0.1 through the public edge and confirm it does not trigger private-IP bypass."
