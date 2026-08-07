# SDK: stop the repeating EVM gap scan, and reach the WebSocket endpoints we already publish

Follow-up work from [`KDF_RPC_BURST_REPORT.md`](../KDF_RPC_BURST_REPORT.md).

**Target:** `gleec-wallet-kdf-integrations`, branch `add/gas-free-tron`. The SDK is the vendored
submodule under `sdk/`. KDF reference (read-only): `komodo-defi-framework` @ **`25f6e1f0b`** —
its worktree is dirty with unrelated in-flight work, so read `git diff` before citing `eth_rpc.rs`.

**Sibling tasks:** [`KDF_RPC_POOL_FIXES.md`](KDF_RPC_POOL_FIXES.md),
[`SDK_BALANCE_STREAMERS.md`](SDK_BALANCE_STREAMERS.md). All independent; no ordering constraint.

Part 1 is the largest single load reduction in the whole investigation and is low risk. Part 2 is a
broad transport rollout and carries real operational surface.

---

# Part 1 — the EVM HD gap scan repeats every 30 seconds, forever

**This is larger than the activation burst the report is about, and the report does not state it.**

`_scanForNewHdAddressesIfNeeded`
(`sdk/packages/komodo_defi_sdk/lib/src/pubkeys/pubkey_manager.dart:795-840`) has exactly one skip on
the success path:

```dart
if (alreadyScannedByActivation && !_hdAddressScanDone.contains(scanKey)) {
  _hdAddressScanDone.add(scanKey);
  return;
}
```

`alreadyScannedByActivation` comes from `_activationAlreadyScanned` (`:777`), which requires
`asset.protocol.defaultActivationParams().scanPolicy != null`. **`EthWithTokensActivationParams` has
no `scanPolicy` field at all** — only UTXO/QTUM/ZHTLC set one. So for ETH-family the branch never
fires, `_hdAddressScanDone` is never populated, and nothing else guards the success path;
`_hdAddressScanRetryAfter` is a post-*failure* cooldown only.

`_fetchFreshPubkeys` (`:775`) calls it, and `watchPubkeys` calls `_fetchFreshPubkeys` on **every
30-second tick** — `Stream<void>.periodic(_defaultPollingInterval)` at `:617`, interval at `:112`,
call site at `:637`. `scanForNewAddresses` is a real KDF RPC:
`hd_multi_address_strategy.dart:38-47` issues `task::scan_for_new_addresses::init` with
`gapLimit: 20` and polls status.

KDF walks from `known_addresses_number` for `gap_limit + 1` addresses
(`mm2src/coins/lp_coins.rs:6351-6395`), probing each with `is_address_used` = one
`eth_getTransactionCount` then one `eth_getBalance` (`mm2src/coins/eth/eth_hd_wallet.rs:68`,
`:124-140`). On an empty wallet nothing becomes "known", so **the same 21 candidates are re-probed
every tick.**

**Cost** (derived from source, not measured): ~42 RPCs every 30 seconds, per EVM asset, for the life
of the session — 21 × (2 + 6) = 168 with the six GRC-20 tokens. That is ~84 RPCs/minute sustained
against an endpoint serving ~20 req/s, roughly doubled at the edge on web by CORS preflights.

**Exposure:** for EVM the `watchPubkeys` watcher is page-scoped — `CoinAddressesBloc`
(`lib/bloc/coin_addresses/bloc/coin_addresses_bloc.dart:960`), closed at
`lib/views/wallet/coin_details/coin_details_info/coin_details_info.dart:75`, `:251`. So this is
triggered by *sitting on a coin page*. It is also permanent for every non-balance-streaming asset via
`BalanceManager._attachPubkeyHintListener` (`balance_manager.dart:981`).

**Verify before fixing** — instrument a session or read KDF's logs — because the fix differs
depending on whether it is the login-time duplicate, the periodic repeat, or both.

## The trap in the obvious fix

