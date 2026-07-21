#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RPC_URL="${RPC_URL:-http://127.0.0.1:8545}"
OWNER="${OWNER:?Set OWNER to the EOA address KDF will use for GNO signing}"
BUILD_DIR="${TMPDIR:-/tmp}/gleec-gnosis-card-harness"

SAFE="0x1111111111111111111111111111111111111111"
DELAY="0x2222222222222222222222222222222222222222"
TOKEN="0x3333333333333333333333333333333333333333"
BOUNCER="0x5555555555555555555555555555555555555555"
ROLES="0x6666666666666666666666666666666666666666"
DELAY_MASTER="0x22d903fd45f441f51bcad198d14eba8a75ea1ef0"
ROLES_MASTER="0x732b9e9f259fba6f65a1a012dc89c20872ffbd2f"
PROXY_PREFIX="363d3d373d3d3d363d73"
PROXY_SUFFIX="5af43d82803e903d91602b57fd5bf3"

if [[ ! "$OWNER" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
  echo "OWNER must be a 20-byte 0x-prefixed EVM address" >&2
  exit 2
fi

mkdir -p "$BUILD_DIR"
docker run --rm \
  -v "$ROOT:/src:ro" \
  -v "$BUILD_DIR:/out" \
  ethereum/solc:0.8.30 \
  --optimize --bin-runtime --overwrite /src/GnosisHarness.sol -o /out >/dev/null

rpc() {
  local method="$1"
  local params="$2"
  curl -fsS "$RPC_URL" \
    -H 'content-type: application/json' \
    --data "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$method\",\"params\":$params}" \
    | grep -q '"result"'
}

runtime_file() {
  find "$BUILD_DIR" -name "$1.bin-runtime" -print -quit
}

set_code() {
  local address="$1"
  local file="$2"
  local code
  code="$(tr -d '\n' < "$file")"
  rpc anvil_setCode "[\"$address\",\"0x$code\"]"
}

pad_address() {
  printf '%064s' "${1#0x}" | tr ' ' '0'
}

set_storage_address() {
  local address="$1"
  local slot="$2"
  local value="$3"
  rpc anvil_setStorageAt "[\"$address\",\"$slot\",\"0x$(pad_address "$value")\"]"
}

set_code "$SAFE" "$(runtime_file SafeHarness)"
set_code "$DELAY_MASTER" "$(runtime_file DelayHarness)"
set_code "$ROLES_MASTER" "$(runtime_file RolesHarness)"
rpc anvil_setCode "[\"$DELAY\",\"0x${PROXY_PREFIX}${DELAY_MASTER#0x}${PROXY_SUFFIX}\"]"
rpc anvil_setCode "[\"$ROLES\",\"0x${PROXY_PREFIX}${ROLES_MASTER#0x}${PROXY_SUFFIX}\"]"
set_code "$BOUNCER" "$ROOT/fixtures/bouncer_runtime_4_10_1.hex"
set_code "$TOKEN" "$(runtime_file TokenHarness)"

set_storage_address "$DELAY" "0x0" "$SAFE"
set_storage_address "$DELAY" "0x1" "$SAFE"
set_storage_address "$DELAY" "0x2" "$SAFE"
set_storage_address "$DELAY" "0x3" "$OWNER"
set_storage_address "$ROLES" "0x0" "$SAFE"
set_storage_address "$ROLES" "0x1" "$SAFE"
set_storage_address "$ROLES" "0x2" "$BOUNCER"
rpc anvil_mine '["0x1"]'

echo "Gnosis card fixtures installed for owner $OWNER on $RPC_URL"
