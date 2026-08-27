# Measuring wallet load

Users reported balances taking **minutes** to appear after login. Fixes have
landed. This is how to prove they worked, and how to catch the next regression.

Everything here produces a number. Nothing here asks anyone to "check if it
feels faster".

> **Set the gap limit deliberately when you measure.** Every published number in
> this repo was taken at `gap_limit: 20`, but the app no longer sends that for
> software wallets —
> [`hd_gap_limit.dart`](../sdk/packages/komodo_defi_types/lib/src/public_key/hd_gap_limit.dart)
> sends `software = 3` (restored) and `newlyGeneratedFirstSignIn = 1` (fresh),
> reserving `hardware = 20` for Trezor. Scan cost is roughly linear in addresses
> walked, so the gap limit dominates any run that includes a pubkey scan.
> **A run that does not state its gap limit is not comparable to anything.**
> The outstanding work is to re-measure the existing matrix at gap 3 and gap 1.

> For the **findings** rather than the method — including the 8-minute HD login
> on the shipped default coin set, native-vs-web, and min/median/max activation
> counts over the top 20 by market cap — see
> [`KDF_LATENCY_REPORT.md`](KDF_LATENCY_REPORT.md). It is self-contained and
> written to be handed to the KDF team as-is.

## The scorecard

| measurement | target | where it comes from |
|---|---|---|
| `Initial activation reached … after Nms` | ≥5× lower than before; **no run over 15s** | `coins_bloc.dart`, INFO, ships in release |
| per-asset activation | **no asset at a ~90s multiple** | `activation_manager.dart`, INFO |
| identity RPCs per login | ~480 → **under 60** | `get_wallet_names` + `get_public_key_hash` |
| `first_post_activation_balance_ms` | within 30% of `tool/bench_baseline.json` | the replay harness |

A ~90s multiple (180s, 270s, 360s) is not "slow" — it is a **fingerprint**. The
app retried activation at 90s, and before the deadline landed each retry
re-joined the wedged attempt instead of starting a new one, so 4 × 90s = 363.5s
per asset. If that shape comes back, the deadline broke, not the network.

## Tier 1 — replay harness (per PR, automatic)

`sdk/packages/komodo_defi_harness`. A real `KomodoDefiSdk` against a scripted
fake KDF: only the RPC backend is faked, so auth, activation, pubkeys, balances
and storage are all production code. No binary, no port, no network, no chain.

```bash
cd sdk/packages/komodo_defi_harness && flutter test
```

CI: `.github/workflows/kdf-harness-on-pr.yml`, matrixed over `hd` and `iguana`,
gating on `tool/bench_baseline.json` with a 30% tolerance.

**`first_paint_ms` is not activation, and must never be the gate.** On a cold
first-time asset `BalanceManager` emits a synthetic zero *before*
`_ensureAssetActivated` is called; on a warm start it emits a hydrated cached
balance, also before activation. Both are fast by design. Gating on that number
would stay green while activation regressed to minutes — which is exactly the
bug this work exists to catch. `first_post_activation_balance_ms` is the gate.

## Tier 2 — real KDF (nightly, informational)

Spawns the actual ~120 MB binary and talks to live electrum servers.

```bash
cd sdk/packages/komodo_defi_harness
KDF_HARNESS=1 KDF_TEST_SEED='…' flutter test --tags process -j 1
```

**Measured, per platform.** Native rows are real numbers from
`test/process/real_kdf_smoke_test.dart` (real KDF binary, real electrum, KMD,
seed `abandon…about`, median of three runs). **Web is not measured** — see
below for why and how to fill it in.

| | native HD | native iguana | web HD | web iguana |
|---|---|---|---|---|
| `auth_signin_ms` | 2 289 | 1 825 | not measured | not measured |
| `activation_ms` | **47 135** | 2 061 | not measured | not measured |
| `first_post_activation_balance_ms` | **89 462** | 2 921 | not measured | not measured |
| identity RPCs (`get_wallet_names` + `get_public_key_hash`) | 63 | 61 | not measured | not measured |

