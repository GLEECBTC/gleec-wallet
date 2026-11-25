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
# The wrapper asset and the response headers are checked separately, because
# they ship through different mechanisms and can land apart: the asset travels
# with the Flutter build and is the actual fix, while the headers exist only if
# the deploy used a firebase.json that declares them for this site.

set -uo pipefail

BASE_URL="${1:-}"
if [ -z "$BASE_URL" ]; then
  echo "usage: $0 <base-url>    e.g. $0 https://dex.gleec.com" >&2
  exit 2
fi
BASE_URL="${BASE_URL%/}"

WIDGET_PATH="/assets/assets/web_pages/fiat_widget.html"
# The site's CSP allows no inline script, so the wrapper page loads its
# validation from this sibling file and that is where the checks have to look.
WIDGET_SCRIPT_PATH="${WIDGET_PATH%/*}/fiat_widget.js"
SCRIPT_TAG="<script[^>]*[[:space:]]src=[\"'](\\./)?fiat_widget\\.js[\"']"
ATTEMPTS="${VERIFY_ATTEMPTS:-5}"
RETRY_DELAY="${VERIFY_RETRY_DELAY:-10}"
CURL_OPTS=(--silent --show-error --max-time 30 --location
           --header 'Cache-Control: no-cache' --header 'Pragma: no-cache')

CURL_ERR=$(mktemp)
trap 'rm -f "$CURL_ERR"' EXIT

failures=0
pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; failures=$((failures + 1)); }

# The CDN keeps a copy for up to an hour, so a check straight after a deploy
# can legitimately still see the previous build. Retry before believing a miss.
#
# fetch_asset <path> <marker>: the body is current once it matches <marker>.
fetch_asset() {
  local path="$1" marker="$2" attempt=1 body
  while :; do
    body=$(curl "${CURL_OPTS[@]}" "${BASE_URL}${path}?cachebust=${attempt}-$$" 2>/dev/null)
    if printf '%s' "$body" | grep -qE -- "$marker"; then
      printf '%s' "$body"
      return 0
    fi
    if [ "$attempt" -ge "$ATTEMPTS" ]; then
      printf '%s' "$body"
      return 1
    fi
    echo "  ..    ${path##*/} not updated yet (attempt ${attempt}/${ATTEMPTS}), retrying in ${RETRY_DELAY}s" >&2
    sleep "$RETRY_DELAY"
    attempt=$((attempt + 1))
  done
}

# A script path answering with markup is the `**` rewrite standing in for a
# file the build does not have.
is_markup() {
  case "${1#"${1%%[![:space:]]*}"}" in
    '<'*) return 0 ;;
    *)    return 1 ;;
  esac
}

# Headers belong to the version being served, so the request has to reach the
# origin rather than an edge copy of the previous one -- hence the cache-bust,
# for the same reason the body probe has one.
fetch_headers() {
  local attempt=1 out
  while :; do
    out=$(curl "${CURL_OPTS[@]}" --output /dev/null --dump-header - \
      "${BASE_URL}${1}?cachebust=headers-${attempt}-$$" 2>"$CURL_ERR" | tr -d '\r')
    if [ -n "$out" ]; then
      printf '%s' "$out"
      return 0
    fi
    if [ "$attempt" -ge "$ATTEMPTS" ]; then
      return 1
    fi
    echo "  ..    no response for ${1} (attempt ${attempt}/${ATTEMPTS}): $(tr -d '\n' <"$CURL_ERR")" >&2
    sleep "$RETRY_DELAY"
    attempt=$((attempt + 1))
  done
}

echo "Verifying ${BASE_URL}"
version=$(curl "${CURL_OPTS[@]}" "${BASE_URL}/version.json" 2>/dev/null)
[ -n "$version" ] && echo "  build: ${version}"
echo

echo "Fiat on-ramp wrapper (${WIDGET_PATH})"
widget=$(fetch_asset "$WIDGET_PATH" "$SCRIPT_TAG")
script=""

if [ -z "$widget" ]; then
  fail "could not fetch the wrapper page"
elif ! printf '%s' "$widget" | grep -q '<title>Fiat OnRamp'; then
  # A missing file falls through firebase.json's `**` rewrite to index.html.
  fail "path did not serve the wrapper asset (SPA rewrite or 404?)"
