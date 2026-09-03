#!/usr/bin/env bash
#
# Tests for hosting_deploy_url.sh.
#
# The thing under test is a regex over another tool's human-readable output, so
# it can stop matching without anything failing loudly: `details_url` would
# quietly go empty and the PR-comment step would be the first to notice. These
# fixtures pin the two lines the Firebase CLI is relied on to print.

set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
readonly subject="$script_dir/hosting_deploy_url.sh"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

failures=0

# expect <name> <expected-url-or-empty> <log lines...>
expect() {
  local name="$1" expected="$2"
  shift 2

  local log="$work/log.txt"
  printf '%s\n' "$@" > "$log"

  local actual status
  actual=$("$subject" "$log" 2>/dev/null)
  status=$?

  if [ -z "$expected" ]; then
    if [ "$status" -eq 1 ] && [ -z "$actual" ]; then
      printf '  ok    %s\n' "$name"
    else
      printf '  FAIL  %s: expected no URL and exit 1, got %q and exit %d\n' \
        "$name" "$actual" "$status" >&2
      failures=$((failures + 1))
    fi
    return
  fi

  if [ "$status" -eq 0 ] && [ "$actual" = "$expected" ]; then
    printf '  ok    %s\n' "$name"
  else
    printf '  FAIL  %s: expected %q (exit 0), got %q (exit %d)\n' \
      "$name" "$expected" "$actual" "$status" >&2
    failures=$((failures + 1))
  fi
}

echo "hosting_deploy_url.sh"

expect 'live deploy reports the resolved site' \
  'https://walletrc.web.app' \
  '=== Deploy complete!' \
  'Project Console: https://console.firebase.google.com/project/komodo-wallet-official/overview' \
  'Hosting URL: https://walletrc.web.app'

# One target resolves to a different site in each project.
expect 'live deploy to another project reports that project'"'"'s site' \
  'https://gleec-wallet-official.web.app' \
  'Project Console: https://console.firebase.google.com/project/gleec-wallet-official/overview' \
  'Hosting URL: https://gleec-wallet-official.web.app'

expect 'preview channel URL' \
  'https://walletrc--pull-3514-merge-8l82t6ov.web.app' \
  'i  hosting: uploading new files [12/12] complete' \
  '+  hosting:channel: Channel URL (walletrc): https://walletrc--pull-3514-merge-8l82t6ov.web.app [expires 2026-09-03] [version fingerprint abc]'

expect 'colourised output' \
  'https://walletrc--pr-1.web.app' \
  "$(printf '\033[32m+\033[39m  hosting:channel: Channel URL (\033[1mwalletrc\033[22m): https://walletrc--pr-1.web.app [expires 2026-09-03]')"

# --debug is passed on every deploy, so the log is mostly API chatter.
expect 'ignores --debug chatter and the console link' \
  'https://walletrc.web.app' \
  '[debug] [2026-08-27T15:13:00.000Z] >>> [apiv2][query] GET https://firebasehosting.googleapis.com/v1beta1/projects/x/sites' \
  '[debug] Deploy target web resolved to site walletrc' \
  'Project Console: https://console.firebase.google.com/project/x/overview' \
  'Hosting URL: https://walletrc.web.app'

expect 'a log with no published URL yields nothing' \
  '' \
  'i  deploying hosting' \
  'Error: HTTP Error: 404, Requested entity was not found.'

expect 'a custom domain in the log does not win over the deploy URL' \
  'https://walletrc.web.app' \
  'i  hosting: see https://dex.gleec.com for the production site' \
  'Hosting URL: https://walletrc.web.app'

if [ "$failures" -eq 0 ]; then
  echo "PASS"
  exit 0
fi
echo "FAIL - ${failures} case(s)" >&2
exit 1
