# KDF wallet-load latency — the `bd413dc` baseline (superseded)

> **Stale for a second reason: the gap limit changed under these numbers.**
> Every measurement in this file was taken at `gap_limit: 20`. The shipped SDK
> no longer sends 20 —
> [`hd_gap_limit.dart`](../sdk/packages/komodo_defi_types/lib/src/public_key/hd_gap_limit.dart)
> sends `software = 3` for a restored wallet and `newlyGeneratedFirstSignIn = 1`
> for a fresh one, keeping `hardware = 20` for Trezor only.
>
> Because the scan cost on an unbatched KDF is roughly linear in addresses
> walked, that client-side change collapses most of the penalty measured here —
> so these numbers overstate both the problem *and* the size of the KDF-side
> wins claimed against them. **The benchmarks need redoing at gap 3 and gap 1.**
> Until then, treat every figure below as a Trezor-path (gap 20) reference,
> where it is still accurate.

> **This is a frozen record of how slow things were, not how they are.**
> Every number below was measured against KDF `bd413dc`, before any of the
> fixes. It is kept because it is the only full write-up of the *method* and of
> the pre-fix matrix, and because the after-numbers are only meaningful against
> it.
>
> For what things cost **now**, and what each change bought, read
> `WALLET_LOAD_PERFORMANCE_REPORT.md` (retired 2026-08-27 — its 9.4x headline described
> the perf fork, not the shipped build; see `KDF_PERF_STACK_DESCOPE.md`).
> For how to take these measurements yourself, read
> [`WALLET_LOAD_MEASUREMENT.md`](WALLET_LOAD_MEASUREMENT.md).
>
> Two claims below are now known to be wrong and are corrected in place where
> they appear: that every number here is a **floor** (the ETH rows are a
> *ceiling* — the seed has Ethereum history), and that a large share of EVM
> per-RPC cost was **unexplained** (it was a wrong RPC-count denominator).

**Repo:** `gleec-wallet-kdf-integrations`, branch `add/gas-free-tron`
**KDF:** `3.0.0-beta_bd413dc` (same build native and web — verified via `version`)
**Host:** macOS 25.5.0, arm64
**Seed:** the public BIP39 vector `abandon … about`. Zero funds, so the UTXO and
TRON numbers are a *floor*. **The ETH numbers are a ceiling** — it is the
most-used public test vector there is, so on Ethereum the gap scan keeps finding
*used* addresses and walks 239 of them rather than 21. An earlier version of
this document called the whole matrix a floor; that was wrong.

---

> **Update (2026-08-04):** the dominant cause below has been **fixed and
> re-measured** — KMD activate 46.9s → 6.1s, BTC-segwit 121.2s → 8.2s, and the
> cost no longer scales with `gap_limit` at all (107.0s → 7.6s at gap 50). See
> [`KDF_IMPROVEMENT_OPPORTUNITIES.md`](KDF_IMPROVEMENT_OPPORTUNITIES.md)
> § Validation. The numbers below are the *baseline* they were measured against.

## 0. TL;DR

0. **The app's shipped default coin set takes 8 minutes to log in on HD**
   (480.7s, measured, §4d). On iguana the same set takes 8.9s.
1. A fresh **HD** login is slow because KDF walks an HD address gap over the
   network, per coin, on activation. It is not client-side orchestration.
2. On UTXO that walk is **~47s per coin** at the shipped `gap_limit: 20`.
   With `scan_policy: do_not_scan` the same activation takes **2.0s**.
3. On **EVM it is far worse**: `enable_eth_with_tokens` for ETH + 2 ERC-20
   tokens takes **356s on HD vs 2.3s on iguana** — and it is a *synchronous*
   RPC, so the client blocks with no progress and no partial result.
4. **iguana is 31× faster** than HD on the identical single-coin case (2.9s vs
   89.4s) and ~150× on the EVM case.
5. Every second of that is KDF working — either blocked inside a synchronous
   RPC or spent polling a task KDF had already accepted. The measurement is
   Python stdlib talking HTTP to a process; there is no Flutter, Dart or SDK
   code anywhere in it.
