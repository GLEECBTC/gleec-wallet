# Hand-off: make EVM activation stop being the slowest thing in a login

You are picking up the second half of a wallet-load latency effort. The first
half is **done, merged and measured**; this document is the remaining work.

Read [`KDF_LATENCY_REPORT.md`](KDF_LATENCY_REPORT.md) for how the measurements
are taken and [`KDF_IMPROVEMENT_OPPORTUNITIES.md`](KDF_IMPROVEMENT_OPPORTUNITIES.md)
§2 and §4 for the source analysis behind items 1 and 2 below.

---

## Where the work happens

**Every file this document asks you to change is in a different repository than
this document.** Three repos are involved:

| repo | role | you will |
|---|---|---|
| `komodo-defi-framework` (sibling checkout) | the Rust source: `mm2src/coins/eth/**`, `common/wio.rs`, `mm2_net/**` | **edit every line here** |
| this repo (`gleec-wallet-kdf-integrations`) | `tool/kdf_latency_probe.py`, `sdk/packages/komodo_defi_harness`, these docs | **measure and validate from here** |
| `nitride-kdf-builds` | 7-target release build + Cloudflare R2 publish | only when shipping a binary to the app |

So: **drive the task from this repo, but make no source edits in it.** This is
the only place that has the probe, the harness, the recorded baselines and the
validation loop; the KDF repo is the only place with the code.

**Use the existing sibling checkout, not a fresh clone.** It carries a warm
Cargo `target/` (~200 GB), which is the difference between a ~5 minute
incremental build and a ~45 minute cold one. You will rebuild many times.

**Branch from `perf/hd-scan-concurrency`** (`ed8de236b`), not from
`feat/tron-gasfree` — you want the concurrent gap scan and the P2P panic fix
underneath you, and that commit is what the app currently pins in
`sdk/packages/komodo_defi_framework/app_build/build_config.json`. Note it is
pushed only to the `fork` remote (`CharlVS/komodo-defi-framework`); if it lands
on `feat/tron-gasfree` or upstream in the meantime, rebase rather than
branching twice.

The loop is: edit in the KDF repo → `cargo build --release --target
aarch64-apple-darwin --bin kdf` → point the probe at the built binary with
`--kdf` → compare. Only bother with the full `nitride-kdf-builds` release and
the `build_config.json` bump once you have a result worth putting in front of
the app.

---

## Where things stand

**Fixed already (KDF `perf/hd-scan-concurrency`, commit `ed8de236b`):** the HD
address gap scan now probes concurrently instead of one address at a time.
Measured through the real SDK on an empty HD wallet:

| | before | after |
|---|---:|---:|
| HD `activation_ms` | 35,966ms | **7,161ms** |
| HD time-to-first-balance | 47,986ms | **8,303ms** |
| BTC-segwit activate | 121.2s | **8.2s** |
| gap 1 / 20 / 50 | 9.1 / 46.9 / 107.0s | **7.1 / 6.1 / 7.6s** |

**Not fixed, and now the dominant cost:** EVM. `enable_eth_with_tokens` for
ETH + 2 ERC-20 tokens still measures **196.9–346.4s** on a fresh HD wallet. On
the app's default coin set that single call is most of the remaining login time.

---

## Expected improvement

Two independent changes. **Do not add their savings** — item 2's handshake cost
is part of the per-RPC cost item 1 holds constant.

| # | change | expected | confidence | helps |
|---|---|---|---|---|
| 1 | Release the `web3_instances` mutex before the network round trip | **~90s off 363.8s** (25%); more with more tokens | medium-high | everyone |
| 2 | Give the EVM transport a pooled Hyper client | **~13–26s** (4–7%) | medium | everyone |

### Why item 1 is worth ~25% and not more

`is_address_used` for EVM (`eth/eth_hd_wallet.rs:125-150`) is **three causally
sequential short-circuiting stages** — `transaction_count`, then
`address_balance`, then the token fan-out. That ordering is in the source and
concurrency cannot merge it. So `(2 + K)` round trips collapse to **3 waves**,
K = ERC-20 token count:

* K=2 (the measured case): 4 → 3 waves = **25%**, 363.8s → ~273s
* K=4 → 50%. K=13 → 79%. The app-default ETH call benefits in proportion.
* Strongest clean win is on **iguana**: `BNB + 13 tokens` is 14 serial round
  trips → 2 waves, 19.95s → ~3–8s.

