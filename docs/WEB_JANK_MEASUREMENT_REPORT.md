# Web activation jank: measurement method and change ledger

Living document. Stage 0 (instrumentation) is complete and verified; the
measurement arms and the per-change ledger below are filled in as each lands.

## Why this document exists

The wallet janks on web while the default 9 assets activate after login. The
open question was whether that is KDF's fault — everything shares one browser
thread there, which is structural and not ours to fix — or our Dart, which is.

The rule this document enforces: **no change stays unless a number says it
helped.** Every entry in the ledger is benchmarked against the commit before it,
and anything that does not move a headline metric beyond noise is reverted and
recorded here so it is not re-proposed. That is the same service commit
`1f271e8d5` did for the activation concurrency cap.

## What we already knew, and its limit

`docs/KDF_LATENCY_REPORT.md` §5b measured KDF's total Long Task time at
**128–241ms across 1–2 tasks**, under 2% of 13–23s of wall clock, and concluded
KDF is not what blocks the UI thread during login.

That number is real but does not settle this question. It was taken with **one
coin, in a plain HTML page, with no Flutter and no Dart in the process**. It
covers neither nine concurrent activations nor any of the Dart-side cost.

## Stage 0 — why the instrument had to be fixed first

Four defects, each of which would have produced a confident wrong answer.

### The metric could not see the failure mode

On web a long task stops the frame *happening*: the browser never fires the
rAF, so there is no frame with a slow `buildDuration` to find. Both capture
paths scored jank as `max(build, raster) > budget` and discarded
`FrameTiming.vsyncStart`, so a frozen UI reported as **"few frames, all fast"**.

The fix adds the frame-arrival view, computed by `computeFrameGapMetrics` in
[`lib/analytics/frame_timing_recorder.dart`](../lib/analytics/frame_timing_recorder.dart)
and shared by the in-app recorder and the integration harness so both produce
numbers that mean the same thing:

| metric | what it answers |
|---|---|
| `gap_p50_ms` | when the app painted, did it paint on time — **the gate** |
| `gap_worst_ms` | longest single stretch with nothing painted |
| `yield_pct` | frames painted ÷ frames offered (informational — see calibration) |
| `stall_ms` / `stall_pct` | total time past budget between frames |
| `missed_frames` | refresh slots that painted nothing |
| `ui_ms` / `raster_ms` | Flutter's own share, reported separately (see below) |

`ui` and `raster` are deliberately **not summed**. Builds are sequential, so
`ui` is always a real fraction of the span; raster is a separate thread on
native that pipelines with the next build, so summing there can exceed the span
and yield a nonsense negative remainder. On web both are the same thread, so
there they do add up to Flutter's share and the rest is KDF's wasm, our RPC
decoding, or genuine idle. The `frames[device]` line records the platform.

The arithmetic is pinned by
[`test_units/tests/analytics/frame_gap_metrics_test.dart`](../test_units/tests/analytics/frame_gap_metrics_test.dart),
including the case that motivated all of it: a run where every frame is 1ms and
the thread vanished for a second still reports a healthy jank ratio, and is only
caught by the arrival gaps.

#### Calibration: yield alone is not the gate

The first real run of the instrument — three iterations of the hermetic
coin-list scroll flow, driven in Chrome, **no login and no network in the
measured window** — came back:

| run | frames | span | yield | jank | gap p50 | gap p90 | worst gap | ui | raster |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 354 | 20.6s | 28.7% | 2.8% | 23.3ms | 108.7ms | 785ms | 1423ms | 1892ms |
| 2 | 359 | 19.5s | 30.6% | 0.0% | 17.7ms | 108.6ms | 308ms | 854ms | 1374ms |
| 3 | 361 | 19.7s | 30.6% | 0.0% | 17.1ms | 108.4ms | 306ms | 897ms | 1373ms |

Two things to take from it.

The instrument works and the old metric is blind: run 2 reports **0.0% jank**
while painting 359 of 1172 offered frames.

But **~30% yield here is idle, not blocking** — `gap p50` sits at one frame
budget, meaning that when the app painted, it painted on time. The flow flings
and then waits for the list to settle, and while nothing is animating there is
nothing to paint. Gating on yield would have called this a freeze.

So the gate is the **median gap**, which idle cannot move, and `gap_worst_ms`
for outright freezes. `yield_pct` is reported as `INFO` and never as a verdict.
The parser states the rule inline: *low yield with a passing median gap means
idle, not blocking.*

This also sets the noise band for the ledger below: on this machine the flow is
reproducible to about ±2 percentage points of yield and ±0.6ms of median gap
across runs, with the worst gap far noisier (306–785ms).

#### The frame budget is mis-detected on web, and yield inherits it