6. One client-side defect *was* found and fixed: a redundant second address
   walk. It cut HD time-to-first-balance from ~89s to ~48s. Everything left is
   KDF-side.
7. **Batching activations does not help.** The same 19 assets cost the same
   whether issued as 6 calls or 21 — the work is per-asset, not per-call (§4c).
8. **Web is ~4× faster than native**, same KDF build, and KDF WASM uses under
   2% of the main thread doing it. The two platforms are on different electrum
   transports and cannot be swapped — native KDF *rejects* WSS by design — so
   the gap is measured but not yet attributed (§5a).
9. The probe also found a **KDF panic**: activating TRX (or NFTs) with
   `disable_p2p` hits an `unwrap()` on an absent P2P context. Native survives
   it; **WASM does not** — a panic kills the whole MM2 instance there (§8).

---

## 1. How this was measured

Three independent paths, deliberately, because each can prove something the
others cannot.

| # | path | what is in the loop | what it proves |
|---|---|---|---|
| A | `tool/kdf_latency_probe.py` | Python stdlib → HTTP → **KDF binary** | The latency is KDF's. No Flutter/Dart/SDK exists in this process. |
| B | `tool/web/kdf_web_probe.html` | plain JS → **KDF WASM** in a browser tab | The same holds on web, *and* how much of it blocks the main thread. |
| C | `sdk/packages/komodo_defi_harness` (Dart) | the **real SDK**, real `KomodoDefiSdk` | What the app actually experiences, including SDK overhead. |

A and C agree within ~2% on identical scenarios, which is what makes both
trustworthy — two independent implementations, same numbers:

| step | A (Python → binary) | C (Dart → SDK → binary) |
|---|---|---|
| activate KMD | 46.91s (94 polls) | 46.6–47.5s (93–95 polls) |
| `scan_for_new_addresses` | 20.09s, timed out (80 polls) | 20.0s, timed out (79–80) |
| `account_balance` | 22.12s (213 polls) | 21.0s (209–210) |

Every scenario in A starts a **fresh KDF with a fresh database directory**; B
does one scenario per page load and deletes KDF's IndexedDB databases between
rows. Nothing is warmed by a previous run.

### Reproducing it

```bash
export KDF_TEST_SEED='abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about'

# native, ~90s
python3 tool/kdf_latency_probe.py --quick

# native, full matrix
python3 tool/kdf_latency_probe.py --json out.json

# audit the activation plan without starting KDF at all
python3 tool/kdf_latency_probe.py --plan-only

# web
flutter build web --release \
  --dart-define=TRON_GASLESS_ENABLED=true \
  --dart-define=TRON_GASLESS_RECEIVE_ENABLED=true \
  --dart-define=TRON_GASLESS_BASE_URL=https://quicknode.gleec.com/gasfree/tron \
  --dart-define=TRON_GASLESS_SERVICE_PROVIDER=TLntW9Z59LYY5KEi9cmwk3PKjQga828ird
python3 tool/kdf_latency_probe.py --web     # then open the printed URL, press Run
```

Python 3 standard library only. No pip installs, no browser driver, no Selenium.

---

## 2. Scan parameters — there are **two** independent gap limits

This is the single most important thing to know before reading any timing.

| | where | values |
|---|---|---|
| **activation-time scan** (KDF-side) | `utxo_protocol.dart` `defaultActivationParams` | `scan_policy: scan_if_new_wallet` (`scan` for Trezor), **`gap_limit: 20`**, `min_addresses_number: 1` |
| **per-fetch scan** (SDK-driven, HD only) | `hd_multi_address_strategy.dart` | `account_index: 0`, **`gap_limit: 20`**, poll 250ms, **timeout 20s**, retry cooldown 2 min |
| **balance read** (HD only) | `hd_multi_address_strategy.dart` | `account_index: 0`, poll 100ms, timeout 60s |

