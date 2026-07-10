#!/usr/bin/env bash
set -euo pipefail

WALLET_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
KDF_WORKTREE="${KDF_WORKTREE:-/Users/charl/Code/Gleec/kdf-gnosis-card-local}"

case "$(uname -s)" in
  Darwin)
    LIBRARY_NAME="libkdflib.dylib"
    ;;
  Linux)
    LIBRARY_NAME="libkdflib.so"
    ;;
  *)
    echo "The local dynamic-library harness currently supports macOS and Linux." >&2
    exit 2
    ;;
esac

LINK_PATH="$WALLET_ROOT/$LIBRARY_NAME"
ARTIFACT="$KDF_WORKTREE/target/release/$LIBRARY_NAME"

if [[ "${REMOVE:-0}" == "1" ]]; then
  rm -f "$LINK_PATH"
  echo "Removed $LINK_PATH"
  exit 0
fi

if [[ "${LINK_ONLY:-0}" != "1" ]]; then
  (
    cd "$KDF_WORKTREE"
    cargo build --release -p mm2_bin_lib --lib
  )
fi

if [[ ! -f "$ARTIFACT" ]]; then
  echo "Local KDF library not found at $ARTIFACT" >&2
  exit 3
fi

ln -sfn "$ARTIFACT" "$LINK_PATH"
echo "Linked local KDF $ARTIFACT at $LINK_PATH"
