# TRON gas-free — KDF follow-ups for the silent native-fallback class

**Audience:** komodo-defi-framework team.
**KDF branch / commit verified against:** `feat/tron-gasfree` @ `947c6fad6`.
**Wallet repo / branch:** `gleec-wallet-kdf-integrations` @ `add/gas-free-tron`.

## Background — the symptom

Users reported: *"the TRC20 gas-free checkbox is ticked, but the withdrawal still
goes out as a native (TRX-funded) transfer."*

Root cause (verified): gas-free vs native is decided by KDF at **preview** time.
The client sends `fee_method=gasless` with `gasless.fallback_to_native=true`. When
KDF cannot build the gas-free rail for a **deterministic-unavailable** reason it
returns `Ok(None)` and the caller falls through to the native build — producing a
native `FeeInfoTron` preview with no error. The client then broadcasts whatever
the preview was.

```
eth_withdraw.rs:341-352   gasless mode → maybe_build_tron_gasless_withdraw(...).await?
                          → Ok(Some) returns gasless; Ok(None) FALLS THROUGH to native (line 354+)
withdraw.rs:109-119       Err(e) → Ok(None) iff Gasless && fallback_to_native && is_deterministic_gasless_unavailable(e)
withdraw.rs:269-277       is_deterministic_gasless_unavailable = {Gasless(Unavailable),
                          NotSufficientBalance, NotSufficientBalanceForActivation, ZeroBalanceToWithdrawMax}
```

### What is NOT broken (verified — please do not "fix" these)

- **Transport/auth failures correctly hard-error.** `401/403/429/CORS/timeout/
  provider-rejection` map to `WithdrawError::Transport` /
  `Gasless(ProviderRejected|InvalidProviderResponse)`
  (`withdraw.rs:491-509`), none of which are in `is_deterministic_gasless_unavailable`,
  so they propagate via `?` (`eth_withdraw.rs:348`) and surface as a visible
  withdraw error (→ HTTP 502). They do **not** silently fall back to native. (This
  corrects an earlier assumption that the proxy-401 / web-CORS issues caused silent
  native — they do not; they are a separate, visible failure.)
- **base_url / network-segment handling is correct** in `komodo_proxy` mode
  (`mod.rs resolve_gasfree_base_url`, KomodoProxy arm preserves the URL verbatim).
- **service_provider** is only bound into the permit at finalize/submit, so a wrong
  one is a hard submit error, not a silent native.

### What the wallet already did (client-side mitigation)

The wallet now **blocks** broadcasting a native preview when gas-free was
requested (`didGaslessDowngrade` → Send disabled + actionable notice; backstop
guard in the submit handler), and **hides the gas-free toggle for Trezor**
(see below, item 4). It still sends `fallback_to_native=true` so the preview
returns the native fee breakdown for display. So the user-facing symptom is fixed
client-side. **The items below are KDF-side improvements** that make the behaviour
observable, correctly scoped, and robust — several are needed for any other client
(or a future "auto-fetch provider") to behave correctly.

---

## Items to verify and fix

### 1. (High) Preview gives no structured signal that a gasless request fell back to native

**Where:** `eth_withdraw.rs:341-354`, withdraw result `fee_details`.

**Problem:** When a `fee_method=gasless` request falls back, the only difference in
the result is that `fee_details` is `TxFeeDetails::Tron` (native) instead of
`TxFeeDetails::TronGasless`. The client must **infer** the fallback by type-checking
the fee. There is no explicit field echoing the requested `fee_method` or a
"gasless_fell_back" flag.

**Why it matters:** Every client has to reverse-engineer intent-vs-result. It is
fragile (a future native fee variant, or a fee shape change, silently breaks
detection) and there is no machine-readable reason for *why* it fell back.

**Recommendation:** Include in the withdraw result (preview) an explicit indicator,
e.g. `requested_fee_method: "gasless"` and `gasless_fallback: { used_native: true,
reason: "insufficient_gasfree_balance" | "token_unsupported" | "not_configured" | ... }`.
Clients can then reliably detect and explain the downgrade without type sniffing.

### 2. (High) Insufficient **GasFree custody** balance silently routes to a native send from the **main** address

