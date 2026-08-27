# The EVM RPC burst — before vs after, measured

**Reported by:** Decker, 2026-08-06, against the shipped build (KDF `25f6e1f`)
**Answered against:** the gas-free baseline (KDF `bd413dc`) and `dev`
(KDF `d56a7bc`)
**Repo:** `gleec-wallet-kdf-integrations`, branch `add/gas-free-tron`
**Host:** macOS 25.5.0, arm64
**Raw data:** historical. The tables below were measured against a ladder of nine KDF commits, none of which is reachable any more (the fork is gone; the wallet now pins KDF `main`). The captures are recoverable only from git history at `ca0212a1b31b` - see [`assets/kdf_rpc_burst_data/README.md`](assets/kdf_rpc_burst_data/README.md). A fresh `tool/kdf_rpc_burst_bench.py` run measures today's KDF and is *not* a reproduction of these numbers.

> **Gap-limit caveat.** The bench here runs at `gap_limit: 20`, but the shipped
> SDK now sends `software = 3` / `newlyGeneratedFirstSignIn = 1`
> ([`hd_gap_limit.dart`](../sdk/packages/komodo_defi_types/lib/src/public_key/hd_gap_limit.dart)).
> The burst *shape* — same logical work, compressed into a shorter window — is a
> property of the RPC layer and holds regardless. The absolute **request counts
> and durations do not**: fewer addresses walked means a smaller burst, so the
> 429 pressure measured here is an upper bound for a software wallet. Re-measure
> at gap 3 before quoting the counts. Trezor still walks 20.

---

## 0. TL;DR

1. **The burst is real. On a healthy endpoint it is the same logical work
   compressed in time; under throttling it also becomes more wire requests.**
   A first-time HD login on the GLEEC chain issues **44 JSON-RPC calls** on
   `bd413dc` and **44** on `25f6e1f`. What changed is the rate: **5 req/s → 43
   req/s** offered, and **10.0s → 1.5s** to finish. Measured, three runs each,
   §2.
2. **The commit responsible is `34ab0e7`** (`perf(eth): stop holding the RPC
   pool lock across the round trip`), not any of the retry or budget work. It
   removed a mutex that had been serialising every EVM RPC to one in flight per
   coin. §2.1.
3. **The addresses that are not in the UI are the BIP44 gap scan**, and they
   pre-date this release. `gap_limit: 20` means KDF probes 21 consecutive
   addresses before it can conclude the account is empty; the UI then shows the
   one address that is actually known. Verified byte-identical across the whole
   commit range. §3.
4. **`evm-rpc.gleec.com` serves ~20 requests/second and refuses the rest — and
   every refusal is invisible to a browser.** Measured directly against the
   endpoint: 44 concurrent requests → 20 × `200`, 24 × `429`, and **0 of the 24
   carried `Access-Control-Allow-Origin`**. §4.
5. **Preflights are rate-limited too, which can approach doubling the wallet's
   cost on web when the browser has no reusable preflight permission.**
   The same test with `OPTIONS`: 20 × `204`, 24 × `429`, again with no CORS
   headers. A KDF EVM call from a browser can cost a preflight plus the POST
   when no reusable preflight permission exists, and a refused preflight is
   unrecoverable — the POST is never sent.
   §4.1.
6. **"Network error. Please check your connection." is the KDF `Transport`
   error surfacing** — the umbrella KDF uses for any web3 transport failure,
   including a pool that exhausted its retries against a refusing node. It is
   not a tx-history or explorer failure. §5.
7. **The native controlled case has a substantially better setting.** At a starting
   concurrency of **6** instead of the current 12, the same login takes the same
   time (2.15s vs 2.16s), makes **44 requests instead of 53**, peaks at **30/s
   instead of 45/s**, and provokes **zero 429s instead of 9**. This does not by
   itself establish a safe web default because the native bench has no CORS
   preflights. §6.

The benchmarked `bd413dc` baseline is newer than `dev`'s `d56a7bc`, but the
relevant old serialized pool and gap-scan behavior are the same. The direct
before/after measurements therefore isolate the KDF change cleanly, while the
comparison to `dev` is source-backed rather than a separate `d56a7bc` binary
benchmark.

---

## 1. How this was measured

Three independent instruments, because each proves something the others cannot.

