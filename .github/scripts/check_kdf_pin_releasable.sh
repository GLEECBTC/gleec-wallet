#!/usr/bin/env bash
#
# Fails when the SDK build configuration pins a local-only KDF build: one whose
# branch is named local/... . Those builds come from a commit no KDF remote
# carries and exist only on our build mirror. They may sit on dev, never on
# main or a release branch.
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

if [[ "$branch" == local/* ]]; then
  echo "::error::KDF ${branch} @ ${commit} is a local-only build allowed on dev only. Repin to a kdf-internal branch before merging into a release branch."
  exit 1
fi

echo "KDF ${branch} @ ${commit} can ship."
