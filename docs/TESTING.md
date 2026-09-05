# Testing

The map of every automated-test surface in this repo: what exists, exactly how to run it,
and what gates a PR.

This file is **authoritative for commands**. It is a *pointer* for depth — the wallet-load
tiers live in [WALLET_LOAD_MEASUREMENT.md](WALLET_LOAD_MEASUREMENT.md), the KDF probes in
[tool/README.md](../tool/README.md), the QA rig's design in
[automated_testing/gleec-qa-architecture.md](../automated_testing/gleec-qa-architecture.md).
If a command here drifts from reality, fix it here first.

```bash
# unit + widget (gates every PR)
flutter test test_units/main.dart \
  --dart-define=TRON_GASLESS_ENABLED=true \
  --dart-define=TRON_GASLESS_RECEIVE_ENABLED=true \
  --dart-define=TRON_GASLESS_BASE_URL=https://quicknode.gleec.com/gasfree/tron \
  --dart-define=TRON_GASLESS_SERVICE_PROVIDER=TLntW9Z59LYY5KEi9cmwk3PKjQga828ird

# integration / GUI (gates every PR)
dart run_integration_tests.dart

# KDF wallet-load harness, replay tier (gates every PR)
cd sdk/packages/komodo_defi_harness && flutter test --exclude-tags bench

# SDK package tests (gates PRs touching sdk/**)
cd sdk/packages/komodo_defi_sdk && KDF_HARNESS="" flutter test
```

## 1. Suite map

| Suite | Where | Command | CI workflow | Gates? |
|---|---|---|---|---|
| Unit + widget | `test_units/` | `flutter test test_units/main.dart` **+ 4 defines** | `unit-tests-on-pr.yml` | Yes |
| Integration / GUI | `test_integration/` | `dart run_integration_tests.dart` | `ui-tests-on-pr.yml` | Yes |
| KDF harness — replay | `sdk/packages/komodo_defi_harness` | `flutter test --exclude-tags bench` | `kdf-harness-on-pr.yml` | Yes |
| KDF harness — bench | same | `flutter test --tags bench` + `compare_bench.dart` | `kdf-harness-on-pr.yml` | Yes, at 30% regression |
| KDF harness — process | same | `KDF_HARNESS=1 … --tags process -j 1` | `kdf-harness-nightly.yml` | Never |
| SDK — `komodo_defi_sdk` | `sdk/packages/komodo_defi_sdk` | `KDF_HARNESS="" flutter test` | `sdk-unit-tests-on-pr.yml` | Yes |
| SDK — other packages | `sdk/packages/*` | `flutter test` per package | — | No |
| Browser-only unit | `test/` | `flutter test --platform chrome test/…` | — | No |
| Skyvern QA | `automated_testing/` | `python -m runner.runner` | — | No |
| Frame timing | `test_integration/tests/perf_tests/` | `-t perf_tests/perf_tests.dart -D macos -m profile` | — | No |

## 2. Unit and widget tests

```bash
flutter test test_units/main.dart \
  --dart-define=TRON_GASLESS_ENABLED=true \
  --dart-define=TRON_GASLESS_RECEIVE_ENABLED=true \
  --dart-define=TRON_GASLESS_BASE_URL=https://quicknode.gleec.com/gasfree/tron \
  --dart-define=TRON_GASLESS_SERVICE_PROVIDER=TLntW9Z59LYY5KEi9cmwk3PKjQga828ird
```

### The four defines are mandatory

Without them `tronGaslessServiceProvider` falls back to its empty default
(`lib/shared/constants.dart`), every GasFree provider-identity check fails closed, and
~36 gas-free tests never reach the state they `await`. They **hang rather than fail** —
an unbounded `bloc.stream.firstWhere` has no deadline — so the symptom is a wedged runner
and a CI timeout, not a red test. The values are non-secret; the source of record is
`.github/workflows/unit-tests-on-pr.yml:9-20` and `test_units/main.dart:101-114`.

### The aggregator trap