An earlier estimate of "~2×, ~180s" assumed 4 independent round trips per
address. That is wrong — it was corrected by two independent reviewers reading
`eth_hd_wallet.rs`. Use 25%.

### Honest uncertainty, read this before you start

**~85% of the EVM per-RPC cost is unexplained.** HD implies ~4.2s per round trip
(363.8s / ~87 RPCs); iguana implies ~0.6s (2.5s / ~4) — same binary, same nodes,
same transport. **A mutex cannot slow down an individual round trip.** Something
else is going on, most likely endpoint rate limiting or failover against the 10s
`TRY_RPC_NODE_TIMEOUT_S`.

If it is rate limiting, item 1's concurrency is partly self-defeating and the
semaphore below caps the win exactly where the estimate assumes it is free.
**Land item 1 with per-endpoint 429/failover instrumentation so this becomes
measured rather than assumed.** If the numbers come back flat, stop and
re-measure before doing item 2 — the bottleneck is elsewhere and neither change
will help.

There is also a second, unrelated measurement oddity on record: the same fixed
build produced **bimodal** EVM timings (196.9 / 219.0 / 346.4s across three
alternating A/B rounds, against a very tight 343.3 / 343.4 / 363.8s baseline).
Never regressed, sometimes ~40% better, cause unknown. Take **at least 3
alternating samples per arm** and report the spread, not a single number.

---

## Item 1 — release the mutex before the round trip

`mm2src/coins/eth/eth_rpc.rs:27`:

```rust
let mut clients = self.web3_instances.lock().await;
```

The guard lives to end of function, because `clients.rotate_left(i)` (`:44`)
still needs it — so every `execute_fut.timeout(TRY_RPC_NODE_TIMEOUT_S).await`
(`:41`, 10s at `:23`) runs under an exclusive `futures::lock::Mutex`. Every EVM
RPC funnels through it: `call` (`:86`), `balance` (`:165`),
`transaction_count` (`:285`). **At most one RPC in flight per `EthCoin`, ever.**

No second serializer underneath — the native HTTP transport takes no lock
(`eth/web3_transport/http_transport.rs:101-190`). KDF already does this
correctly in-tree: `get_addr_nonce` snapshots with `.lock().await.to_vec()`
then fans out unlocked (`eth.rs:6276`).

**TRON repeats the anti-pattern and is worse:**
`TronApiClient { clients: Arc<AsyncMutex<...>> }` (`eth/tron/api.rs:806`) is
Clone-shared, serializing every TRON RPC across TRX and all TRC-20s
process-wide. The comment at `:825` calls the hold-across-await deliberate,
"for consistency with EVM's `try_rpc_send` pattern" — fix both or the comment
becomes false.

### Prerequisites — do not ship without them

1. **`websocket_transport.rs:207`** does
   `notifier.send(res_bytes).expect("receiver channel must be alive")`. The
   notifier stays registered for 30s while `try_rpc_send` abandons at 10s, so a
   response landing in that 20s window **panics the connection loop and drops
   every other in-flight request on that node**. Today the mutex makes 10s
   timeouts rare; concurrency makes them routine. Must become
   `let _ = notifier.send(...)`, or align the timeouts.
   *(A `let _ =` fix for this already shipped on `perf/hd-scan-concurrency` —
   confirm it is in your base before relying on it.)*
2. **`eth_rpc.rs:51-53` and `:58-60`** call `stop_connection_loop()` on every
   failure, pushing `Close` into an unbounded channel
   (`websocket_transport.rs:302-307`). Concurrent failures enqueue N Closes and
   the surplus kills the *next* connection loop the moment it spawns
   (`:281-287`). Needs an idempotency guard.
3. **`pool_max_idle_per_host(0)`** (`common/wio.rs:115`) means no connection
   reuse, so a 14-wide fan-out becomes 14 simultaneous TLS handshakes to one
   host. A **per-coin semaphore (8–16 permits) is mandatory**, not optional, and
   it caps the realized win below the wave arithmetic.
4. **`rotate_left` cannot simply be re-acquired.** `i` indexes the dropped
   snapshot. Use `AtomicUsize` + `Arc<Vec<Web3Instance>>`; budget for retyping
   `web3_instances` at ~6 construction/read sites.

### Swap safety — verified clean, state it in the PR