### Where the 89 seconds go, and it is fully accounted for

The RPC counts multiply out to the wall clock almost exactly, so this is
attribution rather than speculation:

| step | HD | iguana |
|---|---|---|
| `task::enable_utxo::status` polls x 500ms | 95 → **47.5s** | 5 → 2.5s |
| `task::scan_for_new_addresses::status` polls x 250ms | 80 → **20.0s** | 0 |
| `task::account_balance::status` polls x 100ms | 210 → **21.0s** | 0 |
| `my_balance` | 0 | 1 → ~0.9s |
| **sum** | **~88.5s** (measured 89.5) | **~3.4s** (measured 2.9) |

**The 20s address scan is pure waste.** 80 polls x 250ms is exactly
`_scanTimeout`, and the log confirms it:
`PubkeyManager: HD address scan failed for Komodo; continuing with existing
pubkeys | TimeoutException: Timed out scanning for new addresses for KMD`.
It hits its deadline, gives up, sets a 2-minute cooldown, and proceeds anyway —
so a fifth of the HD wait buys nothing at all. It is also the *second* address
scan: KDF already scanned during activation, because
`scan_policy: scan_if_new_wallet` is sent on `task::enable_utxo::init`.

### Fix landed: the second address walk is skipped

`PubkeyManager._scanForNewHdAddressesIfNeeded` no longer issues
`task::scan_for_new_addresses` immediately after an activation that already
scanned. The condition is deliberately narrow - both halves matter:

* the activation must have happened **this session**
  (`ActivationManager.wasFreshlyActivated`; a warm re-login finds the asset
  already enabled and scans nothing, so its scan is still meaningful), and
* the protocol's activation params must actually carry a scan policy.
  `UtxoProtocol` sends `scan_policy: scan_if_new_wallet`; the ETH-family params
  have no `scan_policy` field at all.

> **Correction (2026-08-07).** This section used to conclude from that second
> bullet that ETH-family "HD address discovery is *not* covered by activation
> and must still scan". The premise is true of the Dart; the conclusion is
> false, and it is what made a full gap walk on every 30-second poll look
> intentional.
>
> `EthActivationV2Request` carries
> `#[serde(flatten)] pub enable_params: EnabledCoinBalanceParams`
> (`mm2src/coins/eth/v2_activation.rs:249-250`), so an absent `scan_policy`
> takes its serde default — and that default is `ScanIfNewWallet`, not
> `DoNotScan` (`mm2src/coins/coin_balance.rs:159-178`). ETH-family activation
> therefore *does* walk the gap, but only when KDF has no stored HD account for
> the coin (`coin_balance.rs:532-535`); once the account is persisted, every
> later activation takes the branch at `coin_balance.rs:577`, which requires
> `Scan`, and walks nothing.
>
> The SDK cannot see which branch KDF took, so it still does not skip the
> post-activation scan for EVM — guessing wrong in the "already scanned"
> direction would silently disable address discovery on every warm re-login.
> What was actually wrong was the *repeat*: nothing bounded a **successful**
> scan, so `watchPubkeys` re-walked the whole gap every 30 seconds for the life
> of the session. `PubkeyManager._hdAddressScanCompletedAt` now records each
> completed scan per `(wallet, asset)` and suppresses another for six hours.
> The old `_hdAddressScanDone` set suppressed exactly one scan, so even UTXO
> re-walked its gap from the second tick onward.

Measured, same machine, same coin, same seed:

| | before | after |
|---|---|---|
| `first_post_activation_balance_ms` (HD) | 77 986 – 89 462 | **47 769** |
| `task::scan_for_new_addresses::status` polls | 79 – 80 | **0** |
| `task::account_balance::status` polls | 209 – 210 | **11** |

**~41 seconds, about 45%.** The scan's own 20s was the expected saving; the
other ~20s was `account_balance` polling, which collapsed from 210 polls to 11
once it was no longer contending with a scan of the same account. iguana is
unchanged, which is the control.