| # | instrument | what is in the loop | what it proves |
|---|---|---|---|
| A | `tool/kdf_rpc_burst_bench.py` | Python → HTTP → **KDF binary** | The exact request count and rate KDF offers, per commit, with no app in the way. |
| B | `tool/web/bench_recorder.js` + `bench_serve.py` | the **real Flutter web app**, driven through its GUI | What a node operator actually sees, including the app's own traffic. |
| C | `curl` against `evm-rpc.gleec.com` | nothing of ours | What the endpoint does, independent of any client. |

### A — the standalone ladder

An instrument process stands between KDF and every EVM endpoint in the coins
config: each node URL is rewritten to point at it, and it records every request
with its arrival time, JSON-RPC method, address argument and response status.
Three upstream modes:

* `unlimited` — mocks the chain, answers everything. Measures the load KDF
  *offers*, with no retry pressure mixed in.
* `limited` — the same mock behind a 20 req/s token bucket, the measured
  capacity of `evm-rpc.gleec.com`. The difference between the two is exactly the
  retry amplification.
* `proxy` — forwards to the real endpoint.

The mock imposes a **220 ms round trip**, because request rate is in-flight
concurrency divided by round trip: a mock that answers instantly reports
whatever the CPU can push rather than what the client would offer a real node.

Every run starts a fresh KDF with a fresh database directory. The wallet is a
brand-new BIP39 seed generated from a fixed constant — deliberately *not* the
`abandon … about` vector the other probes in this repo use, because that vector
has Ethereum history and the case under investigation is a wallet with none.

Binaries are the **published artefacts for each commit**, pulled from the build
mirror, not rebuilt locally:

| sha | what it adds |
|---|---|
| `bd413dc` | the previously shipped build — the "before" |
| `ed8de23` | concurrent HD gap scan (`407cf6c0`) + the p2p panic fix |
| `34ab0e7` | connection pooling, and the RPC pool lock released across the round trip |
| `a86fa37` | 429 treated as backpressure; budget-shrink fixes |
| `4254e19` | the per-node starting throttle removed |
| `25f6e1f` | the TRON equivalent — **the shipped build, the "after"** |

### B — the app

The same Flutter web build, served twice on two ports, differing **only** in
which `kdflib_bg.wasm` sits in `kdf/kdf/bin/` — `bd413dc` on one, `25f6e1f` on
the other. That isolates the KDF change exactly: identical Dart, identical SDK,
identical config, one wasm swapped.

A recorder script is injected as the first thing in `<head>`, wrapping `fetch`
and `XMLHttpRequest` before any app or KDF code can capture the originals. It
records url, host, JSON-RPC method, address, status and timing. It catches one
thing devtools cannot label: a fetch rejected by a failed CORS preflight has no
status anywhere in the HAR, but the rejection itself is observable here.

Both arms were driven through the real GUI: import the same seed, HD mode,
fresh wallet, then watch.

### Reproducing it

```bash
export KDF_TEST_SEED='...'   # not needed; the bench generates its own
python3 tool/kdf_rpc_burst_bench.py --bin-root <dir-of-extracted-kdf-builds> \
  --scenario gleec-only --mode unlimited --repeat 3 --json out.json
# (tool/kdf_rpc_burst_report.py was removed 2026-08-27 - it had no argparse and
#  read four hardcoded paths in an untracked out/, so it printed nothing on a
#  clean checkout. The tables below are the published output.)
```

### Evidence limits

The standalone KDF ladder and concurrency-sweep JSON are preserved under the
raw-data directory and are independently reproducible. The direct endpoint
header samples and the app-recorder summary were captured during this
investigation but their raw output is not in that archive, so those two parts
are corroborating evidence rather than the primary quantitative proof. The
reported UI banner itself was not reproduced; §5 establishes the mechanism and
observed opaque failures, not a pixel-for-pixel reproduction.

---

## 2. The headline: same requests, 8× the rate

GLEEC platform coin, HD, brand-new wallet, node answers everything, 220 ms RTT.
Median of three runs.