`gap_limit: 20` means KDF derives and queries history for up to 20 consecutive
*empty* addresses per chain — external **and** internal — against electrum, for
a brand-new wallet with nothing to find.

---

## 3. Coin sets, and why "20 coins" ≠ "20 activations"

A platform and all of its tokens activate in **one** `enable_eth_with_tokens`
call, and requesting a token silently forces its platform to activate too. So
the honest unit for the activation-count dimension is **activation RPCs**, not
coins.

The upper bound is exact: no asset ever needs more than one activation call, so
**max = number of distinct assets KDF must know about** (requested + forced
platforms).

### Availability in this wallet (800-entry `coins_config.json`)

* Native chain available: `BTC` `ETH` `LTC` `BCH` `DOGE` `TRX` `BNB` `AVAX`
  `MATIC` `ATOM` `ETC`
* **Wrapped only** — a bridged IOU, not the native asset: XRP, SOL, ADA, DOT,
  XLM, TON, HBAR, SUI, NEAR, FIL, SHIB, LINK, DAI, USDT, USDC, ARB.
  Of these **ADA, DOT, XLM, HBAR, SUI, NEAR exist only as `-BEP20`** — BNB Chain
  is the sole option.
* **Absent entirely: XMR, APT, OP.** `POL` does not exist either; Polygon is
  still keyed `MATIC`.

Top-20 by market cap is a judgement call as of **2026-08**, not a live feed.
All three constructions below enable the **same 19 assets**; only the batching
differs. `--plan-only` reproduces these counts without starting KDF.

| construction | tickers | activation RPCs |
|---|---|---|
| **min** `top20-min` | BTC LTC DOGE BCH ETH BNB + 13 `-BEP20` tokens | **6** = 4 utxo + 2 platform |
| **median** `top20-median` | BTC LTC DOGE BCH · ETH+USDT/USDC/XRP/LINK/SHIB/DAI-ERC20 · BNB+SOL/ADA/DOT/XLM-BEP20 · AVAX · MATIC · TRX | **9** = 4 utxo + 5 platform |
| **max** `top20-max` (unbatched) | as median but each token on a different chain, tokens issued individually | **21** = 4 utxo + 7 platform + 10 token |

`top20-max` pulls in **two platforms nobody asked for** — `KCS` (via a `-KRC20`
token) and `ETH-BASE` (via `USDC-BASE`). That is 19 requested assets becoming 21.

For reference, the app's own default set (`enabledByDefaultCoins`) is 8 assets →
**5** activation RPCs: GLEEC, KMD, BTC-segwit, ETH(+USDT/USDC-ERC20),
TRX(+USDT-TRC20).

---

## 4. Native results

macOS arm64, KDF 3.0.0-beta_bd413dc, fresh KDF + fresh database per row.
Rows marked † were run with `--p2p` (see §8 — TRX activation panics without
it), so their startup profile differs slightly from the rest.

### 4a. The address walk is the activation cost

One coin (KMD), HD, everything else held constant:

| scenario | total | activate | scan | balance |
|---|---:|---:|---:|---:|
| `gap_limit: 1` | 52.4s | **9.1s** | 20.1s | 21.9s |
| `gap_limit: 20` (shipped) | 90.4s | **46.9s** | 20.1s | 23.1s |
| `gap_limit: 50` | 149.4s | **107.0s** | 20.1s | 22.0s |
| `scan_policy: do_not_scan` | 46.4s | **2.0s** | 20.1s | 24.0s |
| iguana (control) | **2.9s** | 2.0s | – | 0.6s |

Two readings, both decisive:

* **`do_not_scan` activates in 2.0s against 46.9s.** 45 of the 47 seconds are
  the address walk and nothing else.
* It scales with the gap limit at roughly **2.1s per gap unit** on these
  electrum servers. `gap_limit: 20` is a configuration choice, not a fixed cost.

**HD is 31× iguana** on the identical single-coin case (90.4s vs 2.9s).

### 4b. EVM is much worse than UTXO, and it is synchronous

`enable_eth_with_tokens` for ETH + USDT-ERC20 + USDC-ERC20 — **one** RPC:

