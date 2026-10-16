#!/bin/sh
# Render the proxy config from env, wait for the KDF probe RPC, then start.
# Deliberately never prints secret values (no `set -x`, no echo of creds).
set -eu

: "${PROXY_PORT:=6150}"
: "${REDIS_CONNECTION_STRING:?REDIS_CONNECTION_STRING is required}"
: "${KDF_RPC_URL:?KDF_RPC_URL is required}"
: "${KDF_RPC_PASSWORD:?KDF_RPC_PASSWORD is required}"
: "${GASFREE_OUTBOUND_URL:=https://open.gasfree.io}"
: "${GASFREE_API_KEY:?GASFREE_API_KEY is required}"
: "${GASFREE_API_SECRET:?GASFREE_API_SECRET is required}"
: "${AUTH_APP_CONFIG_PATH:=/config/config.json}"

# envsubst only substitutes the variables we export here.
export PROXY_PORT REDIS_CONNECTION_STRING KDF_RPC_URL KDF_RPC_PASSWORD \
       GASFREE_OUTBOUND_URL GASFREE_API_KEY GASFREE_API_SECRET
envsubst < /config/config.template.json > "$AUTH_APP_CONFIG_PATH"
chmod 600 "$AUTH_APP_CONFIG_PATH"

# The proxy panics on startup if its KDF node is unreachable
# (`version_rpc(...).expect("KDF is not available.")`), so wait for it.
echo "[proxy] waiting for KDF probe RPC at ${KDF_RPC_URL} ..."
i=0
until curl -s -m 3 -o /dev/null "${KDF_RPC_URL}"; do
  i=$((i + 1))
  if [ "$i" -gt 90 ]; then
    echo "[proxy] KDF probe RPC not reachable after ~3 min; aborting." >&2
    exit 1
  fi
  sleep 2
done
echo "[proxy] KDF probe reachable; starting komodo-defi-proxy on port ${PROXY_PORT}."

exec komodo-defi-proxy