CI runs *only* `test_units/main.dart`. **A test file not reachable from it never runs,
anywhere, and nothing reports that.** Adding a test means adding an import there. Three
files are orphaned today — see §9.

### Coverage

`unit-tests-on-pr.yml` runs `flutter test` twice: the suite, then a `--coverage` pass via
`.github/actions/code-coverage` with the same four defines. Both are
`continue-on-error: false`, so a wedged coverage run reds the PR just as the suite would.
Change the defines in one place and you must change them in both.

## 3. Integration / GUI tests

`dart run_integration_tests.dart` wraps `flutter drive`. It starts and stops the browser
driver itself, so no manual `chromedriver` step is needed for Chrome.

### Flags

| Flag | Short | Default | Allowed | Notes |
|---|---|---|---|---|
| `--help` | `-h` | — | — | prints usage, exits 0 |
| `--verbose` | `-v` | false | — | passes `-v` to `flutter drive` |
| `--testToRun` | `-t` | `''` | path under `test_integration/tests/` | **replaces** the whole default list |
| `--browserDimension` | `-b` | `1024,1400` | `H,W` | rewritten to `HxW`. Web only |
| `--displayMode` | `-d` | `no-headless` | `headless`, `no-headless` | local default opens a visible browser. Web only |
| `--device` | `-D` | `web-server` | `web-server`, `chrome`, `linux`, `macos`, `windows`, `ios`, `android` | anything but `web-server` takes the native path |
| `--runMode` | `-m` | `profile` | `release`, `debug`, `profile` | `profile` also emits `--profile-memory=memory_profile.json` |
| `--browser-name` | `-n` | `chrome` | `chrome`, `safari`, `firefox` | `CHROME_EXECUTABLE` pins the Chrome binary |
| `--driver-port` | `-p` | `4444` | — | web only |
| `--pub` | — | false | — | `flutter pub get` before each group |
| `--concurrent` | `-c` | false | — | not recommended with the current build steps |
| `--keep-running` | `-k` | false | — | maps to `--keep-app-running` |

**`-d` is display mode; `-D` is device.** They are not `flutter`'s letters. Getting them
backwards is the classic mistake here.

### What the runner injects — and what it does not

Exactly three defines, on both the native and web paths:

```
--dart-define=testing_mode=true       # lib/shared/constants.dart -> isTestMode
--dart-define=CI=true                 # -> isCiEnvironment
--dart-define=ANALYTICS_DISABLED=true # -> analyticsDisabled
```

**No `TRON_GASLESS_*` defines reach the integration suite.** GasFree is compiled off for
every integration run, so no integration test covers that rail. `testing_mode` itself only
changes error handling and log verbosity — it does not touch auth, analytics, or KDF
config.

### Suites

| Suite (`-t` path) | In the default run | Logs in via `restoreWalletToTest` |
|---|---|---|
| `wallets_tests/wallets_tests.dart` | yes | yes |
| `wallets_manager_tests/wallets_manager_tests.dart` | yes | **no** — it *is* the auth test; drives import directly |
| `dex_tests/dex_tests.dart` | yes | yes |
| `misc_tests/misc_tests.dart` | yes | yes, after the theme and feedback tests |
| `fiat_onramp_tests/fiat_onramp_tests.dart` | yes | yes |
| `nfts_tests/nfts_tests.dart` | **no** — `-t` only | yes |
| `no_login_tests/no_login_tests.dart` | **no** — `-t` only | mostly no, but see below |
| `suspended_assets_test/suspended_assets_test.dart` | **no** — hardcoded off | n/a |
| `perf_tests/perf_tests.dart` | **no** — `-t` only, by design (§7) | no |

`no_login_tests` is not entirely login-free: `no_login_taker_form_test.dart` calls
`restoreWalletToTest` and must stay last in its group.

### The test wallet