| build | ok | secs | HTTP reqs | peak req/s | in 1st sec | 429 | addresses probed |
|---|---|---|---|---|---|---|---|
| `bd413dc` **BEFORE** | 3/3 | **10.00** | **44** | **5** | 5 | 0 | 21 |
| `ed8de23` | 3/3 | 9.99 | 44 | 5 | 4 | 0 | 21 |
| `34ab0e7` | 3/3 | **1.50** | 44 | **43** | 37 | 0 | 21 |
| `a86fa37` | 3/3 | 2.17 | 44 | 30 | 19 | 0 | 21 |
| `4254e19` | 3/3 | 1.50 | 44 | 43 | 37 | 0 | 21 |
| `25f6e1f` **AFTER** | 3/3 | **1.49** | **44** | **43** | 37 | 0 | 21 |

The request count does not move. Not once, in any arm, at any commit. The rate
moves by 8.6×, and the wall clock by 6.7×.

What those 44 calls are, from one `25f6e1f` run:

```
  22  eth_getBalance
  21  eth_getTransactionCount
   1  eth_blockNumber
```

21 distinct addresses. §3 explains why.

### 2.1 The commit that did it

`34ab0e7` is the step change: 10.0s → 1.5s, 5/s → 43/s. Its subject is
`perf(eth): stop holding the RPC pool lock across the round trip` — before it, a
mutex around the web3 instance pool was held for the duration of each request,
so a coin could have exactly one EVM RPC in flight no matter what the
concurrency budget said. The gap scan had been running concurrently since
`407cf6c0`, but it could not *express* that concurrency until the lock was
released.

`ed8de23` — the commit that made the scan concurrent — shows no change at all
here, which is the tell: concurrency you cannot express is not concurrency.

### 2.2 With all six GRC-20 tokens enabled

Not the default (a fresh wallet activates GLEEC alone), but the ceiling if a
user enables the lot. Median of two runs:

| build | secs | HTTP reqs | peak req/s | addresses |
|---|---|---|---|---|
| `bd413dc` **BEFORE** | 39.62 | 176 | 5 | 27 |
| `25f6e1f` **AFTER** | 4.03 | 176 | 59 | 27 |

Same shape: identical count, ~12× the rate, ~10× faster.

### 2.3 What happens when the node pushes back

The same scenario with the mock refusing above 20 req/s:

| build | ok | secs | HTTP reqs | peak req/s | 429 |
|---|---|---|---|---|---|
| `bd413dc` **BEFORE** | 3/3 | 10.02 | 44 | 5 | **0** |
| `ed8de23` | 3/3 | 9.98 | 44 | 5 | **0** |
| `34ab0e7` | **0/3** | 1.02 | 37 | 37 | 7 |
| `a86fa37` | 3/3 | 2.14 | 44 | 30 | **0** |
| `4254e19` | 3/3 | 2.13 | 52 | 46 | 8 |
| `25f6e1f` **AFTER** | 3/3 | 2.22 | 53 | 45 | 9 |

Three things worth naming:

* `bd413dc` never trips the limit, because 5 req/s is under it. Decker's node
  never saw a 429 from this wallet before, and that is why.
* `34ab0e7` **fails outright**, 0/3. That was a real regression, found and fixed
  in `08d2228e`/`a86fa37` before it shipped. It is in this table only because
  the ladder is the honest way to attribute the change.
* The shipped build succeeds but pays for it: 53 HTTP requests where 44 are
  logical. The extra ~9 are retries of refused calls — a ~20 % amplification
  that exists only because the node is being pushed past its limit.

---

## 3. The addresses that are not in the UI

This is the BIP44 gap scan, and it is not new.

On a brand-new HD wallet KDF walks `m/44'/60'/0'/0/0` upward until it has seen
`gap_limit` consecutive *unused* addresses. The shipped `gap_limit` is 20, so it
probes 21 addresses, each costing one `eth_getTransactionCount` and one
`eth_getBalance` (plus one `eth_call balanceOf` per registered token). Only then
can it conclude the account is empty. The account ends with exactly one *known*
address — index 0 — and that is the one the UI shows. Nothing is filtering the
other 20 out; they were never known addresses, only candidates that came back
empty.

Verified against the diff: `eth_hd_wallet.rs`, `coin_balance.rs` and
`hd_wallet/` are byte-identical across `bd413dc..25f6e1f`, and the EVM
`is_address_used` body last changed in commits predating `bd413dc`. `407cf6c0`
changed *when* the probes are issued (windowed concurrency), not *which* — its
test pins the exact ordered list of probed addresses and passes unchanged.