else
  # Without this the page would run none of the script inspected below, and
  # those checks would pass on a file nothing loads.
  if ! printf '%s' "$widget" | grep -qE -- "$SCRIPT_TAG"; then
    fail "wrapper page does not load ${WIDGET_SCRIPT_PATH##*/} - its checkout validation cannot be verified"
  else
    pass "wrapper page loads ${WIDGET_SCRIPT_PATH##*/}"
    script=$(fetch_asset "$WIDGET_SCRIPT_PATH" '_komodoApprovedCheckoutUrl')
    if [ -z "$script" ]; then
      fail "could not fetch the wrapper script (${WIDGET_SCRIPT_PATH})"
    elif is_markup "$script"; then
      fail "${WIDGET_SCRIPT_PATH} did not serve the wrapper script (SPA rewrite or 404?)"
      script=""
    elif printf '%s' "$script" | grep -q '_komodoApprovedCheckoutUrl'; then
      pass "checkout URL allowlist is present"
    else
      fail "checkout URL allowlist is MISSING - this build is unpatched"
    fi
  fi

  # The page as well as its script, so inline script coming back is inspected.
  # Neither sink check reports a pass unless the script itself was read.
  wrapper_source=$(printf '%s\n%s' "$widget" "$script")

  if printf '%s' "$wrapper_source" | grep -q 'targetUrl = atob(urlParam)'; then
    fail "unvalidated atob() -> iframe.src sink is still present"
  elif [ -n "$script" ]; then
    pass "no unvalidated atob() -> iframe.src sink"
  fi

  sandbox=$(printf '%s' "$widget" | sed -n 's/.*sandbox="\([^"]*\)".*/\1/p' | head -1)
  if printf ' %s ' "$sandbox" | grep -q ' allow-top-navigation '; then
    fail "iframe sandbox still grants unconditional allow-top-navigation"
  else
    pass "iframe sandbox does not grant unconditional top navigation"
  fi

  if printf '%s' "$wrapper_source" | grep -qE "postMessage\([^)]*,[[:space:]]*['\"]\*['\"]"; then
    fail "wrapper still broadcasts postMessage with a wildcard target origin"
  elif [ -n "$script" ]; then
    pass "postMessage target origin is pinned"
  fi
fi

echo
echo "Response headers (from firebase.json)"
header_value() { printf '%s' "$headers" | grep -i "^$1:" | head -1 | sed 's/^[^:]*: *//'; }

if ! headers=$(fetch_headers "/"); then
  # One transport failure, reported once, rather than as five absent headers.
  fail "could not read response headers from ${BASE_URL}/ - $(tr -d '\n' <"$CURL_ERR")"
else
  csp=$(header_value 'content-security-policy')
  case "$csp" in
    # The verifier and test_units/.../fiat_checkout_url_allowlist_test.dart
    # both require the directive AND its value: `frame-ancestors *` keeps the
    # header in place while removing what it is here for.
    *"frame-ancestors 'self'"*) pass "content-security-policy: ${csp}" ;;
    '')                fail "content-security-policy is missing" ;;
    *)                 fail "content-security-policy does not set frame-ancestors 'self': ${csp}" ;;
  esac

  xfo=$(header_value 'x-frame-options')
  case "$xfo" in
    SAMEORIGIN|DENY) pass "x-frame-options: ${xfo}" ;;
    '')              fail "x-frame-options is missing" ;;
    *)               fail "x-frame-options is '${xfo}', which does not prevent framing" ;;
  esac

  xcto=$(header_value 'x-content-type-options')
  case "$xcto" in
    nosniff) pass "x-content-type-options: ${xcto}" ;;
    '')      fail "x-content-type-options is missing" ;;
    *)       fail "x-content-type-options is '${xcto}', not nosniff" ;;
  esac

  for name in referrer-policy permissions-policy; do
    value=$(header_value "$name")
    if [ -n "$value" ]; then pass "${name}: ${value}"; else fail "${name} is missing"; fi
  done
fi

for asset in "$WIDGET_PATH" "$WIDGET_SCRIPT_PATH"; do
  name="${asset##*/}"
  if ! asset_headers=$(fetch_headers "$asset"); then
    fail "could not read response headers from ${BASE_URL}${asset} - $(tr -d '\n' <"$CURL_ERR")"
    continue
  fi
  asset_cache=$(printf '%s' "$asset_headers" \
    | grep -i '^cache-control:' | head -1 | sed 's/^[^:]*: *//')
  case "$asset_cache" in
    *must-revalidate*) pass "${name} cache-control: ${asset_cache}" ;;
    '')                fail "${name} has no cache-control header" ;;
    *)                 fail "${name} cache-control is '${asset_cache}', not revalidating - a future fix to this file takes up to that long to reach already-shipped desktop and mobile builds" ;;
  esac
done

echo
if [ "$failures" -eq 0 ]; then
  echo "PASS - ${BASE_URL} is serving the hardened build."
  exit 0
fi
echo "FAIL - ${failures} check(s) failed on ${BASE_URL}."
echo
echo "If the wrapper checks failed, the site is running a build from before the"
echo "fix; redeploy it. If only the header checks failed, the deploy did not use"
echo "this repository's hosting config - either it ran from a different checkout,"
echo "or the deploy target resolved somewhere other than this site. See"
echo "docs/WEB_HOSTING_TOPOLOGY.md."
exit 1