`test_integration/helpers/restore_wallet.dart` imports wallet `my-wallet` with password
`pppaaasssDDD555444@@@` in iguana mode. The seed is a randomly chosen **funded WIF key**
from `helpers/get_funded_wif.dart` — RICK/MORTY testnet keys, not secrets, not a BIP39
mnemonic. Because it is not a mnemonic, the helper must confirm the app's custom-seed
dialog. First-time legal acceptance is tied to the setup action. Returning users
who need to accept current agreements use `agree-and-continue-button`; opening a
legal document does not record acceptance. The agreement widget and entry-flow
regressions are included in `test_units/main.dart`.

### Web vs native

The web path (`-D web-server`, the default) serves the app and drives a real browser via
chromedriver, which issues a **fresh browser profile per session** — so storage is clean
every run. The native path (`-D macos|linux|windows|…`) calls `clearNativeAppsData()`
first, but that function targets the wrong bundle identifiers (§9) — neither path should
be assumed to give a clean native profile.

### Recipes

```bash
dart run_integration_tests.dart -t 'wallets_tests/wallets_tests.dart'
dart run_integration_tests.dart -n safari -m release
dart run_integration_tests.dart -d headless -b '1600,1024' -n chrome -m profile  # = the Linux CI leg
dart run_integration_tests.dart -D macos -m debug
```

`Process.run` buffers all output until the run exits — nothing streams, not even the
build. With `-d no-headless` the visible browser window is your progress signal.

## 4. KDF wallet-load harness

Measures wallet load. **Why** the numbers are what they are lives in
[WALLET_LOAD_MEASUREMENT.md](WALLET_LOAD_MEASUREMENT.md); the package internals are in
[its README](../sdk/packages/komodo_defi_harness/README.md). Only the commands live here.

```bash
cd sdk/packages/komodo_defi_harness

# replay tier — what the PR gate runs, per wallet type
KDF_HARNESS_WALLET_TYPE=hd     flutter test --exclude-tags bench
KDF_HARNESS_WALLET_TYPE=iguana flutter test --exclude-tags bench

# benchmark + the gate's own comparison
KDF_HARNESS_WALLET_TYPE=hd BENCH_OUT=build/bench_result.json flutter test --tags bench
dart run tool/compare_bench.dart \
  --baseline tool/bench_baseline.json \
  --current build/bench_result.json \
  --max-regression 0.30

# process tier — nightly only, real binary, real electrum
KDF_HARNESS=1 KDF_TEST_SEED='<throwaway funded seed>' flutter test --tags process -j 1
```

- A bare `flutter test` here runs replay **and** bench; the process tier self-skips
  without `KDF_HARNESS`.
- `-j 1` on the process tier: the RPC port is shared and concurrent files race for it.
- `KDF_TEST_SEED` may only come from the environment. Never upload the harness workspace
  as a CI artifact — it contains a real wallet database.
- **Revert your tree afterwards.** `flutter test` rewrites `pubspec.lock`,
  `sdk/pubspec.lock`, and `sdk/packages/komodo_defi_framework/app_build/build_config.json`;
  the PR gate fails on a dirty tree.

## 5. SDK package tests

```bash
cd sdk/packages/komodo_defi_sdk && KDF_HARNESS="" flutter test
```

`KDF_HARNESS` must stay empty: the suite has no process-tier tests, but asset generation
fetches the KDF binary, so anything keying off binary-existence would spawn a real KDF.
The workflow is path-scoped to `sdk/**`, so an app-only PR never runs it.

Every other SDK package has tests and **no CI**: `komodo_cex_market_data`,
`komodo_defi_types`, `komodo_coin_updates`, `komodo_defi_rpc_methods`,
`komodo_wallet_build_transformer`, `komodo_coins`, `komodo_defi_framework`,
`dragon_charts_flutter`, `komodo_wallet_cli`, `komodo_ui`, `dragon_logs`,
`komodo_symbol_converter`, `komodo_legacy_wallet_migration`. Run them by hand or they ship
unverified. `komodo_defi_local_auth` is the one *deliberate* exclusion — see §9.

## 6. Skyvern QA runner

Vision-based E2E against a **deployed** web build. See
[automated_testing/README.md](../automated_testing/README.md) for the runbook and
prerequisites; the architecture is in `automated_testing/gleec-qa-architecture.md`.

