#!/usr/bin/env bash
#
# Tests for check_kdf_pin_releasable.sh: kdf-internal branches pass, local-only
# and scratch builds fail, and an unreadable configuration has its own exit code.

set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
readonly subject="$script_dir/check_kdf_pin_releasable.sh"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

failures=0

# expect <exit-code> <description> <config-json>
expect() {
  printf '%s' "$3" > "$work/build_config.json"
  "$subject" "$work/build_config.json" > /dev/null 2>&1
  local actual=$?
  if [ "$actual" -ne "$1" ]; then
    echo "FAIL: $2 (exit $actual, expected $1)"
    failures=$((failures + 1))
  else
    echo "ok: $2"
  fi
}

readonly commit=46769c4df3b043669eee59508bf1af017157dcdd

expect 0 'main ships' "{\"api\":{\"branch\":\"main\",\"api_commit_hash\":\"$commit\"}}"
expect 0 'dev ships' "{\"api\":{\"branch\":\"dev\",\"api_commit_hash\":\"$commit\"}}"
expect 0 'a feature branch ships' "{\"api\":{\"branch\":\"feat/lifi-integration\",\"api_commit_hash\":\"$commit\"}}"
expect 1 'a local-only build does not' "{\"api\":{\"branch\":\"local/solana-combined\",\"api_commit_hash\":\"$commit\"}}"
expect 1 'a charl-temp scratch branch does not' "{\"api\":{\"branch\":\"charl-temp/solana-combined\",\"api_commit_hash\":\"$commit\"}}"
expect 0 'a name merely containing charl-temp ships' "{\"api\":{\"branch\":\"feat/charl-temp-notes\",\"api_commit_hash\":\"$commit\"}}"
expect 2 'a missing branch cannot be checked' "{\"api\":{\"api_commit_hash\":\"$commit\"}}"
expect 2 'a non-string branch cannot be checked' "{\"api\":{\"branch\":7,\"api_commit_hash\":\"$commit\"}}"
expect 2 'malformed JSON cannot be checked' '{"api":'

if [ "$failures" -ne 0 ]; then
  echo "$failures test(s) failed"
  exit 1
fi
