#!/usr/bin/env bash
set -euo pipefail

# Gate for the manual GasFree preview deploy: the requested KDF branch/commit
# must be exactly the approved release, and the manifest the build actually
# consumes must pin exactly the approved artifact digests.
#
# The approved release identity - branch, 40-character commit and the
# per-platform SHA-256 digests - lives in one place only: the checked-in SDK
# build manifest, passed here as --approved-config. Nothing in this script
# restates those values, so rolling the KDF artifact is a single-file change.
#
# --approved-config MUST be the pristine checked-in manifest. The preview
# workflow regenerates build_config.json from its dispatch inputs (see the
# "Update KDF API configuration" step) before the build, so pointing both flags
# at that regenerated file would compare it against itself and accept any KDF
# branch. Snapshot the manifest immediately after the SDK checkout and pass the
# snapshot as --approved-config, then pass the regenerated file as --config.
#
# The platform set below is a release-completeness requirement, not part of the
# rolling identity: a preview must never ship a partial artifact set. Rolling
# the KDF build never changes it.

readonly expected_platform_set='android-aarch64,android-armv7,ios,linux,macos,web,windows'
readonly release_blocker_checksum='0000000000000000000000000000000000000000000000000000000000000000'

api_branch=''
api_commit=''
sdk_branch=''
sdk_commit=''
sdk_repo=''
approved_config=''
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
    --approved-config <pristine checked-in build_config.json> \
    [--sdk-repo <checked-out SDK repository>] \
    [--config <build_config.json the build will consume>]
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
    --approved-config)
      (($# >= 2)) || fail 'missing value for --approved-config'
      approved_config=$2
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
[[ -n "$approved_config" ]] || fail '--approved-config is required'

[[ -f "$approved_config" ]] ||
  fail "approved build config not found: $approved_config"
command -v jq >/dev/null 2>&1 || fail 'jq is required'

# Reads one string out of a manifest, failing loudly instead of letting an
# unreadable or malformed file collapse into an empty expectation.
read_config_value() {
  local path=$1 filter=$2 label=$3 value
  value=$(jq -er "$filter" "$path" 2>/dev/null) ||
    fail "$label could not be read from $path"
  [[ -n "$value" ]] || fail "$label is empty in $path"
  printf '%s' "$value"
}

assert_release_platform_set() {
  local path=$1 label=$2 actual
  actual=$(read_config_value \
    "$path" '.api.platforms | keys | sort | join(",")' "$label platform set")
  [[ "$actual" == "$expected_platform_set" ]] ||
    fail "$label platform set is not the exact seven-target release set"
  actual=$(read_config_value \
    "$path" '.api.required_platforms | sort | join(",")' \
    "$label required platform set")
  [[ "$actual" == "$expected_platform_set" ]] ||
    fail "$label required platform set is not the exact seven-target release set"
}

expected_api_branch=$(read_config_value \
  "$approved_config" '.api.branch' 'approved KDF branch')
expected_api_commit=$(read_config_value \
  "$approved_config" '.api.api_commit_hash' 'approved KDF commit')

# The approved manifest has to be a shippable release in its own right, or the
# checks below would happily approve a half-rolled or deliberately blocked pin.
git check-ref-format --branch "$expected_api_branch" >/dev/null 2>&1 ||
  fail 'approved manifest declares an invalid KDF branch name'
[[ "$expected_api_commit" =~ ^[0-9a-f]{40}$ ]] ||
  fail 'approved manifest KDF commit must be an exact lowercase 40-character SHA'
assert_release_platform_set "$approved_config" 'approved build config'
jq -e \
  --arg blocker "$release_blocker_checksum" \
  '.api.platforms
   | to_entries
   | all(.[];
       .value.valid_zip_sha256_checksums
       | length == 1
         and (.[0] | test("^[0-9a-f]{64}$"))
         and .[0] != $blocker)' \
  "$approved_config" >/dev/null ||
  fail 'approved manifest must pin exactly one released digest per platform'

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
  printf 'Verified the requested KDF release identity for %s at %s.\n' \
    "$expected_api_branch" "$expected_api_commit"
  exit 0
fi

[[ -f "$config_path" ]] || fail "build config not found: $config_path"

jq -e \
  --arg branch "$expected_api_branch" \
  --arg commit "$expected_api_commit" \
  '.api.branch == $branch and .api.api_commit_hash == $commit' \
  "$config_path" >/dev/null ||
  fail 'build config KDF branch/commit does not match the approved release'

assert_release_platform_set "$config_path" 'build config'

# Both manifests were just proven to declare exactly this platform set, so
# walking the validated constant cannot silently skip a target the way an
# unchecked `jq | while read` could.
IFS=',' read -r -a release_platforms <<<"$expected_platform_set"
for platform in "${release_platforms[@]}"; do
  approved_checksum=$(
    jq -er --arg platform "$platform" \
      '.api.platforms[$platform].valid_zip_sha256_checksums[0]' \
      "$approved_config" 2>/dev/null
  ) || fail "approved $platform digest could not be read"
  jq -e \
    --arg platform "$platform" \
    --arg checksum "$approved_checksum" \
    '.api.platforms[$platform].valid_zip_sha256_checksums == [$checksum]' \
    "$config_path" >/dev/null ||
    fail "$platform checksum allowlist is not the exact approved digest"
done

printf 'Verified exact GasFree KDF release provenance for %s at %s.\n' \
  "$expected_api_branch" "$expected_api_commit"
