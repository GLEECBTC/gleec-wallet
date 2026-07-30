#!/usr/bin/env bash

set -euo pipefail

fail() {
  echo "Error: $1" >&2
  exit 1
}

path_for_https_url() {
  local value=$1
  local authority_and_path=${value#https://}

  if [[ "$authority_and_path" != */* ]]; then
    return 1
  fi

  printf '/%s' "${authority_and_path#*/}"
}

has_ambiguous_path() {
  local path=$1

  [[ "$path" == *"//"* ||
    "$path" == *"/./"* ||
    "$path" == *"/../"* ||
    "$path" == *"/." ||
    "$path" == *"/.." ]]
}

for gasless_flag in \
  "${TRON_GASLESS_ENABLED:-}" \
  "${TRON_GASLESS_RECEIVE_ENABLED:-}"; do
  if [[ "$gasless_flag" != "true" && "$gasless_flag" != "false" ]]; then
    fail "TRON GasFree switches must be exactly true or false."
  fi
done

case "${TRON_GASLESS_REQUIRED_NETWORK:-}" in
  "" | tron | nile) ;;
  *)
    fail "TRON_GASLESS_REQUIRED_NETWORK must be empty, tron, or nile."
    ;;
esac

if [[ -n "${TRON_GASLESS_BASE_URL:-}" ]]; then
  if [[ ! "$TRON_GASLESS_BASE_URL" =~ ^https://[A-Za-z0-9.-]+(:[0-9]+)?(/[A-Za-z0-9._~-]+)*/(tron|nile)/?$ ]] ||
    [[ "$TRON_GASLESS_BASE_URL" == *"%"* ]]; then
    fail "TRON_GASLESS_BASE_URL must be a strict HTTPS tron/nile endpoint without credentials, query, fragment, encoding, or ambiguous path segments."
  fi

  gasless_base_path=$(path_for_https_url "$TRON_GASLESS_BASE_URL") ||
    fail "TRON_GASLESS_BASE_URL must include a path."
  if has_ambiguous_path "$gasless_base_path"; then
    fail "TRON_GASLESS_BASE_URL contains ambiguous path segments."
  fi

  configured_network=${TRON_GASLESS_BASE_URL%/}
  configured_network=${configured_network##*/}
  if [[ -n "${TRON_GASLESS_REQUIRED_NETWORK:-}" &&
    "$configured_network" != "$TRON_GASLESS_REQUIRED_NETWORK" ]]; then
    fail "This build policy requires the configured TRON GasFree network path."
  fi
fi

if [[ -n "${TRON_GASLESS_SERVICE_PROVIDER:-}" &&
  ! "$TRON_GASLESS_SERVICE_PROVIDER" =~ ^T[1-9A-HJ-NP-Za-km-z]{33}$ ]]; then
  fail "TRON_GASLESS_SERVICE_PROVIDER is not a valid pinned TRON address."
fi

if [[ "$TRON_GASLESS_ENABLED" == "true" &&
  (-z "${TRON_GASLESS_BASE_URL:-}" ||
    -z "${TRON_GASLESS_SERVICE_PROVIDER:-}") ]]; then
  fail "Enabled TRON GasFree builds require a base URL and pinned service provider."
fi

if [[ "$TRON_GASLESS_RECEIVE_ENABLED" == "true" ]]; then
  if [[ "$TRON_GASLESS_ENABLED" != "true" ]]; then
    fail "TRON GasFree Receive requires TRON_GASLESS_ENABLED=true."
  fi
fi