```bash
cd automated_testing
python -m runner.runner --tag smoke --single
```

It is **not wired into CI** — nothing under `.github/` references `automated_testing`.

## 7. Frame timing

Frame-rate and jank measurement. Two tiers, both opt-in.

```bash
# automated: opt-in target, native profile build
dart run_integration_tests.dart -t perf_tests/perf_tests.dart -D macos -m profile
cat build/frame_result.json

# field: in-app recorder, writes into the diagnostic log
fvm flutter run -d macos --profile --dart-define=FRAME_TIMING_CAPTURE=true
# then Settings -> Diagnostic Logging, reproduce, Download Logs
dart run tool/parse_wallet_load_log.dart ~/Downloads/<log-file>
```

A jank frame is one where `max(buildDuration, rasterDuration)` exceeds the frame budget
(`1000 / refreshRate` ms); severe at 3×. **The budget is device-dependent** — 16.67ms at
60Hz, 8.33ms at 120Hz ProMotion — so every result carries its own `refresh_hz`, and
results measured against different budgets are different quantities, not noisier ones.

`-D macos -m profile` is the authoritative target. Debug timings are meaningless (JIT,
asserts on); web CanvasKit raster is a different quantity and KDF shares the main thread
there; headless Linux CI rasterizes in software.

### Read the yield, not just the jank ratio

Build and raster durations only describe frames that **happened**. On web a long task
stops the frame happening at all — the browser never fires the rAF — so a blocked main
thread produces *fewer* frames rather than slower ones, and the jank ratio reads as
healthy while the UI is visibly frozen. Both capture paths therefore also report the
frame-arrival view, from `computeFrameGapMetrics`:

| field | reads as |
|---|---|
| `gap_p50_ms` | when the app painted, did it paint on time — **the gate** |
| `gap_worst_ms` | longest single stretch with nothing painted |
| `yield_pct` | frames painted ÷ frames offered — informational, see below |
| `stall_ms` / `missed_frames` | total time, and refresh slots, that painted nothing |
| `ui_ms` / `raster_total_ms` | Flutter's own share of the span |

**Yield is not a gate.** It only means "the UI froze" in a window where
something animated the whole time. The hermetic scroll flow measures ~30% yield
across runs with a median gap of one frame budget — it painted perfectly and had
nothing to do between flings. The median gap is the honest test, because idle
cannot move it; `gap_worst_ms` catches outright freezes.

`ui` and `raster` are reported separately and **must not be summed on native**, where
raster is a different thread that pipelines with the next frame's build — the two can
exceed the span. On web they are the same thread and do add up to Flutter's share.

A capture can legitimately show `PASS` on jank and `FAIL` on yield. That combination is
the signature of a blocked main thread, not a contradiction.

The `frames[<span>][attrib]` line names what blocked it, from a `long-animation-frame`
observer. Chrome-only, with a 50ms floor, and it credits a task to its entry point — so
wasm called synchronously from Dart is charged to `dart-app` and the KDF figure is a
**floor**. Non-Chrome reports `attribution none` rather than zeroes.

### Spans

| span | window |
|---|---|
| `wallet_load` | `signed_in` → `first_balance` |
| `activation_storm` | the whole initial activation fan-out, from `CoinsBloc` |
| `login_activation_storm` | the driven equivalent, integration suite only |

`activation_storm` exists because `first_balance` is defined as *one* asset having both a
balance and a price, so `wallet_load` closes while the rest of the fan-out is still
running — which is where the jank is.

Spans report **600ms after they close**, not immediately: the engine only flushes
`FrameTiming` when a new frame is submitted and the batch is over ~100ms old, so reporting
on close silently discards the tail — the jankiest part of a stall.

### The login flow

Off by default; it needs a funded seed and network, takes minutes, and is not repeatable
inside one app instance (the second login activates from warm caches):

```bash
dart run_integration_tests.dart -t perf_tests/perf_tests.dart -m profile \
  --dart-define=PERF_LOGIN_ACTIVATION=true
```

