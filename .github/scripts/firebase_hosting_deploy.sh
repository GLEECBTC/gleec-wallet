#!/usr/bin/env bash
# Keep Firebase API bodies and credentials out of Actions logs/artifacts.
set +x
set -euo pipefail
umask 077

project_config="$PWD/firebase.json"
if [ ! -f "$project_config" ]; then
  echo "Firebase Hosting configuration is missing."
  exit 1
fi

# firebase-tools 15.22.3 always writes a debug log in its working directory,
# including without --debug. Absolute --config keeps project paths/targets
# rooted at the checkout while all run-owned logs stay in this private folder.
work_dir=$(mktemp -d "$RUNNER_TEMP/firebase-hosting.XXXXXXXX")
cleanup() { rm -rf -- "$work_dir"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

credentials_file="$work_dir/service-account.json"
deploy_log="$work_dir/deploy.log"

printf '%s' "$FIREBASE_SERVICE_ACCOUNT" > "$credentials_file"
unset FIREBASE_SERVICE_ACCOUNT DEBUG
export XDG_CONFIG_HOME="$work_dir/config"
export npm_config_logs_dir="$work_dir/npm-logs"

if ! jq -e 'type == "object"' "$credentials_file" >/dev/null 2>&1; then
  echo "Firebase service account secret is not valid JSON."
  exit 1
fi

export GOOGLE_APPLICATION_CREDENTIALS="$credentials_file"
export FIREBASE_DEPLOY_AGENT="action-hosting-deploy"

if [ "$CHANNEL_ID" = "live" ]; then
  if [ -n "$TARGET" ]; then
    deploy_args=(deploy --only "hosting:$TARGET")
  else
    deploy_args=(deploy --only hosting)
  fi
  is_preview=false
else
  safe_channel_id=$(printf '%s' "$CHANNEL_ID" | sed 's/[^A-Za-z0-9_.-]/_/g')
  if [ "$safe_channel_id" != "$CHANNEL_ID" ]; then
    echo "Channel ID normalized for Firebase Hosting."
  fi

  deploy_args=(hosting:channel:deploy "$safe_channel_id")
  if [ -n "$TARGET" ]; then
    deploy_args+=(--only "$TARGET")
  fi
  if [ -n "$EXPIRES" ]; then
    deploy_args+=(--expires "$EXPIRES")
  fi
  is_preview=true
fi

deploy_args+=(--project "$PROJECT_ID" --config "$project_config" --non-interactive)

# Firebase Hosting's REST API intermittently drops the connection
# ("premature close error") *after* the server has already actioned a
# request. firebase-tools then retries the call; for the non-idempotent
# channel create this comes back 409 ALREADY_EXISTS and fails the deploy
# even though the channel was created. Re-running hosting:channel:deploy
# is safe -- the existing channel is reused and the version is uploaded
# normally -- so retry these transient failures before giving up.
max_attempts=3
attempt=1
while :; do
  set +e
  (cd "$work_dir" && npx --yes "firebase-tools@$FIREBASE_TOOLS_VERSION" "${deploy_args[@]}") >"$deploy_log" 2>&1
  deploy_status=$?
  set -e

  if [ "$deploy_status" -eq 0 ]; then
    break
  fi

  # The deployed version already being the current active version is
  # not an error -- the served content is already up to date, so
  # Firebase refuses to re-release the identical version with
  # FAILED_PRECONDITION. This applies to live deploys (unchanged web
  # build pushed to `dev`/`main`) as well as preview channels, so it is
  # intentionally NOT gated on is_preview.
  if grep -q "supplied version" "$deploy_log" \
    && grep -q "current active version" "$deploy_log"; then
    echo "Firebase CLI reported the deployed version is already the current active version; treating deploy as successful."
    deploy_status=0
    break
  fi

  # Retry the transient channel/connection failures described above.
  if [ "$attempt" -lt "$max_attempts" ] \
    && grep -qiE "already exists|premature close|ECONNRESET|socket hang up|EAI_AGAIN" "$deploy_log"; then
    echo "Transient Firebase Hosting error on attempt ${attempt}/${max_attempts}; retrying in $((attempt * 10))s..."
    sleep "$((attempt * 10))"
    attempt=$((attempt + 1))
    continue
  fi

  echo "Firebase Hosting deployment failed; provider output was withheld for privacy."
  exit "$deploy_status"
done

# Read the deployed URL out of what the CLI actually did, rather than
# building it from the target name -- a deploy target is not a site ID.
# See the script for why, and .github/scripts/test_hosting_deploy_url.sh
# for the output formats it depends on.
url_mode=live
if [ "$is_preview" = "true" ]; then
  url_mode=preview
fi
if ! details_url=$("$URL_READER" "$deploy_log" "$url_mode" 2>/dev/null); then
  echo "Deploy succeeded but no URL was found in the Firebase CLI output."
  details_url=""
  if [ "$is_preview" = "true" ]; then
    # The preview URL is consumed downstream to comment on the PR, so a
    # missing one is a failure rather than a cosmetic gap.
    exit 1
  fi
fi

echo "details_url=$details_url" >> "$GITHUB_OUTPUT"
echo "Firebase Hosting deployment completed."