The login-activation runs report `yield_pct` around **198%**, which is of course
impossible. `views.first.display.refreshRate` returns **60** in Flutter web on a
120Hz ProMotion panel, so the budget is computed as 16.67ms while frames
actually arrive every 8.3ms. Anything derived from the budget - `yield_pct`,
`missed_frames`, `stall_ms` - is wrong by that factor.

It does not invalidate the comparison: both arms run on the same machine with
the same mis-detected budget, and the two gates (`gap_p50_ms`, `gap_worst_ms`)
are raw milliseconds that never touch it. But a yield over 100% must be read as
"the budget is wrong here", not as a result, and it is a second reason yield is
not a gate.

Worth fixing separately: prefer the observed frame cadence over the reported
refresh rate when the two disagree, and record which was used.

### The window closed before the jank did

`frames[wallet_load]` is bracketed by `WalletLoadMark.firstBalance`, defined as
*one* asset having both a balance and a price — so it ended while the other
eight were still activating. A new `activation_storm` span brackets the real
fan-out from inside `CoinsBloc`, opening at the fan-out and closing in the
`finally` after `await Future.wait(enableFutures)`.

### The device line never reached the log

`initFrameTimingCapture()` runs from `main()` **before**
`AppBootstrapper.ensureInitialized` attaches the listener to
`Logger.root.onRecord`. That is a broadcast stream, so the record was dropped
with no error — and `tool/parse_wallet_load_log.dart` then saw span lines with
no device line and reported *"rebuild with FRAME_TIMING_CAPTURE=true"* for a
build that already had it. The device line is now emitted lazily on the first
span report, which is always after bootstrap.

The same class of bug bit the tail of every span: the engine only flushes
`FrameTiming` when a new frame is submitted *and* the batch is over ~100ms old,
so a span that reported the instant it closed lost its tail — the jankiest part
of a stall. Spans now report after a 600ms drain.

### Two tools could not start

`tool/web/bench_serve.py` opened `recorder.js` (the file is
`bench_recorder.js`) and `tool/kdf_rpc_instrument.py` loaded
`rpc_burst_bench.py` (the file is `kdf_rpc_burst_bench.py`) — both rename
fallout, both raising at import. `bench_serve.py` also served the 33MB KDF
module as `application/octet-stream`, which makes
`WebAssembly.instantiateStreaming` reject and fall back to buffering the whole
thing: a materially slower startup than production, so the arm would have been
measuring the server.

### Attribution

`frames[<span>][attrib]` reports who blocked the thread, from a
`long-animation-frame` `PerformanceObserver` installed before the KDF module is
imported ([`frame_attribution_web.dart`](../lib/analytics/frame_attribution_web.dart)).
Its `scripts[].sourceURL` separates `kdflib.js` from `main.dart.js` — the
KDF-versus-us question — with no change to either codebase.

Deliberately **not** `longtask`: its `attribution` field is designed for iframes
and reports `"window"` with empty fields for a same-document task, i.e. it
confirms the thread was blocked and says nothing about by what.

Limits, which must be printed with any number taken from it:
- **50ms floor.** A login made slow by a thousand 20ms bloc emissions is
  invisible here.
- **Chrome only.** Reports `attribution none` elsewhere rather than zeroes.
- **Credits the entry point**, so wasm invoked synchronously from Dart lands
  under `dart-app`. The KDF figure is a **floor**, not a total.

## How to take a measurement

Field capture (in-app recorder → Download Logs → parser):

```bash
fvm flutter build web --release \
  --dart-define=FRAME_TIMING_CAPTURE=true \
  --dart-define=TRON_GASLESS_ENABLED=true \
  --dart-define=TRON_GASLESS_RECEIVE_ENABLED=true \
  --dart-define=TRON_GASLESS_BASE_URL=https://quicknode.gleec.com/gasfree/tron \
  --dart-define=TRON_GASLESS_SERVICE_PROVIDER=TLntW9Z59LYY5KEi9cmwk3PKjQga828ird
```

```bash
python3 tool/web/bench_serve.py --root build/web --port 8123
```

Then Settings → Diagnostic Logging on → log out → log back in → Download Logs:

```bash
dart run tool/parse_wallet_load_log.dart ~/Downloads/<log> --json
```

Driven capture (integration harness → `build/frame_result.json`):

```bash
dart run_integration_tests.dart -t perf_tests/perf_tests.dart -m profile
```

Add `--dart-define=PERF_LOGIN_ACTIVATION=true` to include the login flow; it is
off by default because it needs a funded seed and network, takes minutes, and is
not repeatable inside one app instance.

**Check the artifact, not the exit code.** The runner exits 0 on a failed test —
observed during this work, when a stale `.dart_tool/hooks_runner` cache failed
the build and the run still reported success. Confirm `END PERF TESTS` printed
and that `build/frame_result.json` has a fresh mtime.

