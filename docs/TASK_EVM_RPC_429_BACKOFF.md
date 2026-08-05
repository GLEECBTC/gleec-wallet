# Task: make the EVM RPC pool survive a rate-limited single-node chain

**Status:** open. **Blocks:** shipping KDF `perf/evm-rpc-concurrency`
(`34ab0e7aa`), which is otherwise a 7.8× win on EVM activation.

> **This file has a lifecycle.** Delete it when the work lands; the findings
> belong in [`KDF_IMPROVEMENT_OPPORTUNITIES.md`](KDF_IMPROVEMENT_OPPORTUNITIES.md),
> the numbers in [`WALLET_LOAD_PERFORMANCE_REPORT.md`](WALLET_LOAD_PERFORMANCE_REPORT.md).
> Do not let it become another permanent incremental document.

---

## The problem, already diagnosed and measured

`34ab0e7aa` released the `web3_instances` mutex, taking EVM activation from a
212.1s median to 27.3s. It also introduced a concurrency budget
(`DEFAULT_MAX_CONCURRENT_RPCS = 12`, `mm2src/coins/eth/web3_pool.rs:65`).

**GLEEC activation now fails 100% of the time.** GLEEC is in the app's
`enabledByDefaultCoins`, so this is on every login.

Measured, alternating arms, same seed and servers:

| binary | r0 | r1 | r2 |
|---|---|---|---|
| `ed8de23` | 11.44s ok | 10.46s ok | 10.50s ok |
| `34ab0e7` | 1.18s ERR | 1.13s ERR | 1.04s ERR |

**Isolated to `34ab0e7aa`.** The two arms are two commits apart - `40ebcbc9c`
("perf(net): add a connection-pooling Hyper client") sits between them and
independently enables HTTP/2 multiplexing, connect-dedup and hyper's
`retry_canceled_requests` on this path. It was tested separately and is
**innocent**:

| binary | r0 | r1 |
|---|---|---|
| `ed8de23` (base) | 10.14s ok | 10.18s ok |
| `40ebcbc9c` (pooled client only, mutex still held) | 10.29s ok | 10.08s ok |
| `34ab0e7aa` (pool + mutex released) | **1.17s FAIL** | **1.20s FAIL** |

So the trigger is in the mutex release and the concurrency budget it introduced,
not in connection pooling.

Cause, measured directly against the endpoint:

| concurrent requests to `evm-rpc.gleec.com` | result |
|---:|---|
| 1 | 1/1 ok |
| 4 | 4/4 ok |
| **12** | **10/12 — `HTTP 429` begins** |
| 24 | 3/24 ok |

The default budget of 12 lands exactly where that endpoint starts refusing.
GLEEC is the only default coin with **one node** (ETH 4, TRX 2,
BNB/AVAX/MATIC 5/5/4), so there is nothing to fail over to and activation dies
in ~1s.

> **That table is a burst measurement and does not transfer directly to KDF.**
> A budget of **4 still fails through KDF** even though the endpoint served 4
> concurrent raw HTTP requests cleanly. So the raw numbers bound what a naive
> client can do, not what KDF does to this endpoint. Something makes KDF's
> pressure at a given permit count higher than the permit count suggests - more
> request types per address, retries, or permits not mapping 1:1 to in-flight
> requests. **This discrepancy is unexplained and is your best clue.** Resolve
> it before choosing a fix shape; a fix aimed at the wrong quantity will look
> right on the raw table and still fail.

**Nodes cannot be borrowed from other coins** — verified via `eth_chainId`
across every configured HTTP node. Each serves only its own chain (ETH 1,
BNB 56, AVAX 43114, MATIC 137, ETC 61); only `evm-rpc.gleec.com` returns
GLEEC's 11169.

**The env var is not a mitigation.**

| `KDF_EVM_RPC_MAX_CONCURRENCY` | GLEEC | ETH + 2 tok |
|---|---|---|
| 12 (default) | **1.14s FAIL** | 20.85s |
| 4 | **2.57s FAIL** | — |
| 2 | 4.90s ok | 94.67s |

Only 2 rescues GLEEC, at a cost of ETH 20.85s → 94.67s (4.5×). And
`configured_concurrency()` (`web3_pool.rs:71-79`) reads `std::env::var`, which on
`wasm32` always returns `Err` - web silently gets 12, and **the preview is web**.
The cap is a native-only diagnostic knob, not a mitigation.

---

## What to build

Make the pool adapt to what an endpoint will actually accept, instead of
applying one process-wide number to every chain.

**Preferred: treat 429 (and 503 / `Retry-After`) as backpressure, not death.**
Today a rate-limited response fails the endpoint over; with one node that ends
the activation. Retry with backoff, honour `Retry-After` when present, and only
fail the request when the budget of retries is exhausted.

**Also worth doing, and cheap: scale the budget by node count.** Something as
simple as `min(default, nodes.len() * k)` gives a single-node chain a small
budget for free and needs no new state. It does not replace backoff — a
single-node chain with a low limit still needs to not fall over — but it removes
the stampede at source.

**Do not** solve this by lowering the global default. It is measured at
ETH 20.85s → 94.67s, and it would penalise the multi-node coins the change
exists to speed up.

Whatever you choose must work on **`wasm32`**. That rules out `std::env::var`
and threads — but the sharper trap is that **a 429 is currently invisible
there**.