Do **not** simply make `_activationAlreadyScanned` return true for EVM.
`_activationCoordinator.wasFreshlyActivated` means "this session issued the activation RPC"
(`activation_manager.dart:62-77`), not "KDF walked the gap". On a warm re-login the asset is already
enabled, activation does nothing, and the scan is genuinely needed. **The existing UTXO path has the
same latent bug — do not copy it.**

What is true and load-bearing: **KDF's ETH-family activation does walk the gap by default.**
`EthActivationV2Request` carries `#[serde(flatten)] pub enable_params: EnabledCoinBalanceParams`
(`mm2src/coins/eth/v2_activation.rs:250`), so `scan_policy` takes its serde default rather than being
absent — the SDK simply never sends one. Confirm the default in KDF and quote it in the fix.

Two things to get right:

1. **The post-activation scan is redundant** when activation actually ran this session — same walk,
   same gap limit, immediately after, against the same host.
2. **A 30-second full gap walk is not a sane steady-state cadence** for a chain whose address set
   cannot change without an on-chain transaction. The guard must bound the *repeat*, not only the
   back-to-back one. Record the completed scan per (wallet, asset) and re-scan on a much longer
   interval, or on a real trigger — an incoming transaction, a user-initiated refresh — rather than a
   timer.

Fix the comment at `pubkey_manager.dart:777-780` too. It says the ETH-family params "have no
`scan_policy` field at all, so their HD address discovery is *not* covered by activation and must
still scan." The first clause is true of the Dart; the conclusion is false. **That wrong comment is
what makes the current behaviour look deliberate.** The same claim appears at
[`WALLET_LOAD_MEASUREMENT.md:92`](../WALLET_LOAD_MEASUREMENT.md) and should be corrected there too.

## Related: the activation fan-out multiplies this

On activation success `ActivationManager` fires `precacheBalance` for
`[group.primary, ...group.children]` without awaiting (`activation_manager.dart:986-993`).
`precacheBalance` → `getPubkeys` → cold cache → `_fetchFreshPubkeys` → scan, **and retries up to 3
times** (`balance_manager.dart:1589-1618`). `coins_bloc` then independently dispatches `getPubkeys`
per coin with 3 more attempts (`lib/bloc/coins_bloc/coins_bloc.dart:47`, `:164-201`); concurrent
calls dedupe via `_inFlightPubkeyRequests` (`pubkey_manager.dart:328-330`), sequential retries do
not.

GLEEC + 6 tokens is therefore ~7 concurrent scans ≈ **294 node requests immediately after
activation**, on top of the 176 measured in report §2.2 — so the app's real login cost is roughly
**2.5× the standalone ladder's**, which the ladder structurally cannot see. Fixing part 1 collapses
most of this; the double retry ladder is worth a look while you are there.

**Expected effect:** fresh GLEEC HD login ~87 logical RPCs → ~45. Sustained ~84/min per EVM asset →
near zero between real events.

---

# Part 2 — roll the WebSocket transport out across every EVM chain that publishes one

## Scope, counted from the shipped `coins_config.json`

**557 of 596 EVM assets carry a `ws_url`** — but the meaningful unit is the platform chain, because
tokens `Arc::clone` the platform coin's pool (`v2_activation.rs:643`, `:751`) rather than opening
their own. **13 platform coins** own a pool and carry a `ws_url`:

| chain | nodes | with `ws_url` | http-only |
|---|---|---|---|
| MATIC | 4 | 4 | **0** |
| GLMR, MOVR | 3 | 3 | **0** |
| AVAX, BNB | 5 | 2 | 3 |
| ETH | 4 | 2 | 2 |
| XDAI | 3 | 2 | 1 |
| ETH-ARB20 | 4 | 1 | 3 |
| ETH-BASE | 3 | 1 | 2 |
| ETC, RBTC | 2 | 1 | 1 |
| **GLEEC, EWT** | **1** | **1** | **0** |

24 distinct wss endpoints, concentrated on publicnode.com, cipig.net, tenderly, drpc and gateway
hosts. The default 8-coin wallet touches GLEEC (1 ws) and ETH (2 ws); TRX is TRON and hard-rejects
non-HTTP (`v2_activation.rs:1242-1251`).

