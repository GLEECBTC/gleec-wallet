#!/usr/bin/env bash
#
# Tests for check_sdk_pin_merged.sh against local repositories: a pin on dev,
# main or a release branch passes; one only a pull-request branch carries, or
# one the SDK lacks, fails; and a check that cannot reach the SDK says so with
# its own exit code.

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

# commit <repo> <message>: an empty commit on the checked-out branch.
commit() {
  git_quiet -C "$1" commit --allow-empty -m "$2"
  git -C "$1" rev-parse HEAD
}

sdk="$work/sdk"
git_quiet init "$sdk"
on_dev=$(commit "$sdk" 'on dev')
git_quiet -C "$sdk" checkout -b main
on_main=$(commit "$sdk" 'only on main')
git_quiet -C "$sdk" checkout -b release-0.9.0 dev
on_release=$(commit "$sdk" 'on the release branch')
git_quiet -C "$sdk" checkout -b release/0.7.0 dev
on_old_release=$(commit "$sdk" 'on an older release branch')
git_quiet -C "$sdk" checkout -b fix/pending dev
pending=$(commit "$sdk" 'only on a pull-request branch')
git_quiet -C "$sdk" checkout -b release-candidate/fix dev
lookalike=$(commit "$sdk" 'only on a branch named like a release')

# An SDK with dev and nothing else.
dev_only="$work/dev-only"
git_quiet init "$dev_only"
dev_only_pin=$(commit "$dev_only" 'on dev')

# A commit no SDK has.
stray="$work/stray"
git_quiet init "$stray"
unknown=$(commit "$stray" 'in another repository')

app="$work/app"
git_quiet init "$app"

# expect <name> <pin> <expected-exit> [remote]
# Without a remote, SDK_REMOTE is unset and the app's .gitmodules decides.
expect() {
  local name="$1" pin="$2" expected="$3"
  git_quiet -C "$app" update-index --add --cacheinfo "160000,${pin},sdk"
  git_quiet -C "$app" commit -m "pin: $name"

  local status
  if [ "$#" -ge 4 ]; then
    (cd "$app" && SDK_REMOTE="$4" "$subject" sdk > /dev/null 2>&1)
  else
    (cd "$app" && unset SDK_REMOTE && "$subject" sdk > /dev/null 2>&1)
  fi
  status=$?

  if [ "$status" -eq "$expected" ]; then
    printf '  ok    %s\n' "$name"
  else
    printf '  FAIL  %s: expected exit %d, got %d\n' \
      "$name" "$expected" "$status" >&2
    failures=$((failures + 1))
  fi
}

expect 'a pin on dev passes' "$on_dev" 0 "$sdk"
expect 'a pin on main passes' "$on_main" 0 "$sdk"
expect 'a pin on a release branch passes' "$on_release" 0 "$sdk"
expect 'a pin on an older release/ branch passes' "$on_old_release" 0 "$sdk"
expect 'a pin only a pull-request branch carries fails' "$pending" 1 "$sdk"
expect 'a branch named like a release does not count' "$lookalike" 1 "$sdk"
expect 'a pin the SDK does not have fails' "$unknown" 1 "$sdk"
expect 'an SDK without main still answers' "$dev_only_pin" 0 "$dev_only"
expect 'an unreachable SDK cannot be checked' "$on_dev" 2 "$work/missing"
expect 'no SDK remote cannot be checked' "$on_dev" 2

printf '[submodule "sdk"]\n\tpath = sdk\n\turl = %s\n' "$sdk" \
  > "$app/.gitmodules"
expect 'the .gitmodules URL is the default remote' "$on_dev" 0

if [ "$failures" -ne 0 ]; then
  printf '%d check(s) failed\n' "$failures" >&2
  exit 1
fi
