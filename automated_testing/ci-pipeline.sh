#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Gleec QA Automation — CI Pipeline
# =============================================================================
# Exit codes:
#   0 = all tests passed
#   1 = test failures or errors
#   2 = pre-flight / infrastructure failure
#   3 = all passed but some flaky
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

MATRIX="${MATRIX:-test_matrix.yaml}"
ARTIFACTS_DIR="${CI_ARTIFACTS_DIR:-results}"

echo "=== Gleec QA CI Pipeline ==="
mkdir -p "$ARTIFACTS_DIR"

# ---------------------------------------------------------------------------
# Infrastructure
# ---------------------------------------------------------------------------
echo "[infra] Verifying Ollama..."
if ! curl -sf http://localhost:11434/api/tags > /dev/null 2>&1; then
    echo "[infra] Starting Ollama..."
    ollama serve &
    sleep 5
fi

echo "[infra] Starting Docker stack..."
docker compose up -d
sleep 10

# ---------------------------------------------------------------------------
# Smoke gate (fast, blocks deployment on failure)
# ---------------------------------------------------------------------------
echo "[smoke] Running smoke gate..."
if python -m runner.runner --matrix "$MATRIX" --tag smoke --single; then
    SMOKE_EXIT=0
else
    SMOKE_EXIT=$?
fi

if [ $SMOKE_EXIT -eq 2 ]; then
    echo "[smoke] INFRASTRUCTURE FAILURE — aborting pipeline"
    exit 2
fi

if [ $SMOKE_EXIT -eq 1 ]; then
    echo "[smoke] SMOKE GATE FAILED — blocking deployment"
    # Copy whatever reports exist
    cp results/run_*/report.html "$ARTIFACTS_DIR/" 2>/dev/null || true
    exit 1
fi

echo "[smoke] Smoke gate passed (exit=$SMOKE_EXIT)"

# ---------------------------------------------------------------------------
# Full suite (with retries and majority vote)
# ---------------------------------------------------------------------------
echo "[full] Running full automated suite..."
if python -m runner.runner --matrix "$MATRIX"; then
    FULL_EXIT=0
else
    FULL_EXIT=$?
fi

# ---------------------------------------------------------------------------
# Collect artifacts
# ---------------------------------------------------------------------------
echo "[artifacts] Collecting reports..."
LATEST_RUN=$(ls -td results/run_* 2>/dev/null | head -1)
if [ -n "$LATEST_RUN" ]; then
    cp "$LATEST_RUN/report.html" "$ARTIFACTS_DIR/" 2>/dev/null || true
    cp "$LATEST_RUN/results.json" "$ARTIFACTS_DIR/" 2>/dev/null || true
fi

echo "[done] Pipeline complete (exit=$FULL_EXIT)"
exit $FULL_EXIT
