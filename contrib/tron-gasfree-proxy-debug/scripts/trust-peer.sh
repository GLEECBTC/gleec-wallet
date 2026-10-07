#!/usr/bin/env bash
# Mark a KDF peer as Trusted (or remove it) in the proxy's redis. A Trusted peer
# bypasses the proxy's libp2p validation gate entirely (healthcheck + signature),
# so its requests forward straight to GasFree.
#
# Use this for local app testing when localhost requests are NOT auto-bypassed
# (e.g. this machine presents an X-Forwarded-For / public source IP to the proxy,
# as seen during setup) and the app's KDF isn't meshed with the probe node.
#
# Find the app's peer id in the `flutter run` / KDF console output:
#   "Local peer id: PeerId(\"12D3Koo...\")"
#
# Usage:
#   ./scripts/trust-peer.sh 12D3Koo...        # trust
#   ./scripts/trust-peer.sh -d 12D3Koo...     # untrust (remove)
set -euo pipefail
cd "$(dirname "$0")/.."

if [ "${1:-}" = "-d" ]; then
  peer="${2:?usage: trust-peer.sh -d <peer-id>}"
  docker compose exec -T redis redis-cli HDEL status_list "$peer" >/dev/null
  echo "removed Trusted status for $peer"
else
  peer="${1:?usage: trust-peer.sh <peer-id>   (from the app KDF log: 'Local peer id: PeerId(...)')}"
  docker compose exec -T redis redis-cli HSET status_list "$peer" 0 >/dev/null
  echo "✅ $peer marked Trusted — its requests bypass the proxy validation gate."
  echo "   Undo with: ./scripts/trust-peer.sh -d $peer"
fi