The lock never spans a read-modify-write: `eth_getTransactionCount` and
`eth_sendRawTransaction` are separate `try_rpc_send` calls with the lock
released between, so it provides **zero atomicity today**. Nonce ordering is
guarded independently and per-address by `nonce_sequencer::PerNetNonceLocks`
(`eth/eth_utils.rs:22-67`). The websocket transport routes by `request_id`
(`websocket_transport.rs:141-210`), so responses cannot be mis-routed. No test
in the tree references `try_rpc_send`, `get_live_client` or `try_clients`.

---

## Item 2 — pooled Hyper client for the EVM transport

`HYPER` is one process-global `lazy_static` built with
`.pool_max_idle_per_host(0)` (`common/wio.rs:115`). In hyper 0.14.26,
`max_idle_per_host == 0` makes `Config::is_enabled()` false (`pool.rs:99-101`)
and `Pool::new` sets `inner = None` (`:105-119`) — which **also disables HTTP/2
connection sharing** (`Pool::connecting`, `:154-178`), despite `wio.rs:102`
enabling h2 and ALPN advertising it. KDF negotiates h2 and then throws the
connection away per request. `HttpConnector` has no DNS cache
(`connect/http.rs:337`), so each RPC pays getaddrinfo too.

The `wio.rs` comment names the mitigation it wished existed
(`pool_idle_timeout`), and hyper has since shipped the safety property it
feared: `retry_canceled_requests: true` by default (`client.rs:923`), retrying
only requests never written to the wire (`proto/h1/dispatch.rs:617-623`). **A
pooled client cannot double-broadcast a signed transaction.**

**Take the scoped variant, not the global flip.** Give the EVM/TRON transport
its own pooled `Client`. `SlurpHttpClient` is a blanket impl over `Client<C>`
(`mm2_net/src/native_http.rs:183-191`), so a second client needs zero new trait
impls (~10 lines). `HYPER` has **32 call sites** — TronGrid, 1inch, price feeds,
the UTXO native client, grpc-web — and those are *not* mutex-serialized, so
enabling h2 multiplexing for them is an untested behaviour change. Note also
that `.pool_idle_timeout(20s)` feeds the connector's TCP keepalive
(`client.rs:1380`), dropping SO_KEEPALIVE from 90s process-wide.

**Untestable from this repo:** a pooled client's behaviour against
komodo-defi-proxy under the `X_AUTH_PAYLOAD` signature path
(`http_transport.rs:120-134`). If the proxy does per-connection auth accounting
or rate limiting, pooling changes attribution. Test against the real proxy.

---

## How to measure

Do **not** measure through the app. Use the Python probe — stdlib only, no
Flutter/Dart/SDK in the loop:

```bash
export KDF_TEST_SEED='abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about'

# baseline vs your build, alternating arms, >=3 rounds each
python3 tool/kdf_latency_probe.py --coin-list ETH --kdf /path/to/old/kdf
python3 tool/kdf_latency_probe.py --coin-list ETH --kdf /path/to/new/kdf

# the realistic login
python3 tool/kdf_latency_probe.py --coin-set app-default --wallet-type hd
```

Then confirm through the real SDK, which is what the app experiences:

```bash
cd sdk/packages/komodo_defi_harness
KDF_HARNESS=1 KDF_TEST_SEED='abandon ... about' flutter test test/process/real_kdf_smoke_test.dart
```

**Traps, all of which have already caught someone on this work:**

* **A failed step returns fast.** If your tooling records an error as a
  completed step, a failure reads as a speedup. A `NoSuchCoin` once presented as
  a 92× win. The probes now flag failures explicitly — keep it that way.
* **Alternate the arms.** A non-alternating A/B once made a change look like a
  regression; it was time-of-day network drift.
* **Compare like for like.** A `--p2p` run with other coins already activated is
  not comparable to a standalone row.
* **Build the KDF binary with the CI-pinned toolchain** and regenerate any Dart
  lockfile with `fvm flutter pub get` — see `docs/FLUTTER_VERSION.md`.

## Definition of done

1. Item 1 landed with its four prerequisites and 429/failover instrumentation.
2. EVM activation re-measured, ≥3 alternating samples per arm, **spread
   reported** — not a single number.
3. If the win is materially below ~25%, say so and report where the time
   actually goes. The unexplained ~85% above matters more than hitting a target.
4. Swap-safety argument restated in the PR against the code as you find it.
5. `docs/KDF_IMPROVEMENT_OPPORTUNITIES.md` § Validation updated with the
   measured result, including anything that turned out wrong.