## The wire contract

KDF needs no schema change. `EthNode` is `{url, komodo_proxy}` with no `deny_unknown_fields`
(`v2_activation.rs:261-266`) — so a `ws_url` key in the payload would be silently discarded, and
`ws_url` appears nowhere in KDF's Rust source. Transport selection is **scheme sniffing on `url`**:

```rust
match uri.scheme_str() {
    Some("ws") | Some("wss") => create_websocket_transport(..),
    Some("http") | Some("https") => create_http_transport(..),
    _ => MmError::err(..),
}
```
`v2_activation.rs:1269-1275`

The websocket transport is not `cfg`-gated off wasm (`web3_transport/mod.rs:16`, unlike
`metamask_transport`) and uses `tokio_tungstenite_wasm`, which is a real browser `WebSocket` on
wasm32 — **it works on web, the platform the incident came from.** `evm-ws.gleec.com` returns
`101 Switching Protocols` through Cloudflare from an arbitrary `Origin`.

So: `EvmNode` parses `ws_url`, and each config node expands into **two** payload entries — the
existing `{"url": "https://…"}` plus `{"url": "<ws_url>"}`.

### Always additive, never a replacement

GLEEC, EWT, GLMR, MATIC and MOVR have **no** http-only node. Substituting rather than adding would
strip those chains of HTTP entirely and leave them with no fallback at all. Expanding gives MATIC 4
entries → 8, and GLEEC 1 → 2 — which is itself the fix for the single-node-no-fallback condition
`web3_pool.rs:52-64` blames for the original incident.

### Where `ws_url` is dropped today

`sdk/packages/komodo_defi_rpc_methods/lib/src/common_structures/activation/evm_node.dart` is 22
lines and drops it twice — `fromJson` never reads it, `toJson` never emits it. Every EVM
construction site funnels through `EvmNode.fromJson`, so the loss is total and happens at parse
time. The payload sites are `eth_activation_params.dart:70` and `erc20_activation_params.dart:40`
(`nodes.map((e) => e.toJson()).toList()`).

**Do not touch the TRX/TRC20 params** — TRON rejects non-HTTP. Note `TronQuickNodeTransform`
(`config_transform.dart:285-320`) rebuilds `nodes` as `{'url': …, 'komodo_proxy': true}`, another
place `ws_url` would be lost; harmless, since TRON cannot use it.

## Validate the 24 endpoints before shipping

A dead ws node is not free. `try_every_node` allots `TRY_RPC_NODE_TIMEOUT_S` = 10s per node, and the
ws path has **no fast-fail** — `send_request` parks on an unbounded channel while
`attempt_to_establish_socket_connection` burns 3 attempts at 1/2/4s and then simply returns, leaving
callers to time out.

Write a re-runnable probe that, for each of the 24 endpoints, opens the socket, sends
`{"jsonrpc":"2.0","method":"net_version","params":[],"id":0}`, and records whether a response
arrives and how quickly. Ship only the endpoints that answer; drop the rest from the expansion with
a comment recording the date and the failure. Commit the probe's results as data.

## Node ordering is an optional follow-up, not a prerequisite

`build_web3_instances` shuffles the node list (`v2_activation.rs:1184-1185`) and `Web3Pool.preferred`
starts at index 0 of the **shuffled** list, so which transport a chain uses is not controllable from
the SDK.

**This does not block the rollout.** `mark_preferred` repoints on the first successful ws call, and
`on_node_refused()` is not called when the failover loop recovered — so an unlucky shuffle costs
roughly the first wave (up to the permit budget, ~12 requests) landing on HTTP, not the whole
44-call burst. What a KDF-side ordering change buys is determinism and the removal of
preferred-thrashing between the two transports. It is written up as item 5 of
[`KDF_RPC_POOL_FIXES.md`](KDF_RPC_POOL_FIXES.md) and can land before, with, or after this.

## Decide native explicitly

`SslElectrumTransform` filters `nodes` to `url.startsWith('https://')` and is in the default
transform list, but `needsTransform` returns **false on web** (`config_transform.dart:365-367`). So
today a wss node would reach KDF on web and be stripped on native.

