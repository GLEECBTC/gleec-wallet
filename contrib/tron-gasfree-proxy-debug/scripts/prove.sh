#!/usr/bin/env bash
# A/B proof for the proxy KDF mesh prerequisite on the fixed proxy branch.
#
# For each case it recreates kdf-client (connected vs not), then asks the probe exactly
# what the proxy asks its kdf_rpc_client:
#
#   peer_connection_healthcheck(peer_address = client PeerId)
#
# On the fixed proxy branch, signature validation runs before peer healthcheck.
# Therefore a dummy X-Auth-Payload is useful only to prove signature-first log
# classification; it must not be used as evidence that the peer gate passed/failed.
#
# Takes a few minutes: gossipsub mesh formation under amd64 emulation is slow.
# Does not print the rpc_password or any GasFree secret.
set -euo pipefail
cd "$(dirname "$0")/.."
set -a
# shellcheck disable=SC1091
. ./.env
set +a
: "${KDF_RPC_PASSWORD:?set KDF_RPC_PASSWORD in .env}"

PROBE_RPC="http://localhost:7790"
CLIENT_RPC="http://localhost:7791"
PROXY="http://localhost:6150"
FWD="203.0.113.7"                 # public-looking IP -> forces the proxy validation path
PROBE_IP="172.28.0.10"            # the probe's fixed compose IP (meshes => true)
DEAD_IP="172.28.0.99"             # reachable subnet IP, no KDF (never meshes => false)
ENDPOINT="/gasfree/tron/api/v1/address/TDpG5sdBXmpCGfJJSr5RGnyHxmcJSYmrg7"

# 25s timeout: a healthcheck for a NOT-connected peer blocks ~10s server-side
# (gossipsub broadcast wait) before returning {"result":false}.
rpc()  { curl -s -m 25 "$1" --data-binary @-; }
ready(){ printf '{"userpass":"%s","method":"version"}' \
  "$KDF_RPC_PASSWORD" | rpc "$1" | grep -q '"result"'; }
peer() { printf '{"userpass":"%s","method":"get_my_peer_id"}' \
  "$KDF_RPC_PASSWORD" | rpc "$CLIENT_RPC" \
    | python3 -c 'import sys,json;print(json.load(sys.stdin).get("result",""))'; }
healthcheck(){ printf '{"userpass":"%s","mmrpc":"2.0","method":"peer_connection_healthcheck","params":{"peer_address":"%s"},"id":0}' \
  "$KDF_RPC_PASSWORD" "$1" | rpc "$PROBE_RPC"; }
craft(){ python3 -c "import json,sys;print(json.dumps({'signature_bytes':[0]*64,'address':sys.argv[1],'raw_message':{'uri':'https://quicknode.gleec.com$ENDPOINT','body_size':0,'public_key_encoded':[0]*38,'expires_at':9999999999}}))" "$1"; }

proxy_branch(){ # $1 = x-auth-payload
  local mark code
  mark=$(docker compose logs proxy 2>&1 | wc -l | tr -d ' ')
  code=$(curl -s -o /dev/null -w '%{http_code}' -m 20 \
    -H "X-Forwarded-For: $FWD" -H "x-auth-payload: $1" "${PROXY}${ENDPOINT}")
  echo "  proxy HTTP: $code"
  docker compose logs proxy 2>&1 | tail -n +$((mark + 1)) \
    | grep -iE "returning 401" | tail -1 | sed 's/.*\] /  proxy log: /' || echo "  (no 401 log line)"
}

run_case(){ # $1 label  $2 seednode  $3 expect(true|false)
  echo "== CASE: $1 (seednodes=$2) =="
  KDF_CLIENT_SEEDNODES="$2" docker compose up -d --force-recreate --no-deps kdf-client >/dev/null 2>&1
  i=0; until ready "$CLIENT_RPC"; do i=$((i+1)); [ "$i" -gt 90 ] && { echo "  client RPC timeout"; return; }; sleep 2; done
  local p; p=$(peer); echo "  client peer: $p"
  # Wait until the healthcheck reaches the expected state (mesh formation is slow).
  local hc i2=0
  while :; do
    hc=$(healthcheck "$p" || true)
    echo "$hc" | grep -q "\"result\":$3" && break
    i2=$((i2+1)); [ "$i2" -gt 40 ] && break
    sleep 3
  done
  echo "  healthcheck: $hc"
  proxy_branch "$(craft "$p")"
  echo
}

echo "Proving the proxy KDF mesh prerequisite with peer_connection_healthcheck ..."
echo
run_case "CONNECTED (meshes with probe)"        "$PROBE_IP" "true"
run_case "DISCONNECTED (cannot reach probe)"    "$DEAD_IP"  "false"
echo "Done."
echo
echo "Interpretation on the fixed branch:"
echo "  healthcheck false -> real signed wallet requests will log:"
echo "    Peer isn't connected to KDF network, returning 401"
echo "  dummy request 401 -> should log invalid signed message first; that is expected."
