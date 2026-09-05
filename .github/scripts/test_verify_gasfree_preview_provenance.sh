#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
repo_root=$(cd "$script_dir/../.." && pwd)
readonly repo_root
readonly validator="$script_dir/verify_gasfree_preview_provenance.sh"
readonly config="$repo_root/sdk/packages/komodo_defi_framework/app_build/build_config.json"

command -v jq >/dev/null 2>&1 || {
  printf 'jq is required to run these tests.\n' >&2
  exit 1
}

# Read the approved KDF identity out of the manifest, exactly as the validator
# does. Restating it here is what let the last artifact roll leave this gate
# pinned to a release that no longer exists.
api_branch=$(jq -er '.api.branch' "$config")
readonly api_branch
api_commit=$(jq -er '.api.api_commit_hash' "$config")
readonly api_commit
readonly sdk_branch='add/tron-gas-free'
readonly sdk_commit='4a1f235d6dbd76dd6e58d689a30ce9fa885a1b0f'

expect_failure() {
  if "$@" >/dev/null 2>&1; then
    printf 'Expected command to fail: %q ' "$@" >&2
    printf '\n' >&2
    exit 1
  fi
}

common_args=(
  --api-branch "$api_branch"
  --api-commit "$api_commit"
  --sdk-branch "$sdk_branch"
  --sdk-commit "$sdk_commit"
  --approved-config "$config"
)

"$validator" "${common_args[@]}" --config "$config" >/dev/null

# The approved identity is not optional: without a manifest to compare against
# there is nothing for the gate to enforce.
expect_failure "$validator" \
  --api-branch "$api_branch" \
  --api-commit "$api_commit" \
  --sdk-branch "$sdk_branch" \
  --sdk-commit "$sdk_commit"

# Derived from the approved branch rather than written out, so it cannot
# silently become the approved value on a future roll - which is exactly what a
# hardcoded 'dev' here did the moment the manifest rolled onto dev.
expect_failure "$validator" \
  --api-branch "$api_branch-not-approved" \
  --api-commit "$api_commit" \
  --sdk-branch "$sdk_branch" \
  --sdk-commit "$sdk_commit" \
  --approved-config "$config"

expect_failure "$validator" \
  --api-branch "$api_branch" \
  --api-commit aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
  --sdk-branch "$sdk_branch" \
  --sdk-commit "$sdk_commit" \
  --approved-config "$config"

expect_failure "$validator" \
  --api-branch "$api_branch" \
  --api-commit "$api_commit" \
  --sdk-branch "$sdk_branch" \
  --sdk-commit 4a1f235d \
  --approved-config "$config"

temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT

tampered_config="$temp_dir/build_config.json"
jq \
  '.api.platforms.web.valid_zip_sha256_checksums = [
    "1242cbba06eda6e82fc057897781cea2adf85f67f0cf5710f4feaf0a5e6d844c"
  ]' \
  "$config" >"$tampered_config"

expect_failure "$validator" "${common_args[@]}" --config "$tampered_config"

# The preview workflow regenerates the manifest from its dispatch inputs before
# the build. A regenerated manifest that names a different KDF release must be
# rejected against the pristine snapshot rather than approving itself.
rolled_config="$temp_dir/rolled_build_config.json"
jq \
  '.api.branch = "attacker/branch"
   | .api.api_commit_hash = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"' \
  "$config" >"$rolled_config"

expect_failure "$validator" "${common_args[@]}" --config "$rolled_config"

# A regenerated manifest that drops a target ships a partial release.
partial_config="$temp_dir/partial_build_config.json"
jq \
  'del(.api.platforms.windows)
   | .api.required_platforms -= ["windows"]' \
  "$config" >"$partial_config"

expect_failure "$validator" "${common_args[@]}" --config "$partial_config"

# A blocked or half-rolled approved manifest must not be able to approve
# anything, or the gate would wave through a release that cannot ship.
blocked_config="$temp_dir/blocked_build_config.json"
jq \
  '.api.platforms.web.valid_zip_sha256_checksums = [
    "0000000000000000000000000000000000000000000000000000000000000000"
  ]' \
  "$config" >"$blocked_config"

expect_failure "$validator" \
  --api-branch "$api_branch" \
  --api-commit "$api_commit" \
  --sdk-branch "$sdk_branch" \
  --sdk-commit "$sdk_commit" \
  --approved-config "$blocked_config"

short_commit_config="$temp_dir/short_commit_build_config.json"
jq '.api.api_commit_hash = "bd413dc"' "$config" >"$short_commit_config"

expect_failure "$validator" \
  --api-branch "$api_branch" \
  --api-commit bd413dc \
  --sdk-branch "$sdk_branch" \
  --sdk-commit "$sdk_commit" \
  --approved-config "$short_commit_config"

expect_failure "$validator" \
  --api-branch "$api_branch" \
  --api-commit "$api_commit" \
  --sdk-branch "$sdk_branch" \
  --sdk-commit "$sdk_commit" \
  --approved-config "$temp_dir/does-not-exist.json"

sdk_repo="$temp_dir/sdk-repo"
git init -q "$sdk_repo"
git -C "$sdk_repo" config user.name 'Preview Provenance Test'
git -C "$sdk_repo" config user.email 'preview-provenance-test@example.invalid'
git -C "$sdk_repo" commit -q --allow-empty -m root
root_commit=$(git -C "$sdk_repo" rev-parse HEAD)
git -C "$sdk_repo" checkout -q -b trusted-sdk
git -C "$sdk_repo" commit -q --allow-empty -m trusted
trusted_sdk_commit=$(git -C "$sdk_repo" rev-parse HEAD)
git -C "$sdk_repo" update-ref \
  refs/remotes/origin/trusted-sdk "$trusted_sdk_commit"

"$validator" \
  --api-branch "$api_branch" \
  --api-commit "$api_commit" \
  --sdk-branch trusted-sdk \
  --sdk-commit "$trusted_sdk_commit" \
  --sdk-repo "$sdk_repo" \
  --approved-config "$config" >/dev/null

git -C "$sdk_repo" checkout -q --detach "$root_commit"
git -C "$sdk_repo" commit -q --allow-empty -m divergent
divergent_sdk_commit=$(git -C "$sdk_repo" rev-parse HEAD)

expect_failure "$validator" \
  --api-branch "$api_branch" \
  --api-commit "$api_commit" \
  --sdk-branch trusted-sdk \
  --sdk-commit "$divergent_sdk_commit" \
  --sdk-repo "$sdk_repo" \
  --approved-config "$config"

printf 'GasFree preview provenance validation tests passed.\n'