That is a defensible default — the preflight doubling and the ACAO-less 429 are web-only problems —
but make it a stated decision rather than an accident. If native is wanted too, that transform is the
place, and `WssWebsocketTransform` (`config_transform.dart:222-262`) already does exactly this kind
of platform-conditional selection for `electrum` and is the pattern to follow.

## Two things to check outside activation

- **Swap and withdrawal.** `get_addr_nonce` (`mm2src/coins/eth.rs:6282`) fans out to **every**
  instance directly — no pool permit, no retry, no backoff — takes the max nonce, and
  `sign_and_send_transaction_with_keypair` broadcasts via the instances it returns. Adding ws
  instances changes what that path talks to. Test a real withdrawal on at least one chain.
- **iOS file descriptors.** Prior measured work put KDF's peak at ~+12 sockets against iOS's
  256-per-process soft limit. `create_websocket_transport` spawns a *temporary* connection loop for
  **every** ws node at activation (`v2_activation.rs:1301`, 20s expiry via `TMP_SOCKET_CONNECTION`),
  so activating all 13 chains transiently opens up to **24** additional sockets. Re-run
  `tool/kdf_fd_probe.py` before shipping and record the new peak.

Also write down: there is no protocol-level ping/pong, so keepalive is an application-level
`net_version` JSON-RPC every 10s per socket per node for the life of the session
(`websocket_transport.rs:37`, `:127`). And a long-lived socket across mobile backgrounding and
network changes is a failure mode the HTTP path does not have — `stop_connection_loop` fires on any
transport error, and the socket is `Arc`-shared by the platform coin and all its tokens, so one bad
frame drops it for all of them.

## Expected effect

On web, a first-time HD login on a ws-preferred chain: ~88 edge requests (44 POST + 44 preflight) →
**1** HTTP Upgrade, with the frames afterwards outside the per-request rate limiter and outside the
CORS model entirely — so the unrecoverable-refused-preflight failure disappears structurally rather
than becoming rarer. Combined with part 1, a GLEEC login goes from ~87 logical RPCs over ~99–210 edge
requests to ~45 logical RPCs over 1.

> **Provenance:** an exploratory probe recorded 44/44 calls over one socket in 0.34s and 200/200 at
> ~130 req/s against `evm-ws.gleec.com`, versus an HTTPS endpoint that refuses above ~20/s. Those
> figures have **no archived raw output** — treat them as indicative and re-measure.

---

## Do not

- **Do not add `scan_policy` to the ETH activation params as the fix for part 1.** KDF would accept
  it (no `deny_unknown_fields`; values are snake_case `do_not_scan`/`scan_if_new_wallet`/`scan`), but
  `scan_policy: scan` moves the 42 probes *inside* `enable_eth_with_tokens`, into the same burst
  window as every other coin's activation — trading a later burst for a denser earlier one, on
  exactly the axis the 429s live on. Total requests do not fall.
- **Do not touch the activation retry counts** (`coins_bloc.dart:24`, `coins_repo.dart:531`) — app
  scope, separate concern.

## Done means

- `cd sdk/packages/komodo_defi_sdk && KDF_HARNESS="" flutter test` passes, with a regression test
  that fails without part 1 — specifically "N ticks of `watchPubkeys` issue at most one gap scan".
- A test that a config node carrying `ws_url` expands to two payload entries and that the https entry
  is never dropped.
- App suite: `flutter test test_units/main.dart` **plus the four mandatory
  `--dart-define=TRON_GASLESS_*` flags** from [`TESTING.md`](../TESTING.md) §2 — without them ~36
  tests hang rather than fail and wedge the runner.
- The endpoint probe's results committed as data, with the date.
- `flutter analyze` clean. Conventional Commits.
- Revert any churn `flutter test` causes in `pubspec.lock`, `sdk/pubspec.lock` and
  `sdk/packages/komodo_defi_framework/app_build/build_config.json` — the PR gate fails on a dirty
  tree, and that `build_config.json` already carries a deliberate unrelated edit.