What remains is the activation itself (~47s, 93 polls of
`task::enable_utxo::status`) - KDF walking a `gap_limit: 20` address gap over
electrum. That is not an SDK-side cost and cannot be scheduled away.

## Verifying it without Flutter

`tool/kdf_latency_probe.py` spawns the KDF binary and speaks its JSON-RPC over
HTTP directly. Python 3 standard library only - no Flutter, no Dart, no SDK.

```bash
export KDF_TEST_SEED='abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about'
python3 tool/kdf_latency_probe.py --quick          # one scenario, ~90s
python3 tool/kdf_latency_probe.py --json out.json  # full matrix
```

It runs a best/worst matrix over both dimensions - address count (`gap_limit`
1 / 20 / 50, plus `scan_policy: do_not_scan`) and activation count (1 coin vs
N) - for HD and iguana, each in a **fresh KDF with a fresh database**, and
prints a full diagnostics report: per-step timings, poll counts, per-method RPC
counts and totals, and derived findings.

For the activation-count dimension it also covers EVM (`enable_eth_with_tokens`
/ `enable_erc20`, which are synchronous rather than task-based) and ships coin
sets whose call counts you can audit before trusting any timing:

```bash
python3 tool/kdf_latency_probe.py --plan-only              # counts, no KDF
python3 tool/kdf_latency_probe.py --coin-set top20-max --unbatched
```

**`--p2p` was required for any set containing TRX** against a KDF older than
`ed8de236b`: with `disable_p2p: true`, TRX activation panicked in
`mm2_p2p/src/p2p_ctx.rs:42`. The panic aborts *that request* — the process
survives, which the 500 body ("The RPC service aborted without responding.")
badly misdescribes. Fixed KDF-side by making the P2P keypair optional for the
three call sites that only need it for proxy signing; TRX now activates with
p2p off. Keep `--p2p` only for older binaries.

The point of it is one number in that report: **how much of the wall clock was
spent inside HTTP calls.** In the first run that was 0.17s out of 90.7s. The
rest is the probe sleeping between polls while KDF works on a task it has
already accepted. Since there is no Flutter or Dart in the measurement, that
settles where the latency lives.

### What the full matrix found

macOS arm64, KDF 3.0.0-beta, KMD (+MARTY/DOC/BTC for the multi-coin rows),
`abandon…about`, fresh KDF and fresh database per row:

| scenario | total | activate | scan | balance |
|---|---:|---:|---:|---:|
| BEST address: HD, 1 coin, `gap_limit: 1` | 53.15s | 9.14s | 20.14s | 22.84s |
| baseline: HD, 1 coin, `gap_limit: 20` (shipped) | 89.40s | 46.99s | 20.10s | 22.05s |
| WORST address: HD, 1 coin, `gap_limit: 50` | 149.41s | 107.02s | 20.14s | 21.99s |
| HD, 1 coin, `scan_policy: do_not_scan` | 47.37s | **2.03s** | 20.12s | 24.96s |
| WORST activation: HD, **4 coins**, gap 20 | 305.06s | 261.48s | 20.11s | 23.21s |
| BEST overall: iguana, 1 coin | **2.88s** | 2.02s | – | 0.60s |
| iguana, 4 coins | 7.54s | 7.07s | – | 0.21s |

Four things fall straight out of it:

1. **Activation time is the address walk, and nothing else.** Same coin, same
   everything, `scan_policy: do_not_scan` activates in **2.03s** against
   **46.99s** for `scan_if_new_wallet`. 45 of the 47 seconds are the walk.
2. **It scales with the gap limit, roughly linearly** — 9.1s at 1, 47.0s at 20,
   107.0s at 50, i.e. ~2.1s per gap unit against these electrum servers.
   `gap_limit: 20` is a configuration choice, not a fixed cost.
3. **It is per-coin.** Four coins cost 261.5s to activate (65.4s each — *worse*
   than the 47.0s a single coin takes, so they contend rather than pipeline).
   A login that enables 20 coins is in minutes territory on HD by arithmetic
   alone.
4. **HD vs iguana is 31x** (89.4s vs 2.9s) on identical inputs.

