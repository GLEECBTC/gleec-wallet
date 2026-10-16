#!/usr/bin/env bash
# preLaunchTask for the "gas-free local proxy" VS Code debug profile.
#
# Ensures the full local stack (redis + kdf-probe + kdf-client + proxy + nginx) is up and
# the NGINX edge (http://localhost:6160 — what the app uses) is serving, before the
# Flutter app launches. Idempotent: a no-op if the stack is already running.
set -uo pipefail
cd "$(dirname "$0")/.."

if [ ! -f .env ]; then
  echo "ERROR: $(pwd)/.env is missing." >&2
  echo "  Run:  cp .env.example .env   and set GASFREE_API_KEY / GASFREE_API_SECRET." >&2
  exit 1
fi

echo "[stack-up] docker compose up -d ..."
if ! docker compose up -d; then
  echo "[stack-up] 'docker compose up -d' failed (is Docker running?)." >&2
  exit 1
fi

# Wait for the NGINX edge to serve a real (non-502/504) response — i.e. nginx is up AND
# the proxy behind it is reachable. (HTTP code 000 = connection not yet accepted.)
echo -n "[stack-up] waiting for NGINX edge http://localhost:6160 "
i=0
while :; do
  code=$(curl -s -m 3 -o /dev/null -w '%{http_code}' http://localhost:6160/ 2>/dev/null || echo 000)
  if [ "$code" != "000" ] && [ "$code" != "502" ] && [ "$code" != "504" ]; then
    echo " ready (HTTP $code)."
    break
  fi
  i=$((i + 1))
  if [ "$i" -gt 90 ]; then
    echo " TIMEOUT (last HTTP $code)." >&2
    echo "  Inspect with:  (cd $(pwd) && docker compose logs --tail 30 proxy nginx)" >&2
    exit 1
  fi
  printf '.'
  sleep 2
done

echo "[stack-up] ready — app will use http://localhost:6160/gasfree/tron"
