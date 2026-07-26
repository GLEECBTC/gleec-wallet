#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
repo_root=$(cd "$script_dir/../.." && pwd)
readonly repo_root
readonly validator="$script_dir/verify_gasfree_preview_provenance.sh"
readonly config="$repo_root/sdk/packages/komodo_defi_framework/app_build/build_config.json"
readonly api_branch='feat/tron-gasfree'
readonly api_commit='bd413dcfea73c9de2e85903323946a378b180fa7'
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
)

"$validator" "${common_args[@]}" --config "$config" >/dev/null

expect_failure "$validator" \
  --api-branch dev \
  --api-commit "$api_commit" \
  --sdk-branch "$sdk_branch" \
  --sdk-commit "$sdk_commit"

expect_failure "$validator" \
  --api-branch "$api_branch" \
  --api-commit aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
  --sdk-branch "$sdk_branch" \
  --sdk-commit "$sdk_commit"

expect_failure "$validator" \
  --api-branch "$api_branch" \
  --api-commit "$api_commit" \
  --sdk-branch "$sdk_branch" \
  --sdk-commit 4a1f235d

temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT
tampered_config="$temp_dir/build_config.json"
jq \
  '.api.platforms.web.valid_zip_sha256_checksums = [
    "1242cbba06eda6e82fc057897781cea2adf85f67f0cf5710f4feaf0a5e6d844c"
  ]' \
  "$config" >"$tampered_config"

expect_failure "$validator" "${common_args[@]}" --config "$tampered_config"

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
  --sdk-repo "$sdk_repo" >/dev/null

git -C "$sdk_repo" checkout -q --detach "$root_commit"
git -C "$sdk_repo" commit -q --allow-empty -m divergent
divergent_sdk_commit=$(git -C "$sdk_repo" rev-parse HEAD)

expect_failure "$validator" \
  --api-branch "$api_branch" \
  --api-commit "$api_commit" \
  --sdk-branch trusted-sdk \
  --sdk-commit "$divergent_sdk_commit" \
  --sdk-repo "$sdk_repo"

printf 'GasFree preview provenance validation tests passed.\n'
