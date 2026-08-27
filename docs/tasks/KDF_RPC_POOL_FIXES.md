# KDF: five RPC-pool defects that make a rate-limited node worse

Follow-up work from [`KDF_RPC_BURST_REPORT.md`](../KDF_RPC_BURST_REPORT.md). Each item below is
**measurement-independent** — none waits on the pending rate-ladder benchmark.

**Target:** `komodo-defi-framework`, branch `perf/evm-rpc-429-backoff` @ **`25f6e1f0b`** — the
shipped build. Remote is `GLEECBTC/kdf-internal` only (no fork, no upstream). Line numbers are
anchored to that commit.

**Sibling tasks:** [`SDK_GAP_SCAN_AND_WEBSOCKET.md`](SDK_GAP_SCAN_AND_WEBSOCKET.md),
[`SDK_BALANCE_STREAMERS.md`](SDK_BALANCE_STREAMERS.md). All three are independent — no ordering
constraint between them. Item 5 here is the only one that interacts with another task, and it is
an optimisation there rather than a prerequisite.

---

> ## Read the working tree before you start
>
> At the time of writing, `perf/evm-rpc-429-backoff` had **~437 uncommitted lines** across
> `mm2src/coins/eth/eth_rpc.rs` (+363), `eth_rpc_retry_tests.rs`, `v2_activation.rs` and `nft.rs`,
> plus two `AGENTS.md` files. That work introduces a `Retry::Allowed`/`Retry::Forbidden` enum with
> `try_rpc_send_once`, `MAX_RPC_RETRY_ELAPSED = 30s` (a wall-clock bound on the EVM retry,
> mirroring TRON's), and classification of the in-band JSON-RPC rate-limit codes `-32005` /
> `-32029`.
>
> Some of what follows may already be partly done there. **Run `git diff` first. Reconcile; do not
> clobber.**

## Context

`MAX_RPC_RETRIES = 4` sits *outside* the node loop, so one logical RPC costs up to 5 passes × N
nodes. GLEEC has exactly one node (`https://evm-rpc.gleec.com`), which serves ~20 req/s and whose
429s are generated at Cloudflare's edge **without** `Access-Control-Allow-Origin` — so in a browser
they arrive as an opaque error with no status at all.

---

## 1. Start and ceiling are the same number

`mm2src/coins/eth/web3_pool.rs:389-391`

```rust
let ceiling = starting_concurrency();
ConcurrencyController {
    permits: RpcPermits::new(ceiling),
    ceiling,
    ...
}
```

Start and ceiling are identical by construction, and `on_success` refuses to grow past
`self.ceiling`. **Any future lowered start silently becomes a permanent cap** — which is precisely
the "permanent tax on all 580 EVM-family coins" objection that motivated commit `4254e19a9`
removing the single-node throttle in the first place.

**Fix.** Split them: `ceiling` from `configured_concurrency()`, `start` as a separate value clamped
by `.min(ceiling)`. Preserve `concurrency_override() -> Option<usize>` semantics exactly — an
explicit `KDF_EVM_RPC_MAX_CONCURRENCY` must still be taken literally, because re-flooring it is the
bug `4254e19a9` legitimately fixed.

This lands no behaviour change on its own. It makes a lowered start *possible* without a permanent
cost. **Do not pick the starting value here** — see [Out of scope](#deliberately-out-of-scope).

## 2. The shrink trigger cannot fire during the burst it exists for

`mm2src/coins/eth/web3_pool.rs:405-433`, constants at `:130-142`

`on_success` does `self.consecutive_refusals.store(0, Ordering::Relaxed)`. During a burst the
endpoint serves 20/s and refuses the rest, so successes and refusals interleave *by construction*
and a run of `REFUSALS_BEFORE_SHRINK = 3` rarely completes.

In the raw data ([`assets/kdf_rpc_burst_data/mitigation_12.json`](../assets/kdf_rpc_burst_data/))
the controller descends at most `12 → 6 → 3` across a whole ~2s activation and never reaches
`MIN_CONCURRENCY`.

> **Caution reading that data:** `mitigation_tok_12.json` run 0 and both `mitigation_tok_6.json`
> runs show *no* pool lines — but they also lack the construction line `EVM RPC pool: 1 node(s),
> max 12 concurrent`, so those tails are truncated before the start. "Zero shrinks with 58
> refusals" would be an artefact. The defensible claim is **"at most two steps, never to the
> floor"**.

**Fix.** Trigger on a **refusal ratio over a sliding window** (e.g. >25% of the last 16 outcomes)
rather than on consecutiveness. This is strictly better than a node-count gate:

- healthy pools have a ratio near zero, so nothing moves — no permanent tax;
- it keys on refusal, which is observable on wasm, so it works on the platform the incident came
  from;
- it covers TRX, which has 2 nodes against TronGrid's 3 req/s allowance (see the comment at
  `mm2src/coins/eth/tron/api.rs:936-946`) and which any `nodes <= 1` gate would miss.

Two existing tests pin the behaviour being deleted and must be replaced:
`budget_halves_under_sustained_refusal` and `a_success_breaks_a_run_of_refusals`.

## 3. `Retry-After` is stored per node but consumed per call

`mm2src/coins/eth/web3_transport/http_transport.rs:90-95`

```rust
pub(crate) fn take_retry_after_s(&self) -> Option<u64> {
    match self.retry_after_s.swap(0, Ordering::Relaxed) { 0 => None, s => Some(s) }
}
```

`swap(0)` is read-and-clear, and `backoff_for` calls it once per backoff computation. When twelve
concurrently-refused calls all take it, one wins and eleven get `None`, falling back to
`RETRY_BACKOFF_BASE_MS = 150` — which after `half + jitter_ms(half)` is an effective **75–150ms**
first backoff. Against an endpoint refilling one token per 50ms, **the retry pass ends up denser
than the burst that caused it.**

The type's own doc comment (`http_transport.rs:48-50`) says the hint is per-node "because that is
the scope the hint describes". The code then makes it per-request.

**Fix.** Store `now + retry_after` as a non-consuming per-node *quiet-until* instant that expires
naturally, read by every caller, and gate `Web3Pool::acquire` on it so the pause applies to the
pool rather than to whichever call won the race.

**Also closes a shipped stall.** At `25f6e1f`, `backoff_for` applies `.min(RETRY_BACKOFF_MAX_MS)` to
the exponential term only, then `let wait = exponential.max(requested_ms)`. `parse_retry_after`
accepts up to 120s, so a node asking for two minutes holds a permit — a slot in a pool shared with
the platform coin and every token on that chain — for two minutes. Check whether the in-flight
working-tree edit already moved that `.min()`; if not, bound the final wait.

Native-only by nature: a browser cannot read the header. Item 4 is the web half.

## 4. On web, a permanently-failing node is retried five times

`mm2src/coins/eth/eth_rpc.rs`, `is_retryable` ~line 268

`is_retryable` correctly refuses to retry `400..500` — *when a status exists*. On wasm a CORS-less
error response has no status, so a 403, a wrong URL or a revoked key falls into the
`web3::Error::Transport(_) => true` arm and costs 4 extra passes. On a one-node pool that is **five
wire requests for a request that can never succeed**, four backoffs, and a shared permit held
throughout.

The 429-blindness has always been discussed as "we cannot *detect* backpressure". The symmetric
half is unaddressed: we cannot detect a *permanent* failure either, so we hammer it.

**Fix, needing no status.** Keep a per-node "has this node ever answered successfully this session"
bit next to `preferred` in `web3_pool.rs`. Before the first success, an opaque transport failure
gets one retry, not five; after it, the full budget. Zero cost on the healthy path, works on every
target.

## 5. Node order is randomised, so transport preference cannot be expressed

`mm2src/coins/eth/v2_activation.rs:1184-1185`

```rust
let mut rng = small_rng();
eth_nodes.as_mut_slice().shuffle(&mut rng);
```

and `Web3Pool.preferred` starts at `AtomicUsize::new(0)` — index 0 of the **shuffled** list.

This is inert today because every node is HTTP. It stops being inert the moment
[`SDK_GAP_SCAN_AND_WEBSOCKET.md`](SDK_GAP_SCAN_AND_WEBSOCKET.md) part 2 lands and pools contain
both `wss://` and `https://` entries for the same chain: which transport a chain actually uses
becomes a coin flip per login, and the pool can thrash `preferred` between the two.

**Fix.** Partition so WebSocket instances sort ahead of HTTP ones, keeping the shuffle *within*
each group so load still spreads across equivalent endpoints.

**This is an optimisation, not a gate.** `mark_preferred` repoints on the first successful ws call,
and `on_node_refused()` is not called when the failover loop recovered — so an unlucky shuffle
costs roughly the first wave (up to the permit budget, ~12 requests) landing on HTTP, not the whole
44-call burst. The SDK-side rollout is correct and beneficial without this. What this buys is
determinism and the removal of preferred-thrashing.

---

## Deliberately out of scope

**Do not pick a starting-concurrency value.** The report's §6 recommends 6, but the raw data
contradicts it: budget 6 shows zero 429s in the GLEEC-alone arm only because a 44-request job fits
inside the endpoint's 20-token burst allowance. The six-token arm at budget 6 draws **37 × 429 and
213 wire requests**. Budget 4 (~18 req/s at the measured 220ms RTT) is the only arm with zero
refusals in both scenarios, and §6 never mentions the budget-6 token arm at all. The value decision
waits on the rate-ladder benchmark; item 1 is what makes it cheap to land later.

**Do not change the wasm content-type to skip the CORS preflight.** Tested against the shipped
endpoint: it returns **HTTP 415** for every CORS-safelisted content type. There is no partial
version worth landing. The real fix is node-side — `Access-Control-Max-Age`, and exempting
`OPTIONS` from the rate limit — and belongs with the node operator.

**Do not implement the report's §8 bullet "classify opaque browser transport failures as
backpressure explicitly".** Already satisfied: `is_retryable` matches `Transport(_)` without
inspecting a status *by design*, so `TransportError::Message` reaches `on_node_refused()` on
exactly the same path a native `Code(429)` does, with no `cfg` gate anywhere. The only real
native/web asymmetry left is the `Retry-After` floor, which is item 3. That bullet should be
corrected in the report rather than implemented.

## Noted, much larger, not this task

**JSON-RPC batching** — 44 logical calls → 1 HTTP request — is the only lever that is strictly
better on both load and latency, and it was verified working against this exact endpoint (a 60-call
batch returns HTTP 200 with all 60 results). But `HttpTransport` implements `Transport` only
(`http_transport.rs:120-129`) and the wasm arm actively rejects an array response
(`Response::Batch(_) => Err("Expected single, got batch.")`). It needs a request-coalescing layer in
`Web3Pool`.

Worth recording so it is not dismissed on stale grounds: the earlier "batching is not a lever"
verdict in [`KDF_LATENCY_REPORT.md`](../KDF_LATENCY_REPORT.md) was about *latency while the pool
mutex was the bottleneck*. It was never assessed as a *load* lever, and post-mutex the arithmetic is
different. Multicall3 is not an alternative — `eth_getCode` on `0xcA11bde05977b3631167028862bE2a173976CA11`
returns `0x` on GLEEC.

## Done means

- `cargo check` passes and the `eth_rpc_retry_tests.rs` suite is green, including replacements for
  the two deleted controller tests.
- Each fix carries a doc comment stating the mechanism and what it cost. Match the existing voice in
  `web3_pool.rs`, which explains *why* rather than *what*.
- Conventional Commits, one commit per fix.
- **Do not build or deploy artefacts**, and do not repoint `build_config.json` in the wallet repo.
  Shipping means 7 targets via `nitride-kdf-builds` and a Cloudflare R2 deploy — a separate,
  outward-facing step that needs explicit sign-off.