Login is driven *before* the measured window opens. `measureFramesUntil` switches the
binding to `benchmarkLive`, under which `pump()` requests are ignored — otherwise the
driving loop manufactures the very frames it is counting — and `restoreWalletToTest` needs
those pumps honoured. The two cannot share a window.

### Running it here: use the pinned SDK

`run_integration_tests.dart` invokes bare `flutter`, which resolves through `PATH`, while
`.fvmrc` pins the project to a different version. The mismatch surfaces as a compile error
inside `flutter_test` (`_TestFlutterView` missing a `FlutterView` member), which looks like
a code problem and is not. Until the runner is taught to respect FVM, drive it directly:

```bash
chromedriver --port=4444 --silent &
fvm flutter drive --driver=test_driver/integration_test.dart \
  --target=test_integration/tests/perf_tests/perf_tests.dart \
  -d web-server --browser-name chrome --no-headless --driver-port=4444 \
  --profile --dart-define=testing_mode=true --dart-define=CI=true \
  --dart-define=ANALYTICS_DISABLED=true
```

**Check the artifact, not the exit code** (§9.1): the runner has been observed exiting 0
on a run whose build failed outright. Confirm `END PERF TESTS` printed and that
`build/frame_result.json` has a fresh mtime.

This is deliberately **not** in the default suite list: it costs seconds per measurement
window, asserts nothing about correctness, and a perf target that reds a functional CI run
trains people to ignore functional CI.

### There is no baseline yet, on purpose

`tool/frame_baseline.json` does not exist. Recording one requires an authoritative run,
and `-D macos -m profile` currently cannot build here — the Debug/Profile configuration
has no provisioning profile (§9). Committing a web-measured baseline would be worse than
having none: it would pin a number from a different renderer on a thread KDF shares.

When the macOS provisioning is fixed, take a run, commit it as `tool/frame_baseline.json`
mirroring the shape of `sdk/packages/komodo_defi_harness/tool/bench_baseline.json`, and
give it a `_comment` block stating which display it was measured on, that it is **never
auto-updated**, and which flows are structurally un-gateable (activation is network-bound;
route-open always carries the first-frame outlier).

Phase 2 — the activation and chart-render flows, a `tool/compare_frames.dart` comparator,
and an informational job in `kdf-harness-nightly.yml` — is deliberately deferred. Gating
needs ~20 nightly samples first: a 30% tolerance on a 3ms p90 is a 0.9ms band, narrower
than scheduling noise on a shared runner, and a flaky perf gate gets ignored within a
fortnight. The chart flow additionally needs keys added to
`packages/komodo_ui_kit/lib/src/inputs/time_period_selector.dart`, which today has none.

## 8. Which suite do I run?

| Change | Run | Also consider |
|---|---|---|
| Pure Dart logic in `lib/` | unit | — |
| A BLoC or its states/events | unit | integration, if it drives a screen a suite touches |
| A widget carrying a `Key` a test uses | unit **and** integration | grep `test_integration/` for the key first |
| Anything GasFree / TRON | unit **with all four defines** | integration will not cover it — no defines injected |
| Auth, activation, pubkeys, balances, storage | SDK **and** harness replay | nightly process tier if it touches the real binary |
| Anything that could move wallet-load timing | harness replay + bench | update `tool/bench_baseline.json` by hand in the same PR |
| An RPC request/response type | SDK + harness replay | serialisation bugs surface only on transports that `jsonEncode` |
| An `sdk/packages/*` package other than `komodo_defi_sdk` | that package's own `flutter test` | not gated — run it or it ships unverified |
| Login / wallet-manager / DEX / fiat UI flows | integration | `-t` a single suite while iterating |
| List, chart, or animation rendering | frame timing (§7) | unit for the logic underneath |
| Full regression on a deployed build | Skyvern | needs the rig; not CI |
| Docs, comments, CI YAML only | none | `flutter analyze` still gates |

## 9. Known-broken and not-run

