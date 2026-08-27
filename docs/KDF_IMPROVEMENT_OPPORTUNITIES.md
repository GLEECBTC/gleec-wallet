# KDF-side opportunities — what to change, ranked by measured seconds

Companion to [`KDF_LATENCY_REPORT.md`](KDF_LATENCY_REPORT.md), which measures
the problem. This one says what to do about it, in KDF's own code.

> **Every "DONE" / "IMPLEMENTED AND MEASURED" marker below describes the perf
> fork, not the shipped build.** On 2026-08-24 the wallet rolled to KDF `main`
> (`f3efd2c`) and descoped the perf stack. Items 1 (concurrent gap scan), 2
> (`web3_instances` mutex) and 4 (pooled Hyper client), plus the TRX/NFT p2p
> panic fix and the TRON `try_clients` retry, are all implemented **only on
> kdf-internal PRs #18/#19/#20, which are unmerged and out of the pin**. Read
> every completion marker as "done on a branch we are not shipping". Items 3
> (`HDAccountsMutex` held across network I/O), 5 (electrum `responses.clear()`
> drain), the Tendermint unwraps, the `rpc.rs:361` string and the three
> coins-config items were never implemented and remain genuinely open — item 3
> is now *more* relevant, since item 1 is not shipped and its ~21s does not
> evaporate. Authoritative status:
> [`KDF_PERF_STACK_DESCOPE.md`](KDF_PERF_STACK_DESCOPE.md).
>
> **The Rust `file:line` anchors are also unusable**: they point into `bd413dc`
> on a fork that is no longer a remote. Re-anchor against `f3efd2c` before
> acting on any of them.

> **The ranking is stale: the gap limit changed under the seconds it ranks by.**
> Every figure inherited from the latency report was measured at
> `gap_limit: 20`; the shipped SDK now sends `software = 3` /
> `newlyGeneratedFirstSignIn = 1`
> ([`hd_gap_limit.dart`](../sdk/packages/komodo_defi_types/lib/src/public_key/hd_gap_limit.dart)),
> with `hardware = 20` for Trezor only. Since this document ranks opportunities
> **by measured seconds**, and the gap-scan items scale with addresses walked,
> narrowing the gap limit shrinks exactly those items — **so the running order
> here is no longer trustworthy.** Re-measure at gap 3 and gap 1 before using
> this to choose what to work on next.

**Source:** `komodo-defi-framework` @ **`bd413dc`** (branch `feat/tron-gasfree`)
— the exact commit of the binary that produced every number in the latency
report. Line numbers are anchored to that commit. The repo's default checkout
is `dev` (`987ef437`), where `lp_coins.rs` and `eth.rs` have drifted 20–90
lines; if a citation does not match, check which commit you are on.

**How this was produced.** Six independent readers of the Rust source, one per
measured symptom, then two adversarial reviewers per surviving candidate — one
asking *"is this actually where the time goes"*, one asking *"would this break
swap safety, and is it really as small as claimed"*. 26 raw findings → 6
candidates → all 6 survived, but **most were corrected in the process**. Where a
reviewer moved a number, the corrected number is what appears below. Claims
marked ✅ I re-verified myself against `bd413dc`.

---