That table is UTXO-only. The EVM rows are worse (`enable_eth_with_tokens` for
ETH + 2 tokens: **363.8s HD vs 2.5s iguana**, one synchronous call with no
progress), the app's own default set takes **480.7s** on HD, and batching turns
out not to be a lever at all — all in
[`KDF_LATENCY_REPORT.md`](KDF_LATENCY_REPORT.md) §4.

And the number that answers "is it KDF or is it us": across all seven
scenarios, **2.0s of 654.8s (0.3%) was spent inside HTTP calls.** The other
99.7% is the probe sleeping between polls while KDF works on a task it already
accepted. No Flutter, Dart or SDK code was involved.

Its quick-mode numbers reproduce the Dart harness almost exactly, which is the
cross-check that makes both trustworthy:

| step | Python probe | Dart harness |
|---|---|---|
| activate KMD | 46.91s (94 polls) | 46.6-47.5s (93-95 polls) |
| `scan_for_new_addresses` | 20.09s, timed out (80 polls) | 20.0s, timed out (79-80) |
| `account_balance` | 22.12s (213 polls) | 21.0s (209-210) |

### Scan parameters

Two independent scans, two independent gap limits:

| | where | values |
|---|---|---|
| **activation-time** (KDF-side) | `utxo_protocol.dart` `defaultActivationParams` | `scan_policy: scan_if_new_wallet` (`scan` for Trezor), `gap_limit: 20`, `min_addresses_number: 1` |
| **per-fetch scan** (SDK-driven, HD only) | `hd_multi_address_strategy.dart` | `account_index: 0`, `gap_limit: 20`, poll 250ms, **timeout 20s**, retry cooldown 2min (`pubkey_manager.dart`) |
| **balance read** (HD only) | `hd_multi_address_strategy.dart` | `account_index: 0`, poll 100ms, timeout 60s |

`gap_limit: 20` means KDF derives and queries history for up to 20 consecutive
empty addresses per chain before stopping — on external *and* internal chains,
against electrum, for a brand-new wallet with nothing to find. That is the 47s.

### Why web is not measured here

The harness is Dart-VM only (`dart:io`), and on web KDF is WASM in the browser,
so the process tier cannot reach it. Getting the web row means running the real
app:

```bash
flutter build web --release \
  --dart-define=TRON_GASLESS_ENABLED=true \
  --dart-define=TRON_GASLESS_RECEIVE_ENABLED=true \
  --dart-define=TRON_GASLESS_BASE_URL=https://quicknode.gleec.com/gasfree/tron \
  --dart-define=TRON_GASLESS_SERVICE_PROVIDER=TLntW9Z59LYY5KEi9cmwk3PKjQga828ird
python3 -m http.server 8090 --directory build/web
```

Then the click-path in "Tier 3" below, and
`dart run tool/parse_wallet_load_log.dart` on the downloaded log. Use a
**release** build: a debug web build swaps dart2js for dartdevc and distorts
exactly the number being measured.

What the native numbers predict for web, and what to check against: 88 of the
89 HD seconds are *waiting on electrum round trips inside KDF*, not local CPU.
On web those same round trips happen in WASM on the main thread, so the wall
clock should be comparable while the UI is additionally blocked — which is what
the Long Task total in the Performance recording measures. If web HD comes back
much *slower* than 89s, the extra is main-thread contention and belongs to the
COEP/COOP/worker question, not to activation.

- `-j 1` unless each test allocates its own port. The port is no longer fixed
  (see below), but the default is still shared.
- Skips cleanly, with a printed reason, when `KDF_HARNESS`, `KDF_TEST_SEED` or
  the binary is missing. It now *waits* for the port to be released rather than
  skipping the moment it sees the previous test's KDF.
- `KDF_TEST_SEED` comes only from the environment, is wrapped in `Secret`, and
  is redacted from the captured log stream. **Never upload the workspace as a CI
  artifact** — it contains a real wallet database.

CI: `.github/workflows/kdf-harness-nightly.yml`. Never gating.

### The port is configurable now

