#!/usr/bin/env bash
#
# Print the URL a Firebase Hosting deploy actually published, read out of the
# CLI's own output.
#
#   hosting_deploy_url.sh <path-to-firebase-cli-log> [auto|live|preview]
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
# A preview deploy emits both forms. The caller can require the expected kind;
# missing or ambiguous output is unverifiable and must never be guessed.

set -uo pipefail

log_path="${1:-}"
if [ -z "$log_path" ] || [ "$#" -gt 2 ]; then
  echo "usage: $0 <path-to-firebase-cli-log> [auto|live|preview]" >&2
  exit 2
fi
if [ ! -f "$log_path" ]; then
  echo "no such log file: $log_path" >&2
  exit 2
fi

# Treat this output as a CI output boundary: only complete Firebase host URLs
# from canonical success lines are publishable, never provider response bodies.
python3 - "$log_path" "${2:-auto}" <<'PYURL'
from pathlib import Path
import re
import sys

mode = sys.argv[2]
if mode not in {"auto", "live", "preview"}:
    sys.exit(2)

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
live_prefix = re.compile(r"^[ \t]*Hosting URL:")
preview_prefix = re.compile(
    r"^[ \t]*(?:[+✔✓][ \t]+)?hosting:channel:[ \t]+Channel URL\b"
)
allowed = re.compile(r"https://[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.web\.app/?")
live_urls = set()
preview_urls = set()
for raw in text.split("\n"):
    line = ansi.sub("", raw)
    preview_match = preview.fullmatch(line)
    match = preview_match or live.fullmatch(line)
    if not match:
        if live_prefix.match(line) or preview_prefix.match(line):
            sys.exit(1)
        continue
    if any(ord(c) < 32 and c != "\t" for c in line):
        sys.exit(1)
    url = match[1]
    if not allowed.fullmatch(url):
        sys.exit(1)
    (preview_urls if preview_match else live_urls).add(url)

# A preview deploy also reports its parent site's ordinary Hosting URL.
# Publish only the unique channel URL when present; conflicting channels must
# never fall back to the live site or be resolved by output order.
if mode == "preview":
    urls = preview_urls
elif mode == "live":
    urls = live_urls
else:
    urls = preview_urls or live_urls
if len(urls) != 1:
    sys.exit(1)
print(urls.pop())
PYURL