Two more traps worth stating, because each silently fakes a good number:
- The measured window must never be driven with `tester.pump`. Under the default
  frame policy each pump manufactures a frame the app never asked for — in a
  window whose point is counting frames the app *failed* to produce, the driving
  loop would supply the missing ones. `measureFramesUntil` switches to
  `benchmarkLive` and drives with `Future.delayed`.
- Diagnostic Logging writes through OPFS on the main thread, so log-based frame
  numbers are an upper bound, not the shipped experience.

## Measurement arms

`C − 3` is KDF's measured share; `C − 2` bounds ours. LoAF gives the same split
within a single run of C. **If the two disagree by more than ~20%, the
attribution is wrong and no percentage gets quoted until it is fixed.**

| arm | what runs | isolates | status |
|---|---|---|---|
| 0 | Stage-0 build, capture off | the probe's own cost | pending |
| 1 | logged in, idle 60s | the yield floor | pending |
| 2 | `kdf_web_probe.html`, 9 coins, no Flutter | KDF's ceiling | pending |
| 3 | our Dart, KDF via same-origin remote proxy | our ceiling | pending |
| C | production baseline, 9 coins | the number to explain | pending |
| 4 | C with 1 coin | fan-out vs framework | pending |
| 5 | C with a 20-entry `coins_config.json` | catalogue-scaling vs per-coin | pending |

Arm 3's subtraction is clean for "is KDF wasm on the thread" and **dirty for the
decode step** — it swaps `dartify` for `jsonDecode`. Take that number from arm
C's `kdf.jsdecode` measure instead.

N=5 per arm, median reported.

## Getting a wallet in without driving the UI

`docs/MANUAL_TESTING_DEBUGGING.md` documents an auto-login: an
`assets/debug_data.json` with `automateLogin: true` makes the app restore a
wallet at startup. It was `kDebugMode`-only, which makes it useless for frame
timing - a debug build measures the JIT, not the app. `perfAutoLoginEnabled`
(`--dart-define=PERF_AUTO_LOGIN=true`) now also opens that path in a profile
build. It is a const, so a normal build folds the condition back to `kDebugMode`
and tree-shakes the rest; `assets/debug_data.json` is git-ignored and absent
unless a developer creates one.

This replaced driving `restoreWalletToTest` from the perf suite, which produced
no artifact and no visible reason - on web `print` goes to the browser console,
which `flutter drive` does not forward, and `catchUnhandledExceptions` never
rethrows while `testing_mode=true`. The perf suite now records any flow failure
into `frame_result.json` under `failures`, because that is the only channel that
reaches the host.

**Two findings came out of that:**

Update (2026-09-05): the release review replaced the invalid test-password
fixtures and fixed test-mode error handling. Browser tests now retain the
integration binding's failure reporting. The findings below describe the
original measurement environment.

1. **The documented test password is rejected by the password policy.**
   `pppaaasssDDD555444@@@` (`test_integration/helpers/restore_wallet.dart:24`,
   `docs/TESTING.md`) contains `ppp`/`aaa`/`sss`. KDF refuses it at wallet init -
   *"Password can't contain the same character 3 times in a row"* - and
   `lib/shared/utils/validators.dart:112-118` enforces the identical rule, so
   the app's own create-password field rejects it too. Verified by asserting
   `checkPasswordRequirements` returns `consecutiveCharacters` for it. Any
   integration test that creates a wallet with this password cannot be
   succeeding; combined with the swallowed-exception behaviour above, it would
   look like a pass.
2. **`run_integration_tests.dart` uses the wrong Flutter SDK.** It invokes bare
   `flutter` from `PATH` while `.fvmrc` pins another version. The symptom is a
   compile error inside `flutter_test` (`_TestFlutterView` missing a
   `FlutterView` member) that looks like a code bug. `tool/bench_web_jank.sh`
   drives `fvm flutter drive` directly and clears `.dart_tool/hooks_runner`
   first, because the two SDKs' native-assets caches are mutually unreadable
   ("Building native assets failed / reserved exit code 253").

## Change ledger

Every change is its own commit, benchmarked against the one before it on arm C,
N=5, median, via `tool/bench_web_jank.sh`. Noise is established from arm 0 and
the arm-1 idle floor **before** any change lands; anything inside ~2× that band
is "no difference".

### The fixture does not reproduce the jank, and that is the headline

Measured, 3 runs before and 3 after, login-activation window of 60s each:

| | gap p50 | gap p90 | gap worst | ui (Σ build) | raster | frames |
|---|---:|---:|---:|---:|---:|---:|
| baseline | 8.3 / 8.3 / 8.3 | 9.1 / 8.9 / 9.1 | 392 / 355 / 17 | 5485 / 5303 / 4973 | 5343 / 5154 / 4930 | ~7200 |
| with fixes | 8.3 / 8.3 / 8.3 | 9.1 / 9.1 / 9.5 | 16 / 17 / 103 | 5407 / 4934 / 5766 | 5119 / 4899 / 5817 | ~7180 |

