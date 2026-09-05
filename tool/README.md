# Wallet-load diagnostics

Three of these answer "why is this login slow", from opposite ends — KDF in
isolation (native and web), and the shipped app's own logs. The rest answer
narrower questions: how close KDF comes to exhausting the iOS file-descriptor
budget, and how many HTTP requests a build actually makes.

| tool | question | platform |
|---|---|---|
| `kdf_latency_probe.py` | is it KDF, or is it us? | native (`--web` serves the browser probe) |
| `web/kdf_web_probe.html` | the same, in the browser, with **no Flutter** | web |
| `parse_wallet_load_log.dart` | what did the shipped app actually do | any (reads a log) |
| `kdf_fd_probe.py` | how close to the iOS 256-FD ceiling | macOS only |
| `kdf_rpc_burst_bench.py` + `_report.py` + `_instrument.py` | how many RPCs, at what rate, against which nodes | native |
| `web/bench_serve.py` + `bench_recorder.js` | the same for the **real web app**, driven through its GUI | web |
| `bench_web_jank.sh` | does the post-login activation storm jank, and did a change help | web |
| `evm_ws_probe.py` | which `ws_url` endpoints actually answer, on web and on native | any |

For frame timing and jank — a different signal from everything here, which all
measure wall clock or request counts — see `docs/TESTING.md` §7 and
`docs/WEB_JANK_MEASUREMENT_REPORT.md`.

## `bench_web_jank.sh` — did that change actually help?

```bash
tool/bench_web_jank.sh baseline 3     # archives build/bench/baseline/run-N.json
# ... apply a change ...
tool/bench_web_jank.sh my-change 3
tool/bench_web_jank.sh --compare baseline my-change
```

Drives the login-activation perf flow N times and prints medians. Needs
`assets/debug_data.json` (git-ignored; see `docs/MANUAL_TESTING_DEBUGGING.md`)
so the app auto-logs-in rather than the test driving the wallet-manager UI.

Three things it does deliberately, each because the naive version was wrong:

* **`fvm flutter drive`, not `run_integration_tests.dart`.** The runner invokes
  bare `flutter` from `PATH` while `.fvmrc` pins another version, which fails
  inside `flutter_test` with a `_TestFlutterView` error that looks like a code
  bug. It also hardcodes its dart-defines with no passthrough.
* **Clears `.dart_tool/hooks_runner` first.** The two SDKs' native-assets caches
  are mutually unreadable; the symptom is "Building native assets failed /
  reserved exit code 253", which says nothing about versions.
* **Checks the artifact, not the exit code.** The runner has been observed
  exiting 0 on a run whose build failed outright.

Read `gap_p50_ms` first — it is the gate. `yield_pct` is reported but is not
one: a window containing genuine idle has a low yield and no jank at all.

## `kdf_latency_probe.py` — is it KDF, or is it us?

Spawns the KDF binary and speaks its JSON-RPC over HTTP directly. **Python 3
standard library only — no Flutter, no Dart, no SDK, no pub packages.** That is
the whole point: a measurement taken through the SDK cannot tell you whether
the SDK is the problem.

```bash
export KDF_TEST_SEED='abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about'

python3 tool/kdf_latency_probe.py --quick           # one scenario, ~90s
python3 tool/kdf_latency_probe.py                   # full matrix, ~11 min
python3 tool/kdf_latency_probe.py --json out.json   # ... and machine-readable
```

It needs the KDF binary, which is a build artifact rather than a checked-in
file: run any Flutter build once so the transformer fetches it to
`sdk/packages/komodo_defi_framework/{macos,linux}/bin/kdf`, or pass `--kdf`.
The coins config is auto-detected from this repo (`--coins` to override).

The matrix covers best and worst cases on both dimensions, for HD and iguana,
each in a **fresh KDF with a fresh database** so nothing is warmed by the
previous row:

| dimension | best | shipped default | worst |
|---|---|---|---|
| address count (`gap_limit`) | 1 | 20 | 50 |
| activation RPCs (top-20 set) | 6 | 9 | 21 |

