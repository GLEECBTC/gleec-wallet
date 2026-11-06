#!/usr/bin/env bash
set -euo pipefail

# Manual, exact-revision exception for the 0.10.0 testing period. Keep it off
# the ordinary PR/dev channels so subsequent builds cannot silently replace it.
channel_id="${GITHUB_REF#*/}"
legal_bypass=false
if [ "${RC_LEGAL_BYPASS:-false}" = "true" ]; then
  if [ "$GITHUB_EVENT_NAME" != "workflow_dispatch" ] ||
     [ "$GITHUB_REPOSITORY" != "GLEECBTC/gleec-wallet" ] ||
     [ "$GITHUB_REF" != "refs/heads/dev" ] ||
     ! [[ "${RC_EXPECTED_APP_COMMIT:-}" =~ ^[0-9a-f]{40}$ ]] ||
     [ "$RC_EXPECTED_APP_COMMIT" != "$GITHUB_SHA" ]; then
    echo "RC legal bypass requires a manual GLEECBTC/gleec-wallet dev run and its exact 40-character commit." >&2
    exit 1
  fi
  channel_id="rc-0-10-0-legal-testing"
  legal_bypass=true
  echo "RC testing only: legal availability bypass enabled. Missing terms remain visible and cannot be recorded as accepted." >> "$GITHUB_STEP_SUMMARY"
fi
printf 'preview_channel_id=%s\nlegal_bypass=%s\n' "$channel_id" "$legal_bypass" >> "$GITHUB_OUTPUT"