`LocalConfig` had no `port` field, so a locally started KDF had nowhere to put
one and `generateWithDefaults`' `rpcPort = 7783` default won unconditionally.
`port` now lives on `IKdfHostConfig`, `rpcUrl` derives from it, the auth path
passes it through, and the three independent hardcoded `7783`s
(`KdfOperationsLocalExecutable`, `KdfOperationsNativeLibrary`, the SSE endpoint)
are gone. Two KDF instances can now coexist on one machine.

## Tier 3 — web (the confirmed problem platform)

The harness is Dart-side and cannot measure the browser. On web, KDF runs as
WASM **on the main thread with Flutter** — COEP/COOP are commented out in
`firebase.json`, so there is no cross-origin isolation and no worker. Main-thread
contention only shows up here.

### KDF alone, without Flutter — `tool/web/kdf_web_probe.html`

The browser equivalent of the Python probe. The framework ships `kdflib.js` +
`kdflib_bg.wasm` and a bootstrapper that sets `window.kdf`, and **none of that
needs Flutter or Dart**, so a static page can drive KDF the way the Python
script drives the binary.

```bash
flutter build web --release   # plus the four TRON_GASLESS dart-defines
python3 tool/kdf_latency_probe.py --web
```

That serves `build/web` with the probe overlaid at `/kdf-probe.html` and waits
for the page to POST its results back, so native and web land in one report.
One scenario per page load, IndexedDB wiped between rows (the browser
equivalent of a fresh `dbdir`). It also reports **total Long Task time per
scenario** via `PerformanceObserver`, which is the number below — measured
rather than eyeballed off a flame chart.

Measured: web is **~4× faster** than the native binary on the identical task
(12.4s activate / 13 polls vs 46.9s / 94), and KDF WASM used **under 2%** of
the main thread. The two platforms sit on different electrum transports and
neither can be swapped — native KDF rejects WSS (`"Incorrect protocol for
native connection"`), browsers cannot open TCP — so the gap is reproducible but
not yet attributed. See §5 of the report.

### Capture (the real app)

1. Settings → General → **Diagnostic Logging ON**. This flips
   `KomodoDefiFramework.enableDebugLogging` and `KdfApiClient.enableDebugLogging`
   (`settings_bloc.dart`), which makes every RPC emit
   `[RPC] <method> completed in <N>ms`.
2. **Log out.**
3. Open DevTools → Performance, start recording.
4. **Log in.** Stop recording once balances are on screen.
5. Settings → **Download Logs**.

### Parse

```bash
dart run tool/parse_wallet_load_log.dart ~/Downloads/<log-file>
```

Prints RPC counts and durations per method, per-asset activation times, the
balance-emission timeline (cache/synthetic paint vs fetched), the
`getActiveUser` windows, and the scorecard above — including the ~90s-multiple
check. `--json` for machine-readable output.

`Initial activation reached …` is INFO and ships in release, so it is present
even with Diagnostic Logging off. The `[RPC]` lines are not.

### Long tasks

In the Performance recording, sum **Long Tasks** between login and the first
balance render. That is the number that says whether the main thread was blocked
by KDF WASM rather than waiting on the network. The two have identical
wall-clock symptoms and completely different fixes.

### HAR (required, not optional)

Etherscan, TronGrid and the CEX price feeds **do not go through `executeRpc`**
and therefore never appear as `[RPC]` lines. If the RPC totals do not account
for the wall clock, the time is in that traffic and only a HAR will show it.
DevTools → Network → Export HAR.

> A HAR records full request/response contents for the session, including
> anything authenticated. Treat it as sensitive and do not attach it to a public
> issue.

### Run it twice: cold profile, then warm re-login

This contrast is what separates the candidate causes, and a single run cannot:

| cause | cold vs warm |
|---|---|
| HD address scan | **large gap** — the scan is the cold cost |
| activation | roughly the same either way |
| identity-RPC amplification | roughly the same either way |

Cold = a fresh browser profile (or cleared site data). Warm = log out and back
in without touching storage. Record both, parse both, compare.