plus a `scan_policy: do_not_scan` row, which isolates the address walk from the
rest of activation, and an EVM row (`enable_eth_with_tokens`) on both derivation
modes.

**"20 coins" is not "20 activations."** A platform and all of its tokens
activate in one call, and requesting a token silently forces its platform in
too. `--plan-only` prints the plan for every coin set without starting KDF, so
you can audit the call count before trusting any timing:

```bash
python3 tool/kdf_latency_probe.py --plan-only
python3 tool/kdf_latency_probe.py --coin-set top20-max --unbatched
```

The report prints per-step timings, poll counts, per-method RPC counts and
totals, and derived findings. **The line to read first** is the last one: how
much of the wall clock was spent inside HTTP calls. On the reference run that
was 2.0s out of 654.8s — 0.3%. Everything else is the probe sleeping between
polls while KDF works on a task it has already accepted, which is what makes
"the latency is KDF-side" a measurement rather than an opinion.

Useful flags: `--coin-list`, `--max-coins`, `--port`, `--keep-workdir`,
`--verbose`.

**`--electrum-protocol {TCP,SSL,WSS}`** (repeatable) restricts which electrum
endpoints are offered, so you can run one platform's server list against the
other platform's binary. The SDK does this split itself — `WssWebsocketTransform`
keeps WSS-only when `kIsWeb` and non-WSS otherwise — and that filter is correct,
because **native KDF refuses WSS outright**:

```
Failed to establish connection: Irrecoverable(
  "Incorrect protocol for native connection ('WS'/'WSS'). Use 'TCP' or 'SSL' instead.")
```

Note the transform also synthesises `ws_url` from `url` for WSS entries; the raw
config has no `ws_url` at all, and the probe mirrors that. Omitting it produces a
connection failure that looks like a protocol failure.

**`--p2p` and TRX.** Against a KDF *without* the `perf/hd-scan-concurrency`
panic fix — **which includes the currently pinned `main` / `f3efd2c`** — any set
containing TRX or NFT needs `--p2p`. With `disable_p2p: true` (the default here,
since a balance-only harness has no use for the DEX network) TRX activation
panics inside KDF:

```
panicked at mm2src/mm2_p2p/src/p2p_ctx.rs:42:14:
  called `Option::unwrap()` on a `None` value
```

The panic aborts *that request* - the process survives and keeps serving, which
the 500 body ("The RPC service aborted without responding.") badly misdescribes.
The probe still fails the scenario, because the 500 is not JSON.

The KDF-side fix — `P2PContext::try_fetch_from_mm_arc`, making the keypair
optional for the call sites that only need it for proxy signing — is
`ed8de236b` / `d2c16fc29`, **kdf-internal PR #18, still unmerged**. `main` calls
`fetch_from_mm_arc` unconditionally from `v2_activation.rs:1217`
(`build_tron_api_client`), `:686` (`initialize_global_nft`) and
`eth/tron/gasfree/client.rs`, so `--p2p` is **required**, not optional, on the
current pin. See `docs/KDF_PERF_STACK_DESCOPE.md` §2.4. Note that p2p changes
the startup profile, so rows measured with it are not directly comparable to
rows without.

`tool/kdf_rpc_burst_bench.py` hardcodes `disable_p2p: True` (`:643`) with no
`--p2p` escape, but it is **unaffected**: none of its six `--scenario` values
activates TRX (`:897-905` — GLEEC, GLEEC+GRC-20s, ETH+2 ERC-20, and the
`app-login-*` variants of each). Its `DEFAULT_COINS` list (`:77-86`) does name
`TRX` and `USDT-TRC20`, but nothing reads it — it is unused. Adding a TRX
scenario would need the escape first.

**Safety.** The seed comes from `KDF_TEST_SEED` only, never an argument to this
script, so it stays out of your shell history.

**It is still readable in `ps`.** KDF takes its entire config - passphrase
included - as `argv[1]` of the process this script spawns, so any local user can
read the seed while a scenario runs. **Use a throwaway seed with no funds.** The
probe starts a real KDF against real electrum servers. Each scenario's workspace
(which contains a wallet database) is deleted unless you pass `--keep-workdir`.

