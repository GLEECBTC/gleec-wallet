#!/usr/bin/env bash
#
# Print the URL a Firebase Hosting deploy actually published, read out of the
# CLI's own output.
#
#   hosting_deploy_url.sh <path-to-firebase-cli-log>
#
# Exits 0 and prints the URL, or exits 1 and prints nothing.
#
# Why this is not simply "https://$TARGET.web.app":
#
# A deploy target is not a site ID. `.firebaserc` maps one target to a
# different site in each project, which is the whole reason the target exists,
# so a URL built from the target name is only right in whichever project
# happens to have a site of the same name. The CLI knows the resolved site and
# prints it, so ask it rather than guessing:
#
#   live deploy     "Hosting URL: https://<site>.web.app"
#                   firebase-tools lib/deploy/index.js
#   preview channel "hosting:channel: Channel URL (<site>): https://<...>.web.app [expires ...]"
#                   firebase-tools lib/commands/hosting-channel-deploy.js
#
# Both lines are emitted unconditionally on success, so an empty result here
# means the deploy did not publish anything.

set -uo pipefail

log_path="${1:-}"
if [ -z "$log_path" ]; then
  echo "usage: $0 <path-to-firebase-cli-log>" >&2
  exit 2
fi
if [ ! -f "$log_path" ]; then
  echo "no such log file: $log_path" >&2
  exit 2
fi

# The CLI colourises these lines when it thinks it has a terminal, and the
# escapes land in the middle of the URL's own line, so strip them first.
url=$(sed $'s/\033\[[0-9;]*m//g' "$log_path" \
  | sed -n \
      -e 's/.*Hosting URL: *\(https:\/\/[^[:space:]]*\).*/\1/p' \
      -e 's/.*Channel URL[^:]*: *\(https:\/\/[^[:space:]]*\).*/\1/p' \
  | tail -n 1)

if [ -z "$url" ]; then
  exit 1
fi

printf '%s\n' "$url"