## A note on `flutter test` and the network

`TestWidgetsFlutterBinding` installs `_MockHttpOverrides`, which makes **every**
`HttpClient` return an empty 400 and issue no request. So:

- The replay tier is genuinely hermetic, and the `Failed to fetch seed nodes.
  Status code: 400` lines in its output are the stub, not a failure.
- Anything that needs real sockets must clear `HttpOverrides.global` —
  `KdfHarness.process` does, and restores it in `dispose`. Without that, RPCs to
  a KDF the harness itself spawned answer 400, and the symptom is
  `KDF RPC did not become ready within 15 seconds`, which points at KDF rather
  than at the test binding.

## What the instrumentation emits

All at INFO, so all present in release builds:

| log | file |
|---|---|
| `getActiveUser: N calls in Tms (R identity RPCs), lock queue …, lock held …` | `auth_service.dart` |
| `Activating <id>` / `Activated <id> in Nms (<status>)` | `activation_manager.dart` |
| `balance[<id>] cached\|hydrated\|synthetic-zero paint after Nms` | `balance_manager.dart` |
| `balance[<id>] fetched after Nms` | `balance_manager.dart` |
| `time_to_first_balance` analytics event | `wallet_overview.dart` |

`getActiveUser` is reported per 5-second window rather than per call: a login
issues hundreds, and per-call logging would itself be a cost. An asset with an
`Activating` line and no `Activated` line **never finished** — that is the stall.

## Updating the baseline

`sdk/packages/komodo_defi_harness/tool/bench_baseline.json` is **never**
auto-updated. `compare_bench.dart` has no `--update` flag on purpose: a gate that
can rewrite its own reference ratchets silently, and three "acceptable" 10%
regressions become a 33% one nobody reported. Move the numbers by hand, in the PR
that causes the change, so the diff is reviewed.

The committed values were measured on macOS; CI runs ubuntu-latest.
`compare_bench.dart` warns when the platform differs. Replace them with the first
green CI run's medians before trusting a marginal result.

---

## A/B-ing two KDF builds

The only honest way to attribute a KDF change. Build both binaries, point the
probe at each with `--kdf`, and **alternate the arms** — a non-alternating run
once made a change look like a regression that was really time-of-day network
drift.

```bash
export KDF_TEST_SEED='<throwaway seed>'
python3 tool/kdf_latency_probe.py --coin-list ETH --kdf /path/to/baseline/kdf
python3 tool/kdf_latency_probe.py --coin-list ETH --kdf /path/to/candidate/kdf
```

**Take at least three samples per arm and report the spread, not a single
number.** EVM timings were bimodal before the RPC-pool fix (196.9 / 219.0 /
346.4s against a tight 343.3 / 343.4 / 363.8s baseline) because activation was
linear in per-RPC latency. One draw from that distribution proves nothing.

Traps, each of which has produced a wrong number at least once:

* **A failed step returns fast**, so tooling that records an error as a
  completed step turns a failure into an apparent speedup. A `NoSuchCoin` once
  presented as a 92× win. Both probes now flag failures explicitly — keep it
  that way.
* **Compare like for like.** A `--p2p` run with other coins already activated is
  not comparable to a standalone row.
* **The seed is not neutral.** `abandon … about` is unused on UTXO and TRON, so
  those numbers are a floor. On **Ethereum it is the most-used public vector
  there is**, so the gap scan walks used addresses (239 of them, against 21 for
  an empty account) and the ETH numbers are a *ceiling*. Do not describe a whole
  matrix as "a floor".
* **Count the RPCs before reasoning about per-RPC cost.** Dividing a wall clock
  by an assumed RPC count produced a confident, wrong conclusion that ~85% of
  EVM time was unexplained; the real count was 14× higher and the per-RPC time
  was healthy all along. `KDF_EVM_RPC_TRACE=1` gives the per-call breakdown.
* **Build the binary with the CI-pinned toolchain**, and regenerate any Dart
  lockfile with `fvm flutter pub get` — see [`FLUTTER_VERSION.md`](FLUTTER_VERSION.md).