## `web/kdf_web_probe.html` — the same measurement, in the browser

The Python probe cannot reach web: there, KDF is WebAssembly inside the page.
But the *isolation argument* transfers, because the framework ships
`kdflib.js` + `kdflib_bg.wasm` and a bootstrapper that sets `window.kdf` with
`mm2_main` / `mm2_main_status` / `mm2_rpc`. **None of that needs Flutter or
Dart**, so a static page can drive KDF exactly as the Python script drives the
binary.

```bash
flutter build web --release \
  --dart-define=TRON_GASLESS_ENABLED=true \
  --dart-define=TRON_GASLESS_RECEIVE_ENABLED=true \
  --dart-define=TRON_GASLESS_BASE_URL=https://quicknode.gleec.com/gasfree/tron \
  --dart-define=TRON_GASLESS_SERVICE_PROVIDER=TLntW9Z59LYY5KEi9cmwk3PKjQga828ird

python3 tool/kdf_latency_probe.py --web
```

That serves `build/web` with the probe page overlaid at `/kdf-probe.html`,
prints the URL, and waits for the page to POST its results back — so native and
web land in one report. Open the URL, press **Run**, paste a throwaway seed.

It runs **one scenario per page load**, advancing by reload and deleting KDF's
IndexedDB databases between rows. That is the browser equivalent of the native
probe's fresh `dbdir` per scenario; without it every row after the first is a
warm start.

It also reports something native cannot: **total Long Task time per scenario**,
via `PerformanceObserver`. On web KDF is WASM on the same thread as the UI, so
blocking time is a first-class symptom rather than a curiosity.

Three config rules are load-bearing on web and the page documents them inline:
omit `dbdir`/`userhome`; **omit `event_streaming_configuration`** (the wasm does
`new SharedWorker(worker_path)` and a 404 there fails the start); and send
`userpass` in every payload. No COOP/COEP is needed — it is a single-threaded
build with no `SharedArrayBuffer`.

## `evm_ws_probe.py` — which `ws_url` endpoints actually answer?

```bash
python3 tool/evm_ws_probe.py                      # every ws_url in coins_config
python3 tool/evm_ws_probe.py --json out.json      # archive the raw result
python3 tool/evm_ws_probe.py --url wss://host/p   # one ad-hoc endpoint
python3 tool/evm_ws_probe.py --baseline docs/assets/evm_ws_probe/evm_ws_probe_2026-08-07.json
```

Opens each endpoint as a real WebSocket, sends one `net_version` — the same
JSON-RPC KDF's own keepalive sends — and records whether an answer came back.
**Python 3 standard library only**; the RFC 6455 handshake and framing are
implemented in the file so this runs on a fresh clone with no `pip install`.

Run it before shipping a change to the ws node expansion, and drop whatever
does not answer. A dead ws node is not free: KDF's `try_every_node` allots
`TRY_RPC_NODE_TIMEOUT_S` = 10s per node and the ws path has no fast fail.

Three things it does deliberately, each because the naive version was wrong:

* **Probes every endpoint twice — with an `Origin` header and without.** That
  one header is the verdict, and the platforms differ on it: native KDF uses
  `tokio_tungstenite` and sends none, while on web it uses
  `tokio_tungstenite_wasm` — the browser's own `WebSocket` — and the browser
  stamps `Origin` where Rust cannot suppress it. Measured 2026-08-07,
  `wss://rpc.energyweb.org/ws` answers **403 to any `Origin` and 101 without
  one**. A single-setting probe calls that "dead" and permanently strips EWT of
  its only ws endpoint.
* **Spaces its retries** (`--spacing`, default 1.5s). Refusals correlate in
  time, so back-to-back retries are one sample, not several.
  `wss://rpc.gnosischain.com/wss` answered 400 on three consecutive tries in one
  sweep and 101 on fifteen of sixteen spaced tries minutes later.
