# Wallet-load diagnostics

Two tools. Both answer "why is this login slow", from opposite ends.

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
panic fix, any set containing TRX needs `--p2p`. With `disable_p2p: true` (the
default here, since a balance-only harness has no use for the DEX network) TRX
activation panicked inside KDF:

```
panicked at mm2src/mm2_p2p/src/p2p_ctx.rs:42:14:
  called `Option::unwrap()` on a `None` value
```

The panic aborts *that request* - the process survives and keeps serving, which
the 500 body ("The RPC service aborted without responding.") badly misdescribes.
The probe still fails the scenario, because the 500 is not JSON.

Fixed KDF-side: `P2PContext::try_fetch_from_mm_arc` makes the keypair optional
for the three call sites that only need it for proxy signing, so TRX now
activates with p2p off. Keep `--p2p` for older binaries. Note that p2p changes
the startup profile, so rows measured with it are not directly comparable to
rows without.

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
