#!/usr/bin/env bash
#
# Repeatable web frame-jank benchmark for the post-login activation storm.
#
# Every entry in the change ledger in docs/WEB_JANK_MEASUREMENT_REPORT.md is
# produced by this script, so that "before" and "after" are the same
# measurement and not two similar-looking ones.
#
#   tool/bench_web_jank.sh <label> [runs]
#
# Results are archived per label under build/bench/<label>/run-N.json, and the
# medians are printed. Compare two labels with --compare:
#
#   tool/bench_web_jank.sh --compare baseline a2-balance-guard
#
# Three deliberate choices:
#
#   * `fvm flutter drive`, not `run_integration_tests.dart`. The runner invokes
#     bare `flutter` from PATH while .fvmrc pins a different version, which
#     fails inside flutter_test with a `_TestFlutterView` error that looks like
#     a code bug. The runner also hardcodes its dart-defines with no passthrough
#     and cannot pass PERF_LOGIN_ACTIVATION.
#   * The artifact is checked, not the exit code. The runner has been observed
#     exiting 0 on a run whose build failed outright.
#   * Median, not mean. One scheduling hiccup moves a mean of three.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

BENCH_DIR="build/bench"
DRIVER_PORT="${DRIVER_PORT:-4444}"

median_report() {
  python3 - "$1" <<'PY'
import json, os, statistics, sys

label = sys.argv[1]
d = os.path.join("build", "bench", label)
runs = []
for name in sorted(os.listdir(d)):
    if not name.endswith(".json"):
        continue
    with open(os.path.join(d, name)) as fh:
        doc = json.load(fh)
    for run in doc.get("runs", []):
        if run["flow"] == "login_activation_storm":
            runs.append(run["metrics"])

if not runs:
    print(f"  {label}: no login_activation_storm runs found")
    sys.exit(1)

# gap_p50 is the gate: idle cannot move it, so it answers "when the app
# painted, did it paint on time". yield is reported but never gated on - a
# window containing genuine idle has a low yield and no jank at all.
keys = [
    "gap_p50_ms", "gap_p90_ms", "gap_worst_ms",
    "yield_pct", "effective_fps", "stall_pct",
    "frame_count", "span_ms", "ui_total_ms", "raster_total_ms",
    "jank_ratio_pct",
]
print(f"  {label}  (n={len(runs)})")
out = {}
for k in keys:
    vals = [r[k] for r in runs if k in r]
    if not vals:
        continue
    out[k] = statistics.median(vals)
    spread = f"{min(vals):.1f}..{max(vals):.1f}" if len(vals) > 1 else "-"
    print(f"    {k:<18} {out[k]:>10.2f}   [{spread}]")
with open(os.path.join(d, "median.json"), "w") as fh:
    json.dump(out, fh, indent=1)
PY
}

if [ "${1:-}" = "--compare" ]; then
  shift
  python3 - "$@" <<'PY'
import json, os, sys

def load(label):
    p = os.path.join("build", "bench", label, "median.json")
    if not os.path.exists(p):
        sys.exit(f"no median for '{label}' - run the benchmark first")
    with open(p) as fh:
        return json.load(fh)

before_label, after_label = sys.argv[1], sys.argv[2]
before, after = load(before_label), load(after_label)

# Lower is better for every gate here.
print(f"{'metric':<18} {before_label:>12} {after_label:>12} {'delta':>10} {'':>8}")
for k in ("gap_p50_ms", "gap_p90_ms", "gap_worst_ms", "stall_pct",
          "yield_pct", "effective_fps", "frame_count", "span_ms"):
    if k not in before or k not in after:
        continue
    b, a = before[k], after[k]
    d = a - b
    pct = (d / b * 100) if b else 0.0
    print(f"{k:<18} {b:>12.2f} {a:>12.2f} {d:>+10.2f} {pct:>+7.1f}%")
PY
  exit 0
fi

LABEL="${1:?usage: tool/bench_web_jank.sh <label> [runs]}"
RUNS="${2:-3}"
OUT="$BENCH_DIR/$LABEL"
mkdir -p "$OUT"
rm -f "$OUT"/run-*.json

# The native-assets hook cache is keyed by nothing useful and holds a compiled
# dill. `fvm flutter` here is Dart 3.11 (kernel 127) while the `flutter` on PATH
# is Dart 3.12 (kernel 130), so whichever ran last leaves a cache the other
# cannot load - surfacing as "Building native assets failed / reserved exit code
# 253", which looks nothing like a version mismatch. Cheaper to rebuild it once
# per benchmark than to debug it again.
rm -rf .dart_tool/hooks_runner

pkill -f "chromedriver --port=$DRIVER_PORT" 2>/dev/null
sleep 1
chromedriver --port="$DRIVER_PORT" --silent >/dev/null 2>&1 &
CHROMEDRIVER_PID=$!
trap 'kill $CHROMEDRIVER_PID 2>/dev/null' EXIT
sleep 2

for i in $(seq 1 "$RUNS"); do
  echo "=== $LABEL: run $i/$RUNS ==="
  rm -f build/frame_result.json
  fvm flutter drive \
    --driver=test_driver/integration_test.dart \
    --target=test_integration/tests/perf_tests/perf_tests.dart \
    -d web-server --browser-name chrome --no-headless \
    --browser-dimension 1400x1024 --driver-port="$DRIVER_PORT" \
    --profile --no-pub \
    --dart-define=testing_mode=true \
    --dart-define=CI=true \
    --dart-define=ANALYTICS_DISABLED=true \
    --dart-define=PERF_LOGIN_ACTIVATION=true \
    --dart-define=PERF_SKIP_SCROLL=true \
    --dart-define=PERF_AUTO_LOGIN=true \
    --dart-define=FRAME_TIMING_CAPTURE=true \
    >"$OUT/run-$i.log" 2>&1

  # The exit code is not evidence; the artifact is.
  if [ ! -f build/frame_result.json ]; then
    echo "  FAILED - no build/frame_result.json (see $OUT/run-$i.log)"
    tail -20 "$OUT/run-$i.log"
    continue
  fi
  cp build/frame_result.json "$OUT/run-$i.json"
  python3 -c "
import json;m=[r for r in json.load(open('$OUT/run-$i.json'))['runs'] if r['flow']=='login_activation_storm']
print('  ok:', {k:m[0]['metrics'][k] for k in ('gap_p50_ms','gap_worst_ms','yield_pct','frame_count')} if m else 'NO LOGIN RUN')
"
done

echo
echo "=== medians ==="
median_report "$LABEL"