**`gap_p50` is 8.3ms in all six runs** and `gap_p90` is 8.9–9.5 — the app painted
at the display's full rate for the whole activation window, in both arms.
`jank_ratio_pct` is 0 throughout. There is no jank here to remove, so **no change
below can be credited with removing any.**

Nor is there a resolvable difference anywhere else. `ui_total_ms` medians move
the *wrong* way (5303 → 5407) inside overlapping ranges of 4973–5485 and
4934–5766; the run-to-run spread is ±10%, far wider than any effect these
changes could have. `gap_worst` medians look dramatic (355 → 16.5) but the
distributions interleave — baseline produced a 17 and the fixes produced a 103.
At n=3 that is a coin flip, not a result.

**Why this fixture cannot show the effect**, which is the useful part:

- It activates **8** coins, not the 40 of a real wallet. `sortByPriorityAndBalance`
  costs ~n·log₂n comparisons, so A1 saves ~24 redundant balance reads here
  against ~426 at 40 coins — roughly **18× less**.
- The seed is an **unfunded testnet WIF**, so almost no balance ticks fire. A2
  and A3 guard the *per-balance-tick* cost; with no balances there is nearly
  nothing to guard.
- It is **iguana, not HD**: no gap scan and none of the 100ms
  `account_balance` polls that make an HD login expensive.
- The machine is a fast M-series Mac at 120Hz.

So the numbers below are honest and they are *null results for this fixture* —
not evidence the changes are worthless, and not evidence they help. To get a
verdict, the fixture has to look like the wallet people complain about: an HD
seed with real balances across ~40 assets. That is the single most valuable
follow-up, and it needs a funded test wallet this repo does not currently have.

All seven were measured together, not one at a time: with the gate flat at
8.3ms in both arms there was nothing for a per-change bisect to resolve, and
six 60-second runs to separate two indistinguishable numbers is not a good use
of anyone's afternoon. Bisecting becomes worthwhile the moment a fixture exists
that actually janks.

| # | change | evidence it is safe | measured effect | verdict |
|---|---|---|---|---|
| A1 | one `lastKnownUsdBalance` per coin instead of ~2 per comparison (`coin_utils.dart`) | 12 order tests written against the original comparator, unchanged and passing | none resolvable (8 coins ⇒ ~18× less to save than at 40) | **KEEP (unproven)** |
| A2 | early-return `_onBalanceChanged` before allocating either map | 6 bloc tests written against the original handler, unchanged and passing; one asserts the pre-change handler already emitted nothing | none resolvable (unfunded wallet ⇒ almost no balance ticks) | **KEEP (unproven)** |
| A3 | same guard in `_onCoinsRefreshed`'s `emit.forEach` | same reasoning as A2; covered by the suite | none resolvable | **KEEP (unproven)** |
| A6 | `mapEquals` guard on the 1Hz ZHTLC `setState` | — | none, as predicted | **KEEP (non-perf)** |
| A7 | delete dead `all_coins_list.dart` | no references outside its own file | none, as predicted | **KEEP (non-perf)** |
| S1 | `censored()` behind a lazy `_debugLogLazy`; hoist the per-key `RegExp` | the native path was already guarded this way — only the web path evaluated it eagerly | none resolvable | **KEEP (unproven)** |
| S3 | `parseResponseJson(JsonMap)` removes a `jsonEncode`+`jsonDecode` per RPC | 208 SDK rpc-method tests green; no subclass overrides `parseResponse` | none resolvable | **KEEP (unproven)** |

**KEEP (unproven)** is deliberately not **KEEP**. Each is a deletion of work
that provably has no observable effect - the tests prove that - so the
downside is bounded at "no benefit". None has earned a performance claim, and
none should be described as one in a changelog. If a representative fixture
later shows nothing either, they should be reconsidered on complexity grounds:
A1 is neutral-to-clearer, A2/A3 add a guard clause each, S1 and S3 remove code.

Not done, and why:
- **A4** (diff activation snapshots) - medium risk, needs the
  `coin_activation_state_bridge` test extended first; measurement-gated.
- **A5** (`BlocSelector` on the per-row price widget) - safe, not yet applied.
- **S2** (`ensureJson` as a scan) and **S4** (`AssetId` memoisation) -
  deliberately measurement-gated in the plan; the correctness surface is every
  RPC and every `Map<AssetId, _>` lookup respectively.

Verdicts:
- **KEEP** — moved a headline metric beyond noise.
- **KEEP (non-perf)** — no measurable win, but a correctness or dead-code fix
  worth having on its own merit.
- **REVERT** — no measurable win, and it costs complexity or risk. Recorded here
  with its number so it is not proposed again.
