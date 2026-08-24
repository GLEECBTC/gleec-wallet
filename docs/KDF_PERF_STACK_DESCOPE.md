# Descoping the wallet from the three open KDF performance PRs

**Date:** 2026-08-24
**Rolled from:** `538724e9e497ab4bc581b71ebcc2aed9cd681de3` (branch `perf/evm-rpc-429-backoff`)
**Rolled to:** `f3efd2ca10420f2982fa127dde84dcc17891f577` (branch `main`, `3.1.0-beta_f3efd2c`)

The wallet was pinned to the **top of an unmerged three-PR stack**. This document
records what that pin was buying, what the roll to `main` gives up, and exactly
what to change back when each PR lands. It is a checklist, not a narrative:
every row is a file and a revert.

`main` carries the merged gas-free work (kdf-internal PR #1, released to `main`
by PR #21), so the roll loses **nothing** gas-free. The gas-free module is
byte-identical between the two pins apart from one file - see
[What did not change](#5-what-did-not-change).

---

## 1. The three PRs

All three are on `GLEECBTC/kdf-internal`, stacked, and rebased onto `main`'s
lineage (base `6afb05f40`). The wallet's old pin `538724e` was the *pre-rebase*
version of the same work off `feat/tron-gasfree`; the commit SHAs below are the
current, rebased ones.

| PR | Branch | Base | Title |
|----|--------|------|-------|
| [#18](https://github.com/GLEECBTC/kdf-internal/pull/18) | `perf/hd-scan-concurrency` | `dev` | perf(hd): probe the address gap concurrently and stop p2p ctx panics |
| [#19](https://github.com/GLEECBTC/kdf-internal/pull/19) | `perf/evm-rpc-concurrency` | `perf/hd-scan-concurrency` | perf(eth): run EVM RPCs concurrently and pool HTTP connections |
| [#20](https://github.com/GLEECBTC/kdf-internal/pull/20) | `perf/evm-rpc-429-backoff` | `perf/evm-rpc-concurrency` | fix(eth): back off and retry rate-limited EVM and TRON RPC nodes |

Load-bearing commits, by PR:

| PR | Commit | What it is |
|----|--------|-----------|
| #18 | `ba4b3996e` | concurrent HD gap scan (32-wide window) |
| #18 | `d2c16fc29` | `P2PContext::try_fetch_from_mm_arc`; **also** `websocket_transport.rs` `.expect` → `let _ =` |
| #19 | `28e923c52` | connection-pooling Hyper client |
| #19 | `1aeca6f30` | stop holding the RPC pool lock across the round trip (`web3_pool.rs`) |
| #20 | `ddf9763ad`, `2fefaf55e`, `7d81dffec`, `a3fb9ea75`, `94deb56c0` | EVM 429 backpressure + bounded retry |
| #20 | `5797c845d`, `794518146` | TRON rate-limit survival; broadcast kept out of the permit queue |
| #20 | `7d4e1872c` | generation-stamped ws `Close` + spawn reservation; NFT/activation no longer take the instance down |
| #20 | `c19bc1755` | keeps node URLs (and any embedded API key) out of RPC error text |

**How to tell the pin has them.** The three markers, cheapest first:

```bash
grep -c web3_pool <(strings -a <extracted kdf binary>)      # 0 = stack absent, >0 = present
grep -c "receiver channel must be alive" <(strings -a ...)  # 6 = PR #18 absent, 0 = present
git -C <kdf clone> merge-base --is-ancestor d2c16fc29 <pinned sha> && echo "PR #18 in"
```

---

## 2. Changes made to descope — revert these

### 2.1 `_kSendWsNodesOnWeb` — the only functional descope

**File:** `sdk/packages/komodo_defi_rpc_methods/lib/src/common_structures/activation/evm_node.dart`
**Unblocked by:** PR #18 (`d2c16fc29`) **and** PR #20 (`7d4e1872c`) — both, not either.

Added a `_kSendWsNodesOnWeb = false` gate mirroring the existing
`_kSendWsNodesOnNative`, and an early return in `shippableWsUrlFor`:

```dart
if (isWeb) {
  if (!_kSendWsNodesOnWeb) return null;          // <- added
  return _webUnusableWsEndpoints.containsKey(wsUrl) ? null : wsUrl;
}
```

**Why.** `main` panics on an ordinary late websocket response, and on wasm a
panic takes the whole MM2 instance down:

- `mm2src/coins/eth/eth_rpc.rs:23`, `:41` — the caller abandons a call at
  `TRY_RPC_NODE_TIMEOUT_S = 10s`, dropping the oneshot `Receiver`.
- `mm2src/coins/eth/web3_transport/websocket_transport.rs:153` — the notifier
  stays registered for `WEB3_REQUEST_TIMEOUT_S = 30s` (`mm2src/coins/eth.rs:222`).
- `websocket_transport.rs:207` — a reply landing in that 10-30s window reaches
  `notifier.send(res_bytes).expect("receiver channel must be alive")` and panics.
- `mm2src/mm2_bin_lib/src/mm2_wasm_lib.rs:129` states outright that the async
  wasm entry cannot be wrapped in `catch_unwind`, so nothing contains it.

The socket is `Arc`-shared by the platform coin and every token on that chain
(`v2_activation.rs:643`, `:751`), so one slow reply takes them all with it.

This was live, not theoretical: the shipped coins config carries **1100** node
entries with a `ws_url`, and `toRpcNodeList` is on the production activation
path (`activation_params/eth_activation_params.dart:89`,
`activation_params/erc20_activation_params.dart:42`).

`7d4e1872c` is also required, not just `d2c16fc29`: without it an untagged
`Close` left over from a previous connection loop kills the next one the moment
it spawns, and `try_lock().is_some()` releases the guard before spawning so N
concurrent callers spawn N loops, N-1 of which park forever.

**To revert:** flip `_kSendWsNodesOnWeb` to `true`. Nothing else in the file
needs to change - `_deadWsEndpoints`, `_webUnusableWsEndpoints` and the
additive shape of `toRpcNodeList` all still hold.

> **Scope: EVM only.** This does *not* take websockets away from web generally.
> Electrum's `ws_url` (`ActivationServers`, `activation_params.dart:542`, `:566`)
> is a different KDF path — `utxo/rpc_clients/electrum_rpc/` — which has **zero**
> `.expect(` on `main` and differs between the pins only in one error-message
> string (`connection.rs:288-291`). UTXO coins keep their WSS transport on web.
> Only the EVM `websocket_transport.rs` is disabled here.

### 2.2 The test that pins 2.1

**File:** `sdk/packages/komodo_defi_rpc_methods/test/src/common_structures/activation/evm_node_ws_expansion_test.dart`
**Unblocked by:** same as 2.1.

Replaced the compile-time `_isWeb` branches with `_wsShippedOnThisBuild = false`,
so the assertions describe the shipping policy rather than the platform. The
`web ships a healthy endpoint` case now expects `isNull` while the gate is off,
with the reason naming `_kSendWsNodesOnWeb` and the two PRs.

**To revert:** set `_wsShippedOnThisBuild = true` in the same commit that flips
`_kSendWsNodesOnWeb`. The constant exists precisely so the two move together and
the tests do not silently pass in the wrong state.

### 2.3 Activation-deadline rationale

**File:** `sdk/packages/komodo_defi_sdk/lib/src/activation/shared_activation_coordinator.dart`
**Unblocked by:** PR #18 (`ba4b3996e`).
**Behaviour change: none.** `defaultActivationTimeout` stays at 3 minutes.

The doc comment cited BTC-segwit 8.2s / KMD 6.1s as the slowest legitimate
activation. Those are concurrent-gap-scan numbers. Sequentially the same runs
measured **BTC-segwit 121.2s / KMD 46.9s** (`docs/KDF_LATENCY_REPORT.md:203`,
`:294`), scaling at ~2.1s per gap unit (`:212`).

For **software** wallets the bound still holds comfortably: those figures were
taken at `gap_limit: 20` and `HdGapLimit.resolve` sends `software = 3`
(`newlyGeneratedFirstSignIn = 1`), so ~4 probes rather than 21.

**Trezor is the exception.** `HdGapLimit.resolve` returns `hardware = 20` for
`PrivateKeyPolicy.trezor()`, and `TrezorHDWalletStrategy` takes no
`scanGapLimit` override (`hd_multi_address_strategy.dart:26`, `:219-222`), so a
hardware wallet still walks the full gap: **121.2s of the 180s bound, ~1.5x
headroom**. Survivable for a backstop, but it is the number to re-measure before
anyone shrinks the bound.

**To revert:** restore the 8.2s / 6.1s figures. Do **not** shrink the 3-minute
bound while the pin lacks PR #18.

> **Related, deliberately NOT changed — see §8.2.** `HDWalletMixin._scanTimeout`
> (`hd_multi_address_strategy.dart:28`) is a flat 20s while `scanGapLimit` is 20
> for Trezor. `docs/KDF_LATENCY_REPORT.md:99` measured the sequential
> `scan_for_new_addresses` at **"20.09s, timed out (80 polls)"** on the
> pre-perf-stack KDF that `main` matches for this path — i.e. the Trezor scan
> times out. It is not fatal: `pubkey_manager.dart:958-972` logs a warning, arms
> a retry cooldown and continues with existing pubkeys, and KDF's task runs to
> completion regardless (`forgetIfFinished: false`), so the addresses surface on
> a later `account_balance`. It is also exactly the behaviour that shipped
> before the perf stack. Widening it (e.g. scaling with `scanGapLimit`) is a
> hardware-path behaviour change that was not verified against a real Trezor
> here, so it was left alone and is flagged instead.

### 2.4 `--p2p` is required again for TRX and NFT

**File:** `tool/kdf_latency_probe.py` (the `--p2p` argument help)
**Unblocked by:** PR #18 (`d2c16fc29`).

`main` restores `P2PContext::fetch_from_mm_arc` (`mm2src/mm2_p2p/src/p2p_ctx.rs:42`,
`Option::unwrap` on `None`). The complete set of unconditional call sites under
`mm2src/coins/` on `f3efd2ca1` — `git grep -n "P2PContext::fetch_from_mm_arc"` —
is:

| site | reached by |
|---|---|
| `eth/v2_activation.rs:1217` | `build_tron_api_client` — every TRX activation |
| `eth/v2_activation.rs:686` | `initialize_global_nft` |
| `eth/v2_activation.rs:1276`, `:1306` | ws / http transport when a node sets `komodo_proxy` |
| `eth/tron/gasfree/client.rs:53` | `TronGasfreeTransport::KomodoProxy` |
| `nft.rs:247`, `:526` | `update_nft` / `refresh_nft_metadata` |
| `tendermint/tendermint_coin.rs:3199` | Tendermint proxy signing |

With `disable_p2p: true` any of these panics and takes the RPC service down.
The `v2_activation.rs:1276`/`:1306` pair is unreachable from the shipped config
regardless — it carries **zero** nodes with `komodo_proxy`/`gui_auth`.

**The shipped app is not affected.** Every KDF start path attaches seed nodes
and leaves `disable_p2p` unset:
`komodo_defi_local_auth/.../auth_service_kdf_extension.dart:467-484` and
`kdf_startup_config.dart:202-204`, and `SeedNodeValidator.validate`
(`seed_node_validator.dart:54-61`) throws rather than starting a non-bootstrap
node with no seed nodes. The exposure is tooling only.

**To revert:** restore the "Fixed in KDF `ed8de236b`" wording.

### 2.5 `KDF_EVM_RPC_TRACE` is inert

**File:** `.github/workflows/kdf-harness-nightly.yml`
**Unblocked by:** PR #19 / #20.
**Behaviour change: none.** The variable is still set.

`KDF_EVM_RPC_MAX_CONCURRENCY` and `KDF_EVM_RPC_TRACE` are the only two env vars
the perf pin reads that `main` does not (verified by diffing the full
`std::env::var(...)` set across both trees). Both lived in code the roll removes:
the concurrency budget in `eth/web3_pool.rs`, the trace switch in `eth_rpc.rs`'s
`mod telemetry`. An unrecognised env var is ignored, so nothing breaks - but a
red nightly no longer says *which* endpoint refused what.

**To revert:** delete the "INERT" paragraph from the comment.

### 2.6 The pin itself

**Files:** `sdk/packages/komodo_defi_framework/app_build/build_config.json`
(canonical) and `build_config.yaml` (reference mirror, previously three pins
stale at `bd413dc`).

Rolled with:

```bash
dart run packages/komodo_wallet_cli/bin/update_api_config.dart \
  --branch main --commit f3efd2ca10420f2982fa127dde84dcc17891f577 \
  --source mirror --mirror-url https://devbuilds.gleec.com --platform all \
  --config packages/komodo_defi_framework/app_build/build_config.json \
  --output-dir packages/komodo_defi_framework/app_build/temp_downloads \
  --strict --verbose
```

All 7 checksums were independently verified against the mirror's published
`.sha256` sidecars (the Windows sidecar is uppercase PowerShell `Get-FileHash`
output). The extracted macOS binary reports `3.1.0-beta_f3efd2c`.

**`source_urls` was reordered** to put `https://devbuilds.gleec.com` first. It is
the only host that serves `f3efd2c` — `kdf-dev-builds.nitride.app`,
`nitride-kdf-builds.web.app` and `nebula.decker.im` all 404 for `main/`. The
build transformer iterates the list with fallback
(`fetch_defi_api_build_step.dart:866`, `:911`), so a dead leading host would only
have cost two failed lookups per platform — but
`.github/workflows/sdk-integration-preview.yml:205` takes `source_urls[0]` and
passes it as the single `--mirror-url` with `--strict`, where there is no
fallback at all. Leading with a 404 host broke every preview dispatch.

This is not a perf-PR descope and should **not** be reverted when they land:
it just makes the list reflect which mirror actually serves the pin. Reorder it
again if the roles swap back. Do not hardcode a host into the preview workflow —
the comment at `sdk-integration-preview.yml:199-203` records why that failed
before.

---

## 3. Roll-blocking fixes that are *not* perf-PR descopes

These were broken by moving to `main`, but re-landing #18/#19/#20 does not undo
them. Keep them.

### 3.1 The `main` Windows artefact ships proc-macro DLLs

**File:** `sdk/packages/komodo_wallet_build_transformer/lib/src/steps/fetch_defi_api_build_step.dart`
(+ tests).

`kdf_f3efd2c-win-x86-64.zip` contains **five** files —
`kdf.exe`, `kdflib.dll`, and `enum_derives.dll`, `ser_error_derive.dll`,
`serialization_derive.dll`. `kdf_538724e-win-x86-64.zip` contained **two**. The
three extras are Rust proc-macro crates: Cargo emits them into
`target/release/` and the KDF Windows packaging job globs the directory.

The extraction guard `_validateStagedPlatformFiles` fails closed on any
top-level file outside the platform's owned runtime set, so **every** build and
every `flutter test` that runs the transformer died with:

```
Bad state: Extracted KDF archive contains files outside the owned top-level
windows runtime set: serialization_derive.dll, ser_error_derive.dll, enum_derives.dll
```

Fixed by adding a named `discardableFilenames` set to `_NativeRuntimeIdentity`:
those three are dropped from staging rather than installed, so they never reach
the bundle or the runtime-set digest, and **anything unrecognised still fails
closed**. Only top-level entries qualify, so an archive cannot smuggle a nested
file past the guard by naming it after known residue. Three tests cover the
drop, the still-fails-closed case, and the nested case.

**The real fix is upstream**, in the KDF release workflow's Windows file list.
When that lands, delete the `discardableFilenames` entry and its tests.

### 3.2 The manifest policy test pinned a specific commit

**File:** `sdk/packages/komodo_wallet_build_transformer/test/steps/models/api/api_build_config_test.dart`

`canonical GasFree manifest pins the complete platform build set` read the real
`build_config.json` and asserted `api_commit_hash == 'bd413dcfea…'`,
`branch == 'feat/tron-gasfree'`, and all seven checksums literally. It had
therefore been **red since the pin moved off `bd413dc`** — three rolls ago — and
would go red again on every future roll.

Rewritten to assert the *policy* it actually guards: a full 40-character
lowercase commit, all seven required platforms present, none release-blocked,
exactly one full-length sha256 checksum each. A roll is now a one-file change.

### 3.3 The nightly KDF roll job hard-failed on `main`

**File:** `sdk/.github/workflows/kdf-version-roll.yml`

The scheduled job resolved the branch tip from `<mirror>/<branch>/manifest.json`
and `exit 1`d when no mirror published one. **No mirror publishes
`main/manifest.json`, and none is expected to** — `devbuilds.gleec.com` serves
artefacts but no manifests for any branch, and `kdf-dev-builds.nitride.app` has
them for `dev` and the perf branches but no `main/` prefix at all. The job would
have gone red every midnight on the default branch, forever.

Rather than just silencing it, the job now falls back to the **branch directory
listing**, which names every artefact `kdf_<short>-<target>.zip`. Three outcomes:

| condition | behaviour |
|---|---|
| manifest found | unchanged — resolve the full sha and open the roll PR |
| listing short sha == the pin's first 7 | clean no-op, `has_updates=false` |
| listing short sha differs | **warn + step summary naming the new build**, with the exact `update_api_config.dart` command to roll it by hand |
| neither manifest nor listing | warn + step summary naming every mirror checked |

The listing can only ever yield a **short** sha, and resolving it to the 40
characters `require_full_commit_hash` demands needs the GitHub API against the
private `GLEECBTC/kdf-internal` repo — which `secrets.GITHUB_TOKEN` cannot read.
So the listing path deliberately **detects but never rolls**. Detection is the
half of this job that was actually at risk of being lost.

Two details worth keeping:

- The listing is fetched with `?sort=time&order=desc` and the **first** match is
  taken, in document order. Do not `sort` the shas — they are hex, so a lexical
  sort is not chronological: a future `a1b2c3d` would sort *before* the older
  `f3efd2c`. Verified against the live mirror, which returns newest-first for
  that query.
- A mirror that ignores the query falls back to name-ascending order and could
  name the wrong build. That costs at most a spurious "new build available"
  note, never a wrong roll, because this path cannot roll.

**Ops follow-up (optional now):** publishing `main/manifest.json` alongside the
artefacts (`docs/KDF_RELEASE_RUNBOOK.md`) would restore the fully automated
roll. Without it the job still tells you when to roll, just not how far.

---

## 4. Accepted regressions — no code change, do not re-derive

These are things the roll gives up where nothing client-side can or should
compensate. They are listed so that a future investigation does not spend time
rediscovering them as bugs.

| Regression | Mechanism | Returns with |
|---|---|---|
| EVM RPCs serialize, one in flight per coin | `eth.rs:1124` `web3_instances: AsyncMutex<Vec<Web3Instance>>`, guard held across the round trip at `eth_rpc.rs:26-27` | #19 |
| No HTTP connection pooling | `pool_max_idle_per_host(0)`; every EVM RPC pays DNS + TCP + TLS again | #19 |
| No EVM 429 retry or backoff | `eth_rpc.rs:26-62` is one pass over the node list, then `Err`. GLEEC has a single node, so that is one attempt | #20 |
| TRON serializes process-wide | `tron/api.rs:806` `clients: Arc<AsyncMutex<Vec<TronHttpClient>>>`, and `TronApiClient` is cloned into every TRC-20 | #20 |
| TRON does not retry a rate-limited node | no backoff loop; both nodes at 429 fails immediately rather than waiting out TronGrid's ~5s suspension | #20 |
| `OutOfTimeException` / `TimeoutException` treated as deterministic rejections | `tron/api.rs:103` `is_retryable` is only `contains(RATE_LIMIT_MSG)`; a busy node aborts a `balanceOf` or a whole TRX activation | #20 |
| A signed TRON broadcast queues behind reads | `broadcast_hex` goes through the same `try_clients` mutex; a TRON tx is only valid 60s after its TAPOS block | #20 |
| HD gap scan walks one address at a time | `lp_coins.rs:6352-6358` | #18 |
| RPC error text embeds the full node URL | `http_transport.rs:169-176` formats `transport.node.uri` verbatim; several EVM providers carry API keys in the path or query, so a pasted error log can leak one | #20 |
| JSON-RPC errors flattened into transport errors | the `Err(rpc_error @ Error::Rpc(_))` passthrough is gone; `execution reverted` now arrives shaped like a socket failure | #20 |
| ws connection loop can wedge permanently | untagged `Close` and `try_lock`-based spawn reservation (`websocket_transport.rs:180`, `:319`) | #20 — moot while §2.1 keeps ws off |

**Partly self-cancelling.** `main` both removes the 429 survivability *and*
removes the concurrency that provoked the 429s. The bursts are smaller, so the
mechanism is hit less often — but when it is hit, it fails hard instead of
backing off.

---

## 5. What did not change

Verified, so nobody re-checks it:

- **The RPC wire contract is identical.** Zero `#[serde(...)]`, `rename`,
  `deny_unknown_fields` or `tag` annotations differ anywhere in the non-test
  diff between the two pins. Activation params, withdraw params,
  `get_new_address`, `account_balance`, `scan_for_new_addresses`, `my_balance`
  and the `task::` manager types are unchanged.
- **The RPC dispatch table is byte-identical.** `mm2_main/src/rpc/dispatcher/dispatcher.rs`
  diffs to nothing between the pins. Neither side added or removed a method.
  `gasless::account_status` still routes at `dispatcher.rs:578`, and
  `gasless::trace_status` / `gasless_trace::enable` are both present.
- **Gas-free is complete on `main`.** `mm2src/coins/eth/tron/gasfree/` differs in
  exactly one file, `client.rs`, and only in the `KomodoProxy` keypair type
  (`Option<Keypair>` → `Keypair`) - no serialized type. `gasfree_address`,
  account status, fee metadata, trace events and `tx_fee_details` are untouched.
  The extracted binary carries 180 gas-free symbols.
- **No error string the app matches on changed.** The app parses none of the
  handful of transport-level strings that differ.

## 6. Main-only gains the roll brings in

Not regressions - state them so a changed fee preview is not misread as one:

- `26d4ea596` fix(eth): the simple EIP-1559 estimator reads the **last**
  `baseFeePerGas` entry (next/pending block) rather than the oldest in the
  window (`fee_estimation/eip1559/simple.rs:141`). Priority-fee estimates move.
- `a3dfadb4a` adapts to geth v1.17.5 gas rules and migrated electrums. The
  shipped `coins_config.json` already carries the migrated electrum hostnames,
  so no UTXO coin loses its servers.
- `1ab2c2a12` / `750be9385` bump to `3.1.0-beta`. Nothing in the app version-gates
  on the KDF version string.

**The EVM swap gas limits roughly double** (`mm2src/coins/eth.rs`, "Resized for
the Amsterdam/Bogota fork gas repricing"). This is the most user-visible thing
the roll changes and it is easy to misread as a regression:

| constant | perf pin | `main` |
|---|---|---|
| `ETH_PAYMENT` | 65,000 | 155,000 |
| `ERC20_PAYMENT` | 150,000 | 345,000 |
| `ETH_RECEIVER_SPEND` | 65,000 | 90,000 |
| `ERC20_RECEIVER_SPEND` | 150,000 | 195,000 |
| `ETH_SENDER_REFUND` | 100,000 | 125,000 |
| `ERC20_SENDER_REFUND` | 150,000 | 195,000 |
| `ETH_MAX_TRADE_GAS` | 150,000 | 345,000 |

So the DEX fee preview for an ETH pair goes 165,000 → 280,000 gas and for an
ERC-20/GRC-20 pair 300,000 → 540,000. The same numbers are the pre-trade balance
check, so a user holding *just* enough platform coin to cover the old estimate
will now be told they have insufficient funds. That is correct behaviour under
the new fork rules — the old limits would have under-funded the transaction —
but it needs saying before someone bisects it.

---

## 7. Re-introduction checklist

When #18, #19 and #20 have merged and a `main` build carrying them is published:

1. Roll the pin with `update_api_config.dart --branch main --commit <sha>`
   (§2.6), and verify the checksums against the mirror's `.sha256` sidecars.
2. Confirm the stack is actually in the artefact:
   `strings` the extracted binary — `web3_pool` should be **non-zero** and
   `receiver channel must be alive` should be **zero**.
3. Flip `_kSendWsNodesOnWeb` → `true` **and** `_wsShippedOnThisBuild` → `true`
   in the same commit (§2.1, §2.2). Run
   `flutter test` in `sdk/packages/komodo_defi_rpc_methods` — 236 tests.
4. Restore the coordinator's measurement citations (§2.3) and the probe's
   `--p2p` help (§2.4); drop the "INERT" note from the nightly (§2.5).
5. Re-run `tool/evm_ws_probe.py` before trusting `_deadWsEndpoints` and
   `_webUnusableWsEndpoints` — both lists were probed on 2026-08-07.
6. Consider `_kSendWsNodesOnNative`, still `false` for its own unrelated reasons
   (iOS file descriptors, socket lifecycle across backgrounding). Its
   preconditions are documented on the constant and are **not** satisfied by
   these PRs landing.
7. Leave everything in §3 alone — those fixes are about the `main` artefact and
   the CI around it, not about the perf stack, and re-landing #18/#19/#20 does
   not make any of them unnecessary. §3.1 goes away only when the KDF Windows
   packaging job stops shipping proc-macro DLLs.

Green after the roll, for comparison:

| suite | result |
|---|---|
| `sdk/packages/komodo_wallet_build_transformer` | 113 passed |
| `sdk/packages/komodo_defi_rpc_methods` | 236 passed |
| `sdk/packages/komodo_defi_sdk` | 851 passed, 1 skipped |

---

## 8. Recommendations deliberately not applied

Each of these is a real consequence of the roll, verified against the code, and
each would change user-visible behaviour to compensate for a slower KDF. That
is a product call rather than a descope, so they are recorded rather than
made. All of them stop mattering when the relevant PR lands.

| # | Finding | Evidence | Returns with |
|---|---|---|---|
| 8.1 | **TRX HD activation never sends `gap_limit`**, so it walks KDF's default 20 — sequentially, over the now process-wide TRON mutex. `EthWithTokensActivationParams` has a `gapLimit` field (`eth_activation_params.dart:55`, `:94`); `TrxWithTokensActivationParams` has none. | `trx_activation_params.dart` — no `gapLimit` in the constructor, `fromJson` or `toRpcParams` | #18 / #20 |
| 8.2 | **`HDWalletMixin._scanTimeout` is a flat 20s** against `scanGapLimit = 20` for Trezor, and the sequential scan measured "20.09s, timed out". Non-fatal and self-healing — see the note in §2.3. | `hd_multi_address_strategy.dart:26`, `:28`; `docs/KDF_LATENCY_REPORT.md:99` | #18 |
| 8.3 | **A transient TRON node failure demotes the whole gas-free rail in the UI.** On `main`, `OutOfTimeException` is a deterministic rejection (`tron/api.rs:103`), so one busy-node reply fails `gasless::account_status` without trying the second node, and the registry marks the asset temporarily unavailable. | `gasless_capability_registry.dart:300-304`; `withdraw_form_bloc.dart:1500` | #20 |
| 8.4 | **The balance sweep caps each coin at 20s with concurrency 4**, while every TRON RPC in the process now serializes behind one mutex. Two TRON coins in the same wave can push the second past the ceiling; the error is swallowed per coin, so it presents as a stale balance. | `coins_repo.dart:42`, `:50`, `:1226` | #20 |
| 8.5 | **The TRON confirm gate allows submitting with ~1s left** in the 60s TAPOS window, and a signed broadcast can now queue behind reads on that same mutex. Widening the gate to a broadcast margin (refuse below ~15s, auto-refresh the preview) would close it. | `withdraw_form_state.dart:35`; `withdraw_form_bloc.dart:287-292`, `:2384` | #20 |

**Checked and dismissed:** `tool/kdf_rpc_burst_bench.py` hardcodes
`disable_p2p: True` with no escape, but none of its six scenarios activates TRX
(`:897-905`), and the `DEFAULT_COINS` list naming `TRX`/`USDT-TRC20` (`:77-86`)
is never read. It is unaffected by the p2p panic. Noted in `tool/README.md` so
the next person does not re-derive it.
