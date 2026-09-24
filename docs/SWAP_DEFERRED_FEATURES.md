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
| **Revoke an approval** | The generic `approve_token` and `get_token_allowance` RPCs exist (`rpc/dispatcher/dispatcher.rs:256-257`), so approving zero is possible. There is no fee preview for that transaction. The prototype's revoke dialog promises "may cost up to $4.80", and that figure can't be computed. | A follow-up: read the allowance, estimate the gas for approving zero, then confirm with a real fee. The recovery copy already tells the user when an exact permission remains. |
| **Maximum network cost** | Routes carry estimates only (`gas_costs`, `total_gas_costs`). KDF bounds gas by its own safety limits at signing (contract l.380) but never reports a ceiling. | A ceiling in the contract. Until then the review shows "Network cost (estimate)". |
| **Timestamps for each step** | A history entry has `created_at`, `updated_at` and `finished_at` only (`routed_swap/history.rs:216-221`). The per-event log is internal. | Expose the event log in `routed_swap::history`. Today the timeline shows how far a swap got, not when each step happened. |
| **Action required** | `ActionRequired` is a dead-code variant kept only for wire compatibility (`routed_swap/types.rs:249-251`, enum at 244), and "`action_required` is not emitted in v1" (contract l.208). | Nothing. The UI already handles it: an "Action required" hero, a route-page button when `action_url` is present, a notice, and an Activity badge. |
| **Picking between routes** | "`routes` has exactly one entry in v1" (contract l.85). | Nothing yet. The options sheet already compares the cheapest and fastest orders and the atomic fill, so a longer `routes` list slots in. |
| **Route warnings** (low liquidity and similar) | Routes have no warnings or tags field (`routed_swap/types.rs`, `RoutedSwapRoute`). | A contract field. The review already warns when price impact reaches 5% or more, and when a price is missing. |
| **Editing slippage** | The request takes `slippage`, defaulting to 0.005 with a maximum of 0.5 (`types.rs:24-25`; contract l.45). | A UI decision, not a contract gap. v1 keeps the 0.5% default. The review shows it, along with the minimum it guarantees. |
| **Routed swaps in `my_recent_swaps`** | `swap_type: "routed" \| "all"` exists (contract l.373). | Not needed. Activity reads `routed_swap::history`, which the contract calls "the primary typed surface", and keeps atomic history on the legacy list, so no swap is listed twice. |
| **External wallet steps** (awaiting approval or signature) | `init` accepts internal signing (iguana and HD) and WalletConnect. It refuses Trezor and Metamask with `InvalidParam { param: "from" }` (`routed_swap/swap_task.rs:1854-1869`). The app already disables the Swap menu entry for hardware wallets, and it signs these swaps internally, so the prototype's approval and signature prompts never appear. | Trezor or Metamask support in the routed task, plus the prompt states from the prototype. |
| **A `/swap` route** | The app router serves `/dex`. `from_currency`, `to_currency`, `from_amount` and `order_type=maker` deep links work as before. | Router work, separate from this feature. |

## Interim: Max

The spec's Max option is still to come, so v1 has an interim version behind a single SDK entry point, `RoutedSwapManager.maxSellAmount`:

- **Selling a token:** Max uses the whole balance. The network fee is paid in the network's own coin.
- **Selling a network's own coin:** Max keeps back the native `total_gas_costs` from a probe quote, times 1.25. The form says how much was kept back.
- **Atomic swaps:** Max uses KDF's `max_taker_vol`, which already accounts for the trading and network fees.

When the spec adds Max, it replaces the probe inside `maxSellAmount`. The form does not change.

## Prototype adaptations

These choices are deliberate, and the reason for each follows it.

- **Mobile navigation is a row of tabs at the top.** The app already has a bottom navigation bar, and two would compete. The prototype's kebab menu is also dropped, since everything it held is in Activity or the evidence sheet.
- **"Maximum network cost" is shown as "Network cost (estimate)".** The contract has no ceiling to show (see the table above).
- **The "maximum-cost guard" is replaced by the minimum guard.** A swap stops before anything is sent if the latest price would pay less than the minimum the user agreed to. That is enforced by `init`'s `min_to_amount` and `QuoteWorsened`.
- **Provider names appear only in the legal consent line.** A wallet's first routed swap shows LI.FI's terms, because the contract requires it. Everywhere else a route is described by how it completes (direct exchange, same network, across networks). The provider and tool names go only into support diagnostics.
- **Addresses are read-only.** Both amount cards show the address used, and tapping it copies the full address. There is no Change button (see the recipient and HD address rows above).
- **Atomic swaps show one step for exchanging with the counterparty.** The atomic protocol has no bridge or conversion, so its timeline is prepare → send → exchange → receive.
- **The review opens in a side panel from 960 px of content width.** The prototype switches at a 1024 px viewport. The app's own menu takes part of the screen, so the breakpoint is measured on the swap area instead.
