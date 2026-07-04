# TRON GasFree support — what our fork adds over upstream KDF

**Audience:** komodo-defi-framework (KDF) core team.
**Fork:** `komodo-defi-framework`, branch `feat/tron-gasfree`, tip `d4fc1bd04` (2026-06-30), diffed against `origin/main` (`d56a7bc5`) — plus a further batch of uncommitted working-tree changes described inline below and dated 2026-07-02.
**Consumer:** `gleec-wallet-kdf-integrations` (Gleec Wallet), branch `add/gas-free-tron`.
**Companion docs (same `docs/` folder):** [`TRON_GASFREE_KDF_FOLLOWUPS.md`](./TRON_GASFREE_KDF_FOLLOWUPS.md) — behavioral/observability follow-ups on top of this feature (silent native-fallback class, multi-address proposal, HD-storage cleanup); [`TRON_GASFREE_PROXY_401.md`](./TRON_GASFREE_PROXY_401.md) — a separate, adjacent service (`komodo-defi-proxy`) that is out of scope here.

## Why this document exists

Gleec Wallet needed to let a user hold and send TRC-20 USDT on TRON **without ever owning TRX**. TRON's ecosystem answer to this is [GasFree](https://gasfree.io) — a relayer protocol where the user signs an off-chain TIP-712 (TRON's EIP-712 variant) permit authorizing a transfer, and a third-party relayer broadcasts the actual on-chain transaction, taking its fee out of the transferred token itself. This is the same UX pattern TronLink, Klever and NOW Wallet ship for USDT-TRC20.

**Upstream KDF has no support for this at all — not "incomplete," genuinely absent.** Stock KDF's withdraw pipeline has exactly one model: an address signs its own transaction and pays its own network fee in the chain's native asset, broadcast immediately by the node itself. There is no config vocabulary for a third-party fee relayer, no representation for "signed authorization awaiting relay" as distinct from "signed transaction awaiting broadcast," no RPC that can report a balance for anything other than the coin's own derived address, and (as a byproduct of building this) two real, pre-existing bugs were found in shared code paths unrelated to TRON.

We built the entire feature in this fork: ~6,700 lines across 79 files, the large majority in a new `mm2src/coins/eth/tron/gasfree/` module, plus surgical touch-points through activation, withdraw, broadcast, and streaming. This document summarizes what was built, organized by layer, so the KDF team can evaluate adopting it (as a whole, in pieces, or as a design reference for a native implementation).

**Status as of 2026-07-02:** feature-complete and verified live against TRON's Nile testnet and a real GasFree provider account (see [Test coverage](#test-coverage-summary)). The newest layer — a custody-first `gasless::account_status` RPC and a deferred/auto-fetched `service_provider` — landed in this session as **uncommitted working-tree changes** on top of the committed branch tip; they're included below and flagged explicitly wherever they're not yet committed.

---

## Architecture at a glance

```
Activation:  enable_eth_with_tokens(tron_gasless_provider: {...})
                 └─ TRON-only validation gate → ResolvedTronGaslessProvider on the platform coin
                      └─ inherited by each TRC-20 token at token-activation time

Custody:     every TRON address → CREATE2 → a deterministic GasFree "custody" address
                 └─ surfaced on every balance/address RPC (get_new_address, account_balance, my_balance, ...)
                 └─ gasless::account_status → live custody balance + fees + activation state

Withdraw:    withdraw(fee_method: "gasless", gasless: {max_fee, deadline_seconds, fallback_to_native})
                 └─ preflight against GasFree (balance/fee/activation check)
                 └─ sign a TIP-712 PermitTransfer locally (no broadcast yet)
                 └─ return TransactionData::Unsigned{relay_type: "tron_gasfree", ...}

Broadcast:   send_raw_transaction(tx_json: <the unsigned payload above>)
                 └─ re-validate, then POST to the GasFree relayer (KDF never puts bytes on-chain)
                 └─ relayer returns a trace_id

Tracking:    gasless_trace::enable(coin) → SSE stream of trace_id state transitions
             (Pending → Submitted → OnChain → Confirmed/Failed), polling the relayer server-side
```

Eight functional layers make this work. Each is described below with: the gap in upstream, what we built, why the GUI needed it, and notes for upstream reviewers.

---

## 1. Provider configuration & activation wiring

**Files:** `coins/eth/tron/gasfree/{config,mod}.rs`, `coins/eth/v2_activation.rs`, `coins_activation/{eth_with_token_activation,platform_coin_with_tokens}.rs`, `coins/eth/tron.rs`.

**Gap:** no config schema field, no credential-storage convention, no "token inherits config from platform" mechanism, and no activation-time gate for "this coin's fees are paid via an external service" exists anywhere in KDF.

**What we built:** A new `EthActivationV2Request.tron_gasless_provider: Option<TronGaslessProviderConfig>` field, validated by `resolve_tron_gasless_provider` at platform-coin construction — this is a **hard TRON-only gate**: supplying the field on any non-TRON `ChainSpec` is a construction error, so it cannot be misapplied to an EVM activation. The resolved provider (`ResolvedTronGaslessProvider`, `Arc`-wrapped, cheap to clone) is stored on `EthCoinImpl` and copied into each TRC-20 token's own `EthCoinImpl` at token-activation time — a shallow, point-in-time inheritance pattern loosely modeled on the existing `Eip1559Ops` trait, though not literally the same mechanism (`Eip1559Ops` does a live `platform_coin()` lookup on every call; this eagerly clones once at activation).