The bench confirms it end to end: **21 distinct addresses on every build in the
ladder**, before and after, and the one address the app displayed
(`0xD341531d…dB6b`) is in that list.

So the honest answer to "requests balances for addresses that are not even
visible in the wallet" is: yes, by design, and it did so before this release
too — at 5 req/s, where it was invisible.

---

## 4. What the endpoint actually does

Measured directly with `curl`, 44 concurrent POSTs — one login's worth, the same
volume a single real user generates:

```
  20 HTTP/2 200
  24 HTTP/2 429
```

A refusal looks like this:

```
HTTP/2 429
date: Thu, 06 Aug 2026 21:52:49 GMT
content-length: 0
retry-after: 1
server: cloudflare
cf-ray: a2714553dbec5de5-JNB
```

**429 responses: 24 ; of those carrying `access-control-allow-origin`: 0.**

A successful response *does* carry `access-control-allow-origin: *` — it comes
from the Caddy origin (`via: 1.1 Caddy`). The 429 does not, because it is
generated at Cloudflare's edge and never reaches the origin that sets CORS.

The consequence in a browser: the response is CORS-invalid, so `fetch` rejects
with an opaque `TypeError` carrying **no status**. KDF's wasm transport turns
that into `TransportError::Message`, not `TransportError::Code(429)`. The retry
still fires (its catch-all covers transport errors), but the 429-specific
classification degrades to a bare `transport` — which is why our own logs could
not corroborate the screenshot. The `retry-after: 1` the node politely sends is
unreadable for the same reason.

### 4.1 Preflights are rate-limited too

The same 44-wide burst, but `OPTIONS`:

```
  20 HTTP/2 204
  24 HTTP/2 429
```

**429 preflights: 24 ; with `access-control-allow-origin`: 0.**

This matters more than the POST case:

* A KDF EVM RPC from a browser can be **two** charges against the limiter,
  because the wasm transport sends `Content-Type: application/json` in `cors`
  mode, which requires a preflight unless the browser can reuse a cached CORS
  permission. A fresh or preflight-expired 44-call login can therefore approach
  88 requests at the edge; it is not guaranteed to be exactly 88.
* A refused preflight is **unrecoverable by any client**. A preflight must
  return 2xx; there is no CORS header that rescues a 429 on `OPTIONS`. The POST
  is never sent.

That is exactly the pair of rows in Decker's screenshot: `preflight 429`
followed by `fetch CORS …`.

---

## 5. "Network error. Please check your connection."

The string is the translation for KDF's `error_type: "Transport"` — key
`kdfErrorTransport` (`assets/translations/en.json:1032`,
`sdk/…/kdf_error_messages.dart:178-181`). Nothing hardcodes it; it is emitted
only by the KDF-error formatters, keyed on that one error type, which KDF uses
as an umbrella for every web3 transport failure. A pool that exhausted its
retries against a refusing node, a CORS-blocked response and a dead network are
literally the same message.

On the coin-detail page the red banner is the `ErrorDisplay` inside the
**Addresses** card (`coin_addresses.dart:791-806`). The transaction table
renders a different string, so a tx-history failure cannot produce this
sentence. GRC-20 tx history does **not** go through `etherscan.gleec.com` at all
— `CoinSubClass.grc20` has no entry in the Etherscan helper's switch, so GLEEC
falls through to KDF's legacy `my_tx_history`.

So the banner in the screenshot is the GLEEC pubkey/activation path failing with
a transport error — i.e. the 429/CORS storm — not an explorer problem.

### What we reproduced

Against the real endpoints, the same app build, same seed, fresh wallet:

| | `bd413dc` BEFORE | `25f6e1f` AFTER |
|---|---|---|
| peak req/s on `evm-rpc.gleec.com` | **6** | **30** |
| requests that failed with **no status** (CORS-blocked) | **0** | **12** in the first 37 s |
| all other responses | 96 × `200` | `200` |

The peak-rate and failure figures are matched: both are the login burst, same
machine, same wallet, one wasm swapped. The *total* session request counts are
not directly comparable, because the "after" session also navigated to the
GLEEC coin page and its tabs — for the count comparison, use the standalone
ladder in §2, which is matched by construction.

