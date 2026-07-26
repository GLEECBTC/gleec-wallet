#!/usr/bin/env bash
set -euo pipefail

readonly expected_api_branch='feat/tron-gasfree'
readonly expected_api_commit='bd413dcfea73c9de2e85903323946a378b180fa7'
readonly expected_platform_set='android-aarch64,android-armv7,ios,linux,macos,web,windows'

api_branch=''
api_commit=''
sdk_branch=''
sdk_commit=''
sdk_repo=''
config_path=''

fail() {
  printf 'GasFree preview provenance validation failed: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
Usage:
  verify_gasfree_preview_provenance.sh \
    --api-branch <branch> \
    --api-commit <40-character SHA> \
    --sdk-branch <branch> \
    --sdk-commit <40-character SHA> \
    [--sdk-repo <checked-out SDK repository>] \
    [--config <build_config.json>]
USAGE
}

while (($# > 0)); do
  case "$1" in
    --api-branch)
      (($# >= 2)) || fail 'missing value for --api-branch'
      api_branch=$2
      shift 2
      ;;
    --api-commit)
      (($# >= 2)) || fail 'missing value for --api-commit'
      api_commit=$2
      shift 2
      ;;
    --sdk-branch)
      (($# >= 2)) || fail 'missing value for --sdk-branch'
      sdk_branch=$2
      shift 2
      ;;
    --sdk-commit)
      (($# >= 2)) || fail 'missing value for --sdk-commit'
      sdk_commit=$2
      shift 2
      ;;
    --sdk-repo)
      (($# >= 2)) || fail 'missing value for --sdk-repo'
      sdk_repo=$2
      shift 2
      ;;
    --config)
      (($# >= 2)) || fail 'missing value for --config'
      config_path=$2
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

[[ -n "$api_branch" ]] || fail '--api-branch is required'
[[ -n "$api_commit" ]] || fail '--api-commit is required'
[[ -n "$sdk_branch" ]] || fail '--sdk-branch is required'
[[ -n "$sdk_commit" ]] || fail '--sdk-commit is required'

git check-ref-format --branch "$api_branch" >/dev/null 2>&1 ||
  fail 'invalid KDF branch name'
git check-ref-format --branch "$sdk_branch" >/dev/null 2>&1 ||
  fail 'invalid SDK branch name'
[[ "$api_commit" =~ ^[0-9a-f]{40}$ ]] ||
  fail 'KDF commit must be an exact lowercase 40-character SHA'
[[ "$sdk_commit" =~ ^[0-9a-f]{40}$ ]] ||
  fail 'SDK commit must be an exact lowercase 40-character SHA'

[[ "$api_branch" == "$expected_api_branch" ]] ||
  fail "this workflow only accepts KDF branch $expected_api_branch"
[[ "$api_commit" == "$expected_api_commit" ]] ||
  fail "KDF branch $expected_api_branch is bound to commit $expected_api_commit"

if [[ -n "$sdk_repo" ]]; then
  git -C "$sdk_repo" rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
    fail "SDK repository is invalid: $sdk_repo"
  resolved_sdk_commit=$(
    git -C "$sdk_repo" rev-parse "$sdk_commit^{commit}" 2>/dev/null
  ) || fail 'SDK commit is not present in the checked-out repository'
  [[ "$resolved_sdk_commit" == "$sdk_commit" ]] ||
    fail 'SDK commit did not resolve to the exact requested SHA'
  sdk_branch_ref="refs/remotes/origin/$sdk_branch"
  git -C "$sdk_repo" show-ref --verify --quiet "$sdk_branch_ref" ||
    fail 'requested SDK remote branch is not present'
  git -C "$sdk_repo" merge-base --is-ancestor \
    "$resolved_sdk_commit" "$sdk_branch_ref" ||
    fail 'requested SDK commit does not belong to the requested SDK branch'
  checked_out_sdk_commit=$(git -C "$sdk_repo" rev-parse HEAD)
  [[ "$checked_out_sdk_commit" == "$resolved_sdk_commit" ]] ||
    fail 'checked-out SDK HEAD is not the requested SDK commit'
fi

if [[ -z "$config_path" ]]; then
  exit 0
fi

[[ -f "$config_path" ]] || fail "build config not found: $config_path"
command -v jq >/dev/null 2>&1 || fail 'jq is required'

jq -e \
  --arg branch "$expected_api_branch" \
  --arg commit "$expected_api_commit" \
  '.api.branch == $branch and .api.api_commit_hash == $commit' \
  "$config_path" >/dev/null ||
  fail 'build config KDF branch/commit does not match the approved release'

actual_platform_set=$(
  jq -r '.api.platforms | keys | sort | join(",")' "$config_path"
)
[[ "$actual_platform_set" == "$expected_platform_set" ]] ||
  fail 'build config platform set is not the exact seven-target release set'

required_platform_set=$(
  jq -r '.api.required_platforms | sort | join(",")' "$config_path"
)
[[ "$required_platform_set" == "$expected_platform_set" ]] ||
  fail 'required platform set is not the exact seven-target release set'

platforms=(
  web
  ios
  macos
  android-armv7
  android-aarch64
  linux
  windows
)
checksums=(
  9242cbba06eda6e82fc057897781cea2adf85f67f0cf5710f4feaf0a5e6d844c
  0cc494a8ff7b3f926cebc6956cda61c9928c7366624d592c71e29f080a3255bd
  f1d8a52c7c34d9721761733586f7262177b5362f911d8a220b2550e1f9844bbe
  929d57312908544c9e6ae94d660d8ae14c21fb84547821ba0e0aba26c4daf29a
  9953572e03956a751dcef365df76b6b84a3675800323220d50409dbd8175f037
  ec5e2c801520e00ed1fd18c82c0edc0ade30716c6a4fb8aab453f265ce6afb33
  04062cf1a271888eab9a757fa1a19e41038beea15b19484a21e5731d4dfc05e0
)

for index in "${!platforms[@]}"; do
  platform=${platforms[$index]}
  checksum=${checksums[$index]}
  jq -e \
    --arg platform "$platform" \
    --arg checksum "$checksum" \
    '.api.platforms[$platform].valid_zip_sha256_checksums == [$checksum]' \
    "$config_path" >/dev/null ||
    fail "$platform checksum allowlist is not the exact approved digest"
done

printf 'Verified exact GasFree KDF release provenance for %s at %s.\n' \
  "$expected_api_branch" "$expected_api_commit"
