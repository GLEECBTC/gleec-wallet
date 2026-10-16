#!/usr/bin/env bash
# Auto-trust churning local KDF peers for hands-free local app testing.
#
# The browser/native app's KDF libp2p peer id is EPHEMERAL — it changes on every
# reload / re-login / hot restart — so manually trusting a peer doesn't survive.
# This polls the proxy log and marks any peer that fails the healthcheck gate as
# Trusted in redis, so its next (retried) request forwards. LOCAL DEBUG ONLY — it
# blanket-bypasses the proxy's libp2p gate for whoever talks to this local proxy.
#
# Poll-based (not a streaming pipe) to avoid log buffering and `docker compose exec`
# stealing the loop's stdin.
# No `set -e`: a transient `docker compose` hiccup must not kill this long-running daemon.
set -uo pipefail
cd "$(dirname "$0")/.."
echo "auto-trust: polling proxy log for healthcheck 401s every 4s (Ctrl-C to stop)"
while true; do
  # peers that hit the healthcheck gate in the last ~6s (overlaps the 4s sleep)
  # NOTE: the proxy logs "Peer isn't connected to KDF network, returning 401" — match on
  # "returning 401" (any 401 with a real peer), not "not connected" (the text is "isn't").
  peers=$(docker compose logs --since 8s --no-log-prefix proxy 2>&1 \
            | grep "returning 401" \
            | grep -oE "Peer: 12D3[A-Za-z0-9]+" | sed 's/^Peer: //' | sort -u || true)
  for peer in $peers; do
    # only trust if not already trusted (avoids log spam)
    cur=$(docker compose exec -T redis redis-cli HGET status_list "$peer" </dev/null 2>/dev/null || true)
    if [ "$cur" != "0" ]; then
      docker compose exec -T redis redis-cli HSET status_list "$peer" 0 </dev/null >/dev/null 2>&1 \
        && echo "auto-trusted $peer ($(date -u +%H:%M:%S))"
    fi
  done
  sleep 4
done