| | total | that one activation call |
|---|---:|---:|
| HD | 444.3s | **363.8s** |
| iguana | 3.0s | **2.5s** |

**~150×.** And unlike `task::enable_utxo`, this RPC has no task id, no status
endpoint and no progress events. The caller is simply blocked for six minutes
with nothing to show the user. The probe's original 180s ceiling timed out on
it, which is how it was found.

### 4c. Activation cost is per-asset, not per-call

All three rows enable the **same 19 assets**; only the number of activation
RPCs differs. Measured on iguana so per-call cost (~2s) does not swamp the
count — §4b already quantifies the HD multiplier separately.

| construction | assets | activation RPCs | total | activate |
|---|---:|---:|---:|---:|
| **min** — all-BEP20, batched † | 19 | **6** | 28.2s | 25.7s |
| **median** — canonical, batched † | 19 | **9** | 18.3s | 17.0s |
| **max** — max-spread, unbatched † | 19 (+2 forced) | **21** | 26.8s | 25.6s |

**The curve is flat, and that is the finding.** Fewer calls is not faster. The
per-call breakdown shows why:

| construction | the expensive call |
|---|---|
| min (6 calls) | `BNB + 13 tokens` alone = **19.95s** of the 25.7s |
| median (9 calls) | `ETH + 6 tokens` = 5.12s, `BNB + 4 tokens` = 2.47s |
| max (21 calls) | 21 calls of 0.26s – 6.29s each |

Batching **concentrates** the work into one long call; it does not remove it.
Thirteen tokens cost ~20s whether they arrive in one request or thirteen. So
batching is a round-trip optimisation, not a latency one — the levers that
actually move the number are derivation mode and `gap_limit`.

### 4d. The realistic login — the app's own default coin set

`enabledByDefaultCoins` (`lib/app_config/app_config.dart`): 8 assets, 5
activation RPCs. This is what a real new HD user actually waits for. †

| step | HD |
|---|---:|
| KDF boot | 1.0s |
| `activate: GLEEC` | 12.2s |
| `activate: KMD` | 47.0s |
| `activate: BTC-segwit` | 121.2s |
| `activate: ETH + 2 tokens` | **246.1s** |
| `activate: TRX + 1 token` | 41.0s |
| `scan_for_new_addresses` | 12.0s |
| `account_balance` | 0.3s |
| **total** | **480.7s** |

**Eight minutes**, on the shipped default set, with a wallet that has no
history to find. The same set on iguana: **8.9s**. That is the user report
— "balances take minutes to appear" — reproduced end to end with no Flutter,
no Dart and no SDK in the process.

### 4e. Cost is per-coin and varies a lot by coin — but there is no contention

> **Correction.** An earlier version of this report divided the 4-coin total by
> four, got 65.2s/coin against 46.9s for a single coin, and concluded the coins
> "contend rather than overlap." That was an unsupported inference from an
> average. **The probe activates coins strictly sequentially** — one awaited
> `task::enable_utxo` at a time (`kdf_latency_probe.py:588`) — so the run could
> never have shown pipelining, and the per-coin average across heterogeneous
> coins is not evidence of anything. Re-measured with the breakdown:

| coin | activate (in the 4-coin run) | solo reference |
|---|---:|---:|
| KMD | 46.4s | 46.9s |
| MARTY | 42.9s | – |
| DOC | 43.9s | – |
| **BTC** | **126.2s** | 121.2s (§4d) |
| sum | 259.5s | |

Three of the four cost within 4s of what a single coin costs on its own, and
BTC costs the same in company as it does alone. **There is no contention** —
the 65.2s "per coin" average was BTC dragging the mean. Whatever makes BTC
~2.7× KMD is a property of BTC's electrum servers, not of activating in a group.

iguana, for contrast: 1 coin 2.0s, 4 coins 7.1s (1.8s/coin).

What remains true, and is the point of this row: **the cost is per-asset and
strictly additive.** Nothing overlaps because nothing is asked to overlap —
whether KDF *could* pipeline concurrent activations is untested here.