> ## ✅ Items 1 and the panic fix are IMPLEMENTED and MEASURED
>
> Branch `perf/hd-scan-concurrency` off `bd413dc` in the local KDF clone — two
> commits. (It was pushed to `CharlVS/komodo-defi-framework` at the time; that
> fork is no longer a remote of the clone.) Built for
> `aarch64-apple-darwin` and re-measured with the same probe, same seed, same
> servers. Results in [§ Validation](#validation-what-actually-happened) below.
> **Headline: KMD activate 46.9s → 6.1s; BTC-segwit 121.2s → 8.2s; gap-50
> 107.0s → 7.6s.** Predictions that were wrong are called out there.

## Answer

**Yes, and one change dominates.** Batching the HD gap scan removes ~38–41s
*per UTXO coin* and, uniquely, its saving does not scale with `gap_limit` — it
makes the gap limit nearly free rather than merely smaller.

Two framing points that change how to read the numbers:

* **Almost all of this is new-wallet pain.** The dominant cost is the gap walk,
  which only runs to full length on a wallet with no history. Items 2 and 4 help
  every wallet; the rest largely do not.
* **Do not sum the savings.** Items 1 and 3 overlap (fixing the scan dissolves
  most of the account-balance stall). Items 2 and 4 overlap (the handshake is
  part of the per-RPC cost item 2 holds constant).

---

## 1. Window and batch the HD gap scan — ~38–41s per UTXO coin

**Current behaviour.** `scan_for_new_addresses_impl` is a strictly sequential
per-address loop:

* `lp_coins.rs:6328` — the function ✅
* `lp_coins.rs:6349` — `while checking_address_id < max_addresses_number && unused_addresses_counter <= gap_limit` ✅
  (note `<=`, so `gap_limit + 1` probes per chain)
* `lp_coins.rs:6357` — exactly one awaited `coin.is_address_used(...)` per iteration, no early exit ✅
* `utxo.rs:970-983` — the Electrum arm of that probe is one `blockchain.scripthash.get_history`
* `utxo_common.rs:190-209` — External is awaited to completion, *then* Internal

At the shipped `DEFAULT_GAP_LIMIT = 20` (`hd_wallet/mod.rs:73`) that is
2 × 21 = **42 strictly serialized round trips per coin**.

**The batch primitive already exists and is already in production.**
`scripthash_get_history_batch` (`electrum_rpc/client.rs:593-601`) ✅ builds one
`JsonRpcRequestEnum::Batch` through one `transport()` call
(`jsonrpc_client.rs:336-363`) — a single socket round trip. Its only caller
today is tx history (`utxo_tx_history_v2_common.rs:379`) ✅. The scan path does
not use it.

**Attribution is airtight.** `gap_limit` has no other consumer in the
activation path — it reaches only this loop, `enable_hd_account`
(`coin_balance.rs:444-448`) and the unrelated `get_new_address.rs:508`. Nothing
else can produce the measured 9.1 → 46.9 → 107.0s scaling.

**Corrected impact.** Both reviewers rejected the original arithmetic. Fitting
all three probe counts (4 / 42 / 102 at gap 1 / 20 / 50) against the measured
9.1 / 46.9 / 107.0s gives slope **≈1.00 s/probe, intercept ≈5.0s**, predicting
every point to within 0.5%; the original two-point fit mispredicted gap-1 by
~30%. The floor is ~5.0s, not 2.0s:

| | measured | after |
|---|---:|---|
| 1 UTXO coin, gap 20 | 46.9s | **~6–9s** (save ~38–41s) |
| gap 50 | 107.0s | **~6–9s** (save ~98–101s) |
| 4 UTXO coins | 259.5s | **~25–40s** |
| EVM half | 363.8s | **0s** — needs item 2 |

It also **fixes the scan exceeding the client's 20s ceiling** (report §1) — a
correctness-visible fix, not just latency.

**The decisive evidence:** the WASM/native pair. Identical Rust, identical probe
count, and the wasm `derive_addresses` is *strictly slower* (it re-locks the
address cache every iteration, `hd_wallet/coin_ops.rs:113-131`, with an in-code
comment that `derive_child` "takes a long time") — yet wasm finished in 12.4s
against native's 46.9s. That rules out CPU, derivation and storage, and pins the
cost to per-request round-trip latency, which is exactly what a batch collapses.

**Implementation corrections — do not skip these:**

* **"Run External and Internal concurrently" does not compile.** Both take
  `hd_account: &mut HDCoinHDAccount<T>` (`lp_coins.rs:6331`) and each awaits
  `set_known_addresses_number`, also `&mut` (`hd_wallet/coin_ops.rs:213-236`).
  Derive both chains' windows up front and probe them in **one** batch instead —
  sidesteps the borrow entirely and is strictly better.
* **Chunk the batches.** `ELECTRUM_REQUEST_TIMEOUT = 20` (`constants.rs:2`) is
  per request, hence per *batch*. An unchunked 42-item batch converts 42
  independently-budgeted requests into one all-or-nothing 20s budget with no
  partial-result path — strictly worse than today. Chunk at ~10–15 with a
  per-chunk fallback to singles.
* **A cheaper first step exists.** `ElectrumConnection` already multiplexes by
  `rpc_id` (`connection.rs:168`, resolved at `:346`), so issuing the window's
  probes concurrently via `FuturesUnordered` gets ~1 RTT with no new trait
  method and per-request timeouts preserved. The windowing rewrite is the
  load-bearing part; `are_addresses_used` is a refinement.
* **`utxo_tests.rs:4695` must be rewritten, not relied on.** It asserts the
  exact *ordered* probed-address sequence and mocks `is_address_used`, which an
  `are_addresses_used` override would bypass. It also exercises the Native
  `HashSet` path, so it covers none of the Electrum batching.

**Swap safety: clean, and worth stating in the PR.** The scan's only persisted
output is `set_known_addresses_number` (`lp_coins.rs:6397`). Swap paths resolve
addresses via `derivation_method.single_addr_or_err()` (`lp_coins.rs:4702`) at
`utxo_common.rs:1535, 1759, 1875, 1940, 2004, 2046, 5394, 5563, 5625`, and
`get_unspent_ordered_list` takes that single address (`:4389, :4420`).
`known_addresses_number` reaches only `is_address_activated`
(`hd_wallet/mod.rs:212-215`), consumed by withdraw and tx-history — never by
UTXO selection during a trade. A wider probe window persists an identical value.

**Worth telling maintainers:** post-fix the cost stops scaling with `gap_limit`,
so KDF could safely *raise* the default rather than clients lowering it.

---

## 2. Release the `web3_instances` mutex before the network round trip — DONE, 212.1s → 27.3s

> **Done, and the estimate below is wrong — measured 212.1s → 27.3s (7.8×), not 25%.**
> The "~85% unexplained per-RPC cost" was a wrong denominator, not a real effect.
> The TRON half of this item is also done: 35.7s → 5.2s on activation (6.9×) and
> 68.1s → 8.4s over the whole TRON path (8.1×).
> See [Validation round 2](#validation-round-2-the-evm-mutex-item-2-and-the-pooled-transport-item-4).

**Current behaviour.** `try_rpc_send` binds
`let mut clients = self.web3_instances.lock().await;` (`eth/eth_rpc.rs:27`) ✅
and the guard lives to end of function, because `clients.rotate_left(i)` (`:44`)
still needs it — so every `execute_fut.timeout(TRY_RPC_NODE_TIMEOUT_S).await`
(`:41`, 10s at `:23`) ✅ runs under an exclusive `futures::lock::Mutex`. Every
EVM RPC funnels through it: `call` (`:86`), `balance` (`:165`),
`transaction_count` (`:285`). **At most one RPC in flight per `EthCoin`, ever.**

No second serializer underneath — the native HTTP transport takes no lock
(`web3_transport/http_transport.rs:101-190`). KDF already does this correctly
elsewhere in-tree: `get_addr_nonce` snapshots with `.lock().await.to_vec()` then
fans out unlocked (`eth.rs:6276`). TRON repeats the anti-pattern and is *worse*:
`TronApiClient { clients: Arc<AsyncMutex<...>> }` (`eth/tron/api.rs:806`) is
Clone-shared, serializing every TRON RPC across TRX and all TRC20s
process-wide — with a comment at `:825` calling the hold-across-await
deliberate, "for consistency with EVM's `try_rpc_send` pattern".

**Corrected impact.** The original claim said "4 serial round trips → 2 waves,
~2×, ~180s". Wrong: `is_address_used` for EVM (`eth_hd_wallet.rs:125-150`) is
**three** causally sequential short-circuiting stages — `transaction_count`
(`:133`, returns at `:134-136`), then `address_balance` (`:141`, returns at
`:142-144`), then the token fan-out (`:148`). Removing the mutex cannot merge
them. Corrected: `(2 + K)` round trips → **3 waves**, K = token count.

* ETH + USDT + USDC (K=2): 4 → 3 waves = 25%, **363.8s → ~273s (~90s saved)**
* K=4 → 50%; K=13 → 79%, so the 246.1s app-default call benefits in proportion
* Strongest clean win is on **iguana**: "BNB + 13 tokens" is 14 serial round
  trips → 2 waves, 19.95s → ~3–8s, i.e. **~12–17s off the 25.7s six-call run**

Two of the three "voided fan-outs" the finder flagged contribute nothing on the
measured run: `known_addresses_balances`'s `try_join_all`
(`eth_hd_wallet.rs:228-241`) fans out over *zero* addresses
(`HDAccount::new` sets `external_addresses_number: 0`, `hd_wallet/mod.rs:176`),
and the balance streamer (`eth_balance_events.rs:94-107`) is post-activation.

**Prerequisites — do not ship without them:**

* `websocket_transport.rs:207` does
  `notifier.send(res_bytes).expect("receiver channel must be alive")`, with the
  notifier registered for 30s while `try_rpc_send` abandons at 10s. A response
  arriving in that 20s window **panics the connection loop and drops every other
  in-flight request on that node.** Today the mutex makes 10s timeouts rare; a
  semaphore makes them routine. Must become `let _ = notifier.send(...)`.
* `eth_rpc.rs:51-53` and `:58-60` call `stop_connection_loop()` on every
  failure, pushing `Close` into an unbounded channel
  (`websocket_transport.rs:302-307`). Concurrent failures enqueue N Closes; the
  surplus kills the *next* connection loop the moment it spawns (`:281-287`).
  Needs an idempotency guard.
* `pool_max_idle_per_host(0)` (`common/wio.rs:115`) means no connection reuse, so
  a 14-wide fan-out is 14 simultaneous TLS handshakes to one host. A per-coin
  semaphore (8–16 permits) is **mandatory**, and it caps the win below the wave
  arithmetic.
* `"re-acquire briefly to apply rotate_left"` is unsound as written — `i` indexes
  the dropped snapshot. Use `AtomicUsize` + `Arc<Vec<Web3Instance>>`, and budget
  for retyping `web3_instances` at ~6 sites.

**Swap safety: clean.** The lock never spans a read-modify-write —
`eth_getTransactionCount` and `eth_sendRawTransaction` are separate
`try_rpc_send` calls with the lock released between, so it provides zero
atomicity today. Nonce ordering is guarded independently per-address by
`nonce_sequencer::PerNetNonceLocks` (`eth/eth_utils.rs:22-67`). The websocket
transport routes by `request_id` (`websocket_transport.rs:141-210`), so
responses cannot be mis-routed. No test references `try_rpc_send`.

**Who it helps:** everyone.

---

## 3. Stop holding the whole-wallet `HDAccountsMutex` across network I/O

**Current behaviour.** `HDAccountsMutex` is one `AsyncMutex` over a coin's
entire accounts map (`hd_wallet/mod.rs:60`); `get_account_mut` returns a guard
over the **whole map** (`:365-376`). `scan_for_new_addresses_rpc` binds it at
`init_scan_for_new_addresses.rs:174` and still holds it at `:183` (the walk) and
`:192` — spanning the entire 42-round-trip walk. `init_account_balance_rpc`
blocks on the same mutex (`init_account_balance.rs:154-160`). So does the swap
path: `get_enabled_address` → `get_account` → the mutex
(`hd_wallet/mod.rs:397-408`), reached from `single_addr_or_err`
(`lp_coins.rs:4702`) and `my_addr` (`utxo.rs:1155-1165`, which `.expect()`s — it
stalls, it does not error).

**This explains the measured 21.6s exactly.** The scan is ~42s. The client
abandons polling at 20s but never cancels the task, so the server-side scan
keeps running and keeps the guard, then `task::account_balance` is issued
immediately. Residual block ≈ 42 − 20 = **22s**. Measured: **21.6s**.
`account_balance`'s own work cannot explain it — `all_known_addresses_balances`
(`utxo_common.rs:214-240`) issues one batched `scripthash_get_balances` per
chain, sub-second for two addresses.

**A reviewer caught the candidate's own self-correction being wrong.** It
claimed the fresh-wallet branch is safe because of `drop(accounts)` at
`coin_balance.rs:522` — but `create_new_account` at `:529` returns
`HDAccountMut` = `AsyncMappedMutexGuard` over the whole map
(`hd_wallet/mod.rs:478`), held across `enable_hd_account` at `:537` (the entire
scan) and released only at `:547`. **The whole-wallet lock IS held across cold
activation.** Uncontended in the harness, so it does not cause the 46.9s — but
the "re-activation only" framing is false.

**Scope that does hold:** re-activation cannot block a concurrent swap, because
`get_activation_result` completes *before*
`coins_ctx.add_platform_with_tokens(...)` registers the coin
(`platform_coin_with_tokens.rs:421-429`), so `lp_coinfind` cannot return it yet.
The real exposure is **the scan RPC on an already-active coin** — an HTLC spend
or refund stalling for the length of a user-triggered scan.

**A regression the proposal must address.** Detaching the scan drops its mutual
exclusion against `get_new_address`, which holds the same whole-map guard
(`get_new_address.rs:503, :544`) across network `is_address_used` calls
(`:576-611`). Interleaved, `get_new_address` can read a stale count K and hand
the user index K while the detached scan has already found K used.
Compare-and-max keeps the counter monotonic but does **not** prevent handing out
a used address — an address-reuse/privacy regression. Needs a shared
address-space lock, not the claimed one-function edit.

Also: `set_known_addresses_number` writes **storage before memory**
(`hd_wallet/coin_ops.rs:214-238`) and UTXO runs the walk twice, so a cancel
mid-walk leaves storage ahead of memory and under-reports balances for the
session. Write back per-chain.

**Overlap:** if item 1 lands, most of this 21s evaporates on its own. Residual
value is the liveness fix, which no test covers today.

---

## 4. Give the EVM transport a pooled Hyper client — ~13–26s, and it helps everyone

> **Done. Measured −16% on per-RPC wire time (246ms → 207ms); the wall-clock
> difference is inside the noise at n=3.** One claim below is refuted: the
> `pool_idle_timeout` → SO_KEEPALIVE argument does not hold, because `wio.rs`
> does not use `build_http()` and no HYPER socket has a keepalive today.
> See [Validation round 2](#validation-round-2-the-evm-mutex-item-2-and-the-pooled-transport-item-4).

**Current behaviour.** `HYPER` is one process-global `lazy_static` built with
`.pool_max_idle_per_host(0)` (`common/wio.rs:115`). Every native EVM/TRON
JSON-RPC goes through it (`http_transport.rs:107, :137` →
`native_http.rs:194-196`).

A reviewer checked the vendored hyper rather than assuming, and it is **worse
than claimed**: in hyper 0.14.26, `max_idle_per_host == 0` makes
`Config::is_enabled()` false (`pool.rs:99-101`) and `Pool::new` sets
`inner = None` (`:105-119`), which also disables **HTTP/2 connection sharing**
(`Pool::connecting`, `:154-178`) — despite `wio.rs:102` enabling h2 and ALPN
advertising it. KDF negotiates h2 and then throws the connection away per
request. `HttpConnector` also has no DNS cache (`connect/http.rs:337`), so each
RPC pays getaddrinfo too.

The `wio.rs` comment names the exact mitigation it wished existed
(`pool_idle_timeout`), and hyper has since shipped the safety property it
feared: `retry_canceled_requests: true` by default (`client.rs:923`), retrying
only requests never written to the wire (`proto/h1/dispatch.rs:617-623`). **A
pooled client cannot double-broadcast a signed transaction.**

**Corrected impact.** The reviewers split; the lower estimate is better
grounded. Iguana runs the *same* call through the *same* pool-disabled client in
2.5s while issuing 4–8 RPCs, each with its own handshake — capping a complete
handshake+request at ~0.4–0.5s. Realistic: **~13–26s (4–7%) off 363.8s**. The
claimed 35s is the arithmetic maximum, reachable only if a handshake were 100%
of an RPC's cost, which iguana refutes.

**Take the scoped variant.** Give the EVM/TRON transport its own pooled
`Client` rather than changing `HYPER`. `SlurpHttpClient` is a blanket impl over
`Client<C>` (`native_http.rs:183-191`), so a second client needs zero new trait
impls (~10 lines). `HYPER` has 32 call sites — TronGrid, 1inch, price feeds, the
UTXO native client, grpc-web — none mutex-serialized, so enabling h2
multiplexing for them is an untested behaviour change. Note also that
`.pool_idle_timeout(20s)` feeds the connector's TCP keepalive
(`client.rs:1380`), dropping SO_KEEPALIVE from 90s process-wide.

**Who it helps:** everyone, and that is its main argument. Largest on HD
activation, small (~0.5–1.0s) on a steady-state refresh — but it applies to
every swap-time EVM RPC, where latency is user-visible.

---

## 5. Electrum dispatch: fix the failure cascade *before* item 1 ships — ~0s alone

Both reviewers scored the latency at **~0s on the measured workload**, and the
underlying rate-limit model was refuted. One sub-fix is still a prerequisite.

**Verified defects:**

* `let concurrency = if send_to_all { connections.len() } else { 1 };`
  (`electrum_rpc/client.rs:364`); `send_to_all` is true only for `server.ping`.
  `send_request_using` iterates `connections.chunks(max_concurrency)`
  sequentially (`:442, :470`), so every request goes to the top-priority
  connection and the other 5 are pure failover.
* **Any** per-request error, including a plain 20s timeout, force-disconnects the
  socket (`client.rs:491-493`), and `disconnect` does
  `self.responses.lock().unwrap().clear()` (`connection.rs:240`) plus
  `abort_all_and_reset()` (`:245`) — dropping the oneshot for every *other*
  in-flight request, which surfaces as `Transport("The sender didn't send")`
  (`:291`), losing the true first cause. `on_disconnected` fires per errored
  request (`client.rs:494`) *and* from the loop (`connection.rs:731`), each
  reaching `SuspendTimer::double()` — an N-way cascade compounds to
  10s × 2^(N+1).

**What was refuted:**

* The claimed "benign teardown charged to exponential backoff" does not happen.
  `get_active_connections()` *is* `read_maintained_connections()`
  (`connection_manager/manager.rs:216-220`) and `not_needed` only disconnects
  `if !contains_key(&id)` (`:298`), so the success-path call at `client.rs:479`
  is a guaranteed no-op.
* The rate-bucket model is refuted by the measurements themselves. A
  per-connection token bucket predicts scan costs of 0.03 / 15.2 / 75.2s at gap
  1/20/50; measured (minus floor) are 7.1 / 44.9 / 105.0s — flat ~1.05 s/req
  from request #1, no burst.
* "A single JSON-RPC error disconnects" is wrong: error responses are delivered
  as `Ok(JsonRpcResponseEnum)` (`connection.rs:344-348`) and take the success
  branch. Only transport failures and the 20s timeout disconnect — which matters,
  because it means "server rejects batches" is already benign for item 1.
* **Do not do the `establish_connection_loop` reorder.** `connection.rs:229-231`
  states the `establishing_connection` lock is what makes the transition atomic,
  and `connect(tx)` (`:711`) sets `is_connected()` true *before*
  `check_server_version` (`:742-748`). A lock-free fast path lets requests out on
  a socket with un-negotiated protocol version, and `VersionMismatch` is
  Irrecoverable (`:150-155`).
* **Do not simply remove disconnect-on-timeout** — it is the only eviction path
  for a ping-responsive-but-stalled server (`timeout_loop` only fires after 60s
  of no bytes, `connection.rs:514-525`; `ping_task` pings every 30s). Needs a
  consecutive-failure counter that unmaintains without suspending.

**What to actually ship:** replace the `responses.clear()` at
`connection.rs:240` with a drain that sends each waiter the real
`ElectrumConnectionErr`. ~20 lines, 5 call sites all inside `electrum_rpc/`, no
RPC-shape or on-disk change, no test pins it. Today *every* cascaded electrum
failure reports a lie — a permanent tax on diagnosing this class of report. Ship
it alongside item 1, because batching turns a serial request stream into a
concurrent one and makes this latent bug active.

---

## Correctness bugs — zero seconds, ship anyway

### The TRX/NFT activation panic

`build_tron_api_client` fetches the P2P signing keypair unconditionally, before
looking at whether any node is a proxy:

```rust
// v2_activation.rs:1217
let proxy_sign_keypair = Some(Arc::new(P2PContext::fetch_from_mm_arc(ctx).keypair().clone()));
```
✅ `fetch_from_mm_arc` is four unwraps (`p2p_ctx.rs:37-46`) ✅, and `p2p_ctx` is
populated only at `lp_native_dex.rs:619-620`, unreachable when `init_p2p`
early-returns on `ctx.disable_p2p()` (`:555-558`).

Three corrections to how this was originally reported — see the correction note
in `KDF_LATENCY_REPORT.md` §8:

1. **The native RPC service does not die.** ✅ Re-tested: after the panic the
   same process answered `version`, activated `ETH + USDT-ERC20` successfully,
   and listed both in `get_enabled_coins`. `panic = 'unwind'` (`Cargo.toml:241`)
   ✅ and the 500 body is a fixed string at `rpc.rs:361` ✅ emitted whenever the
   spawned per-request task drops its sender. **That misleading string is what
   caused the misdiagnosis and is worth fixing on its own.**
2. **It is not TRON-specific.** `initialize_global_nft` does the same
   unconditional fetch at `v2_activation.rs:686` — seventeen lines *before* its
   own `if komodo_proxy` guard at `:703`. A plain `enable_nft` with
   `komodo_proxy: false` panics identically.
3. **The precondition is a default, not an opt-out.** `MmCtx::disable_p2p()`
   (`mm2_core/src/mm_ctx.rs:451-460`) returns true by default when the config has
   no `seednodes`, is not a bootstrap node, and has no in-memory p2p.

**It is genuinely fatal on WASM** — which is what the web wallet runs. KDF says
so in-code: a panic terminates the MM2 instance because `catch_unwind` is
unusable with async on wasm32 (`mm2_bin_lib/src/mm2_wasm_lib.rs:127-131`).

**The fix has in-tree prior art.** `tendermint_coin.rs:3198-3203` already does
exactly the right shape:
`let p2p_keypair = if nodes.iter().any(|n| n.komodo_proxy) { … } else { None };`
and downstream already tolerates `None` (`eth/tron/api.rs:202, :216-221`, with a
typed error for proxy-without-keypair). Add `try_fetch_from_mm_arc` beside
`p2p_ctx.rs:37` and fix **three** sites — `v2_activation.rs:686`, `:1217`,
`eth/tron/gasfree/client.rs:53` — not the 26 `fetch_from_mm_arc` call sites; the
other 23 are legitimately P2P-mandatory.

**Two sub-proposals to drop:**

* **Do not add per-request `catch_unwind`.** `handle_request` is inside
  `#[cfg(not(target_arch = "wasm32"))]` (`rpc.rs:294-493`); WASM uses a separate
  `spawn_rpc` at `:495-547` — so it does nothing for the one platform where the
  panic is fatal, contradicting its own goal. On native it would swallow
  arbitrary panics from `rpc_service`, which dispatches buy/sell/setprice, swap
  state machines and DB writes. Converting fail-fast into "return an error and
  keep going" inside a DEX's order path is exactly what mutex poisoning exists to
  prevent. Take **only** the string fix at `rpc.rs:361`.
* **The `parking_lot` swap on `MmCtx::p2p_ctx` is redundant.** `init_p2p` is
  awaited at `lp_native_dex.rs:375` and `spawn_rpc` only runs at `:455`, so there
  is no window where a request poisons a lock a later `store_to_mm_arc` needs.
  Also `mm2_core/Cargo.toml` has no parking_lot dependency, so the "consistency"
  justification is wrong. Once the unwraps are gone there is no panic to poison
  anything.

### Six unwraps on client-supplied JSON in the Tendermint activation deserializer

`deserialize_account_public_key` has raw unwraps at
`tendermint_with_assets_activation.rs:86, :88, :90, :95, :97, :99`, alongside the
`serde::de::Error::custom` style the author used for the cases they did think
about (`:101-113`). Reached via `#[serde(deserialize_with = ...)]` from
`enable_tendermint_with_assets` (`dispatcher.rs:259`). Three malformed shapes
were reproduced as panics. Fatal on WASM, same as above.

**Additional bug found in the same function:** `.as_u64().unwrap() as u8` at
`:88` and `:97` silently **truncates** any array element ≥ 256, so a
well-formed-but-hostile pubkey array is accepted with wrapped bytes rather than
rejected. Deserializing into `Vec<u8>` via serde closes both.

**Reach is narrower than "remote":** params are deserialized after `auth()`
(`dispatcher.rs:118, :159-169`), so the caller must already hold the
rpc_password.

No test covers any of this: no test references `deserialize_account_public_key`,
and `disable_p2p: true` appears in the integration tests but never with TRON or
`komodo_proxy: true`.

---

## Checked and ruled out

* **"Multiple coins do not pipeline" is not KDF-side contention.** ✅ The probe
  activates coins strictly sequentially (`kdf_latency_probe.py:588`), and no
  shared activation lock exists. Re-measured per-coin: KMD 46.4s, MARTY 42.9s,
  DOC 43.9s, **BTC 126.2s** — three of four match their solo cost, and the
  "65.2s/coin" average was BTC dragging the mean. **Do not go hunting for that
  lock.** (Why BTC is ~2.7× KMD remains open.)
* **`not_needed` charging benign teardowns to exponential backoff** — refuted
  from source (`manager.rs:216-220`, `:298`).
* **"Native and WASM are different Electrum clients"** — refuted; every `cfg`
  gate under `electrum_rpc/` is a transport swap in one file.
* **Adding a native WSS transport to explain the 4×** — the rejection is real
  (`connection.rs:430-434` hardcodes it), but the 4× is confounded and
  unattributed, it is new network code on the DEX-critical native path, and once
  item 1 cuts round trips from 42 to ~2 the per-RTT delta stops being worth
  minutes. Revisit only if the 4× survives item 1.
* **Blocking `getaddrinfo` in connection establishment** (`connection.rs:378`,
  std `ToSocketAddrs` inside an async fn) — real, one-line fix via
  `tokio::net::lookup_host`, but per connection-establishment, not per request.
  Sub-second against every measured number. Good drive-by, not a candidate.
* **Honouring `get_balances: false` on the HD branch** — saves ~3 of ~88 RPCs on
  the measured wallet, and is the highest-risk-per-second item in the set:
  `enable_coin_balance` creates and persists the HD account, so a naive skip
  leaves the wallet un-indexed.
* **Persisting a scan watermark** — helps only a repeat scan on an unchanged
  tip, does nothing for the first scan, and item 1 makes the repeat scan a single
  batch anyway. Would need a two-store (SQLite + IndexedDB) migration.
* **Making `enable_eth_with_tokens` task-based** — unnecessary;
  `task::enable_eth::init` already exists (`dispatcher.rs:343-347` registers both
  forms against the same generic). What remains is progress emission, which saves
  zero seconds. *(This corrects a suggestion in `KDF_LATENCY_REPORT.md` §10 Q2 —
  the task form is already there; the client just does not use it.)*

---

## RESOLVED — `34ab0e7` broke GLEEC activation; the pool now absorbs a 429

**Status: fixed.** The pool retries a refused request with backoff instead of
writing the endpoint off, carries the HTTP status structurally on both targets,
and scales its concurrency budget by node count. `34ab0e7`'s 7.8× EVM win is
shippable.

The original diagnosis was right about the *what* — HTTP 429 from
`evm-rpc.gleec.com` — and wrong about the *shape*, in a way that would have
produced a fix tuned to the wrong quantity. Both are recorded below, because
the mistake is the reusable part.

### The failure

Reproduced 6/6 on `34ab0e7`, GLEEC alone, alternating arms, same seed:

| binary | HD | iguana |
|---|---|---|
| `ed8de23` | 11.44 / 10.46 / 10.50s ok | ok |
| `34ab0e7` | **1.18 / 1.13 / 1.04s ERR** | **0.41s ok** |

**It is HD-only**, which the first write-up did not say and which matters: on
iguana GLEEC activates in 0.41s even on the broken build. iguana derives one
address; HD fans a ~21-wide gap scan out across the permit budget, and the
fan-out is the trigger. A test or CI gate written in iguana mode would have
stayed green throughout.

Confirmed with `KDF_EVM_RPC_TRACE=1` rather than inferred — KDF's own log:

```
INFO  EVM RPC pool: 1 node(s), max 12 concurrent request(s)
WARN  evm_rpc_failover coin=GLEEC method=eth_getTransactionCount
      node=evm-rpc.gleec.com attempt=0 after_ms=176 kind=http_429
WARN  evm_rpc_exhausted coin=GLEEC method=eth_getTransactionCount nodes=1
```

18 × `kind=http_429` against 6 successful RPCs, all inside one second.
`eth_getTransactionCount` was 21 of the 24 — the gap scan probing addresses.
**The whole activation only asks for ~24-44 RPCs**, so this was never a volume
problem.

### The correction: it is a rate limit, not a concurrency limit

The earlier entry flagged a leftover puzzle — a budget of 4 still failed
through KDF although the endpoint served 4 concurrent raw requests cleanly —
and guessed that "KDF issues more request types per address and the pooled
client opens more connections than a naive probe." **That guess was wrong.**
Permits map 1:1 to in-flight requests; nothing on the activation path bypasses
the budget.

The real answer is that the two experiments measured different quantities.
Measured directly against the endpoint:

| experiment | offered | served | codes |
|---|---:|---:|---|
| burst 12 (one instant) | 12 | **12** | all 200 |
| burst 24 | 24 | 12 | 12 × 429 |
| closed loop, budget 2, 6s | 9.2/s | 56/56 | all 200 |
| closed loop, budget 4, 6s | 18.3/s | 110/112 | 2 × 429 |
| **closed loop, budget 12, 6s** | 55.6/s | **120** | 227 × 429 |
| open loop, 16/s, 6s | 15.6/s | 92/96 | 4 × 429 |
| **open loop, 32/s, 6s** | 31.0/s | **119** | 73 × 429 |

Two rows settle it: at budget 12 the endpoint served **exactly 120** requests
in six seconds, and at an offered 32/s it served **119**. Both are 20/s × 6s.
**The endpoint serves ~20 requests per second** and refuses the remainder.

A budget of C at round trip R is a *sustained* C/R requests per second. At
R ≈ 220ms, C=4 is ~18/s — right on the limit — and C=12 is ~55/s, nearly three
times over. The burst table measured a **quantity**; the limit is a **rate**.
Note also that the old "429 begins at 12 concurrent" row does not reproduce:
12 at one instant is served cleanly, so the instantaneous allowance is
somewhere between 12 and 24, and it was the sustained rate that mattered all
along.

**And a budget under the limit was still not enough.** At budget 4 the refusal
rate is ~2%, yet activation failed every time, because KDF's tolerance for one
refusal was **zero**: the gap scan collects its window with `try_collect`, so
the first `Err` aborts the whole window and the whole activation. Over ~43
RPCs, a 2% refusal rate fails 58% of the time. That is why the retry, not the
budget, is the load-bearing half of the fix.

### The trap: on web the status does not exist

Full header capture of a real 429 from this endpoint:

| | HTTP 200 | HTTP 429 |
|---|---|---|
| `access-control-allow-origin` | `*` | **absent** |
| `retry-after` | – | `1` |
| `via` | `1.1 Caddy` | **absent** |

No `via: Caddy` means **Cloudflare's edge rate limiter** is answering, never
reaching the origin that sets CORS. Its canned response carries no CORS
headers, so in a browser `fetch` rejects before JavaScript sees anything: no
status, no body, an opaque `TypeError`. `Retry-After` is unreadable there too —
it is not CORS-safelisted and is not named in `Access-Control-Expose-Headers`.

So **any retry keyed on reading `429` is dead code on web**, which is the
platform the preview runs on. The fix triggers on transport failure generally
and treats the status as description rather than as the decision.

### What was built

1. **Retry with backoff when every node refused** (`eth_rpc.rs`). Bounded at 4
   retries, exponential from 150ms, jittered, floored by `Retry-After` where it
   is readable. It sits *outside* the node loop, so a multi-node pool reaches it
   only when every node failed — an outage, not a rate limit — and healthy pools
   pay nothing. The permit is held across the wait on purpose: releasing it
   would hand the slot to a queued request and keep offering the endpoint the
   rate it just refused.
2. **A machine-readable status on both targets** (`http_transport.rs`). Both
   arms now return `TransportError::Code(status)`, which already existed in the
   web3 fork. It had been recovered by string-matching `"response !200: "`, a
   marker only the native arm emitted — the wasm arm wrote `"!200: {status}"` —
   so on web every status classified as a bare `transport` and `http_429` never
   fired at all. That string contract caused this bug twice; it is gone.
3. **An adaptive budget, and no per-chain cap** (`web3_pool.rs`). The budget
   halves under sustained refusal and grows back one permit at a time, so each
   pool converges on what its own endpoints will take.

   A per-node *starting* cap was tried and removed — see the sweep below. It
   bought no reliability and cost time.

Also fixed, found by the new tests: `send_request` flattened JSON-RPC errors
into `Error::Transport`, so `execution reverted` was indistinguishable from a
dead socket. That made the retry try again on a deterministic failure, and it
had already been silently defeating the websocket-teardown guard that exists to
stop one reverted `eth_call` dropping a socket shared with every other coin.

### The concurrency sweep: capping is the wrong lever

The obvious follow-on question is whether the budget should be capped for
chains that cannot fail over. Measured across **33 activations**, budgets 2 to
48, on a one-node chain and a four-node one, three runs each:

| budget | GLEEC (1 node) | 429s | ETH + 2 ERC-20 (4 nodes) | 429s |
|---|---|---:|---|---:|
| 2 | **10.20s** | 0 | – | – |
| 4 | 8.34s | 8 | – | – |
| 6 | 7.44s | 10 | – | – |
| 12 | 8.31s | 20 | 35.88s | 53 |
| 24 | 8.50s | 48 | **27.88s** | 492 |
| 48 | 8.05s | 62 | 35.50s | 713 |

**Every run succeeded, at every budget, with zero `evm_rpc_exhausted`.**

Three things fall out:

1. **The cap buys no reliability.** GLEEC survives a budget of 48 — four times
   the default, on a single node against an endpoint that serves ~20/s. The
   retry is what makes a refusal survivable; the budget only decides how much
   work is wasted discovering the limit.
2. **Throttling is counterproductive.** GLEEC's *slowest* arm is budget 2, the
   one setting that provokes no 429s at all. It trades each refusal for a round
   trip it then waits on, and round trips cost more than refusals.
3. **The controller converges from anywhere.** GLEEC lands on 2–3 whether it
   starts at 6, 12, 24 or 48; ETH lands on 12.

So the per-node cap was removed. A permanent tax on all 580 EVM-family coins,
levied to protect 5 of them from a failure mode they no longer have, does not
earn its complexity — and it was worst exactly where it could not be measured,
since `std::env::var` always fails on `wasm32` and a browser had no way to try
a different number.

Re-verified uncapped: GLEEC **10/10** consecutive HD activations (median 8.7s,
worst 10.45s), **web 9.6s**, app-default set **48.92s** — all at or better than
the capped numbers.

> **ETH at 24 was ~20% faster than at 12** (27.88s vs 35.88s), which is a real
> and unclaimed win. It is not taken here: it drew 492 × 429 against public
> endpoints the budget exists to protect, and the controller walked it back to
> 12 anyway. Raising `DEFAULT_MAX_CONCURRENT_RPCS` is a separate decision with
> a node-operator cost, and wants its own measurement across more chains.

> **One rough edge, recorded rather than fixed.** At budget 48 the controller
> walked **ETH** — a four-node chain — down to 2–3, having read a burst of
> simultaneous refusals across all four nodes as sustained pressure. It still
> finished in 35.50s, but recovery is slow by design (60 successes per +1
> permit), so a pool that over-shrinks early stays small for the rest of a
> session. It does not arise at the shipped default of 12, where ETH holds at
> 12 across every run.

### Single-node EVM coins are not a GLEEC quirk

| nodes | EVM-family coins in the shipped config |
|---:|---:|
| **1** | **5** — AVAXT, BNBT, EWT, GLEEC, KMDT-GRC20 |
| 2 | 33 |
| 3 | 15 |
| 4 | 315 |
| 5 | 212 |

GLEEC and KMDT-GRC20 share chain 11169 and the same endpoint. The 33 two-node
coins have the same exposure whenever both nodes refuse.

**Borrowing nodes from other coins is not an option** — tested. An EVM RPC node
only serves the chain it is synced to: every other configured node returns its
own `eth_chainId` (ETH 1, BNB 56, AVAX 43114, MATIC 137, ETC 61) and only
`evm-rpc.gleec.com` returns GLEEC's 11169.

> **An earlier version of this entry blamed the websocket transport.** That was
> wrong and worth recording: GLEEC's config carries a `ws_url`, so a 93-line
> rewrite of `websocket_transport.rs` in the same commit looked like the obvious
> culprit. But the probe *drops* `ws_url` and activates over HTTP only — the
> failing path never touched websockets. The tell was there in the error itself
> (`eth_getBalance` over HTTP); the reasoning started from the config rather
> than from what was actually sent.

### The env-var cap was never the mitigation

| `KDF_EVM_RPC_MAX_CONCURRENCY` | GLEEC | ETH + 2 tok |
|---|---|---|
| 12 (default) | **1.14s FAIL** | 20.85s |
| 4 | **2.57s FAIL** | — |
| 2 | 4.90s ok | 94.67s |

Only 2 rescued GLEEC, at ETH 20.85s → 94.67s (4.5×). And
`configured_concurrency()` reads `std::env::var`, which on `wasm32` always
returns `Err`, so the browser silently got 12 regardless. It is a native-only
diagnostic knob. The node-count scaling deliberately lives outside it for
exactly that reason — web has to get it too, and web is where the 429 is
invisible.

### TRON had the same weakness — fixed, and the cause was worse than expected

`tron/api.rs` builds its own pool and `try_clients` had no retry. Measured:
**8 failures in 14 consecutive TRX + USDT-TRC20 activations.**

The cause is not the TVM exception first observed. It is that
**`api.trongrid.io` unauthenticated allows 3 requests per second**, and answers
a breach with `HTTP 429` *plus a five-second suspension of the client*, stated
in the body:

```
request rate exceeded the allowed_rps(3), and the query server is suspended for 5 s
```

Measured against the endpoints directly:

| node | 40 calls @ concurrency 2 | median | note |
|---|---|---|---|
| `api.trongrid.io` | 39/40 | 1706ms | 3 rps cap, suspends 5s on breach |
| `tron-rpc.publicnode.com` | **40/40** | **236ms** | 7x faster, no cap seen |
| `public-trx-mainnet.fastnode.io` | **0/40** | - | **HTTP 404 - does not serve `/wallet/*` at all** |

On trongrid alone, concurrency is decisive: 40/40 at 1, **12/40 at 4**, 3/40 at
12. The pool allowed **12**.

Three fixes, one per observed failure:

1. **Retry with backoff in `try_clients`**, base 1.5s capped at 6s - sized to
   outlast the five-second suspension rather than land inside it.
2. **`OTHER_ERROR` is no longer uniformly permanent.** `OutOfTimeException` is
   the TVM's per-transaction wall-clock budget, consumed by whatever else the
   node is doing; java-tron itself re-runs the identical call on it and on no
   other exception. Anchored on named exceptions, so the catch-all stays one.
3. **Adaptive concurrency** for the TRON pool, reusing the EVM controller.
   Twelve permits against three-per-second is not a budget.

`broadcast_hex` is excluded from the retry - the only non-idempotent call
reachable from the pool. Node rotation still applies; the backoff loop does not.

**Result**, alternating arms, 7 activations each:

| arm | passed | median |
|---|---|---|
| baseline | **5/7** | 10.77s |
| with fix | **7/7** | 12.27s |

Two hard failures to zero, for +1.5s median - the suspension being waited out
rather than run into.

> **The follow-up this leaves open is config, and it lives in `GLEECBTC/coins`,
> not here** - `coins_config.json` is fetched at build
> (`fetch_at_build_enabled: true`), so editing the copy in this repo is
> overwritten on the next build.
>
> **TRX's node list is ordered worst-first.** It is
> `[api.trongrid.io, tron-rpc.publicnode.com]`, and the cursor starts at index
> 0, so every cold activation aims its whole first burst at the 3-rps node
> while the 7x-faster un-capped one idles until something fails. Swapping the
> order, or obtaining a TronGrid API key, would remove most of the pressure at
> source - more than the retry does, because it stops producing the refusals
> rather than absorbing them.
>
> `public-trx-mainnet.fastnode.io` answers `404` on every path tried
> (`wallet/*`, `/jsonrpc`, `/`), so it is dead - but it is **inert, not
> harmful**, and an earlier draft of this note had that wrong. It appears only
> in USDT-TRC20's own `nodes` list, and a TRC-20 token never builds a pool from
> that list: activation clones the platform coin's client wholesale
> (`v2_activation.rs:644,752` - `rpc_client: self.rpc_client.clone()`), so only
> TRX's list is ever read. Worth deleting as tidiness and to stop it misleading
> the next person, not as a fix.

### Superseded note: the original TRON follow-up

`tron/api.rs:836` builds `RpcPermits::new(configured_concurrency())` directly
rather than going through `Web3Pool::new`, and its `try_clients` loop has **no
retry**. Nothing in this work reaches it — deliberately, to keep TRX out of the
regression surface — but it means TRX still fails outright the first time every
node refuses.

**Observed live, twice, during this work's own measurements.** Once on
`34ab0e7` and once on the final artefact, TRX activation failed with:

```
activate:TRX+1tok failed: Transport: OTHER_ERROR:
class org.tron.core.vm.program.Program$OutOfTimeException : CPU ti...
```

That is a TRON node exhausting VM CPU on a contract call during token
activation — not rate limiting — but the shape is identical to the GLEEC bug: a
transient, retryable node-side failure that kills the whole activation because
nothing above it will try again. Roughly 2 failures in ~15 TRX activations
across both arms, so ~13%, and it is **pre-existing** rather than introduced
here.

Porting `try_rpc_send`'s retry to `try_clients` is the obvious fix and is
already the subject of the `RpcPool` trait TODO at the top of `eth_rpc.rs`.

### Coverage gap, now closed

Every gate passed on the broken build — sdk 631, harness replay 22, process
tier 4, bench within 1.9%, app 528, full app CI 8/8 green. The real-KDF process
tier exercises **KMD, a UTXO coin**; nothing in CI activated GLEEC or any
single-node EVM coin, and the failure surfaced only from a probe scenario run
by hand.

Closed by a `single_node_evm` job in `kdf-harness-nightly.yml` that activates
GLEEC on HD against its one real node. Two properties are load-bearing: **HD**,
because iguana passes even when broken, and **a single-node coin**, because on
a four-node chain the failure needs four simultaneous outages.

Two probe defects that made the gate impossible are fixed alongside it:
`_activate_eth_with_tokens` recorded a failure as `timed_out` rather than
`failed`, so a 1.1s hard error printed as a timing; and the exit code was
`0 if any(not r.error ...)`, which returns success as long as one row of the
matrix survived. Both are why the probe could see the failure and still exit 0.

---

## Where the evidence is thin

1. ~~**~85% of the EVM per-RPC cost is unexplained.**~~ **RESOLVED — the premise
   was arithmetic error, not a real effect.** The reasoning below divided by an
   *assumed* ~87 RPCs; per-call tracing shows **1208**, at a healthy 238ms
   median, with 289s of wire time inside a 292s wall clock. There was no
   unexplained per-RPC cost and nothing was rate limited — the mutex serialized
   ~1200 healthy requests. Kept struck through rather than deleted because the
   failure mode is worth remembering: a confident conclusion drawn from a
   denominator nobody checked. The original text follows.
   <br><br>
   <em>HD implies ~4.2s per round
   trip (363.8s / ~87), iguana ~0.6s (2.5s / ~4) — same binary, same nodes, same
   transport. A mutex cannot slow an individual round trip. One reviewer flagged
   endpoint rate-limiting or failover against the 10s `TRY_RPC_NODE_TIMEOUT_S`;
   the other neither contested nor explained it. **If it is rate-limiting, item
   2's concurrency is partly self-defeating and the semaphore caps the win
   exactly where the estimate assumes it is free.** Land item 2 with per-endpoint
   429 instrumentation so this is tested, not assumed.
2. **Why BTC costs ~2.7× KMD** for the identical operation. Not investigated.
3. **The 4× native/WASM gap is confounded by transport and was never isolated.**
   It is used above only as *negative* evidence (ruling out CPU/derivation),
   which is sound. Any positive claim built on it is not.
4. **Item 4's saving is inferred from the code path, not isolated by
   measurement** — the least directly evidenced number here, which is why the
   range was cut from 18–35s to 13–26s using iguana's 2.5s as the bound.
5. **Untestable from this repo:** a pooled client's behaviour against
   komodo-defi-proxy under the `X_AUTH_PAYLOAD` signature path
   (`http_transport.rs:120-134`). If the proxy does per-connection auth
   accounting or rate limiting, pooling changes attribution. Test against the
   real proxy.

---

## Suggested sequencing

1. **Item 5's response-map drain** (~20 lines) — prerequisite insurance; ships
   first because item 1 activates the bug it fixes.
2. **Item 1, chunked** — the single biggest win, ~38–41s per UTXO coin, and it
   makes `gap_limit` nearly cost-free.
3. **The TRX/NFT panic fix + tendermint deserializer** (~40 lines) — zero
   seconds, closes two WASM instance-kills, and fixes the misleading 500 string
   that caused the original misdiagnosis.
4. ~~**Item 2**~~ **— DONE.** Measured 212.1s → 27.3s (7.8×), far beyond the
   ~90s forecast, plus the TRON half at 68.1s → 8.4s.
5. ~~**Item 4, scoped to a dedicated EVM client**~~ **— DONE.** Median round
   trip 246ms → 207ms, p90 379ms → 245ms.
6. **Item 3** — re-measure after item 1; most of the 21s should already be gone.
   Pursue the remainder for the HTLC liveness fix, and only with the
   `get_new_address` exclusion designed in.

---

## Validation: what actually happened

Implemented on branch `perf/hd-scan-concurrency` off `bd413dc`, built for
`aarch64-apple-darwin`, and re-measured with the **same probe, same seed
(`abandon … about`), same electrum/RPC endpoints**. The only variable is the
binary. `bd413dc` remains in place as the control.

### What shipped

The scan probes in **windows** rather than one address at a time. Each window is
exactly `gap_limit + 1 - unused_counter` addresses — the number of consecutive
unused addresses still needed to end the walk — so it never probes an address
the sequential walk would not have. Results are consumed in order via
`buffered`, driving the identical state machine.

Note this is the **concurrency** variant, not the `scripthash_get_history_batch`
variant. It needs no new trait method, keeps per-request timeouts (a 42-item
electrum batch would have collapsed 42 independently-budgeted requests into one
all-or-nothing 20s budget), and the measurements below say it was sufficient.

Two bugs found while implementing, both fixed:

* **`gap_limit + 1` overflows.** `gap_limit` comes straight off the RPC request;
  `u32::MAX` wrapped to a zero-length window, which in a release build spins the
  loop forever. Now saturating. This was a defect I introduced and caught in
  self-review, not a pre-existing one.
* **Borrowing the address in the probe closure does not compile** — the closure
  is not general enough over the address lifetime, and *every*
  `HDWalletBalanceOps` impl then fails to satisfy the bound. The probes own
  their address instead.

### Equivalence

`test_scan_for_new_addresses` (`utxo_tests.rs:4695`) passes **unchanged**. It
asserts the exact *ordered* list of probed addresses, the resulting
`known_addresses_number` for both chains across two accounts, and includes
used addresses, so it exercises the reset branch. That is the equivalence proof —
same addresses, same order, same results.

Workspace compiles clean on `aarch64-apple-darwin` **and**
`wasm32-unknown-unknown`.

### Results

| scenario | `bd413dc` | with fix | |
|---|---:|---:|---|
| KMD activate, gap 20 | 46.9s (94 polls) | **6.1s** (13 polls) | **7.7×** |
| BTC-segwit activate | 121.2s | **8.2s** | **14.8×** |
| activate, gap 1 / 20 / 50 | 9.1 / 46.9 / 107.0s | **7.1 / 6.1 / 7.6s** | flat |
| HD, 4 UTXO coins | 260.9s | **21.7s** | **12×** |
| `scan_for_new_addresses` | 20.1s, **timed out** | **2.3s**, completes | fixed |
| `account_balance` | 21.6s (208 polls) | **1.4s** (14 polls) | **15.9×** |
| single-coin total | 89.8s | **10.2s** | **8.8×** |
| iguana, 1 coin *(control)* | 2.0s | 2.0s | unchanged ✓ |
| `do_not_scan` *(control)* | 2.0s | 2.0s | unchanged ✓ |

**The gap limit stopped costing anything.** 107.0s → 7.6s at gap 50, and the
flat 7.1 / 6.1 / 7.6s across gap 1/20/50 is the load-bearing result: `gap_limit`
is now a correctness choice rather than a latency one, and the default could be
*raised* rather than clients lowering it.

**`account_balance` fell 15.9× with no change to its code.** That confirms item
3's diagnosis by prediction rather than inspection: its 21.6s was blocking on
the whole-wallet `HDAccountsMutex` held by the still-running scan. Shorten the
scan and it evaporates — which is exactly why item 3 was ranked below item 1.

The fitted model held: 1.00 s/probe + ~5.0s floor predicted ~6–9s post-fix;
measured 6.1s. The mechanism was identified correctly, not merely perturbed.

### The panic fix

With `disable_p2p: true`, TRX now **activates successfully** and reports an
address (`TFm1esUk…`) where `bd413dc` panicked at `p2p_ctx.rs:42`. The probe's
`--p2p` flag is no longer required for TRX-containing coin sets.

### Where the prediction was wrong

**I predicted EVM would be flat, because its probes re-serialize on the
`web3_instances` mutex. That was too confident in both directions.** Three
alternating A/B rounds of `enable_eth_with_tokens` (ETH + 2 ERC-20, HD):

| | samples | min | median | max |
|---|---|---:|---:|---:|
| `bd413dc` | 3 | 343.3s | 343.4s | 363.8s |
| with fix | 3 | **196.9s** | 219.0s | 346.4s |

The baseline is remarkably tight (~343s); this build was **bimodal** —
sometimes ~200–220s, sometimes ~345s.

**Now explained.** Under full serialization the wall clock is a direct multiple
of per-RPC latency, so an endpoint having a slow hour turned a 212s activation
into a 331s one: the slow round's wire median was 372ms against 235ms. The
spread was the mechanism announcing itself, not noise. Once the mutex is
released (item 2) the call does not track endpoint latency at all.

What this does support: **~343s is a ceiling the concurrency cannot break
through**, consistent with the mutex being the binding constraint. Item 2 is
now the clear next move, and it has a measured ceiling to beat.

> A correction to an earlier reading of this data. On two samples it looked like
> EVM had got *worse* inside the app-default set (246.1s → 342.3s). That was not
> like-for-like: the 246.1s figure came from a `--p2p` run with other coins
> activated first. The controlled alternating A/B above shows no regression.

Because the app-default set is EVM-dominated, its headline moved much less than
the UTXO rows: **480.7s → 411.6s**, essentially all of it from KMD + BTC-segwit
(168.2s → 14.3s) with the ETH call unchanged-to-noisy. The eight-minute login is
now a ~7-minute login; **item 2 is what takes the rest out.**

---

# Validation round 2: the EVM mutex (item 2) and the pooled transport (item 4)

Implemented on KDF branch `perf/evm-rpc-concurrency` off `perf/hd-scan-concurrency`
(`ed8de236b`), built for `aarch64-apple-darwin`, measured with the same probe,
the same seed and the same endpoints. Three alternating rounds per arm, arms
alternating *within* each round so network drift hits both equally.

## First: two things above were wrong, and one of them mattered a lot

**There was no "unexplained ~85% of per-RPC cost". It was a wrong denominator.**
The hand-off divided 363.8s by an *assumed* ~87 RPCs to get ~4.2s per round trip,
could not explain it, and guessed at endpoint rate limiting. Instrumenting the
pool and counting gives **1160 RPCs** on that call — 13× the assumption — which
implies ~314ms each. KDF's own telemetry measures the median wire time at
**236ms**, with **one failover in 1208 calls**. The endpoints were never slow and
nothing was being rate limited. Do not go looking for that explanation again.

Two compounding reasons the census was off:

* **`abandon abandon … about` is not an empty wallet on Ethereum.** It is the
  most-used public test vector there is, so the gap scan keeps finding *used*
  addresses, keeps resetting its unused counter, and walked **239** addresses
  instead of 21 — about 68 of them used. Every EVM measurement in these docs
  used this seed. The `~87` arithmetic is still right for a genuinely empty
  wallet, and still the right number for reasoning about a new user; it is not
  the number this seed produces.
* **A used address costs roughly double.** `AddressBalanceStatus::Used` issues a
  full `known_address_balance` on top of everything `is_address_used` just
  fetched, duplicating the native balance and every `balanceOf`.

**The bimodality recorded above is now explained.** It was attributed to an
unknown cause. Baseline round 3 here took 331.4s against 211-212s for the other
two, reproducing the 196.9 / 219.0 / 346.4 spread — and its **wire median was
372ms against 235ms**. The endpoint was simply slower for those few minutes.
Under full serialization wall clock is a direct multiple of per-RPC latency, so
a 58% latency excursion becomes a 57% longer activation. The mutex did not just
make activation slow, it made it **fragile**.

## Item 2 — release the `web3_instances` mutex: 7.8×, not 25%

| | baseline | item 2 |
|---|---:|---:|
| `enable_eth_with_tokens` median | 212.1s | **27.3s** |
| samples | 212.1 / 211.2 / 331.4s | 27.3 / 28.9 / 22.6s |
| spread | 120.1s (57% of median) | **6.3s (23%)** |
| `scan_for_new_addresses` | 20.1s, **timed out** ×2 | **2.1s**, completes |
| `account_balance` | 60.0s, **timed out** ×3, **0 addresses** | **12.2s, 197 addresses** |
| RPCs completed | 1208 / 1207 / 1086 | 1548 / 1548 / 1548 |
| wire time, median | 238ms | 243ms |
| wait before send, mean | 4028ms | **920ms** |

The ranges do not overlap. Two things matter more than the headline.

**The baseline never actually delivers balances.** `account_balance` hit the
SDK's 60s ceiling and returned **0 addresses** in all three baseline rounds;
`scan_for_new_addresses` hit its 20s ceiling in two of three. With the fix both
complete. End to end that is 292s-ending-in-nothing versus 42s-ending-in-197-
addresses — and it is why the baseline shows *fewer* RPCs: it was being cut off,
not doing less work.

**Wire time is unchanged: 238ms → 243ms.** That is the proof the mechanism was
identified rather than merely perturbed — a mutex cannot slow a round trip, and
it didn't. What collapsed is wait-before-send: mean 4028ms → 920ms, median
232ms → 16ms. Sum of wire time in a baseline run is 289s inside a 292s wall
clock, i.e. exactly one request in flight, always.

The estimate of 25% was low because the wave arithmetic modelled the wrong
thing. It reasoned about collapsing 4 sequential round trips into 3 waves per
address. The real structure is ~1200 requests funnelled one-at-a-time through a
per-coin mutex, so the win is not "4 waves → 3", it is "1-wide → 12-wide".

## Item 4 — pooled Hyper client: real, but small and inside the noise

| | item 2 only | + pooled client |
|---|---:|---:|
| `enable_eth_with_tokens` median | 26.2s | 23.5s (+10.6%) |
| samples | 23.8 / 28.6s (1 run failed) | 20.0 / 23.5 / 24.6s |
| **wire time, median** | 246ms | **207ms (-16%)** |
| wire time, p90 | 379ms | **245ms (-35%)** |

**The wall-clock difference is not separated by the noise** — the two arms'
sample ranges overlap and the driver says so. The *mechanism*, though, is
confirmed: per-request wire time drops 246ms → 207ms and holds at 206/206/208ms
across all three rounds, which is what removing a per-request TLS handshake
should look like. The handshake was worth ~40ms against these endpoints, not the
~150ms a 3-4× improvement would have needed.

So item 4 is worth keeping — it is ~16% off every EVM round trip, it makes
concurrency cheaper rather than more expensive, and it costs one extra
`lazy_static` — but on this workload it is a refinement, not a headline. Its
value will be larger on higher-latency links, where the handshake is a larger
share of the round trip.

## TRON: 6.9× on activation, 8.1× on the whole path

The same fix applies to `TronApiClient::try_clients`, whose comment called the
hold-across-await deliberate "for consistency with EVM's `try_rpc_send`
pattern". It was worse than the thing it matched: EVM's lock was per-coin, so
ETH contended only with its own tokens, but the TRON pool is `Clone`-shared via
`rpc_client: self.rpc_client.clone()` at activation — so **one mutex serialized
every TRON RPC in the process**: TRX balances, every TRC-20 `balanceOf`, TAPOS,
energy estimates, broadcasts and the HD gap probes alike.

Measured on `TRX + USDT-TRC20`, HD, gap 20, seven runs per arm alternating:

| step | baseline | final | |
|---|---:|---:|---|
| `enable_eth_with_tokens` | 35.7s | **5.2s** | **6.9×** |
| `scan_for_new_addresses` | 10.3s | **1.3s** | 7.9× |
| `account_balance` | 20.1s | **1.8s** | 11.2× |
| **total, excl. boot** | **68.1s** | **8.4s** | **8.1×** |

Medians. Activation samples were 35.0 / 35.1 / 35.6 / 35.8 / 48.3 / 122.6s
against 4.5 / 4.5 / 5.1 / 5.2 / 5.3 / 5.5 / 6.9s — **the ranges do not overlap**,
and the baseline's spread is again the fragility signature: its worst run was
3.5× its best, while the fixed build stayed inside 4.5-6.9s.

Both arms return all 41 addresses, so unlike the ETH case nothing is being
truncated — this is a like-for-like comparison of completed work.

**On iguana the change is not separated by the noise**, as expected: 1.6s → 0.9s
medians with overlapping ranges. A single-address wallet has almost no fan-out
to serialize, so there is nothing for the fix to recover. The win is a property
of the gap scan, not of TRON activation per se.

One baseline run failed outright with a TRON node-side
`Program$OutOfTimeException` on a `triggerconstantcontract`, aborting activation
for TRX *and* the token. As with the ERC-20 `decimals()` failure, this is on the
**unmodified** binary and is not caused by the concurrency work.

**Caveat: there is no TRON-side telemetry.** The `evm_rpc` / `evm_rpc_failover`
instrumentation lives in `eth_rpc.rs` and covers the EVM pool only, so the TRON
numbers above are wall clock and step timings, without the per-endpoint wire/wait
breakdown that makes the EVM result self-evidencing. Giving `try_clients` the
same two log lines is worth doing and would need both arms rebuilt to compare.

## What concurrency uncovered

**Rate limiting is now real, where before it was not.** Serialization at ~4
requests/second never provoked it; a 12-wide fan-out does. Counts rose from 1
per baseline run to 24-26, then to 49-230 as testing continued. Treat the
absolute numbers with suspicion: they climbed monotonically across ~40 minutes
of sustained testing from one IP, which looks like accumulating endpoint-side
limits against the tester rather than a property of either arm. Re-measure from
a clean IP before tuning on them.

Every 429 is handled — a non-200 returns immediately and fails over to the next
node at the cost of one round trip, and the pool's cursor then prefers the node
that answered. But two things follow:

* The concurrency budget is **not optional**. It defaults to 12 and is
  overridable with `KDF_EVM_RPC_MAX_CONCURRENCY` so this can be re-measured
  without a rebuild.
* **Spreading load across nodes instead of concentrating on one preferred node
  is the obvious follow-up.** With 4 nodes it would cut per-node load ~4×. It is
  not done here because it changes failover semantics and deserves its own
  measurement from an uncontaminated IP.

### A pre-existing single point of failure in activation

Two measured runs failed outright — a 429 on the ERC-20 `decimals()` call aborted
`enable_eth_with_tokens` for the platform *and* both tokens. That call goes
through `EthCoin::web3()` → `get_live_client`, which hands back **a single
transport with no failover at all**, so one rate-limited response kills the
activation.

**This is not caused by the concurrency change.** One of the two failures was on
the *unmodified* baseline binary, which still serializes every RPC and drew only
1-3 429s in its successful runs. A single unlucky one was enough. Concurrency
raises the 429 rate and therefore the probability, but the fragility is
pre-existing and fires on shipped code.

Rate: **2 activation failures in 20 measured runs**, both in the second half of
the session once the endpoints were rate-limiting hardest — 2 of the 12 runs in
that window. Read the 1-in-10 as the honest overall figure and the 1-in-6 as what
it degrades to on a bad hour; neither is a stable estimate from 20 samples, and
both are from one IP that had been hammering these endpoints for an hour.

It is also self-inflicted upstream: **neither `USDT-ERC20` nor `USDC-ERC20`
carries `decimals` in the shipped coins config**, so `v2_activation.rs` falls
back to reading it from chain on *every* ETH activation — two no-failover RPCs
per login, on the critical path, for a constant that is known in advance.

Fixed here by routing the ERC-20 constant getters through the pool, so they fail
over like everything else. **Adding `decimals` to those two coins-config entries
would remove the RPCs entirely** and is worth doing separately — that file is
synced from the coins repo, so it is not changed here.

## End to end, and why the baseline number moved

A third A/B, original baseline versus the final build with everything in:

| | baseline | final |
|---|---:|---:|
| `enable_eth_with_tokens` median | 329.1s | **21.9s** |
| samples | 332.0 / 326.3s (1 run failed) | 21.9 / 24.3 / 20.0s |
| wire time, median | 371ms | **210ms** |
| wait before send, mean | 4185ms | **857ms** |

The baseline is slower here than in the item-2 table above — 329.1s versus
212.1s — because the endpoints degraded over roughly an hour of sustained
testing from one IP. That is not noise to be apologised for; it is the clearest
evidence in this whole exercise:

> baseline wire time rose 238ms → 371ms, a factor of **1.56**.
> baseline wall clock rose 212.1s → 329.1s, a factor of **1.55**.

Serialized activation is a *linear function of per-RPC latency*, exactly as the
"one request in flight, always" reading predicts. Over the same degradation the
fixed build went 27.3s → 21.9s, i.e. did not track it at all. Whatever the
network is doing, concurrency absorbs it and serialization multiplies it.

Treat **7.8×** as the honest like-for-like figure (both arms measured early,
under equal conditions) and **15×** as what the same change is worth when the
network is having a bad hour.
