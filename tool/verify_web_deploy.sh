#!/usr/bin/env bash
#
# Verify that a deployed Gleec Wallet web build carries the fiat on-ramp
# hardening, by asking the deployed site itself.
#
# Needs nothing but curl -- no Firebase credentials and no console access -- so
# whoever runs the production deploy can confirm the result without granting
# anyone else access.
#
#   tool/verify_web_deploy.sh https://dex.gleec.com
#   tool/verify_web_deploy.sh https://walletrc.web.app
#
# Exit status is 0 only when every check passes.
#
# Two independent things are checked, because they ship through different
# mechanisms and can land separately:
#
#   1. The wrapper asset (build output). Travels with the Flutter build, so it
#      is correct regardless of which Firebase site or firebase.json was used.
#      This is the check that matters: it is the actual vulnerability fix, and
#      desktop and mobile builds already in users' hands fetch this file from
#      the deployed site at runtime.
#   2. The response headers (firebase.json). These only exist if the deploy
#      used a firebase.json that declares them for the site being deployed, so
#      they are the half that can silently go missing.

set -uo pipefail

BASE_URL="${1:-}"
if [ -z "$BASE_URL" ]; then
  echo "usage: $0 <base-url>    e.g. $0 https://dex.gleec.com" >&2
  exit 2
fi
BASE_URL="${BASE_URL%/}"

WIDGET_PATH="/assets/assets/web_pages/fiat_widget.html"
ATTEMPTS="${VERIFY_ATTEMPTS:-5}"
RETRY_DELAY="${VERIFY_RETRY_DELAY:-10}"
CURL_OPTS=(--silent --show-error --max-time 30 --location
           --header 'Cache-Control: no-cache' --header 'Pragma: no-cache')

failures=0
pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; failures=$((failures + 1)); }

# The CDN keeps a copy for up to an hour, so a check straight after a deploy
# can legitimately still see the previous build. Retry before believing a miss.
fetch_widget() {
  local attempt=1 body
  while :; do
    body=$(curl "${CURL_OPTS[@]}" "${BASE_URL}${WIDGET_PATH}?cachebust=${attempt}-$$" 2>/dev/null)
    if printf '%s' "$body" | grep -q '_komodoApprovedCheckoutUrl'; then
      printf '%s' "$body"
      return 0
    fi
    if [ "$attempt" -ge "$ATTEMPTS" ]; then
      printf '%s' "$body"
      return 1
    fi
    echo "  ..    wrapper not updated yet (attempt ${attempt}/${ATTEMPTS}), retrying in ${RETRY_DELAY}s" >&2
    sleep "$RETRY_DELAY"
    attempt=$((attempt + 1))
  done
}

echo "Verifying ${BASE_URL}"
version=$(curl "${CURL_OPTS[@]}" "${BASE_URL}/version.json" 2>/dev/null)
[ -n "$version" ] && echo "  build: ${version}"
echo

echo "Fiat on-ramp wrapper (${WIDGET_PATH})"
widget=$(fetch_widget)

if [ -z "$widget" ]; then
  fail "could not fetch the wrapper page"
elif ! printf '%s' "$widget" | grep -q '<title>Fiat OnRamp'; then
  # A missing file falls through firebase.json's `**` rewrite to index.html.
  fail "path did not serve the wrapper asset (SPA rewrite or 404?)"
else
  if printf '%s' "$widget" | grep -q '_komodoApprovedCheckoutUrl'; then
    pass "checkout URL allowlist is present"
  else
    fail "checkout URL allowlist is MISSING - this build is unpatched"
  fi

  if printf '%s' "$widget" | grep -q 'targetUrl = atob(urlParam)'; then
    fail "unvalidated atob() -> iframe.src sink is still present"
  else
    pass "no unvalidated atob() -> iframe.src sink"
  fi

  sandbox=$(printf '%s' "$widget" | sed -n 's/.*sandbox="\([^"]*\)".*/\1/p' | head -1)
  if printf ' %s ' "$sandbox" | grep -q ' allow-top-navigation '; then
    fail "iframe sandbox still grants unconditional allow-top-navigation"
  else
    pass "iframe sandbox does not grant unconditional top navigation"
  fi

  if printf '%s' "$widget" | grep -q 'postMessage(messageString, "\*")'; then
    fail "wrapper still broadcasts postMessage with a wildcard target origin"
  else
    pass "postMessage target origin is pinned"
  fi
fi

echo
echo "Response headers (from firebase.json)"
headers=$(curl "${CURL_OPTS[@]}" --output /dev/null --dump-header - "${BASE_URL}/" 2>/dev/null | tr -d '\r')
header_value() { printf '%s' "$headers" | grep -i "^$1:" | head -1 | cut -d' ' -f2-; }

csp=$(header_value 'content-security-policy')
case "$csp" in
  *frame-ancestors*) pass "content-security-policy: ${csp}" ;;
  '')                fail "content-security-policy is missing (no frame-ancestors)" ;;
  *)                 fail "content-security-policy has no frame-ancestors: ${csp}" ;;
esac

for name in x-frame-options x-content-type-options referrer-policy permissions-policy; do
  value=$(header_value "$name")
  if [ -n "$value" ]; then pass "${name}: ${value}"; else fail "${name} is missing"; fi
done

widget_cache=$(curl "${CURL_OPTS[@]}" --output /dev/null --dump-header - \
  "${BASE_URL}${WIDGET_PATH}" 2>/dev/null | tr -d '\r' \
  | grep -i '^cache-control:' | head -1 | cut -d' ' -f2-)
case "$widget_cache" in
  *must-revalidate*) pass "wrapper cache-control: ${widget_cache}" ;;
  '')                fail "wrapper has no cache-control header" ;;
  *)                 fail "wrapper cache-control is '${widget_cache}', not revalidating - a future fix to this file takes up to that long to reach already-shipped desktop and mobile builds" ;;
esac

echo
if [ "$failures" -eq 0 ]; then
  echo "PASS - ${BASE_URL} is serving the hardened build."
  exit 0
fi
echo "FAIL - ${failures} check(s) failed on ${BASE_URL}."
echo
echo "If the wrapper checks failed, the site is running a build from before the"
echo "fix; redeploy it. If only the header checks failed, the deploy used a"
echo "firebase.json that does not declare these headers for this site - see"
echo "docs/WEB_HOSTING_TOPOLOGY.md."
exit 1