**Where:** `service.rs:249-298` (preflight reads `trc20_balance(token, local_gasfree_address)`),
`withdraw.rs:434-461` (`InsufficientSpendableBalance` / `InactiveAccountInsufficientBalance`
→ `NotSufficientBalance` / `NotSufficientBalanceForActivation`), `withdraw.rs:269-277`
(both are deterministic-unavailable), native path settles from `coin.address_balance(from_tagged)`
= the user's **main** address (`eth_withdraw.rs:354`).

**Problem:** Gas-free settles from the CREATE2-derived GasFree custody address;
native settles from the main address. A user holding the token on their **main**
address (the common case — they never pre-funded the GasFree custody) gets:
custody balance insufficient → deterministic-unavailable → fallback → a perfectly
valid native transfer from the main address. This is the **most likely real-world
trigger** of the reported symptom.

Additionally, the resulting `NotSufficientBalance` error (when surfaced, e.g. with
`fallback_to_native=false`) reports the coin ticker but **does not convey that the
shortfall is at the GasFree custody address** — so a user with funds on their main
address sees a confusing "not enough balance".

**Recommendation:**
- Carry the GasFree custody address (and that the balance checked was the custody
  balance) in the insufficient-balance error so clients can show *"fund your
  GasFree address `T…`"* rather than a generic balance error.
- Consider whether custody-balance shortfall should be **fallback-eligible at all**,
  or should be a distinct, clearly-messaged condition (it is not a transient rail
  outage — it is "this token isn't in your GasFree account yet"). At minimum pair
  with item 1's structured reason.

### 3. (Medium) `TokenUnsupported` (token missing from provider account-info) is indistinguishable from "not configured", and falls back silently

**Where:** `service.rs:199-213` (`assets.iter().find(... token_address ...)` →
`DisabledReason::TokenUnsupported`), `withdraw.rs:427-430` (→ `Gasless(Unavailable)`),
`withdraw.rs:269-277` (deterministic).

**Problem:** If the proxy's GasFree account `/api/v1/address/{account}` response
omits the token (enrollment gap, upstream config drift, or a transient partial
response), preflight returns `TokenUnsupported` → `Gasless(Unavailable)` → silent
native. This is indistinguishable from "gasless genuinely not configured," even
though the local `tron_gasless_token_config` is present (i.e. the operator *expects*
it to be supported).

**Recommendation:** When local `tron_gasless_token_config` is `Some` but the provider
omits the token, treat it as an operational anomaly: emit a `warn!` and/or a distinct
reason (item 1) rather than collapsing into the generic silent fallback.

### 4. (Medium) Missing `tron_gasless_token_config` downgrades with no log

**Where:** `withdraw.rs:303-308` — `resolve_gasless_withdraw_policy`'s first gate
returns `Ok(None)` for `Gasless + fallback_to_native` when the token has no
`tron_gasless_token_config`, with no log.

**Context (client-side, FYI):** On hardware wallets (Trezor) the wallet's
activation path does not thread `tron_gasless_provider`, so the token activates
without gasless config and every gas-free request hits this gate. The wallet now
hides the gas-free toggle for Trezor, but other clients may not. (If KDF intends
gas-free to be unsupported on HW wallets, consider rejecting/erroring the activation
of a gasless token config under an HW policy rather than silently dropping it.)

**Recommendation:** `warn!` when this gate downgrades a `fee_method=gasless` request,
and surface the reason via item 1.

### 5. (Medium) Passive platform re-enable does not re-apply `tron_gasless_provider`

**Where:** `platform_coin_with_tokens.rs:399-434` (`re_enable_passive_platform_coin_with_tokens`)
reuses the existing `platform_coin` instance and re-enables tokens against it, ignoring
`req.tron_gasless_provider`. The provider is only set on a fresh platform activation
(`v2_activation.rs:862-863, 993`; tokens inherit it at `v2_activation.rs:666`).
`resolve_gasfree_provider_for_coin` (`mod.rs:46-55`) returns the platform's provider
for a token; if the platform was ever made active **without** a provider, it stays
provider-less, and every TRC20 gas-free request silently falls back (item 4 path).

**Why it matters:** Latent: an already-active provider-less platform (activated by
an older build, an alternate path, or a passive re-enable) persistently disables
gas-free for all its tokens with no signal, until a clean re-activation.

**Recommendation:** Re-apply `req.tron_gasless_provider` to the platform on passive
re-enable; and/or expose the resolved provider in coin/enable info so clients can
detect a provider-less active platform and force a clean re-activation.