`telemetry::http_status` (`eth_rpc.rs:163`) recovers the status by matching the
marker `"response !200: "`, which only the **native** transport emits
(`http_transport.rs:180`). The wasm arm emits `"!200: {status}"` without the
`response ` prefix (`http_transport.rs:274`), so `classify()` returns
`transport` and any `kind == "http_429"` trigger **never fires in a browser**.

An implementer who reuses that helper — the obvious move, it is already named
`http_429` — ships a fix that passes every native criterion and does nothing on
the one target criterion 2 exists for. Two consequences:

* Do not build the trigger on that string. Make the status machine-readable on
  both targets: unify the two format strings, or better, carry the status in the
  error rather than re-parsing a message. That string contract has now caused a
  bug twice.
* **The retry must also engage without a recognised status.** A rate-limited
  response in a browser can surface as an opaque network error with no readable
  status if the endpoint omits CORS headers on error responses. Capture a raw
  429 from `evm-rpc.gleec.com` and check whether `Access-Control-Allow-Origin`
  and `Retry-After` are actually present before depending on either.

Use `common::executor::Timer::sleep_ms` and `compatible_time::Instant` (both
exist on either target) — not `std::thread::sleep`, `std::time::Instant`, or
tokio timers.

**Consider making the budget adaptive rather than status-driven.** A budget that
shrinks on sustained refusal and recovers afterwards works on wasm *without*
being able to read a status, because repeated failure is observable on both
targets. `RpcPermits` (`web3_pool.rs:91-120`) is channel-backed, so resizing at
runtime is cheap: shrink by taking a permit and dropping it, grow with
`tx.unbounded_send(())`.

---

## Acceptance criteria

**Correctness**

1. GLEEC activates on `34ab0e7`+fix, **10/10 consecutive runs**, native.
2. GLEEC activates in a **web** build — the case the env var cannot reach and
   the one the preview exercises.
   **`tool/web/kdf_web_probe.html` cannot do this today.** All three of its
   scenarios are `coins: ["KMD"]` and its only activation helper is
   `activateUtxo` → `task::enable_utxo::init`; it has no
   `enable_eth_with_tokens` at all. Extending it is part of this task, not a
   precondition someone else has met. Mirror the params from
   `kdf_latency_probe.py::_activate_eth_with_tokens` so the two tiers stay
   comparable, and note the page must be served from a `flutter build web`
   output so the wasm and coins config resolve.
3. No regression on the multi-node coins: KMD, BTC-segwit, ETH+2 tokens,
   TRX+1 token all within noise of their `34ab0e7` numbers.
4. The app-default coin set completes end to end with **zero failed steps**.

**Performance** — at least **3 alternating rounds per arm**, medians *and*
spread reported, never a single draw:

| scenario | `34ab0e7` | target |
|---|---|---|
| ETH + 2 ERC-20, first-time HD | 20.85s | **keep it.** ≤25s |
| TRX + USDT-TRC20, whole path | 8.4s | ≤10s |
| GLEEC | fails | **works**, ≤11s (its `ed8de23` time) |
| app-default set, HD, `--p2p` | n/a (GLEEC fails) | publish the number |

If the fix costs more than ~20% on ETH, say so plainly and explain the
trade-off rather than quietly shipping it.

**Evidence quality**

5. A test that **fails without the fix** — not merely passes with it. Verify by
   reverting the fix and watching it go red.
6. Per-endpoint 429 counts captured via `evm_rpc_failover` / `KDF_EVM_RPC_TRACE=1`,
   showing backoff engaging rather than the endpoint being written off.

**Coverage — the gap that let this ship**

7. Something in CI must activate GLEEC, or any single-node EVM coin. Every gate
   was green on the broken build: sdk 631, harness replay 22, process tier 4,
   bench within 1.9%, app 528, full app CI 8/8. The process tier exercises
   **KMD, a UTXO coin**. Without this, the next occurrence is equally invisible.

**Scope analysis — required in the PR description**

8. State up front, before writing code, your expected **complexity, scope and
   duration**: which files, roughly how many lines, and how long.
9. On completion, report the **actual** against that estimate, and explain any
   divergence. Specifically:
   * files/lines you did not anticipate touching, and why;
   * anything that turned out to be a different problem than diagnosed above.
     Treat this document as a strong lead, not gospel: its root cause was
     **wrong once** (it blamed the websocket transport until measurement showed
     HTTP 429s over HTTP), and its attribution was **under-controlled once**
     (the original A/B spanned two commits; `40ebcbc9c` was only cleared later,
     by direct test). The budget-4 anomaly flagged above is still unexplained;
   * whether the acceptance criteria were the right ones, and what you would
     add.

   The point is calibration, not blame. A large divergence is a useful finding
   about the codebase; hiding it is not.

---

## How to work

* **Edit in** `komodo-defi-framework` (sibling checkout), branch from
  `perf/evm-rpc-concurrency` (`34ab0e7aa`). Push to `fork` (CharlVS) **only**.
* **Measure from** this repo — the probe and harness take `--kdf <path>` and
  never require repointing the app.
* Build loop: `cargo build --release --target aarch64-apple-darwin --bin kdf`,
  then `python3 tool/kdf_latency_probe.py --coin-list GLEEC --kdf <path> --p2p`.
* Full process in [`KDF_RELEASE_RUNBOOK.md`](KDF_RELEASE_RUNBOOK.md); measurement
  traps in [`WALLET_LOAD_MEASUREMENT.md`](WALLET_LOAD_MEASUREMENT.md) — read the
  traps, they have each produced a wrong number at least once.

**Reproduce the failure first, before changing anything.** If it does not
reproduce, stop and find out why before writing a fix for a problem you cannot
see.
