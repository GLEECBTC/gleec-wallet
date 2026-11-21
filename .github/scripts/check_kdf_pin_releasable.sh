#!/usr/bin/env bash
#
# Rejects KDF builds published under temporary build labels. The SDK uses
# local/... and charl-temp/... for these dev-only pins.
#
# Usage: check_kdf_pin_releasable.sh [build-config-path]
# Exits 0 when the pin can ship, 1 when it cannot, and 2 when the check
# cannot run.

set -euo pipefail

config="${1:-sdk/packages/komodo_defi_framework/app_build/build_config.json}"

if ! branch=$(jq -er '.api.branch | strings' "$config" 2> /dev/null) ||
  ! commit=$(jq -er '.api.api_commit_hash | strings' "$config" 2> /dev/null); then
  echo "::error::Cannot read .api.branch and .api.api_commit_hash from ${config}."
  exit 2
fi

if [[ "$branch" == local/* || "$branch" == charl-temp/* ]]; then
  echo "::error::KDF ${branch} @ ${commit} is a temporary build allowed on dev only. Repin to a merged kdf-internal build before release."
  exit 1
fi

echo "KDF ${branch} @ ${commit} can ship."