### 6. (Low) Permit `deadline_seconds` floor

**Where:** `withdraw.rs:311-321` reads `gasless.deadline_seconds` (default
`DEFAULT_GASLESS_DEADLINE_SECONDS = 300`).

**Context:** The wallet currently sends `deadline_seconds = 60` (tied to its preview
TTL), well under the 300s default, shrinking the signed-permit validity window and
raising the rate of `GaslessAuthorizationExpired` at submit. This is client-driven,
but KDF could enforce a sane minimum (or document a recommended range) to protect
against clients picking a too-small window.

### 7. (Low / known) Auto-fetch `service_provider`

KDF has a TODO to auto-fetch the GasFree service provider from
`/api/v1/config/provider/all` at activation (referenced in `gasfree/config.rs` and
in the wallet's `constants.dart`). Until then every client hardcodes the provider
(the wallet default is `TLntW9Z59LYY5KEi9cmwk3PKjQga828ird`, verified against the
Gleec proxy account on 2026-06-24). Implementing the auto-fetch removes a brittle
hardcoded constant and a class of "wrong provider → submit failure" bugs. **Note:**
items 1-3 (structured fallback reason + custody-aware errors) are prerequisites for
a good client experience once gas-free is the default rail.

### 8. (Proposal) Multi-address (HD) custody support

**Current state:** the custody-first model is effectively **single-address**. Every TRON
address gets a `gasfree_address` for display (`compute_gasfree_for_display`, applied on
get_new_address / account_balance / scan paths), but everything transactional binds to the
coin's enabled (primary) address:

- `gasless::account_status { coin }` takes no address parameter — the preflight and the
  on-chain fallback both use the enabled address's custody account only.
- Gasless `withdraw` derives/settles from the enabled address's custody account.
- Balance/event streams and (client-side) history have no per-address custody notion.

A user who creates a second HD address and deposits into *its* custody address holds funds
that no RPC reports as a balance — invisible until manually swept. The wallet consequently
**gates address creation for gasless assets** (single-address UX, matching TronLink/Klever)
and pairs the asset-level custody balance only with a sole gasless address row.

**Proposed KDF changes to lift the restriction (in dependency order):**

1. `gasless::account_status { coin, address? }` — optional `address` (must be one of the
   coin's derived addresses; `AddressMismatch`-style hard error otherwise). Default stays
   the enabled address for backward compatibility. The custody derivation and
   `preflight_transfer(value=0)` already operate on an explicit address internally, so this
   is mostly plumbing.
2. `withdraw` (gasless mode) honoring `from` for the custody derivation — today the `from`
   HD-path selects the signer; the gasless build must derive the custody account from the
   same selected address rather than the enabled one, so signer and custody stay paired.
3. Aggregation semantics: either (a) clients iterate addresses and sum (needs only item 1),
   or (b) a `gasless::accounts_summary { coin }` returning per-address custody snapshots +
   a total. (a) is sufficient for wallets; (b) avoids N preflights per refresh.
4. Balance events: emit custody-balance changes per address (or at least for all derived
   addresses, not just the enabled one) so clients don't need timer polling per address.

Until then, single-address is the only configuration in which custody balances, withdraw
previews, and history can be presented coherently — clients should gate HD address creation
for gasless-enabled TRC20 tokens.

### 9. (Low) `gasless::account_status` hard-errors on provider auth failures instead of degrading to the on-chain fallback

**Where:** the provider-unreachable fallback in `account_status` covers transport-class
failures (degrades to `balance_only` with `provider_available: false`), but
`Unauthorized`/`Forbidden` from the provider (e.g. a revoked/rotated GasFree proxy API key)
surface as a hard `ProviderError` RPC error instead.

**Why it matters:** a custody-first client that caches the last good custody balance has no
better option than serving the stale cache during such an outage (falling back to the EOA
number would be plain wrong), so a credential outage silently pins a stale balance until the
key is fixed. The on-chain custody balance is auth-free readable — exactly what the existing
`balance_only` fallback does.

**Recommendation:** treat `Unauthorized`/`Forbidden` (and other provider-side auth errors)
like provider-unreachable in `account_status`: return the degraded on-chain snapshot with
`provider_available: false` rather than a hard error. Withdraw-time behavior should stay a
hard error (submitting can't succeed without auth).

### 10. (Low) HD storage keeps re-reporting never-used TRON addresses ("phantoms")

**Where:** `get_new_address` increments and persists `known_addresses_number`
(`hd_wallet/coin_ops.rs` → `set_known_addresses_number` → SQLite `hd_account` table /
IndexedDB on WASM); activation and `task::account_balance` then report `0..known` on every
session (`eth/eth_hd_wallet.rs`, `coin_balance.rs`). `scan_for_new_addresses` only *extends*
the count when it finds USED addresses — nothing ever shrinks it.

**Why it matters:** TRON addresses created via `get_new_address` before a client adopted the
single-address custody model are re-reported forever, even if never used. Every such address
also gets a `gasfree_address` stamped on it, so custody-first clients see multiple
"gasless-looking" rows while `gasless::account_status` and gasless sends only ever bind to
the enabled address. The wallet now filters these client-side (SDK `PubkeyManager`
`filterGaslessPhantomAddresses`: keep the enabled address + any funded address, drop the
rest), but the phantoms live in KDF's own DB and are re-supplied on every fetch.

**Recommendation:** at TRON platform activation (or via a maintenance RPC), clamp
`hd_account.external_addresses_number` to `max(enabled_address_id + 1, last_used_index + 1)`
using the existing TRON `is_address_used` scanner (`eth_hd_wallet.rs`) — i.e. forget derived
addresses that were never used on-chain. Only increment (`get_new_address`) and extend
(`scan`) exist today; there is no shrink path.

---

## Priority summary

| # | Item | Severity | Type | Status |
|---|------|----------|------|--------|
| 1 | Structured fallback signal in preview result | High | Observability / API | Open (mitigated: this wallet sends `fallback_to_native:false`, so KDF hard-errors instead of downgrading) |
| 2 | Custody-balance fallback routes to main-address native; opaque error | High | Semantics / UX | Open (mitigated client-side: custody-first model; native downgrade hard-blocked) |
| 3 | `TokenUnsupported` enrollment-gap silent fallback | Medium | Observability | **DONE in fork (2026-07-02)** — `warn!` at the enrollment-gap site (`service.rs` preflight) |
| 4 | Missing token-config downgrade has no log | Medium | Observability | **DONE in fork (2026-07-02)** — `warn!` at the `resolve_gasless_withdraw_policy` gate |
| 5 | Passive re-enable drops `tron_gasless_provider` | Medium | Activation robustness | **DONE in fork (2026-07-02)** — new `on_passive_re_enable` trait hook; ETH impl warns when the request carries a provider the live instance lacks (in-place update impossible: the provider is applied at construction) |
| 6 | Permit `deadline_seconds` floor | Low | Reliability | Mitigated client-side: wallet now sends 300s (= KDF default; live provider bounds are 60–600s) |
| 7 | Auto-fetch `service_provider` | Low | Config (known TODO) | **DONE in fork (2026-07-02)** — `service_provider` is now optional; `ResolvedTronGaslessProvider::ensure_service_provider()` fetches `/api/v1/config/provider/all` at first use (cached), keeps a configured address only when the API offers it (warns + substitutes otherwise), and falls back to the configured value on fetch failure. Verified live: activation with no `service_provider` + a real gasless preview through the Gleec proxy succeeded. |
| 8 | Multi-address (HD) custody support | Medium | API / Semantics | Proposal (2026-07-02) — see item 8; wallet is single-address-gated until implemented |
| 9 | `account_status` should degrade provider auth failures to the on-chain fallback | Low | Robustness | Open (2026-07-02) — client mitigates by serving the last custody-sourced balance |
| 10 | Clamp never-used TRON HD addresses in `hd_account` storage | Low | HD storage | Open (2026-07-02) — client mitigates via the SDK pubkey phantom filter |

All file:line references are against `feat/tron-gasfree` @ `947c6fad6`; please
re-verify line numbers if rebasing.

## Unrelated pre-existing breakage (noted 2026-07-02)

`cargo check -p mm2_main` fails on the current stable toolchain (1.95) with 5
errors in `mm2src/coins/lightning/` (`bitcoin::BlockHeader/Transaction` `From`
impl mismatches) — only under `default-features = false` on the `coins`
dependency (mm2_main's configuration). Verified pre-existing on the unmodified
tree. `cargo check -p coins`, the full gasfree test suite (37 tests), and a
binary build with coins default features all pass.
