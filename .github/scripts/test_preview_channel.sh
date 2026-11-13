#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
sha=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
run_case() {
  local name="$1" expected="$2" event="$3" repo="$4" ref="$5" bypass="$6" requested="$7"
  : > "$fixture/output"
  : > "$fixture/summary"
  local status=0
  GITHUB_EVENT_NAME="$event" GITHUB_REPOSITORY="$repo" GITHUB_REF="$ref" \
    GITHUB_SHA="$sha" RC_LEGAL_BYPASS="$bypass" RC_EXPECTED_APP_COMMIT="$requested" \
    GITHUB_OUTPUT="$fixture/output" GITHUB_STEP_SUMMARY="$fixture/summary" \
    bash "$script_dir/preview_channel.sh" > "$fixture/log" 2>&1 || status=$?
  if [ "$expected" = reject ]; then
    [ "$status" -ne 0 ] && [ ! -s "$fixture/output" ] || { cat "$fixture/log"; exit 1; }
  else
    [ "$status" -eq 0 ] || { cat "$fixture/log"; exit 1; }
    diff -u <(printf '%s\n' "$expected") "$fixture/output"
    if [[ "$expected" == *'legal_bypass=true'* ]]; then
      test -s "$fixture/summary"
    else
      test ! -s "$fixture/summary"
    fi
  fi
  printf 'ok: %s\n' "$name"
}

run_case 'ordinary PR retains legal gate' $'preview_channel_id=pull/3561/merge\nlegal_bypass=false' pull_request GLEECBTC/gleec-wallet refs/pull/3561/merge false ''
run_case 'ordinary dev retains legal gate' $'preview_channel_id=heads/dev\nlegal_bypass=false' push GLEECBTC/gleec-wallet refs/heads/dev false ''
run_case 'default manual run retains legal gate' $'preview_channel_id=heads/dev\nlegal_bypass=false' workflow_dispatch GLEECBTC/gleec-wallet refs/heads/dev false ''
run_case 'explicit pinned RC uses isolated channel' $'preview_channel_id=rc-0-10-0-legal-testing\nlegal_bypass=true' workflow_dispatch GLEECBTC/gleec-wallet refs/heads/dev true "$sha"
run_case 'production ref rejected' reject workflow_dispatch GLEECBTC/gleec-wallet refs/heads/main true "$sha"
run_case 'old feature ref rejected' reject workflow_dispatch GLEECBTC/gleec-wallet refs/heads/feat/kdf-667045c true "$sha"
run_case 'fork rejected' reject workflow_dispatch example/gleec-wallet refs/heads/dev true "$sha"
run_case 'automatic event rejected' reject push GLEECBTC/gleec-wallet refs/heads/dev true "$sha"
run_case 'missing pin rejected' reject workflow_dispatch GLEECBTC/gleec-wallet refs/heads/dev true ''
run_case 'abbreviated pin rejected' reject workflow_dispatch GLEECBTC/gleec-wallet refs/heads/dev true aaaaaaa
run_case 'moved head rejected' reject workflow_dispatch GLEECBTC/gleec-wallet refs/heads/dev true bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