Current as of the last audit. Each is a real defect, not a caveat.

> Three entries were removed on 2026-08-27 after verifying they had been fixed on this
> branch: the `pumpUntilDisappear` timeout is now a `timeout` parameter defaulting to 60s
> (`widget_tester_pump_extension.dart:55`), `clearNativeAppsData()` uses the Gleec bundle
> ids (`app_data.dart:16-17`), and nothing references `active-coin-item-` any more.

1. **The integration suite reports green when a test throws.** `app.main()` sets
   `FlutterError.onError = catchUnhandledExceptions` (`lib/main.dart:65-67`), and that
   handler **never rethrows when `isTestMode` is true** (`lib/main.dart:186-194`) — which
   the runner always makes true via `--dart-define=testing_mode=true`. It replaces the
   handler `testWidgets` installed to record failures, so the throw is printed to the
   browser console and the run still ends `All tests passed!`. Observed directly: a
   `misc_tests` run where `testFeedbackForm` died on `Bad state: No element`, never
   reached `restoreWalletToTest`, never printed its own `END MISC TESTS`, and exited 0.
   **Do not trust a green integration run** — read the browser console
   (`chromedriver.log`) and confirm the suite's final marker actually printed.
2. **Three `test_units/` files are orphaned** and never run anywhere:
   `tests/wallet/legacy_native_wallet_migration_test.dart`,
   `views/wallets_manager/widgets/legacy_migration_compatibility_dialog_test.dart`,
   `views/settings/widgets/security_settings/legacy_migration_cleanup_plate_test.dart`.
   `testTruncateDecimal()` is also commented out in `test_units/main.dart`.
3. **The macOS Debug/Profile configuration has no provisioning profile.** A
   `-D macos -m profile` run fails at `No profiles for 'com.GleecDEX.wallet' were found`.
   Only the Release configuration (bundle id `com23.GleecDEX.wallet`, Developer ID
   signing) is set up. Until that is fixed, the native perf target of §7 cannot run
   locally, and web is the only path — with the caveat there that web frame numbers are
   not baseline-worthy.
4. **`--timeout=600` is inert.** `flutter drive` only arms that timer when `--screenshot`
   is passed, which the runner never does. A hung integration test has no wrapper-level
   cap; only a test's own `Timeout` bounds it.
5. **`suspended_assets_test` is hardcoded off** (`getTestsList(false)`). The `*.cipig.net`
   URL-blocking machinery is intact but unreachable.
6. **`nfts_tests` and `no_login_tests` are not in the default list** — `-t` only, so they
   run only when someone remembers.
7. **Integration coverage is disabled** in `ui-tests-on-pr.yml` — Hive and other storage
   providers need mocking, and `flutter drive` is deprecated upstream.
8. **`komodo_defi_local_auth` is deliberately ungated** — 57 pass, 1 fails
   (`trezor_repository_test.dart`). Unresolved: either a stale fixture or a real loss of
   device-error detail.
9. **`test/gasless_journal_web_key_discovery_test.dart` is `@TestOn('browser')`** and no
   workflow runs it: `flutter test --platform chrome test/…`.
10. **No integration coverage of the GasFree rail** — §3.
11. **Skyvern is not in CI** — §6.

## 10. See also

| Doc | Authoritative for |
|---|---|
| [WALLET_LOAD_MEASUREMENT.md](WALLET_LOAD_MEASUREMENT.md) | the wallet-load tiers, what to measure and why, baseline policy |
| [../tool/README.md](../tool/README.md) | the KDF probes and the log parser |
| [../sdk/packages/komodo_defi_harness/README.md](../sdk/packages/komodo_defi_harness/README.md) | harness internals and its API |
| [MANUAL_TESTING_DEBUGGING.md](MANUAL_TESTING_DEBUGGING.md) | debug login, web debugging, crash logs |
| [../automated_testing/README.md](../automated_testing/README.md) | running the Skyvern rig |
| [CONTRIBUTION_GUIDE.md](CONTRIBUTION_GUIDE.md) | the PR checklist |
