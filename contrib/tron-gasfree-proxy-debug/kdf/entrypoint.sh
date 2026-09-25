#!/bin/sh
# Write MM2.json from env and start KDF. Mirrors the wallet's startup config
# (netid 6133, p2p enabled). Never echoes the rpc_password or passphrase.
set -eu

: "${KDF_ROLE:=node}"
: "${KDF_NETID:=6133}"
: "${KDF_I_AM_SEED:=false}"
: "${KDF_SEEDNODES:=}"
: "${KDF_RPC_PASSWORD:?KDF_RPC_PASSWORD is required}"
: "${KDF_PASSPHRASE:?KDF_PASSPHRASE is required}"

# Build a JSON array from a comma-separated host list (KDF_SEEDNODES="a,b").
seednodes_json="[]"
if [ -n "$KDF_SEEDNODES" ]; then
  inner=$(printf '%s' "$KDF_SEEDNODES" \
    | awk -F, '{ for (i = 1; i <= NF; i++) { printf (i > 1 ? "," : ""); printf "\"%s\"", $i } }')
  seednodes_json="[${inner}]"
fi

# Write the config without echoing secrets (cat > file does not print to stdout).
umask 077
cat > /kdf/MM2.json <<EOF
{
  "gui": "gasfree-debug-${KDF_ROLE}",
  "mm2": 1,
  "netid": ${KDF_NETID},
  "rpc_password": "${KDF_RPC_PASSWORD}",
  "rpcip": "0.0.0.0",
  "rpcport": 7783,
  "rpc_local_only": false,
  "i_am_seed": ${KDF_I_AM_SEED},
  "disable_p2p": false,
  "seednodes": ${seednodes_json},
  "passphrase": "${KDF_PASSPHRASE}",
  "coins": [],
  "allow_weak_password": true
}
EOF

echo "[kdf:${KDF_ROLE}] netid=${KDF_NETID} i_am_seed=${KDF_I_AM_SEED} seednodes=${seednodes_json} rpcport=7783"

exec /usr/local/bin/kdf