We did not reproduce the banner itself in the lab; the controlled
CORS-stripping arm was set up but the GUI import could not be driven to
completion. The mechanism is nonetheless established by three independent
pieces of evidence: the endpoint's measured behaviour (§4), the wasm transport's
code path, and the 12 opaque failures observed live against the real node.

---

## 6. Native concurrency sweep

`KDF_EVM_RPC_MAX_CONCURRENCY` sweep on the shipped build, node at 20 req/s,
GLEEC alone, median of three runs each:

| starting concurrency | secs | HTTP reqs | peak req/s | 429s |
|---|---|---|---|---|
| 2 | 5.30 | 44 | 10 | **0** |
| 4 | 3.04 | 44 | 20 | **0** |
| **6** | **2.15** | **44** | **30** | **0** |
| 8 | 1.92 | 46 | 40 | 2 |
| 12 *(current default)* | 2.16 | 53 | 45 | 9 |

**6 is strictly better than 12 in this native controlled scenario**: the same wall
clock (2.15s vs 2.16s), 17 % fewer requests, a third lower peak, and no
refusals at all. The extra 9 requests at budget 12 are retries the client only
needs because it provoked the refusals in the first place.

This is the throttle that commit `4254e19` removed. That commit's own sweep
supports keeping it — it recorded budget 6 at 7.44s against budget 12 at 8.31s —
but read the table as showing the throttle "counterproductive" on the strength
of budget **2** being slowest. Budget 2 is slow; budget 6 is not.

With all six tokens the picture is similar but noisier (two runs, high variance):
budget 4 gives 176 requests and zero 429s in 10.45s, against 185–234 requests
and 9–58 429s at the default.

**Caveats that decide the shape of the fix:** the benchmark sends POST requests
directly and therefore does not include browser CORS preflights. If `OPTIONS`
shares the node's limiter, the web edge load can be materially higher, so this
table alone does not justify a global default of 6. A production fix should be
web-aware and preferably rate-aware or per-chain rather than relying on one
global concurrency number.

Also, `std::env::var` always fails on
`wasm32`, so `KDF_EVM_RPC_MAX_CONCURRENCY` is unreachable in a browser — the
platform where this was reported. The knob is a native-only diagnostic. Fixing
this for web means changing the default in code, not shipping a setting.

---

## 7. Amplifiers worth naming

Found while tracing the above; each is outside the `bd413dc..25f6e1f` range and
each independently multiplies the traffic a node sees.

1. **The SDK re-runs the whole gap scan per EVM asset, every session.**
   This already existed on `dev`. On a brand-new EVM/TRON wallet KDF's default
   `scan_if_new_wallet` activation behavior means the immediately following SDK
   scan is duplicate work, even though ETH-family SDK activation params do not
   expose that policy. On a warm login activation does not scan, so the SDK scan
   is necessary; it is not redundant in every session.
2. **`watchPubkeys` re-polls every 30 s**, and `EthBalanceEventStreamer` every
   10 s, for the life of the session. Those timers predate this KDF range. The
   faster KDF makes each refresh burst sharper, but does not inherently increase
   a fixed timer's number of cycles per minute.
3. **The app retries activation up to 4 times** (`coins_repo.dart:661`) on top of
   KDF's 5 attempts per RPC. This can amplify failures, but it is not a branch
   regression: `dev` allowed up to 15 activation attempts on this path.
4. **Three blocs fan out over the whole coin list at login** — `PortfolioGrowth`,
   `ProfitLoss`, `AssetOverview` — each walking every coin with `Future.wait`.
   ~9 GETs to `etherscan.gleec.com` and up to 15 to `api.trongrid.io` in the
   first seconds for the default 8-coin wallet.
5. **TronGrid's polite-retry path is dead on web** for the same CORS reason: a
   blocked 429 arrives as a `ClientException`, so the `Retry-After` handling
   never runs and each logical page can become six GETs.

Items 1-5 are not the primary KDF regression, and several are requests to
different services rather than the EVM node. They should not be added to the
44-call KDF activation count.

### 7.1 TRON and GasFree-specific traffic

