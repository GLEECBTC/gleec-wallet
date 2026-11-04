#!/usr/bin/env bash
#
# Fails when the commit this checkout pins for the SDK is on none of the SDK's
# long-lived branches: dev, main or a release branch.
#
# A pin only a pull-request branch carries stops resolving once that branch is
# deleted, and every later checkout of the app commit then fails to fetch its
# SDK. Repin to the merged SDK commit before merging.
#
# Usage: check_sdk_pin_merged.sh [sdk-path]
# SDK_REMOTE overrides the SDK remote, which defaults to the .gitmodules URL.

set -euo pipefail

sdk_path="${1:-sdk}"
pin=$(git rev-parse "HEAD:${sdk_path}")
remote="${SDK_REMOTE:-$(git config -f .gitmodules "submodule.${sdk_path}.url")}"

history=$(mktemp -d)
trap 'rm -rf "$history"' EXIT
git init --quiet --bare "$history"

# Commits and trees only: enough to walk ancestry without the files.
if ! git -C "$history" fetch --quiet --no-tags --filter=blob:none "$remote" \
  '+refs/heads/dev:refs/heads/dev' \
  '+refs/heads/main:refs/heads/main' \
  '+refs/heads/release-*:refs/heads/release-*'; then
  echo "::error::Could not read the SDK's branches from ${remote}."
  exit 2
fi

while read -r branch; do
  # A pin no fetched branch reaches is not even present here; that fails too.
  if git -C "$history" merge-base --is-ancestor "$pin" "$branch" 2>/dev/null; then
    echo "The SDK pin ${pin} is on ${branch}."
    exit 0
  fi
done < <(git -C "$history" for-each-ref --format='%(refname:short)' refs/heads)

echo "::error::The SDK pin ${pin} is on none of the SDK's dev, main or release branches. Repin to the merged SDK commit before merging."
exit 1
