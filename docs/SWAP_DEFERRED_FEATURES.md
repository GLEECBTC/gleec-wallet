# Unified swap — deferred features and prototype adaptations

The unified swap ships everything the routed-swap contract supports. This file covers what it does not ship. Some prototype features are missing because the contract does not support them yet. Others are deliberate adaptations.

Each claim below was checked against three sources:

- the routed-swap contract, `gleec-specs#2` at `0b209b2`;
- the KDF source at the pinned `feat/lifi-integration@4872ef2`;
- the SDK on the `add/routed-swap` branch.

KDF paths are relative to `mm2src/mm2_main/src/` unless a path says otherwise. Line numbers are at that commit.

## Deferred: not supported by the contract

| Feature | Evidence | What it would take |
|---|---|---|
| **Send to another recipient** | The quote request has no recipient field and uses `#[serde(deny_unknown_fields)]` (`routed_swap/types.rs:14-31`), so a `to_address` is rejected. `to_address` "always equals `from_address` in v1 (swaps send to self)" (`types.rs:65`). The spec's preflight binds a "self recipient unless a separately reviewed `to_address` feature is added" (contract l.380). | A reviewed KDF change to accept and bind a recipient. The UI would then need the prototype's recipient sheet and external-recipient confirmation. |
| **Choosing the HD source address** | KDF takes the source from `derivation_method().single_addr_or_err()` (`routed_swap/quote.rs:91-99`). For an HD wallet that is the globally enabled address (`coins/lp_coins.rs:4738-4750`). That address is an activation parameter (`path_to_address`, `coins/lp_coins.rs:535`), and no RPC changes it without re-activating. The spec says to "switch the coin's enabled address before quoting" (contract l.88). | Re-activating the coin with a different `path_to_address`. That moves every balance, order and atomic swap on that coin to the new address, so it needs its own design. It cannot sit behind a picker in the swap form. |
| **Mixed routes** (atomic and routed legs in one swap) | The contract prices "single best route" (contract l.13), and no RPC composes an atomic leg with a routed one. | A composition layer, in KDF or the SDK, that can hold and prove an intermediate holding between legs. |
| **Stop after the current step** | Cancelling works only while the execution gate is reversible. Once it is `Irreversible`, cancel returns `TaskAlreadyBroadcast` (`routed_swap/swap_task.rs:1974-1979`). No "finish this step, skip the rest" state exists. | A KDF execution gate between steps. |
| **Claim a refund** | LI.FI refunds itself; `refunded` means "funds returned on the source chain" (contract l.230). `BridgeFailed` means "direct user to the explorer link / support" (contract l.244). No claim RPC exists. | Nothing, unless a provider adds a claimable refund. The shipped recovery screen sends users to the evidence and support hand-off. |
| **Revoke an approval** | The generic `approve_token` and `get_token_allowance` RPCs exist (`rpc/dispatcher/dispatcher.rs:256-257`), so approving zero is possible, but nothing can price it first. `approve_token` signs and sends at once. Its gas limit comes from a live `eth_estimateGas` times the coin's `estimate_gas_mult` (`coins/eth.rs` `approve` → `sign_and_send_transaction` → `estimate_gas_for_contract_call_if_conf`), at KDF's own gas price. The estimator that could say it, `estimate_erc20_approval`, only reaches the wire inside a routed quote, for the provider's spender. The prototype's revoke dialog promises "may cost up to $4.80", and the wallet can't compute that figure. KDF changes are out of scope for this release (decided 2026-09-24), so revoke stays deferred. | A KDF RPC that estimates an approval without sending it. Then read the allowance and confirm the revoke with that real fee. The recovery copy already tells the user when an exact permission remains. |
| **Maximum network cost** | Routes carry estimates only (`gas_costs`, `total_gas_costs`). KDF bounds gas by its own safety limits at signing (contract l.380) but never reports a ceiling. | A ceiling in the contract. Until then the review shows "Network cost (estimate)". |
| **Timestamps for each step** | A history entry has `created_at`, `updated_at` and `finished_at` only (`routed_swap/history.rs:216-221`). The per-event log is internal. | Expose the event log in `routed_swap::history`. Today the timeline shows how far a swap got, not when each step happened. |
| **Action required** | `ActionRequired` is a dead-code variant kept only for wire compatibility (`routed_swap/types.rs:249-251`, enum at 244), and "`action_required` is not emitted in v1" (contract l.208). | Nothing. The UI already handles it: an "Action required" hero, a route-page button when `action_url` is present, a notice, and an Activity badge. |
| **Picking between routes** | "`routes` has exactly one entry in v1" (contract l.85). | Nothing yet. The options sheet already compares the cheapest and fastest orders and the atomic fill, so a longer `routes` list slots in. The fastest is priced only when the sheet opens, since each order is a separate provider request. |
| **Route warnings** (low liquidity and similar) | Routes have no warnings or tags field (`routed_swap/types.rs`, `RoutedSwapRoute`). | A contract field. The review already warns when price impact reaches 5% or more, and when a price is missing. |
| **Routed swaps in `my_recent_swaps`** | `swap_type: "routed" \| "all"` exists (contract l.373). | Not needed. Activity reads `routed_swap::history`, which the contract calls "the primary typed surface", and keeps atomic history on the legacy list, so no swap is listed twice. |
| **External wallet steps** (awaiting approval or signature) | `init` accepts internal signing (iguana and HD) and WalletConnect. It refuses Trezor and Metamask with `InvalidParam { param: "from" }` (`routed_swap/swap_task.rs:1854-1869`). The app already disables the Swap menu entry for hardware wallets, and it signs these swaps internally, so the prototype's approval and signature prompts never appear. | Trezor or Metamask support in the routed task, plus the prompt states from the prototype. |