Two auth transports are supported via a `service` enum on the config:
- **`GasFree` (direct):** HMAC-SHA256 over `method+path+timestamp`, using an operator-held API key/secret.
- **`KomodoProxy`:** the request is instead signed with the node's *existing* P2P Ed25519 identity (the same mechanism KDF already uses for `EthNode.komodo_proxy`) and forwarded to a Komodo-operated proxy that holds the real GasFree credentials server-side. This is what lets a wallet ship a build where **no distributed node/app config ever contains the GasFree API secret**.

A per-token `gasless: {enabled, transfer_max_fee}` activation field lets an operator opt individual TRC-20 tokens in and cap the permit's signed fee; activating a token with `gasless.enabled=true` against a platform with no provider is a hard activation error, not a silent no-op.

A new `on_passive_re_enable` trait hook (default no-op) closes a real gap: because the provider is inherited by eager clone rather than live lookup, a platform coin re-enabled from an already-active state (e.g. a token-only disable/enable cycle) reuses the existing `EthCoinImpl` and silently discards any newly-supplied provider config in the re-enable request. The hook currently only `warn!`-logs the condition (it can't rebuild `EthCoinImpl` in place) — see [design notes](#design-notes-1) below.

**Uncommitted addition (2026-07-02):** `service_provider` changed from a mandatory config field to `Option<String>`, with `ResolvedTronGaslessProvider::ensure_service_provider()` lazily fetching the live provider list from GasFree's `GET /api/v1/config/provider/all` at first use (cached), preferring a configured address if it's still valid, warning-and-substituting the first available one if not, and falling back to the configured value if the fetch itself fails. This closes a known TODO ("KDF should auto-fetch the provider, not require it hardcoded") and removes a whole bug class of "wrong hardcoded provider address → submit fails."

**Why the GUI needed it:** without this layer, the withdraw-time GasFree logic has nowhere to get credentials/base-URL/provider-address from, and every TRC-20 token would have to redundantly carry its own copy of relayer config. The proxy transport specifically exists because Gleec cannot ship GasFree's raw API secret inside a distributed mobile/web app.

<a id="design-notes-1"></a>**Notes for upstream review:**
- TRON-only gating is implemented independently at two layers (platform + token) via separate `ChainSpec` matches — easy to desync if a third gate is ever needed; a shared predicate would help.
- `ensure_service_provider`'s three-tier fallback degrades via `warn!` only — a misconfigured or API-rejected provider address never hard-fails at activation, only (silently, to a different address) at first use. Acceptable as a "don't brick a wallet over one field" choice, but a startup health-check or a surfaced fallback event would make this less silent.
- `on_passive_re_enable` is log-only, not self-healing. Upstream should decide whether a stronger recovery (forcing a full re-activation, or making the provider field genuinely live) is worth the added complexity.
- Manual, hand-written `Debug` redaction for credentials (no derive/macro enforcement) — a future field addition could leak into logs if the impl isn't updated in lockstep.
- `config.rs` is the least stable file in this batch (rewritten mid-session); re-diff carefully if adopting.

---

## 2. Deterministic custody-address derivation (CREATE2) & response wiring

**Files:** `coins/eth/tron/gasfree/address.rs`, `coins/eth/tron/primitives.rs`, `coins/coin_balance.rs`, `coins/rpc_command/get_new_address.rs`, `mm2_rpc/src/data/legacy/wallet.rs`, `mm2_main/src/rpc/lp_commands/legacy.rs`, `coins/eth.rs`, plus shared-struct fallout in `coins_activation/{prelude,bch_with_tokens_activation,sia_coin_activation,z_coin_activation,erc20_token_activation,init_erc20_token_activation}.rs`.

**Gap:** upstream has no concept of a "provider-derived receive address" distinct from the address the wallet actually controls. Every balance/address RPC assumes the reported address *is* where funds live.

**What we built:** `compute_gasfree_address` (`address.rs`) implements TRON's CREATE2 variant against GasFree's beacon-proxy contract system: `salt` = the user's 20-byte EVM-form address; `init_code_hash` from the (per-network, hardcoded) creation-code bytecode plus ABI-encoded constructor args; final address = last 20 bytes of `keccak256(0x41 || controller || salt || init_code_hash)` — note the TRON-specific `0x41` prefix in place of Ethereum's `0xff`. This is a **pure, infallible, local computation** — no RPC call needed — validated against 6 official GasFree JS SDK test vectors across Mainnet/Nile/Shasta (all pass).

`EthCoinImpl::compute_gasfree_for_display` / `enrich_balance_report_with_gasfree` wire this into **nine call sites**: `get_new_address`, `account_balance`, `init_account_balance`, `init_scan_for_new_addresses`, `init_create_account` (both Iguana and HD variants), sync and task-based ERC-20 token activation, and the legacy v1 `my_balance` RPC. Every one of these now carries an optional `gasfree_address` field alongside the real address.

**Why the GUI needed it:** the deposit address shown to the user has to be computed identically everywhere it's displayed. Duplicating the CREATE2 formula (and its three ~1-2KB hardcoded bytecode blobs) client-side in Dart would risk a silent mismatch between what KDF derives and what the GUI shows — an unrecoverable-funds risk if it diverges. Centralizing it in KDF means the same derivation works automatically across every existing address/balance code path the GUI already calls.

**Notes for upstream review:**
- **Shared-struct coupling cost, worth flagging clearly:** `CoinAddressInfo<Balance>` (used by *every* activation module — BCH, Sia, ZCoin, generic ERC-20, not just TRON) and `IguanaWalletBalance`/`HDAddressBalance` (used by every UTXO/QTUM/generic-HD coin) each gained one `Option<String>` field. That forced unrelated coin modules (`bch_with_tokens_activation.rs`, `sia_coin_activation.rs`, `z_coin_activation.rs`) to write a meaningless `gasfree_address: None` purely to satisfy the struct literal. This doesn't scale if a second provider-derived-address concept ever shows up on another coin family. Worth considering a trait-based `address_metadata()` hook, a side-channel map, or a TRON-specific response wrapper instead — the existing code already has `TODO` comments at the relevant sites acknowledging this.
- The hardcoded controller/beacon/bytecode constants (three per network) have no on-chain freshness check — if GasFree redeploys/upgrades its contracts, KDF will silently keep deriving against the old set until someone manually re-syncs from the JS SDK. Worth discussing whether an activation-time sanity check against the live contract bytecode hash is warranted.
- The "generic code writes `None`, `EthCoin` patches the real value in afterward" pattern is repeated at all nine call sites — workable, but it's a workaround for the lack of an extension hook rather than a designed one.

---

## 3. GasFree HTTP client, typed schema, and the two auth transports

**Files:** `coins/eth/tron/gasfree/{client,api_types,error}.rs`, `proxy_signature/src/lib.rs` (existing crate, reused).

**Gap:** KDF has never called out to a third-party, non-blockchain HTTP API as part of a withdraw flow. There was no pluggable authenticated-transport abstraction, no typed wrapper for a relayer's bespoke envelope format, and no protocol-conformance enforcement for an externally-controlled wire format that fund safety depends on.

**What we built:** `TronGasfreeClient` exposes four typed operations (`get_account_info`, `submit_transfer`, `get_trace`, `get_supported_tokens`/`get_providers`, the latter two cached) funneled through one `execute<T>` helper. Both auth transports (direct HMAC vs. Komodo Proxy, described in §1) implement a single `auth_headers()` method so the request/response code is fully transport-agnostic.

The response envelope (`{code, reason, message, data}`) is decoded as a **second, independent success signal beyond HTTP status** — a `200` with `code != 200` is converted into a typed error; this is a real, observed provider behavior (unit-tested: a 200-with-code-429 body maps to `RateLimited`).

The typed schema (`api_types.rs`) treats **serde deserialization itself as the protocol-conformance boundary**: request IDs must be UUIDv4, permit-version fields must equal exactly the current schema version (any drift is a hard rejection, not a warning), signature/hash fields are fixed-width wrappers that explicitly reject `0x`-prefixed input (because the underlying `FromStr` impls silently strip it, which would otherwise let inconsistent hex encodings round-trip), and transfer/transaction-state enums have no catch-all variant — an unrecognized state string from the provider is a hard error, deliberately, "so API drift is surfaced immediately" (this is a direct code comment, and it's unit-tested with literal `"UNKNOWN_STATE"`/`"MYSTERY"` rejection cases). One real API quirk is handled via a serde alias rather than trusted-one-spelling: the provider's fee field appears as both `estimatedTransferFee` and `estimateTransferFee` depending on response, and there's a regression test pinning both.

The error taxonomy (`error.rs`) maps HTTP/transport/provider-envelope failures onto a stable, coin-agnostic `HttpStatusCode` contract (401→Unauthorized, 429→RateLimited, 5xx→Upstream, etc.), three layers deep: transport-level (`TronGasfreeError`) → send-level (`GaslessSendError`) → withdraw-level (`GaslessWithdrawError`) — broader than typical KDF coin-error handling, because a third-party HTTP dependency genuinely has more failure modes than an on-chain RPC error model does.

**Why the GUI needed it:** to show accurate live fee quotes before confirmation, to render an actionable, specific error (insufficient balance vs. provider rejected vs. rate-limited vs. timeout) instead of a generic failure, and to support both transport modes through one identical client so the GUI's integration code doesn't fork per build target.

**Notes for upstream review:**
- The HMAC signing string (`method + path + timestamp`, no delimiter) is spec-mandated by GasFree, not a KDF choice, but it's worth flagging as a footgun if the vendor's spec ever changes.
- The provider/token-list caches have no TTL — fine for effectively-static data, but a long-lived node wouldn't pick up a provider-side addition/removal without a restart.
- This whole layer is reverse-engineered-and-pinned-by-tests against a live external service KDF doesn't control (no OpenAPI/spec reference exists in-repo) — a genuine, ongoing maintenance burden distinct from typical KDF coin integrations, worth the team's eyes-open acknowledgment if adopted.
- `KomodoProxy` mode reuses the node's own P2P identity keypair as the proxy-auth key — convenient, but worth confirming that trust-boundary reuse (vs. minting a dedicated key) is acceptable.

---

## 4. TIP-712 typed-data signing — and a standalone bug fix in shared EIP-712 code

**Files:** `coins/eth/tron/gasfree/{typed_data,authorization}.rs`, `mm2_eth/src/{eip712,eip712_encode}.rs`, `mm2_metamask/src/lib.rs`.

This section covers two genuinely separate things.

### 4a. New capability: PermitTransfer builder & signer

`typed_data.rs` builds the off-chain TIP-712 domain + `PermitTransfer` message the GasFree relayer's contract recomputes and verifies via `ecrecover`. The domain strings (`"GasFreeController"` / `"V1.0.0"`) are exact per-protocol constants. A critical, easy-to-get-wrong detail: **TRON addresses are 21 bytes (`0x41` prefix + 20-byte EVM form), but the typed-data schema declares address fields as Solidity `address` (20 bytes)** — every address field is normalized by stripping the prefix before hashing. Getting this wrong would silently produce a hash the relayer's contract-side recovery either rejects, or (worse) recovers a different signer for.

`authorization.rs` signs the built message and, **before signing**, runs two fail-closed checks: the deadline hasn't already passed, and the resolved signing key's derived address actually matches the permit's claimed `user`. The signature format (`r||s||v`, `v = recovery_id + 27`) is explicit and validated. `GasfreeSignedAuthorization` has a hand-written `Debug` impl that redacts the signature field — since a valid signature here is effectively a bearer fund-transfer authorization, it should never land in a log line.

Correctness rigor: two Nile+Mainnet domain-separator vectors (cross-checked via an independently hand-rolled encoding, not the crate's own hasher) and 6 full end-to-end PermitTransfer hash vectors (1 official mainnet hash, 5 from the GasFree JS SDK's own examples) all assert exact hash equality — bit-for-bit verification against externally-produced reference values.

### 4b. Bug fix: `eip712_encode.rs` `bytes32` encoding was spec-non-conformant

**This is the single item in this whole document we'd recommend prioritizing independent of any GasFree adoption decision.** Per the EIP-712 spec, only *dynamic* types (`string`, `bytes`) are `keccak256`-hashed before being placed into the encoded struct tuple; fixed-size types — including `bytesN` like `bytes32` — must be encoded **directly**, the same way `uint256`/`address` are. The pre-existing `encode_bytes32` in `mm2_eth/src/eip712_encode.rs` was hashing the value instead, almost certainly a copy-paste from the adjacent (correct) dynamic-`bytes`-hashing branch.

**This is not TRON-specific and not behind any feature flag** — `eip712_encode.rs` is always-compiled shared code, and this exact function is reached by `mm2_metamask`'s `hash_typed_data`, the code path used today for real browser-wallet `eth_signTypedData_v4` requests. Any pre-existing or future KDF EIP-712 flow signing a typed-data structure with a `bytes32` field (extremely common — Permit2, order salts, generic domain salts) would compute the wrong struct hash: best case the signature fails on-chain verification (broken but safe), worst case a permissive downstream contract accepts it, meaning the user's key signs different semantic content than the wallet UI displayed.

The fix was discovered as a direct byproduct of writing this branch's own official-hash test vectors — getting them to match required an encoder that follows the spec exactly. GasFree's own schema happens not to use a `bytes32` field, so this bug wasn't blocking GasFree itself; it was caught while hardening the shared encoder GasFree now depends on. Also fixed in the same pass: dynamic `bytes` support was previously entirely absent (any typed-data payload with a `"bytes"`-typed field would hit an "unknown type" fallback), stricter hex-length validation was added, and `EIP712_DOMAIN`/`CustomTypes` were made `pub` for downstream crates to reuse.

New regression tests explicitly diff against the old buggy behavior, and one end-to-end test's expected hash was independently verified via Python + `pycryptodome`.

**Why the GUI needed it:** GasFree's off-chain-permit-plus-relayer model *is* an EIP-712-family signing problem; without a spec-correct encoder, any mismatch (domain string, address normalization, `v`-encoding, or the `bytes32` bug had the schema used one) means the relayer's contract rejects the permit and gas-free sending simply fails.

**Notes for upstream review:**
- **Recommend backporting the `eip712_encode.rs` fix standalone**, regardless of the GasFree adoption decision — it's small, self-contained, covered by tests including an independently-computed one, and touches code already live in the Metamask signing path.
- `GASFREE_DOMAIN_NAME`/`VERSION`/`GASFREE_PERMIT_VERSION` are hardcoded to the current GasFree protocol version — a future protocol bump needs a code change, not a config change. Acceptable for v1, worth flagging as a forward-compat rough edge.
- TRON-to-EVM address normalization is applied ad hoc at each call site (`format!("{:#x}", addr.to_evm_address())`) rather than being structurally enforced by a distinct address newtype — a refactor opportunity if this pattern is extended to new message types.
- `decode_error`'s existing `TODO` (reusing `web3::Error::Decoder`, a type meant for RPC parsing, for input-validation errors) is carried through unchanged — flagged in-code by the branch's own authors as tech debt.

---

## 5. GasFree account preflight service, and the custody-first `account_status` RPC

**Files:** `coins/eth/tron/gasfree/service.rs`, `coins/eth/tron/gasfree/account_status.rs` (**new, untracked**), `mm2_main/src/rpc/lp_commands/gasless.rs`, `mm2_main/src/rpc/dispatcher/dispatcher.rs`.

**Gap:** upstream has no concept of a relayer-custody account, and consequently no RPC that can report a balance for anything other than the coin's own derived/signing address. There's also no preflight mechanism anywhere in the ETH/EVM stack that combines a third-party provider's account state with an independent on-chain read to produce a go/no-go decision *before* a transfer is attempted.

**What we built — two layers.**

**`GasfreeAccountService`** is a stateless per-request preflight, generic over an `OnChainBalanceFetcher` trait so it's testable without a live chain. On every single call it re-derives the custody address locally (CREATE2) and compares it against what the provider *claims* the custody address is — any mismatch short-circuits to a hard `AddressMismatch` failure before any balance is even read, catching not just a first-run misconfiguration but live config drift or a misbehaving provider trying to redirect funds. It then checks token enrollment/decimals against the provider's asset list, enforces GasFree's one-in-flight-transfer-per-account rule, and only then reads the live on-chain TRC-20 balance to compute availability — including the correct (and non-obvious) inactive-account math: a first-ever transfer from an unactivated custody address must cover the transfer amount **plus** the transfer fee **plus** a one-time activation fee, sourced from the raw on-chain balance (not just the spendable slice), because activation is bundled into that first on-chain transaction.

**`gasless::account_status { coin }`** (**uncommitted, 2026-07-02**) is the newest, most product-driven piece. Gleec's design decision — documented in prior work, referenced here as background — is that for GasFree USDT-TRC20, **the custody address itself is the user's effective account**: the user deposits and holds funds there directly and never needs TRX at all, matching TronLink/Klever/NOW Wallet. That's only viable if the wallet can show a live, correct balance *for the custody address*, which no existing KDF balance RPC can do. `account_status` returns `{gasfree_address, active, nonce, on_chain_balance, frozen_balance, spendable_balance, transfer_fee, activation_fee, max_withdrawable, provider_available}` by running a zero-value preflight (reusing the exact same code path a real withdraw would use, so status and withdraw can never disagree about fees). It degrades gracefully — a GasFree outage falls back to an unauthenticated on-chain `trc20_balance_of` read with `provider_available:false` rather than hard-failing — but an address-mismatch result is deliberately **never** degraded, on the explicit reasoning "never report a balance for an unverifiable custody."

**Why the GUI needed it:** without this RPC, the wallet could only show the coin's own EOA balance (always near-zero by design, since the user never touches it directly) or fake a balance by running a full withdraw-preview cycle, which requires an up-front spend amount and doesn't degrade gracefully on provider outage.

**Notes for upstream review:**
- **This RPC shape is a genuinely new pattern and deserves debate, not just a merge.** It reports a balance for an address that isn't the coin's own derivation-method address. We chose a bespoke `gasless`-namespaced RPC for velocity/isolation; upstream might instead prefer eventually folding this into the standard balance-RPC family via a "custody-aware" variant — a bigger, more invasive change, but more discoverable/composable long-term.
- **Deliberate v1 scope cut, not an oversight:** single-address only (derives strictly from the coin's own signing address; hard-errors for HD/multi-address contexts). A multi-address variant is proposed future work (see the companion followups doc, item 8) but not designed or built.
- The zero-value preflight trick means every `account_status` call pays the same provider round-trip cost as a real withdraw preflight — no caching/TTL exists in this layer (the wallet may add one client-side, but a polling coin-details screen will hit the provider on every refresh as built).
- A small internal coupling risk: `account_status.rs` has to infer, by hand, which of `service.rs`'s internal short-circuit branches actually fetched a real on-chain balance vs. returned a zeroed placeholder. If a new short-circuit variant is added to `service.rs` without updating that inference in `account_status.rs`, the status RPC could silently report a stale/zero balance for the new case. Worth having `GasfreeTransferPreflight` carry an explicit "balance was sampled" bit instead.
- No live-network/mocked-HTTP integration test exists yet for `build_gasless_account_status`'s own control flow (the provider-unreachable degrade and address-mismatch hard-error paths) — the underlying `GasfreeAccountService` has good mock-based unit coverage, but this outer wiring doesn't. Given this is the layer deciding whether to trust a custody balance, that gap is worth closing before relying on it in production.

---

## 6. Withdraw path integration: fee methods, schemas, and error taxonomy

**Files:** `coins/eth/tron/gasfree/{withdraw,send}.rs`, `coins/eth/tron/{withdraw,fee,address}.rs`, `coins/eth/{eth_withdraw,eth_utils}.rs`, `coins/tx_fee_details.rs`, `coins/rpc_command/init_withdraw.rs`, `coins/lp_coins.rs` (`WithdrawRequest`/`WithdrawError` additions), `mm2_main/tests/mm2_tests/tron_tests.rs`.

**Gap:** stock `withdraw` has no field for "who pays the fee, in what asset," and no transaction representation for a signed-but-unbroadcast authorization awaiting third-party relay, as distinct from a signed transaction awaiting the node's own broadcast.

**What we built:** `WithdrawRequest` gains `fee_method: Option<WithdrawFeeMethod>` (`Native` | `Gasless`) and `gasless: Option<GaslessWithdrawOptions>` (`max_fee`, `deadline_seconds`, `fallback_to_native`).

**A design reversal worth calling out explicitly:** an earlier commit added a third `Auto` variant (try gasless, silently fall back to native on failure); a later commit removed it entirely, along with the associated silent native-fallback path, so callers must now choose the rail explicitly. This is almost certainly the right call: implicit rail selection meant a GUI couldn't reliably predict, from the request alone, whether the response would carry a TRX-denominated or token-denominated fee, nor whether funds would move through the custody address or the main one — a real correctness hazard for any UI that shows a preview before confirmation.

On the `Gasless` branch, the withdraw builds and signs a TIP-712 `PermitTransfer` **locally** — no TAPOS data, no protobuf transaction, no broadcast — and returns it wrapped in `TransactionData::Unsigned` (a new `TronGasfreeRelayPayload`, tagged `relay_type: "tron_gasfree"`). This is deliberate: **the KDF node is not the entity that submits this to the TRON chain**; the relayer is (covered in §7).

The fee-details shape stays cleanly separated: `TxFeeDetails::TronGasless` is a new, independent enum variant (not an extension of the existing `TronTxFeeDetails`), carrying `gasfree_address`, `transfer_fee`, `activation_fee`, `total_token_fee`, `signed_max_fee`, and `trace_id` — so native TRON withdraw responses are completely undisturbed in shape, and a client can pattern-match on the variant instead of guessing whether an overloaded field means "TRX fee" or "token fee."

A dedicated `GaslessWithdrawError` enum replaces a previously-confusing reuse of the generic `NotSufficientBalance` message: `InsufficientGasFreeBalance{coin, available, required}` and `…ForActivation{…, activation_fee}` explicitly name the GasFree deposit address and the one-time activation fee, because the shortfall being reported is about the *custody* address, not the address the user thinks of as "their wallet" — a real, previously-shipped user-confusion bug, not a hypothetical.

`fallback_to_native` is opt-in and narrowly scoped: only a specific allowlist of errors judged "clearly economic" (insufficient balance variants, zero-balance-max) are eligible to silently downgrade to a native send; anything ambiguous (provider rejection, signature failure, transport error, fee cap exceeded) is a hard error even with fallback enabled. **This is already tracked as a known observability gap in the companion followups doc** — even a correctly-scoped fallback can currently produce a native send with no strong client-visible signal beyond the response's fee-details type differing from what was requested; not re-litigated here.

A parallel small regression fix, `f8cd326c2` ("preserve native account fee compatibility"), reverted two overly-strict zero-checks that had broken native TRX-to-new-account withdraws — evidence that the native and gasless paths share enough surface area (`TronChainPrices`, `DestAccountState`) that changes to one can regress the other; worth dedicated native-path test coverage whenever gasless-adjacent fields are touched going forward.

**Why the GUI needed it:** to build a fee-preview screen with an explicit token-denominated fee and a user-settable safety cap; to show "you'll pay X USDT from your GasFree address Y" instead of a TRX figure that doesn't apply; to give the withdraw-progress UI distinct states (`FetchingGaslessQuote`, `SigningGaslessAuthorization`) instead of an indistinguishable generic spinner; and because the confirmation flow is necessarily two RPC calls (build/sign, then broadcast-or-relay) with the GUI passing the second payload through opaquely.

**Notes for upstream review:**
- Removal of `WithdrawFeeMethod::Auto` is a real API-surface break for anyone who adopted the earlier semantics — call this out explicitly in any upstream PR description, since it's not a graceful deprecation.
- `is_deterministic_gasless_unavailable` (the fallback allowlist) is hand-maintained with no compile-time link to `GaslessWithdrawError`'s variant list — a future variant addition could accidentally fall on the wrong side of the always/never-fallback line without anyone noticing there was a decision to make.
- `TronGasfreeRelayPayload` uses `serde(deny_unknown_fields)` — good hygiene for an untrusted round-tripped blob, but means any future field addition is a breaking wire-format change for an already-built-but-not-yet-broadcast transaction; worth an explicit version field if this is adopted long-term.
- The **uncommitted** `ensure_service_provider()` calls added at both quote-time and submit-time (binding the resolved provider address into the signed permit at both points, so it can't silently diverge between quote and submit) are a good defense-in-depth pattern but are new and not yet covered by the live Nile e2e suite — worth specifically exercising "provider address changes between quote and submit" before merging.

---

## 7. Broadcast, trace tracking, and streaming activation status

**Files:** `coins/eth/tron/gasfree/{relay_payload,trace_status}.rs`, `mm2_main/src/rpc/streaming_activations/gasless_trace.rs`, `mm2_event_stream/src/streamer_ids.rs`, plus a generic hook on `coins/lp_coins.rs`'s `MarketCoinOps` consumed by `coins/eth.rs` and (incidentally) `coins/siacoin.rs`.

**Gap:** upstream's only broadcast model is "sign locally, hand raw bytes to the node's own RPC immediately, watch mempool/confirmations." There's no concept of handing a signed-but-unbroadcast payload to a third party for relay, and no streaming primitive for "poll a relayer for the fate of a specific submission ID and push state transitions to the client."

**What we built — two pieces, one genuinely coin-agnostic, one TRON-specific.**

**A generic dispatch hook.** `MarketCoinOps` gained a default-implemented `try_send_raw_tx_json(&self, tx_json) -> Result<Option<Vec<u8>>, String>` (defaulting to `Ok(None)`), and `send_raw_transaction` now checks for a `tx_json` body before falling through to the existing `tx_hex` path. `EthCoin`'s implementation inspects a `relay_type` tag inside the JSON; anything other than `"tron_gasfree"` falls through untouched, so ordinary EVM/TRON hex sends are completely unaffected. When it matches, it deserializes the payload and calls `submit_tron_gasfree_payload`, which **re-validates everything** (chain ID, verifying contract, recomputed CREATE2 custody address, service-provider address, TIP-712 signature recovery against the claimed user, wallet ownership of the signing address, deadline not expired) before POSTing to the relayer's submit endpoint. **This is the actual broadcast step** — KDF itself never puts bytes on the TRON network for a gasless transfer; the relayer does, asynchronously, after accepting the submission.

This hook proved genuinely coin-agnostic in practice: `siacoin.rs` needed the identical hook for an unrelated reason (Sia transactions are always JSON-encoded, never raw hex, so the pre-existing `tx_hex` path was never usable for Sia at all) — a real, independent second consumer, not TRON-specific plumbing dressed up as generic.

**A new streaming activation, `gasless_trace`.** Because broadcast is now delegated to a relayer on its own schedule, the client doesn't have a chain tx hash at submission time — only a relayer-issued `trace_id`. `gasless_trace::enable(coin)` registers a per-coin streamer that multiplexes every in-flight trace for that coin onto one SSE channel. It collapses the relayer's own two-axis state model (a transfer-lifecycle axis crossed with an on-chain-inclusion axis) into one ordered 5-state enum (`Pending → Submitted → OnChain → Confirmed → Failed`, with TRON's "solidified" finality — not just first inclusion — as the confirmation bar), emits only on forward state transitions (plus a forced initial snapshot right after registration), and stops polling a trace once it reaches a terminal state or after 10 consecutive polling errors.

**Why the GUI needed it:** to show real withdraw-confirmation progress (submitted → broadcast → confirmed) using the same `send_raw_transaction` call site the wallet already uses for every other coin, and to get push-based status updates without shipping GasFree API credentials/polling logic into the Flutter app itself.

**Notes for upstream review:**
- **Silent registration loss:** if a client calls the gasless withdraw before first calling `gasless_trace::enable` for that coin, the trace-id push registration is dropped with only a `warn!` log — the withdraw still succeeds and returns a `trace_id`, but the client silently loses the streaming channel and must fall back to a separate one-shot `trace_status` RPC. A footgun for any integration that assumes "withdraw implies you'll be told about state changes." Consider auto-provisioning the streamer on first submit, or flagging the miss in the withdraw response itself.
- `failure_reason` on a `Failed` trace is currently a hardcoded `"unknown"` string — the relayer's actual failure/error text (if the API exposes one) isn't threaded through yet.
- 10-consecutive-errors is a deliberate "stop wasting resources on a dead relayer" safety valve, but it means the streaming channel does **not** guarantee eventual delivery of a terminal state — a client can be left not knowing the true outcome and must fall back to `trace_status` or tx-history.
- Assessment of reusability: the lower layer (`try_send_raw_tx_json` as a generic "accept a structured JSON payload instead of hex" hook) generalizes cleanly and is already proven by Sia. The upper layer (the trace state machine, the streamer, the GasFree-specific client calls) is entirely GasFree-specific — adopting this pattern for a different relayed-tx type would need a new streamer and projection, not reuse of this one, though the overall architectural template (submit → push an ID into a running per-coin streamer → poll → project to a small ordered enum → emit only forward transitions) is a reusable shape even where the code isn't.

---

## 8. Cross-platform HTTP: POST with custom headers (native + WASM)

**Files:** `mm2_net/src/native_http.rs`, `mm2_net/src/wasm/http.rs`, `mm2_net/src/transport.rs`.

**Gap:** stock `mm2_net` could do a GET with custom headers, and a POST with a *fixed* `Content-Type: application/json` header, but not a POST with both a JSON body **and** caller-supplied, runtime-generated headers — needed because GasFree's HMAC signature and the Komodo Proxy's `X-Auth-Payload` are computed fresh per request, not static. And this had to work identically on native **and** WASM, since the wallet ships as a Flutter web app too.

**What we built:** `slurp_post_json_with_headers` on both native (`hyper`-backed) and WASM (`fetch()`-backed), sharing a builder that validates header names/values and always force-applies `Content-Type: application/json` *after* the caller's headers, so it can never be silently overridden.

**Two genuine, pre-existing bugs were found and fixed as part of this work, independent of GasFree:**
1. **WASM silently discarded all response headers, always, on every existing `slurp_*` call** — the old code unconditionally returned an empty `HeaderMap` regardless of what the server sent back. Any existing WASM caller relying on response headers (rate-limit headers, ETags, custom API headers) was getting silently empty results, with no error and no warning.
2. **WASM header keys were not case-normalized**, unlike native's case-insensitive `HeaderMap` — setting the same header twice with different casing silently kept *both* entries instead of last-write-wins, a real behavioral divergence between native and WASM builds of the same code.

Also fixed: response bodies on the new path are read via `array_buffer()` (raw bytes) instead of the old `text()`-based path, which decodes as UTF-8 with lossy replacement per the Fetch spec — meaning any binary payload or non-UTF-8 JSON body was previously silently corrupted before mm2 code ever saw it.

**Why the GUI needed it:** without this, GasFree could work on desktop/mobile (where a bespoke request could be hand-rolled per call) but be unimplementable in the same code path for Flutter-web users — forcing either a maintained per-platform fork of the client, or dropping gasless support on web entirely.

**Notes for upstream review:**
- **Recommend evaluating this on its own merits** — it fixes a real, silent, pre-existing WASM bug (dropped response headers) and a real native/WASM behavioral divergence (header case handling), both of which would be worth fixing even if GasFree were dropped from consideration entirely.
- Small, additive, no new external dependencies — reuses `http::{HeaderName, HeaderValue, HeaderMap}` and `js_sys::try_iter`, both already dependencies.
- The WASM module now has two separate body-materialization code paths side by side long-term (the new `array_buffer()`-based one used by all `slurp_*` functions, and the older `text()`-based one still used by `request_str()`/`request_array()` and their pre-existing callers) — left this way to minimize diff size; worth consolidating eventually.
- Response-header extraction on WASM is deliberately best-effort/lossy (a header that fails to parse is silently dropped, not surfaced as a partial-failure signal) — mirrors real browser CORS header-exposure limits, but means a caller can't distinguish "blocked by CORS" from "failed to parse" from "genuinely absent."

---

## Dependency footprint

Deliberately minimal — nothing here should give a reviewer pause on supply-chain grounds:

| Change | Where |
|---|---|
| `hmac` (workspace dep, newly consumed) | `coins/Cargo.toml` |
| `mm2_eth` (existing internal crate) added as a path dependency of `coins` | `coins/Cargo.toml` |
| `chrono` bumped `0.4.41` → `0.4.44`, with explicit `alloc`/`clock` features added to `common`'s non-wasm deps | root `Cargo.toml`, `common/Cargo.toml` (needed because `common` was previously getting these transitively via feature unification across the full workspace build, which breaks when building a single crate in isolation, e.g. `cargo test -p mm2_eth`) |

No new external crates were introduced. Everything else is internal reorganization (the `hmac`/`uuid`/`sha2`-style primitives used throughout `gasfree/` were already workspace dependencies used elsewhere in the codebase).

A separate, unrelated batch of files (`hd_wallet/storage`, `lightning/*`, `nft/storage/wasm`, `qrc20/history.rs`, `utxo*`, `z_coin*`, `mm2_p2p`, `mm2_db`, `derives/enum_derives`, `ordermatch_tests.rs`) shows up in the branch diff purely from two `chore:` commits bringing the branch in line with Rust 1.96 clippy lints (`sort_by` → `sort_by_key`, redundant `.into_iter()` removal, import ordering). **These are toolchain-compat noise, not part of the GasFree feature**, and are omitted from the sections above.

---

## Test coverage summary

Coverage is dense and, notably, includes **live-network verification**, not just unit tests:

- **Pure-function/unit tests**, in `#[cfg(test)]` modules co-located with each source file: CREATE2 address derivation (8 vectors against the official GasFree JS SDK, all networks), TIP-712 domain-separator and PermitTransfer hashing (2 + 6 vectors, cross-checked independently), HMAC signing (known-vector), the full GasFree wire-schema protocol-conformance suite (malformed UUIDs, version drift, unknown enum states, hex edge cases — all deliberately rejected), the account preflight math (inactive-account/frozen-balance/pending-transfer/address-mismatch scenarios against mocks), and the new EIP-712 `bytes32` fix (including one hash independently verified via Python + `pycryptodome`).
- **Live integration tests against TRON's Nile testnet and a real GasFree provider account** (`mm2_main/tests/mm2_tests/tron_tests.rs`, ~513 new lines): full end-to-end gasless withdraw → send → poll-trace → confirm → balance-changed; separate build/submit; expired-deadline rejection; pending-transfer rejection (409) — serialized behind a shared mutex since these tests reuse one funded account and GasFree enforces one in-flight transfer per account. Native TRON withdraw tests continue to pass alongside these, which is the regression signal for the `f8cd326c2` fee-compatibility fix.
- **Gaps worth the KDF team's attention before relying on this in production** (collected from the notes above): no unit coverage for the trace-state-machine cross-product or the streamer's emission-suppression/error-backoff logic; no live-network or mocked-provider test for `account_status`'s own control flow (only its arithmetic is unit-tested); no dedicated test for `is_deterministic_gasless_unavailable`'s fallback allowlist; no browser-based (`wasm_bindgen_test`) coverage of the new WASM response-header/raw-bytes behavior specifically (validated so far only indirectly, through the GasFree path).

---

## Known follow-ups (tracked separately)

Two categories of further work are already documented elsewhere in this repo and intentionally **not** repeated in full here:

- **[`TRON_GASFREE_KDF_FOLLOWUPS.md`](./TRON_GASFREE_KDF_FOLLOWUPS.md)** — 10 prioritized items on top of this feature: a structured "did this gasless request silently fall back to native, and why" signal in the withdraw response (High); custody-balance shortfall reporting (High, partially addressed by §6's dedicated error variants); several already fixed in this session (`warn!` logging for enrollment gaps and passive re-enable, the `service_provider` auto-fetch); and two concrete proposals — multi-address (HD) custody support, and clamping never-used TRON HD addresses in storage.
- **[`TRON_GASFREE_PROXY_401.md`](./TRON_GASFREE_PROXY_401.md)** — covers the separate `komodo-defi-proxy` service (not this repo) that backs the `KomodoProxy` transport in §1/§3; out of scope for a KDF-core review but relevant if evaluating the proxy transport end-to-end.

---

## Suggested path to upstreaming

The branch's own commit history is already close to a reasonable PR-splitting boundary, since it was built incrementally layer-by-layer:

1. **Standalone, ship-regardless-of-GasFree fixes** (§4b, §8) — the EIP-712 `bytes32` correctness fix and the WASM HTTP header/body bugs. Small, self-contained, already tested, valuable independent of any TRON decision. Lowest-risk, highest-value first PR.
2. **Provider config & activation wiring** (§1) — establishes the config schema and the TRON-only gating pattern the rest depends on.
3. **Custody address derivation & response wiring** (§2) — the most invasive in terms of touching shared structs; worth a design conversation (see the coupling-cost note) before merging as-is versus adopting a cleaner extension mechanism first.
4. **GasFree client + TIP-712 signing** (§3, §4a) — self-contained, well-tested, no dependencies on the withdraw/RPC layers.
5. **Withdraw integration + broadcast/trace** (§6, §7) — the largest behavioral surface; recommend discussing the `fallback_to_native` observability gap (already tracked) alongside this PR rather than deferring it.
6. **Custody-first `account_status`** (§5) — newest and least battle-tested piece; consider landing after the others stabilize, and specifically after closing the account-status control-flow test gap noted above.

All file:line references throughout are against `feat/tron-gasfree` @ `d4fc1bd04` plus the uncommitted working-tree state as of 2026-07-02; re-verify line numbers if rebasing before use.