The same lock-release change also removed TRON's request-around-the-pool mutex,
so TRON activation changed from effectively serial traffic to a shared budget
of 12. Current TRON reads then retry up to three times after the first attempt;
with the two configured platform nodes that is a theoretical ceiling of eight
wire attempts for one retryable logical read. The final TRON retry commit
improved its own activation reliability from 5/7 to 7/7 test runs while
recording 24 rate-limit backoffs across seven runs. That is a deliberate
reliability-for-volume tradeoff, though this investigation has no TRON raw
request-count trace equivalent to the EVM ladder.

GasFree itself adds a much smaller branch-specific call: after successful
activation the SDK requests `gasless::account_status`. That normally means one
GasFree-provider request plus an on-chain TRC-20 balance read, and custody-aware
history polling can repeat the status request. It is real extra traffic, but it
does not explain the dozens of simultaneous EVM-node requests.

---

### Checked and ruled out — do not spend time here

Carried over from the retired `SDK_BALANCE_STREAMERS.md` task. Negative results
are exactly what gets re-derived at cost, so they outlive the task that produced
them.

- **`get_enabled_coins` is a local KDF state read** (`mm2src/coins/rpc_command/get_enabled_coins.rs:37`).
  Zero node traffic. So `ActivatedAssetsCache` (`assets/activated_assets_cache.dart:184`),
  `_waitForCoinAvailability` (15 tries) and `waitForEnabledAssetsToPassThreshold`'s 2s backstop
  (`activation/shared_activation_coordinator.dart:350-395`, `komodo_defi_sdk.dart:101`, `:534`) are
  not amplifiers. The 250ms join window already collapses the login burst.
- **`retry(() => _activationCoordinator.activateAsset(...))`** in `pubkey_manager.dart` looks like a
  5× activation amplifier (`retry_utils.dart:39-41`, no `shouldRetry` filter) but is **inert on the
  failure path**: `activateAsset` returns `ActivationResult.failure(...)` rather than throwing
  (`shared_activation_coordinator.dart:225-268`). It can only fire on a *thrown* error, and
  `_fetchFreshPubkeys` ignores the result and proceeds regardless.
- **EVM transaction history hits the explorer, not the node.** `EtherscanTransactionStrategy` is
  first in the factory list and matches any `Erc20Protocol` with a configured API URL
  (`transaction_history_strategies.dart:17`). The tx-history manager's 30s `my_balance` timer poll
  (`transaction_history_manager.dart:107`, `:923`, `:1144`) is gated to non-streaming or gasless
  TRC-20 assets (`:1090-1096`) and therefore **never runs for GRC-20**.
- **`MarketDataManager`, `FeeManager`, and `coins_bloc`'s two 3-minute timers**
  (`market_data/market_data_manager.dart:95`; `lib/bloc/coins_bloc/coins_bloc.dart:248`, `:427`)
  touch CEX price APIs or app state only. The balance sweep only fires when a watcher is actually
  missing.

## 8. What to do

**On the wallet/KDF side**

* Add a web-aware/per-chain request-rate guard. The native data makes 4–6 a
  strong candidate range for this GLEEC scenario, but browser preflights must be
  included before selecting the production default. It must be a code default,
  not an env var, because the env var does not exist on web.
* Avoid the immediate duplicate gap scan on a brand-new EVM/TRON activation
  without suppressing the necessary scan on warm login. That requires making
  the activation scan decision explicit or returning whether activation
  actually scanned; merely assuming every activation scanned is unsafe.
* Consider whether `watchPubkeys` needs 30 s on a chain whose addresses cannot
  change without a transaction.
* Classify opaque browser transport failures as backpressure explicitly rather
  than relying on the retry's catch-all, so the adaptive budget reacts on web
  the way it does on native.

**On the node side** — in this order, because the first is the one no client can
work around

1. **Exempt `OPTIONS` from rate limiting.** A preflight carries no payload and
   costs the origin nothing, it is currently charged at full rate, and a 429 on
   a preflight cannot be retried into success by any client.
2. **Add `Access-Control-Allow-Origin` to error responses**, including the ones
   Cloudflare generates at the edge. Today the `retry-after: 1` the node sends is
   unreadable by every browser client. With it, clients can back off precisely
   instead of guessing.

Between them, those two changes turn an unrecoverable opaque failure into a
readable, honoured backoff — which is what makes the rate limit do its job
instead of just breaking the client.