---

## 5. Web results

Same KDF build (`3.0.0-beta_bd413dc`, confirmed via `version`), driven from a
static HTML page with no Flutter and no Dart. WASM cold-boot to `RpcIsUp`:
**230ms**.

Three scenarios, one per page load, IndexedDB wiped between rows.

| scenario | total | activate | scan | balance | long tasks |
|---|---:|---:|---:|---:|---:|
| HD, KMD, `gap_limit: 20` | **22.7s** | 12.4s (13 polls) | 9.0s ✅ completed | 1.0s (2 polls) | 241ms / 2 |
| iguana, KMD | 2.1s | 1.8s (3 polls) | – | 0.2s | 128ms / 1 |
| HD, KMD, `do_not_scan` | 13.8s | 1.6s (3 polls) | 11.0s ✅ completed | 1.0s | 128ms / 1 |

### 5a. Web is ~4× **faster** than native, and that is not a mistake

The same KDF build, same coin, same gap limit, same seed:

| | activate | polls | `scan_for_new_addresses` | `account_balance` |
|---|---:|---:|---|---:|
| **native** | 46.9s | 94 | **times out at 20s** | 22.0s (211 polls) |
| **web (WASM)** | **12.4s** | **13** | **completes in 9.0s** | **1.0s** (2 polls) |

This was re-checked against a native run executed *immediately after* the web
run to rule out network variance — native came back at 46.93s activate / 20.13s
scan timeout / 22.03s balance, i.e. unchanged. The difference is real.

The poll counts are the cleanest statement of it: same 500ms poll interval,
94 polls native versus 13 on web. KDF genuinely finishes the same task ~4×
sooner in the browser.

**The two platforms are not on the same electrum transport, and cannot be put
on one.** The config offers three endpoints per host — TCP `:10001`, SSL
`:20001`, WSS `:30001` — and each platform gets a filtered subset:

* **Web** must use WSS; a browser cannot open a raw socket.
* **Native gets TCP + SSL**, because KDF's native build *refuses* WSS. The
  error is explicit, not a failure to connect:

  ```
  Failed to establish connection: Irrecoverable(
    "Incorrect protocol for native connection ('WS'/'WSS'). Use 'TCP' or 'SSL' instead.")
  ```

The SDK enforces exactly that split at config-transform time
(`config_transform.dart` `WssWebsocketTransform`: WSS-only when `kIsWeb`,
non-WSS otherwise, synthesising `ws_url` from `url` for WSS entries). **That
filter is correct** — it mirrors what the binary will accept. No client-side
bug here.

Native, restricted to one protocol at a time (`--electrum-protocol`):

| protocol offered to native | result |
|---|---|
| WSS only | **rejected by KDF** in 0.5s — see the error above |
| SSL only | 46.4s ✅ |
| TCP only | 47.0s ✅ |
| all six (shipped config) | 47.1s ✅ |

So the transport is a **confounder that cannot be removed by configuration**:
native cannot be made to speak WSS, and web cannot be made to speak TCP. The 4×
gap is measured and reproducible, but it is *not yet isolated* to the transport
— the WASM and native builds also differ in electrum client, connection pooling
and async runtime. Attributing it needs someone who can instrument inside KDF.

> Two caveats, both stated because each nearly produced a wrong finding:
>
> 1. The 0.5s WSS row is a *rejection*, not a speedup. An earlier version of
>    the probe recorded a task ending in `Error` as a completed step, which made
>    it look like a 92× win. The probe now marks `Error` as failed; what caught
>    it was asking KDF for the balance afterwards — `NoSuchCoin KMD`.
> 2. The first WSS attempt also omitted `ws_url`, which the SDK synthesises and
>    the raw config does not carry. That was a probe defect, and it was fixed
>    before the row above was re-measured — the rejection reproduces with
>    `ws_url` correctly set, so it is KDF's rule, not a malformed request.

### 5b. KDF WASM barely touches the main thread