## Interim: Max

The spec's Max option is still to come, so v1 has an interim version behind a single SDK entry point, `RoutedSwapManager.maxSellAmount`:

- **Selling a token:** Max uses the whole balance. The network fee is paid in the network's own coin.
- **Selling a network's own coin:** Max keeps back three times the native network fee of the route. The form says how much was kept back. The fee comes from a quote on the same pair in the last minute when there is one, and from a probe quote otherwise. The margin is large because `init` checks the balance against the route's gas limit at KDF's own maximum fee per gas (`check_balances` in `routed_swap/swap_task.rs`), which runs well above the provider's estimate. If that check still fails, nothing is sent and the result screen shows KDF's shortfall.
- **Atomic swaps:** Max uses KDF's `max_taker_vol`, which already accounts for the trading and network fees.

When the spec adds Max, it replaces this inside `maxSellAmount`, and the form does not change. A draft for the spec is kept outside the repos until it is agreed.

## Shipped from this list

- **Editing slippage.** The comparison sheet shows the allowance for cross-network routes and offers 0.5%, 1% or 2%, or a custom 0.05–5%. It warns above 1% and below 0.1%. A change prices every option again. It lasts for the session only.
- **A `/swap` route.** `/swap` opens the same surface as `/dex`, with the same deep-link parameters, and settles on `/dex`.

## KDF behaviour the wallet works around

KDF changes are out of scope for this release, so the wallet compensates for these. Each is worth raising with the KDF team for a later version.

| Behaviour | Effect without the workaround | What the wallet does |
|---|---|---|
| `routed_swap::quote` never checks the provider's chain list (`routed_swap/quote.rs` `resolve_routed_request`/`resolve_routed_coin`; only `supported_coins.rs` filters on it). | A pair on a chain the provider does not serve reaches the provider, which answers HTTP 400, code 1011. KDF maps that to `ProviderApiError`, and the form said "We couldn't check swap options" for GLEEC, GRC-20, KCC, ETC and others. | The swap catalog only asks a source that can price the pair. Anything else is answered locally, with the reason. |
| `supported_coins` lists activated coins only (contract l.298). | No way to tell whether an inactive asset is routable. | A bundled copy of the provider's EVM chain list (`routed_swap_chains.dart`) decides until the asset is active. |
| A token quote from an address without the network's own coin fails as `TransportError: Unable to estimate source-chain approval cost` (`routed_swap/quote.rs:334`). The approval estimate sends `eth_estimateGas` with a gas price, and nodes refuse it without funds for gas. It fails after the provider quote, so the request is spent. | A permanent condition reads as an outage, and each retry spends another request. | A token with none of its network's coin is stopped at the form with that reason. A routed service error on a token sale suggests checking that coin. |
| `init` reserves the route's gas limit at KDF's maximum fee (`check_balances`). The quote reports the provider's estimate. | A Max built on the quoted gas could fail at start. | Max keeps back three times the quoted gas. |
| Routed status is polled every 5 seconds per swap with no backoff (`routed_swap/swap_task.rs`, `resume.rs`). | About 12 provider calls a minute per bridging swap. Harmless without a key, because the per-address limit for status calls is 100 a minute. It matters once a shared-key proxy is in place. | Nothing yet; recorded for the proxy work. |
| On web, a provider error carries no `provider_request_id`. The provider's `x-lifi-requestid` header is not exposed to browsers (CORS). | Support diagnostics on web lack the provider's correlation id. | Nothing; the evidence still carries the swap's uuid and hashes. |
| `trade_preimage` refuses an amount above the balance with `NotSufficientBalance`, and it is the only source of an order-book swap's fees. | Nobody could see an order-book price for an asset they don't hold. | Above the balance, the order's price is shown without the preimage. Its costs read as incomplete and it is never ranked, and review stays closed until the amount fits the balance. |

