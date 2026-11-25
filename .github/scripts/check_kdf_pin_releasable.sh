#!/usr/bin/env bash
#
# Fails when the SDK build configuration pins a temporary KDF build: one whose
# branch is named local/... (a commit in a local clone only) or charl-temp/...
# (a scratch branch in kdf-internal). The KDF team has not reviewed or merged
# either kind, and their artifacts exist only on our build mirror. They may sit
# on dev, never on main or a release branch.
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
  echo "::error::KDF ${branch} @ ${commit} is a temporary build allowed on dev only. Repin to a merged kdf-internal commit before merging into a release branch."
  exit 1
fi

echo "KDF ${branch} @ ${commit} can ship."