Total Long Task time was **128–241ms per scenario**, across 1–2 tasks. Against
13–23s of wall clock that is under 2%.

This matters because the standing assumption has been that web is slow *because*
KDF WASM shares the main thread with Flutter. For activation and balance
fetching, it does not — the work is asynchronous network I/O, not computation.
Whatever makes the web app feel slow, it is not KDF blocking the UI thread
during login.

---

## 6. The client-side defect that was found and fixed

Not everything was KDF's. The SDK issued `task::scan_for_new_addresses`
immediately after an activation that had *already* walked the same gap. It hit
its 20s ceiling every time and was discarded:

```
PubkeyManager: HD address scan failed for Komodo; continuing with existing pubkeys
  | TimeoutException: Timed out scanning for new addresses for KMD
```

The fix skips that second walk when — and only when — the activation happened
this session *and* the protocol's params actually carry a scan policy.
`UtxoProtocol` sends `scan_policy: scan_if_new_wallet`; the ETH-family params
have no `scan_policy` field at all, so ETH must still scan.

| | before | after |
|---|---|---|
| HD `first_post_activation_balance_ms` | 77,986 – 89,462 | **47,986** |
| `scan_for_new_addresses::status` polls | 79 – 80 | **0** |
| `task::account_balance::status` polls | 209 – 210 | **8** |

**~41s, about 45%.** The scan's own 20s was the expected saving; the other ~20s
was `account_balance` polling collapsing once it stopped contending with a scan
of the same account. iguana is unchanged, which is the control.

---

## 7. What is KDF-side vs client-side

**KDF-side** (the client cannot schedule these away):

* The `gap_limit: 20` address walk during activation — 45 of the 47 UTXO
  seconds, and the dominant term on EVM.
* `enable_eth_with_tokens` being **synchronous**. There is no task id, no
  progress events, no partial result — a caller blocks for the full duration
  and cannot show the user anything. Contrast `task::enable_utxo`, which at
  least reports progress.
* Cost that is strictly per-asset and additive — nothing about a login's
  activation set is shared or amortised (§4e).
* Whatever makes the native binary ~4× slower than the WASM build on the
  identical task (§5a). Only KDF can isolate this: the transports differ by
  platform and neither can be swapped from outside.

**Client-side** (levers we control):

* `scan_policy` and `gap_limit` are ours to choose — `utxo_protocol.dart`.
* ~~Batching~~ — **measured, and it is not a lever** (§4c). The same 19 assets
  cost the same whether issued as 6 calls or 21, because the work is per-asset.
  Batching saves round trips, not seconds.
* How many coins a login enables at all (`enabledByDefaultCoins`).
* The redundant second scan — fixed above.

---

## 8. A KDF crash found by the probe

**TRX activation panics when p2p is disabled.**

```
panicked at mm2src/mm2_p2p/src/p2p_ctx.rs:42:14:
  called `Option::unwrap()` on a `None` value
→ mm2_main::rpc:362 ERROR The RPC service aborted without responding.
```

Reproduce: start KDF with `disable_p2p: true` and send
`enable_eth_with_tokens` for `TRX`. The request returns HTTP 500 with the body
`The RPC service aborted without responding.`

> **Correction.** An earlier version of this report said the whole RPC service
> died from that point on. **It does not.** That sentence came from trusting
> the 500's body text: the message is a fixed string at
> `mm2src/mm2_main/src/rpc.rs:361`, emitted whenever the spawned per-request
> task drops its sender — which a panic does. `panic = 'unwind'` is set
> (`Cargo.toml:241`). Re-tested explicitly: after the TRX panic the same
> process answered `version`, then activated `ETH + USDT-ERC20` successfully,
> and `get_enabled_coins` listed both. What actually aborted was *my probe*,
> whose `json.loads` choked on the non-JSON 500 body. The misleading string is
> itself worth fixing.

`enable_eth_with_tokens` for ETH, BNB, AVAX, MATIC and GLEEC all succeed under
the same configuration. With p2p enabled TRX activates in 1.4s (iguana).

