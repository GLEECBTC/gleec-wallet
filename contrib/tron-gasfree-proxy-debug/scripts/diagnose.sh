#!/usr/bin/env bash
# Reproduce/diagnose the gas-free 401 against the local stack.
#
#   1. read each KDF node's libp2p PeerId
#   2. ask the PROBE whether the CLIENT peer is connected (peer_connection_healthcheck)
#      -> this is the exact check the proxy runs; `true` => no 401, `false` => 401
#   3. hit the proxy /gasfree route with X-Forwarded-For (a public IP) to force the
#      validation path (private/loopback source IPs bypass validation in the proxy)
#
# Does not print the rpc_password or any GasFree secret.
set -euo pipefail

cd "$(dirname "$0")/.."
# shellcheck disable=SC1091
[ -f .env ] && set -a && . ./.env && set +a

: "${KDF_RPC_PASSWORD:?set KDF_RPC_PASSWORD in .env}"
PROBE_RPC="${PROBE_RPC:-http://localhost:7790}"
CLIENT_RPC="${CLIENT_RPC:-http://localhost:7791}"
PROXY_URL="${PROXY_URL:-http://localhost:6150}"
FORWARDED_IP="${FORWARDED_IP:-203.0.113.7}"   # TEST-NET-3, a routable-looking public IP

have_jq() { command -v jq >/dev/null 2>&1; }

peer_id() { # $1 = rpc url
  # get_my_peer_id is a legacy (non-mmrpc) method.
  local body resp
  body="$(printf '{"userpass":"%s","method":"get_my_peer_id"}' "$KDF_RPC_PASSWORD")"
  resp="$(curl -s -m 10 "$1" --data "$body" || true)"
  if have_jq; then echo "$resp" | jq -r '.result // .peer_id // empty'; else echo "$resp"; fi
}

healthcheck() { # $1 = prober rpc url, $2 = target peer id
  local body
  body="$(printf '{"userpass":"%s","mmrpc":"2.0","method":"peer_connection_healthcheck","params":{"peer_address":"%s"},"id":0}' \
    "$KDF_RPC_PASSWORD" "$2")"
  curl -s -m 20 "$1" --data "$body"
}

echo "== 1. PeerIds =="
PROBE_PEER="$(peer_id "$PROBE_RPC")"
CLIENT_PEER="$(peer_id "$CLIENT_RPC")"
echo "   probe  : ${PROBE_PEER:-<unreachable>}"
echo "   client : ${CLIENT_PEER:-<unreachable>}"

echo
echo "== 2. peer_connection_healthcheck (the proxy's gate) =="
if [ -n "${CLIENT_PEER:-}" ]; then
  echo "   probe -> is client connected?  (expect {\"result\":true} when kdf-client seednodes include kdf-probe)"
  echo -n "   "; healthcheck "$PROBE_RPC" "$CLIENT_PEER"; echo
else
  echo "   (client PeerId unavailable; is the client container up?)"
fi

echo
echo "== 3. proxy /gasfree route (validation forced via X-Forwarded-For: $FORWARDED_IP) =="
for path in \
  "/gasfree/tron/api/v1/config/token/all" \
  "/gasfree/tron/api/v1/address/TDpG5sdBXmpCGfJJSr5RGnyHxmcJSYmrg7"; do
  code="$(curl -s -o /dev/null -w '%{http_code}' -m 20 \
    -H "X-Forwarded-For: $FORWARDED_IP" "${PROXY_URL}${path}" || echo "ERR")"
  echo "   [$code] ${path}"
done
echo
echo "   Note: this curl sends NO X-Auth-Payload, so a 401 here just confirms the"
echo "   route is gated. The meaningful signal is in the proxy logs:"
echo "     docker compose logs -f proxy | grep -E 'returning 401|not connected'"
echo "   'Peer isn'\\''t connected to KDF network, returning 401' == the diagnosed cause."