* **`--baseline` reds only on a regression**, not on the endpoints already known
  to be dead — otherwise the gate is permanently red and gets ignored.

Results as of 2026-08-07 (`docs/assets/evm_ws_probe/`): of the 24 distinct
`wss://` endpoints across the 13 EVM platform coins that publish one, **22 work
on both platforms**, `wss://rpc.energyweb.org/ws` is native-only, and
`wss://polygon.gateway.tenderly.co` is dead both ways — 404, because the
Tenderly gateway wants an access key in the path and the config carries the bare
host. The shipping policy lives in `EvmNode` in `komodo_defi_rpc_methods`.

## `kdf_fd_probe.py` — how close is KDF to the FD ceiling?

A different question from the other three. On iOS the soft `RLIMIT_NOFILE` is
**256 for the whole app process**, and KDF is a static library sharing that
budget with Flutter, the network stack, and everything else. This measures KDF's
peak file-descriptor usage during a real activation.

Measuring a spawned binary rather than the device is deliberate: how many sockets
KDF's networking holds open at once is a property of the Rust code and is
identical on every native target. The device contributes only the limit to
compare against, which is a constant. So this costs no signing, no wallet and no
hardware — and it samples fast enough to catch a burst a 60s in-app poll would
miss.

```bash
export KDF_TEST_SEED='abandon abandon ... about'

python3 tool/kdf_fd_probe.py --kdf before=/path/to/kdf --kdf after=/path/to/kdf
python3 tool/kdf_fd_probe.py --kdf head=/path/to/kdf --idle-seconds 30 --json fd.json
```

`--kdf LABEL=PATH` is required and repeatable; two binaries print a delta. It
reuses `kdf_latency_probe` wholesale for the activation itself, so the workload
is exactly the one the latency work measured, down to the seed and coin set. The
seed contract is the same — `KDF_TEST_SEED` only, never an argument, and **use a
throwaway seed with no funds**: this starts a real KDF against real electrum
servers, and KDF takes its config (passphrase included) as `argv[1]`, readable
in `ps`.

**`--port` if the wallet is running.** The default is 7783, which is also the
port a running wallet holds. The probe does not steal it — the scenario fails
rather than disturbing your session. Pass `--port 7784`, or quit the wallet.

**macOS only.** It reads the FD table through `proc_pidinfo`, which has no
portable equivalent. The same numbers come from `/proc/<pid>/fd` on Linux, but
that path is not implemented.

**`--idle-seconds` is what makes the number mean something.** With `0` (the
default) you get the activation peak but no steady state. `HYPER_POOLED` holds a
20s `pool_idle_timeout`, so you need to exceed that — 25-30s — to tell a
transient connect burst from a pool that stays held. The report prints the drain
curve and the idle floor.

The report ends with each build's peak against the 256 limit as a percentage,
plus the caveats: these are KDF's descriptors alone — Flutter, Hive and non-KDF
sockets sit on top — and it is n=1 per build, so repeat before drawing a fine
conclusion.

## `parse_wallet_load_log.dart` — what the real app did

For measuring the shipped app rather than KDF in isolation, web is read from
the app's own logs:

1. Settings → General → **Diagnostic Logging ON**
2. Log out, start a DevTools Performance recording, log back in
3. Settings → **Download Logs**

```bash
dart run tool/parse_wallet_load_log.dart ~/Downloads/<log-file>
dart run tool/parse_wallet_load_log.dart ~/Downloads/<log-file> --json
```

It prints RPC counts and durations per method, per-asset activation times, the
balance-emission timeline (cached/synthetic paint vs fetched), the
`getActiveUser` windows, and a scorecard — including a check for per-asset
times sitting at a ~90s multiple, which is the fingerprint of a retry re-joining
a dead activation rather than of a slow network.

Use a **release** build. A debug web build swaps dart2js for dartdevc and
distorts the number you are measuring.

See `docs/WALLET_LOAD_MEASUREMENT.md` for the full picture, including the Dart
harness tiers and what each measurement can and cannot tell you.