The cause is in `mm2src/coins/eth/v2_activation.rs:1217`, which fetches the
P2P signing keypair **unconditionally**, before checking whether any node
actually needs proxy signing:

```rust
let proxy_sign_keypair = Some(Arc::new(P2PContext::fetch_from_mm_arc(ctx).keypair().clone()));
```

`fetch_from_mm_arc` is a chain of `unwrap()`s (`p2p_ctx.rs:37-46`), and the
context is only populated when p2p starts. So this is an `unwrap()` on a
legitimately-absent value rather than a validation error.

Three things make it worth fixing beyond the panic itself:

* **It is not TRON-specific.** `initialize_global_nft` does the same
  unconditional fetch at `v2_activation.rs:686` — seventeen lines *before* its
  own `if komodo_proxy` guard at `:703`. A plain `enable_nft` with
  `komodo_proxy: false` panics identically.
* **It is fatal on WASM**, which is what the web wallet runs: a panic
  terminates the MM2 instance there, because `catch_unwind` is unusable with
  async on wasm32 (`mm2_bin_lib/src/mm2_wasm_lib.rs:127-131`).
* **The fix already exists in-tree.** `tendermint_coin.rs:3198-3203` does
  exactly the right shape:
  `let p2p_keypair = if nodes.iter().any(|n| n.komodo_proxy) { … } else { None };`
  and the TRON client already accepts `None` with a typed error
  (`eth/tron/api.rs:202, :216-221`). Three call sites need it —
  `v2_activation.rs:686`, `:1217`, and `eth/tron/gasfree/client.rs:53`.

---

## 9. Incidental defects found while doing this

Neither is on the wallet-load path, both are real:

* **`CoinSubClass.parse("Gnosis")` throws `StateError`.** The 7 Gnosis entries
  (`XDAI`, `USDC-GNO`, `GNO-GNO`, …) cannot be classified, let alone activated.
  `coin_subclasses.dart` ends in a bare `firstWhere` with no `orElse`.
* **`SBCH` is unreachable.** `smartBch` exists in the enum but is commented out
  of `UtxoActivationStrategy.supportedProtocols` and appears in no other
  strategy, so it raises `UnsupportedError: No activation strategy found`.

Also worth flagging: `GetPublicKeyHashRequest.toJson` shipped
`'params': <JsonMap>{}` from 2024 — a single type argument on `{}` makes it an
empty **Set**, which `jsonEncode` refuses. It could never be sent over any
serialising transport. Fixed, with a round-trip test over the request types.

---

## 10. Suggested questions for the KDF team

> These were written before the KDF source was audited. Questions 1–3 now have
> concrete answers and proposed patches in
> [`KDF_IMPROVEMENT_OPPORTUNITIES.md`](KDF_IMPROVEMENT_OPPORTUNITIES.md); Q2 in
> particular turns out to be already-solved (`task::enable_eth::init` exists —
> the client just does not use it). Kept here as the questions the measurements
> raised.

1. Can the activation-time address walk be **incremental or backgrounded** —
   return the wallet as usable and discover addresses behind it? Today the
   whole activation blocks on it.
2. Can `enable_eth_with_tokens` become **task-based** like `task::enable_utxo`,
   so a 356s call reports progress instead of appearing hung?
3. Is `gap_limit: 20` per chain (external *and* internal) intentional for a
   brand-new wallet with no history? A new wallet cannot have gaps.
4. Why is BTC ~2.7× KMD for the identical operation (126.2s vs 46.4s, same
   gap limit, same empty wallet)? Server-side history lookup cost, or something
   in the client's per-coin path?
5. **Why is the native binary ~4× slower than the WASM build on the identical
   task?** 94 polls vs 13, same 500ms interval, same seed, same coin. We cannot
   isolate it from outside: native rejects WSS (`"Incorrect protocol for native
   connection"`) and browsers cannot open TCP, so the transport can never be
   held constant across the two. Is the native TCP/SSL electrum client doing
   serially what the WSS client pipelines — and is native WSS support something
   that could be added?
