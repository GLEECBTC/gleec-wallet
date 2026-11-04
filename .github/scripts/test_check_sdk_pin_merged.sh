#!/usr/bin/env bash
#
# Tests for check_sdk_pin_merged.sh against local repositories: a pin on dev or
# on a release branch passes, and one only a pull-request branch carries fails.

set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
readonly subject="$script_dir/check_sdk_pin_merged.sh"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

failures=0

git_quiet() {
  git -c user.name=test -c user.email=test@example.com \
    -c init.defaultBranch=dev "$@" > /dev/null 2>&1
}

sdk="$work/sdk"
git_quiet init "$sdk"
commit() {
  git_quiet -C "$sdk" commit --allow-empty -m "$1"
  git -C "$sdk" rev-parse HEAD
}
on_dev=$(commit 'on dev')
git_quiet -C "$sdk" branch main
git_quiet -C "$sdk" checkout -b release-0.9.0
on_release=$(commit 'on the release branch')
git_quiet -C "$sdk" checkout -b fix/pending dev
pending=$(commit 'only on a pull-request branch')

app="$work/app"
git_quiet init "$app"

# expect <name> <pin> <expected-exit>
expect() {
  local name="$1" pin="$2" expected="$3"
  git_quiet -C "$app" update-index --add --cacheinfo "160000,${pin},sdk"
  git_quiet -C "$app" commit -m "pin: $name"

  local status
  (cd "$app" && SDK_REMOTE="$sdk" "$subject" sdk > /dev/null 2>&1)
  status=$?

  if [ "$status" -eq "$expected" ]; then
    printf '  ok    %s\n' "$name"
  else
    printf '  FAIL  %s: expected exit %d, got %d\n' \
      "$name" "$expected" "$status" >&2
    failures=$((failures + 1))
  fi
}

expect 'a pin on dev passes' "$on_dev" 0
expect 'a pin on a release branch passes' "$on_release" 0
expect 'a pin only a pull-request branch carries fails' "$pending" 1

if [ "$failures" -ne 0 ]; then
  printf '%d check(s) failed\n' "$failures" >&2
  exit 1
fi
