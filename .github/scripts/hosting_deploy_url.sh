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

# Treat this output as a CI output boundary: only complete Firebase host URLs
# from canonical success lines are publishable, never provider response bodies.
python3 - "$log_path" <<'PYURL'
from pathlib import Path
import re
import sys

try:
    text = Path(sys.argv[1]).read_bytes().decode("utf-8", errors="replace")
except OSError:
    sys.exit(2)

ansi = re.compile(r"\x1b\[[0-9;]*m")
live = re.compile(r"^[ \t]*Hosting URL:[ \t]+(https://[^ \t]+)[ \t]*$")
preview = re.compile(
    r"^[ \t]*(?:[+✔✓][ \t]+)?hosting:channel:[ \t]+"
    r"Channel URL \([^)]*\):[ \t]+(https://[^ \t]+)"
    r"(?:[ \t]+\[(?:expires|version) [^]\r\n]*\])*[ \t]*$"
)
allowed = re.compile(r"https://[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.web\.app/?")
urls = set()
for raw in text.split("\n"):
    line = ansi.sub("", raw)
    match = live.fullmatch(line) or preview.fullmatch(line)
    if not match:
        continue
    if any(ord(c) < 32 and c != "\t" for c in line):
        sys.exit(1)
    url = match[1]
    if not allowed.fullmatch(url):
        sys.exit(1)
    urls.add(url)

if len(urls) != 1:
    sys.exit(1)
print(urls.pop())
PYURL
