#!/usr/bin/env bash
#
# Fails when the commit this checkout pins for the SDK is on none of the SDK's
# long-lived branches: dev, main, or a release branch named release-X.Y.Z or
# release/X.Y.Z.
#
# A pin only a pull-request branch carries stops resolving once that branch is
# deleted, and every later checkout of the app commit then fails to fetch its
# SDK. Repin to the merged SDK commit before merging.
#
# Usage: check_sdk_pin_merged.sh [sdk-path]
# SDK_REMOTE overrides the SDK remote, which defaults to the .gitmodules URL.
# Exits 0 when the pin is merged, 1 when it is not, and 2 when the check
# cannot run.

set -euo pipefail

sdk_path="${1:-sdk}"
pin=$(git rev-parse "HEAD:${sdk_path}")
remote="${SDK_REMOTE:-$(git config -f .gitmodules --get "submodule.${sdk_path}.url" || true)}"
if [ -z "$remote" ]; then
  echo "::error::No SDK remote: .gitmodules has no URL for ${sdk_path}, and SDK_REMOTE is unset."
  exit 2
fi

# Exact names only: a pull-request branch such as release-candidate/fix never
# counts.
readonly long_lived='^refs/heads/(dev|main|release[-/][0-9]+(\.[0-9]+)*)$'

if ! heads=$(git ls-remote --heads -- "$remote"); then
  echo "::error::Could not list the SDK's branches at ${remote}."
  exit 2
fi
branches=()
while read -r _ ref; do
  if [[ "$ref" =~ $long_lived ]]; then
    branches+=("$ref")
  fi
done <<< "$heads"
if [ "${#branches[@]}" -eq 0 ]; then
  echo "::error::The SDK at ${remote} has no dev, main or release branch."
  exit 2
fi

history=$(mktemp -d)
trap 'rm -rf "$history"' EXIT
git init --quiet --bare "$history"

refspecs=()
for branch in "${branches[@]}"; do
  refspecs+=("+${branch}:${branch}")
done
# Commits and trees only: enough to walk ancestry without the files.
if ! git -C "$history" fetch --quiet --no-tags --filter=blob:none \
  -- "$remote" "${refspecs[@]}"; then
  echo "::error::Could not fetch the SDK's branches from ${remote}."
  exit 2
fi

for branch in "${branches[@]}"; do
  # A pin no fetched branch reaches fails, even though this partial clone may
  # fetch the commit itself to answer.
  if git -C "$history" merge-base --is-ancestor "$pin" "$branch" 2>/dev/null; then
    echo "The SDK pin ${pin} is on ${branch#refs/heads/}."
    exit 0
  fi
done

echo "::error::The SDK pin ${pin} is on none of the SDK's dev, main or release branches. Repin to the merged SDK commit before merging."
exit 1
