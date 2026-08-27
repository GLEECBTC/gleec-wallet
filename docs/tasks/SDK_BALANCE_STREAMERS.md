# SDK: duplicate per-token balance streamers, and a fallback that cannot see a balance change

Follow-up work from [`KDF_RPC_BURST_REPORT.md`](../KDF_RPC_BURST_REPORT.md). Both defects live in
`sdk/packages/komodo_defi_sdk/lib/src/balances/balance_manager.dart`.

The first is the only **permanent** background load the wallet puts on an EVM node. The second is a
correctness bug that bites in exactly the conditions the investigation is about.

**Target:** `gleec-wallet-kdf-integrations`, branch `add/gas-free-tron`; SDK is the vendored
submodule under `sdk/`. KDF reference (read-only): `komodo-defi-framework` @ **`25f6e1f0b`**.

**Sibling tasks:** [`KDF_RPC_POOL_FIXES.md`](KDF_RPC_POOL_FIXES.md),
[`SDK_GAP_SCAN_AND_WEBSOCKET.md`](SDK_GAP_SCAN_AND_WEBSOCKET.md). All independent — no ordering
constraint — but the gap-scan task touches `pubkey_manager.dart`, which item 2 below reads. Check
what it landed before measuring.

---

## 1. One KDF balance streamer per token, where the platform streamer already covers every token

`BalanceManager` subscribes per asset:

```dart
final balanceStreamSubscription = await _eventStreamingManager
    .subscribeToBalance(coin: assetId.id);
```
`balance_manager.dart:999-1000`, keyed `balance:$coin` (`streaming/event_streaming_manager.dart:204`)

and `supportsBalanceStreaming` returns true for ERC-20 child assets — it excludes only SLP,
Tendermint tokens, Sia, and QRC-20 children
(`komodo_defi_types/lib/src/coin_classes/protocol_class.dart:154-166`).

But KDF's `EthBalanceEventStreamer` already polls `all_addresses()` × (its own ticker **plus every
registered token**) every 10 seconds (`mm2src/coins/eth/eth_balance_events.rs:30`, `:190`). Tokens
register on the **platform** coin (`mm2src/coins_activation/src/eth_with_token_activation.rs`); a
token coin's own `erc20_tokens_infos` is `Default::default()` (`mm2src/coins/eth/v2_activation.rs:654`).
And the SDK already splits one platform BALANCE payload into one `BalanceEvent` per ticker
(`komodo_defi_framework/lib/src/streaming/events/kdf_event.dart:159-199`).

**So the platform streamer alone would satisfy every token subscriber, and each extra token streamer
re-polls the same address set.**

### Cost

With `N` known addresses and `T` tokens, the platform streamer does `N × (1 + T)` per 10s and is
sufficient; the token streamers add `N × T` on top.

| wallet | today | sufficient |
|---|---|---|
| GLEEC alone, `N=1` | 1 req / 10s | 1 req / 10s |
| GLEEC + 6 GRC-20, `N=1` | **13 req / 10s** | 7 req / 10s |
| 5 used addresses + 6 tokens | **65 req / 10s** = 6.5 req/s | 35 req / 10s |

6.5 req/s sustained **from one idle user** is roughly a third of the measured ~20 req/s capacity of
`evm-rpc.gleec.com`, and it doubles at the edge on web where every POST carries a CORS preflight.

### Fix

**Verify the premise first.** Subscribe a platform coin and a token, and confirm from KDF's logs that
the platform streamer's payload already carries the token's balance and that the SDK fans it out
correctly. If it does, suppress the per-token subscription for EVM child assets and serve them from
the platform coin's stream.

Watch for the case where a token is activated but its platform coin has no active subscriber.

---

## 2. When the balance stream dies, the polling fallback cannot observe changes

`fallbackToPolling` (`balance_manager.dart:1007-1046`) cancels the SSE subscription and calls
`_startBalancePolling`, whose timer calls `getBalance(assetId)` (`:955`, `:966`). `getBalance` is:

```dart
final balance = await _pubkeyManager!
    .getPubkeys(asset)
    .then((pubkeys) => pubkeys.balance);
```
`balance_manager.dart:537`

and `getPubkeys` returns `_pubkeysCache[asset.id]` whenever it is populated
(`pubkey_manager.dart:126-131`). **That cache has no TTL** — it is written by `_fetchFreshPubkeys`
and hydration, and cleared only on wallet reset or dispose.

So the "fallback" polls a cache that nothing in the fallback path refreshes. **The balance freezes at
its last value for the rest of the session, silently, with no error surfaced.**

The one thing that does refresh it is `watchPubkeys`' 30s tick (`pubkey_manager.dart:639`) — but for
EVM that watcher is page-scoped, alive only while `CoinAddressesBloc` is
(`lib/bloc/coin_addresses/bloc/coin_addresses_bloc.dart:960`, closed at
`lib/views/wallet/coin_details/coin_details_info/coin_details_info.dart:75`, `:251`). **On the wallet
list, with no coin page open, nothing refreshes it.**

Confirm that reading before fixing — it decides whether this is "always frozen" or "frozen unless a
coin page is open".

### Why it matters here specifically

The trigger is the incident itself: on web, under the 429 storm, the KDF balance SSE stream dies
(report §5) and this fallback is what takes over.

### Fix

Make the polling path actually fetch — a `forceRefresh`/bypass on the `getPubkeys` read, or a TTL on
`_pubkeysCache`, whichever fits the manager's ownership rules. `_pubkeysCache` is wallet-owned state
guarded by the generation token, so any TTL must not resurrect a previous wallet's entry; follow the
existing `_requireWalletContextCurrent` discipline.

Add a regression test that fails without the fix: stream dies → poll → balance reflects a changed
on-chain value.

---

## Do not

- **Do not reduce KDF's 10s `stream_interval_seconds` as a substitute.** It is a KDF-side constant
  and changes behaviour for every consumer. The duplication is the defect, not the interval.
- **Do not touch `pubkey_manager.dart`'s gap-scan guard** — that is
  [`SDK_GAP_SCAN_AND_WEBSOCKET.md`](SDK_GAP_SCAN_AND_WEBSOCKET.md), and both changing it invites a
  conflict.

## Checked and ruled out — do not spend time here

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

## Done means

- `cd sdk/packages/komodo_defi_sdk && KDF_HARNESS="" flutter test` passes, with regression tests for
  both fixes.
- App suite: `flutter test test_units/main.dart` **plus the four mandatory
  `--dart-define=TRON_GASLESS_*` flags** from [`TESTING.md`](../TESTING.md) §2 — without them ~36
  tests hang rather than fail and wedge the runner.
- `flutter analyze` clean. Conventional Commits.
- Revert any churn `flutter test` causes in `pubspec.lock`, `sdk/pubspec.lock` and
  `sdk/packages/komodo_defi_framework/app_build/build_config.json` — the PR gate fails on a dirty
  tree, and that `build_config.json` carries a deliberate unrelated edit.