## Phase 2 change points

Phase 2 (BTC as the source coin, and Tron) is KDF's to add (contract l.12). The provider already serves Solana, Bitcoin, Sui and Tron. These wallet and SDK parts assume EVM and must change with it:

- **Network names for route legs** (`lib/shared/swap/swap_networks.dart`). Legs are named from EVM chain ids only (`networkOfEvmChain`, and `evmChainIdOf` checks an EVM subclass list). A non-EVM leg falls back to the route's source or destination network name, so a hop through Bitcoin or Tron would be mislabelled.
- **Which assets are routable before activation** (`lib/shared/swap/routed_swap_chains.dart`). The bundled list is `chainTypes=EVM`, keyed by integer chain id.
- **Chain ids are integers** (`RoutedSwapSupportedCoin.chainId` in the SDK). An entry with another chain id is skipped and logged rather than failing the whole list, so a Phase 2 coin disappears quietly until the SDK models it.
- **One source address per asset** (`SwapServices.addressOf`, KDF's `single_addr_or_err`). A UTXO source can spend from many addresses of an HD account, and the form, Max and the review all assume one.
- **Max's native-gas rule** (`RoutedSwapManager.maxSellAmount`, `RoutedSwapQuoteSource._nativeMax`). It assumes the fee is paid in the sold coin at EVM gas prices. UTXO fees depend on the inputs spent, and Tron has energy, bandwidth and gas-free transfers.
- **Fees in the network's own coin** (`SwapFormIssue.noFeeBalance`). This is true for EVM tokens. A Tron token may pay with energy, or through GasFree.
- **Exact approvals and zero-reset** (the approve stages in `routed_swap_source.dart`, and the review's permission copy). These are ERC-20 concepts. A BTC source needs none, and Tron's TRC-20 approvals differ.

## Prototype adaptations

These choices are deliberate, and the reason for each follows it.

- **Mobile navigation is a row of tabs at the top.** The app already has a bottom navigation bar, and two would compete. The prototype's kebab menu is also dropped, since everything it held is in Activity or the evidence sheet.
- **"Maximum network cost" is shown as "Network cost (estimate)".** The contract has no ceiling to show (see the table above).
- **The "maximum-cost guard" is replaced by the minimum guard.** A swap stops before anything is sent if the latest price would pay less than the minimum the user agreed to. That is enforced by `init`'s `min_to_amount` and `QuoteWorsened`.
- **Provider names appear only in the legal consent line.** A wallet's first routed swap shows LI.FI's terms, because the contract requires it. Everywhere else a route is described by how it completes (direct exchange, same network, across networks). The provider and tool names go only into support diagnostics.
- **Addresses are read-only.** Both amount cards show the address used, and tapping it copies the full address. There is no Change button (see the recipient and HD address rows above).
- **Atomic swaps show one step for exchanging with the counterparty.** The atomic protocol has no bridge or conversion, so its timeline is prepare → send → exchange → receive.
- **The review opens in a side panel from 960 px of content width.** The prototype switches at a 1024 px viewport. The app's own menu takes part of the screen, so the breakpoint is measured on the swap area instead.
