#!/usr/bin/env bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
validator="$script_dir/validate_tron_gasless_config.sh"
provider="TLntW9Z59LYY5KEi9cmwk3PKjQga828ird"

expect_success() {
  env \
    TRON_GASLESS_ENABLED=true \
    TRON_GASLESS_RECEIVE_ENABLED=false \
    TRON_GASLESS_BASE_URL=https://quicknode.gleec.com/gasfree/nile \
    TRON_GASLESS_SERVICE_PROVIDER="$provider" \
    TRON_GASLESS_CONTROL_URL= \
    TRON_GASLESS_REQUIRED_NETWORK=nile \
    "$@" \
    bash "$validator" >/dev/null
}

expect_failure() {
  if env \
    TRON_GASLESS_ENABLED=true \
    TRON_GASLESS_RECEIVE_ENABLED=false \
    TRON_GASLESS_BASE_URL=https://quicknode.gleec.com/gasfree/nile \
    TRON_GASLESS_SERVICE_PROVIDER="$provider" \
    TRON_GASLESS_CONTROL_URL= \
    TRON_GASLESS_REQUIRED_NETWORK=nile \
    "$@" \
    bash "$validator" >/dev/null 2>&1; then
    echo "Expected validation to fail for: $*" >&2
    exit 1
  fi
}

expect_success
expect_success TRON_GASLESS_REQUIRED_NETWORK=tron \
  TRON_GASLESS_BASE_URL=https://quicknode.gleec.com/gasfree/tron
expect_success TRON_GASLESS_RECEIVE_ENABLED=true \
  TRON_GASLESS_CONTROL_URL=https://controls.gleec.com/v1/gasfree

expect_failure TRON_GASLESS_BASE_URL=https://quicknode.gleec.com/gasfree/tron
expect_failure TRON_GASLESS_REQUIRED_NETWORK=shasta
expect_failure TRON_GASLESS_ENABLED=TRUE
expect_failure TRON_GASLESS_BASE_URL=
expect_failure TRON_GASLESS_SERVICE_PROVIDER=invalid
expect_failure TRON_GASLESS_BASE_URL=https://quicknode.gleec.com/gasfree//nile
expect_failure TRON_GASLESS_BASE_URL=https://quicknode.gleec.com/gasfree/./nile
expect_failure TRON_GASLESS_BASE_URL=https://quicknode.gleec.com/gasfree/../nile
expect_failure TRON_GASLESS_BASE_URL=https://user@example.com/gasfree/nile
expect_failure TRON_GASLESS_BASE_URL=https://quicknode.gleec.com/gasfree/nile?x=1
expect_failure TRON_GASLESS_BASE_URL=https://quicknode.gleec.com/gasfree/%6eile
expect_failure TRON_GASLESS_RECEIVE_ENABLED=true \
  TRON_GASLESS_CONTROL_URL=https://controls.gleec.com/gasfree/.
expect_failure TRON_GASLESS_RECEIVE_ENABLED=true \
  TRON_GASLESS_CONTROL_URL=https://controls.gleec.com/gasfree/..
expect_failure TRON_GASLESS_RECEIVE_ENABLED=true \
  TRON_GASLESS_CONTROL_URL=https://controls.gleec.com/gasfree//control
expect_failure TRON_GASLESS_RECEIVE_ENABLED=true \
  TRON_GASLESS_CONTROL_URL=https://controls.gleec.com/gasfree/./control
expect_failure TRON_GASLESS_RECEIVE_ENABLED=true \
  TRON_GASLESS_CONTROL_URL=https://controls.gleec.com/gasfree/../control
expect_failure TRON_GASLESS_RECEIVE_ENABLED=true
expect_failure TRON_GASLESS_ENABLED=false TRON_GASLESS_RECEIVE_ENABLED=true

echo "TRON GasFree CI configuration validation passed."
