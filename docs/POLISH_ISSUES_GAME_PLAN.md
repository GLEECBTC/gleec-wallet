# App Polish Issue Game Plan

_Reviewed 159 open issues._

_Review update (February 9, 2026): Statuses below were re-validated against the current workspace implementation; checkbox states now mirror implementation status (`[x]` for Done), and several items were reclassified based on code evidence. Follow-up fixes were applied for high-risk regressions in swap history, transaction ordering, private key visibility controls, ARRR cancel flow, and mobile tab/address dialogs._

## RPC efficiency plan (implemented)
- Goal: reduce avoidable RPC volume in app + SDK without slowing UX-critical paths.
- Scope date: February 12, 2026.

### Phase 1: stream-first updates with polling fallback
- [x] Expose managed stream subscriptions in SDK for `orderbook`, `swap_status`, and `order_status`.
- [x] Convert orderbook refresh flow to stream-first with stale-guard fallback polling.
- [x] Replace 1-second trading details polling with stream-triggered updates and slower fallback polling.

### Phase 2: request deduping and payload shaping
- [x] Add short-lived in-flight/result cache for `trade_preimage`, `max_taker_vol`, `max_maker_vol`, and `min_trading_vol`.
- [x] Reduce recurring `my_recent_swaps` payload pressure by using smaller periodic limits and merged incremental state.
- [x] Add adaptive swaps/orders polling cadence when user is outside DEX/Bridge routes.

### Phase 3: bridge/balance validation and fallback hardening
- [x] Add bridge orderbook depth request cache + in-flight dedupe and reduce retry fan-out pressure.
- [x] Add taker preimage cache parity with bridge validator.
- [x] Keep minute-level balance sweeping as fallback only when real-time balance watchers are unavailable.

### Verification checklist
- [ ] Confirm no visible regression in orderbook responsiveness on DEX.
- [ ] Confirm swap/order details update immediately on stream events and still recover via fallback polling.
- [ ] Confirm reduced RPC traffic for repeated fee/volume requests during rapid form edits.
- [ ] Confirm balance updates still propagate for both streaming and non-streaming assets.

## Scope and selection
Included issues that directly affect UI/UX polish (layout, styling, copy, error messaging, perceived performance, and small workflow improvements). Excluded build/release/infra work and major product features that materially expand scope (for example: Payment Requests, Coin Control, Expanded Import Types). Items marked as awaiting design or awaiting API are noted.

## Prioritization approach
- P0/P1 polish blockers: address first to eliminate confusing states, incorrect UI data, and disruptive modal behavior.
- P2/P3: batch by theme (layout, messaging, responsiveness) to minimize UI churn and QA overhead.
- Dependencies: keep design and API-bound items moving in parallel so fixes can land quickly when ready.

## Status legend
- Done (verified in codebase): Evidence found in the current codebase.
- Partially addressed (needs verification): Evidence found, but coverage is incomplete or needs QA.
- Not found in codebase: No evidence found in the current codebase; needs verification.
- Blocked (design): Waiting on design guidance.
- Blocked (API): Waiting on API support.

## Out of scope (not polish)
Examples reviewed but excluded due to feature scope or backend dependency: #2518 (Payment Requests), #2487 (Coin control), #3077 (Expanded wallet import types), #3072 (WIF/private key import), #2717 (Legacy desktop wallet migration).

## Visual and layout consistency

- [x] [#3368](https://github.com/GLEECBTC/gleec-wallet/issues/3368) Mobile Keys display layout needs better alignment
  - Status: Done (verified in codebase)
  - Details: Mobile security key rows now use aligned label/value columns with fixed label width and responsive wrapping.
  - Evidence: `lib/views/wallet/wallet_page/common/expandable_private_key_list.dart`.

- [x] [#3367](https://github.com/GLEECBTC/gleec-wallet/issues/3367) Mobile coin addresses layout overflow
  - Status: Done (verified in codebase)
  - Details: Mobile address rows now truncate safely, wrap action buttons, and provide a full-address dialog fallback.
  - Evidence: `lib/views/wallet/coin_details/coin_details_info/coin_addresses.dart`.

- [x] [#3366](https://github.com/GLEECBTC/gleec-wallet/issues/3366) Mobile keyboard blocks coin activation view
  - Status: Done (verified in codebase)
  - Details: Keyboard covers activation list and invites misclicks on mobile.
  - Plan: Add keyboard-aware padding and scrollability; reposition or minimize the custom token CTA while typing.

- [x] [#3365](https://github.com/GLEECBTC/gleec-wallet/issues/3365) Design required for swap export in mobile swaps/orders/history list views
  - Status: Done (verified in codebase)
  - Details: Mobile swap rows now expose copy UUID/export actions through a compact per-row overflow menu with loading feedback.
  - Evidence: `lib/views/dex/entities_list/common/swap_actions_menu.dart`, `lib/views/dex/entities_list/history/history_item.dart`, `lib/views/dex/entities_list/in_progress/in_progress_item.dart`.

- [x] [#3322](https://github.com/GLEECBTC/gleec-wallet/issues/3322) Swap coin selection dropdown alignment and text overflow on mobile
  - Status: Done (verified in codebase)
  - Details: Dropdown rows misalign and long names/balances overflow.
  - Plan: Standardize row layout (icon/name/balance columns), use ellipsis, tighten padding.

- [x] [#3299](https://github.com/GLEECBTC/gleec-wallet/issues/3299) Swap page tabs shoehorned on mobile
  - Status: Done (verified in codebase)
  - Details: Tabs and overflow behavior are mobile-safe, and hidden-tab selected state now remains correct.
  - Plan: Use scrollable tabs or a "more" menu; move destructive actions into overflow.

- [x] [#3337](https://github.com/GLEECBTC/gleec-wallet/issues/3337) Coin page UX enhancements
  - Status: Done (verified in codebase)
  - Details: HD address list pushes transaction history out of view.
  - Plan: Collapse/limit address list by default; add section toggles or tabs to keep history visible.

- [x] [#3218](https://github.com/GLEECBTC/gleec-wallet/issues/3218) No padding in swap details status view
  - Status: Done (verified in codebase)
  - Details: Icons and values touch each other; lacks whitespace.
  - Plan: Add padding and spacing between icons/values; verify on narrow widths.

- [x] [#3212](https://github.com/GLEECBTC/gleec-wallet/issues/3212) Makerbot in mobile lacks important elements present in web/desktop
  - Status: Done (verified in codebase)
  - Details: Mobile Makerbot flow now includes key desktop parity controls and responsive sectioning.
  - Evidence: `lib/views/market_maker_bot/market_maker_bot_tab_content_wrapper.dart`, `lib/views/market_maker_bot/market_maker_bot_form.dart`, `lib/views/market_maker_bot/market_maker_bot_form_content.dart`.

- [x] [#3183](https://github.com/GLEECBTC/gleec-wallet/issues/3183) Memo input punctuation renders strangely
  - Status: Done (verified in codebase)
  - Details: Punctuation glyphs render incorrectly (likely font fallback).
  - Plan: Ensure memo input uses a font with full punctuation glyphs; validate on Linux.

- [x] [#3157](https://github.com/GLEECBTC/gleec-wallet/issues/3157) Button text overflow in DEX when blocked
  - Status: Done (verified in codebase)
  - Details: Error text overflows the DEX action button in blocked regions.
  - Plan: Allow text wrap or shrink; add max lines and ensure readability.

- [x] [#3147](https://github.com/GLEECBTC/gleec-wallet/issues/3147) UI: Statistics coin list text color ignores theme (unreadable)
  - Status: Done (verified in codebase)
  - Details: Text color does not match theme, causing low contrast.
  - Plan: Replace hard-coded colors with theme tokens; run contrast checks.

- [x] [#3136](https://github.com/GLEECBTC/gleec-wallet/issues/3136) Full address display UI issue
  - Status: Done (verified in codebase)
  - Details: Full-address dialog is available and constrained responsively to avoid narrow-screen overflow.
  - Plan: Add a "show full address" modal or expandable row with copy action.

- [x] [#3135](https://github.com/GLEECBTC/gleec-wallet/issues/3135) Improve wallet coin display layout & fix fiat price update delays
  - Status: Done (verified in codebase)
  - Details: Balance layout is hard to scan on mobile; fiat updates lag.
  - Plan: Reflow layout for hierarchy/alignment and ensure fiat updates are pushed to the UI promptly.

- [x] [#3096](https://github.com/GLEECBTC/gleec-wallet/issues/3096) UX: Asset selector styling and dark mode polish
  - Status: Done (verified in codebase)
  - Details: Asset selector styling/contrast diverges from design system.
  - Plan: Apply design tokens for backgrounds/borders/text and fix dark mode states.

- [x] [#3093](https://github.com/GLEECBTC/gleec-wallet/issues/3093) UX: Logout dropdown positioning across resolutions
  - Status: Done (verified in codebase)
  - Details: Dropdown is clipped or misplaced on resize/scroll.
  - Plan: Anchor overlay to the trigger and clamp to viewport bounds on resize.

- [x] [#3076](https://github.com/GLEECBTC/gleec-wallet/issues/3076) App-wide viewport audit and mobile adaptiveness
  - Status: Done (verified in codebase)
  - Details: Core app shells and primary navigation now apply responsive constraints/padding for narrow viewports.
  - Evidence: `lib/views/common/pages/page_layout.dart`, `lib/router/navigators/main_layout/main_layout_router_delegate.dart`, `lib/views/main_layout/widgets/main_layout_top_bar.dart`, `lib/views/common/main_menu/main_menu_bar_mobile.dart`.

- [x] [#3075](https://github.com/GLEECBTC/gleec-wallet/issues/3075) Coin details layout optimization and persistent scrollbars
  - Status: Done (verified in codebase)
  - Details: Transaction history moved above addresses on desktop, charts reduced in height, and scrollbars are now persistently visible.
  - Plan: Reorder sections, increase above-the-fold density, and enable persistent scrollbars.

- [x] [#3057](https://github.com/GLEECBTC/gleec-wallet/issues/3057) NFT network icons are green
  - Status: Done (verified in codebase)
  - Details: Icons appear with incorrect green tint.
  - Plan: Fix icon assets or tint logic; ensure theme-driven colors.

- [x] [#3025](https://github.com/GLEECBTC/gleec-wallet/issues/3025) Tendermint HD privkey output extends beyond singleaddress
  - Status: Done (verified in codebase)
  - Details: Privkey display overflows; Tendermint is single-address.
  - Plan: Restrict output to index 0 and update layout to prevent overflow.

- [x] [#3022](https://github.com/GLEECBTC/gleec-wallet/issues/3022) fix(ui): Review and replace hard-coded style values
  - Status: Done (verified in codebase)
  - Details: Targeted hard-coded style values were replaced with theme-driven tokens/components in high-impact UI paths.
  - Evidence: `packages/komodo_ui_kit/lib/src/buttons/ui_primary_button.dart`, `lib/shared/widgets/coin_select_item_widget.dart`, `lib/views/main_layout/widgets/main_layout_top_bar.dart`.

- [x] [#2980](https://github.com/GLEECBTC/gleec-wallet/issues/2980) fix(ui): Align address list columns
  - Status: Done (verified in codebase)
  - Details: Address list needs column alignment for readability.
  - Plan: Use table-like layout with fixed label columns and flexible values.

- [x] [#2942](https://github.com/GLEECBTC/gleec-wallet/issues/2942) Duplicated "add assets" button
  - Status: Done (verified in codebase)
  - Details: Duplicate CTAs on portfolio page.
  - Plan: Remove redundant CTA and keep a single primary action.

- [x] [#2941](https://github.com/GLEECBTC/gleec-wallet/issues/2941) Elements without theme applied need fixing
  - Status: Done (verified in codebase)
  - Details: Previously non-themed text/components in wallet/topbar/address flows now bind to active theme colors and typography.
  - Evidence: `lib/shared/widgets/coin_select_item_widget.dart`, `lib/views/wallet/coin_details/coin_details_info/coin_addresses.dart`, `lib/views/main_layout/widgets/main_layout_top_bar.dart`.

- [x] [#2936](https://github.com/GLEECBTC/gleec-wallet/issues/2936) Inconsistent toggle component styles
  - Status: Done (verified in codebase)
  - Details: Toggle usage was consolidated to shared switcher components in coins manager and withdraw custom-fee flows.
  - Evidence: `lib/views/wallet/coins_manager/coins_manager_list_item.dart`, `lib/views/wallet/coin_details/withdraw_form/widgets/fill_form/fields/fields.dart`.

- [x] [#2763](https://github.com/GLEECBTC/gleec-wallet/issues/2763) Move log out button into sidebar
  - Status: Done (verified in codebase)
  - Details: Logout button breaks on resize; sidebar is stable.
  - Plan: Relocate to sidebar and remove top-right button variant.

- [x] [#2762](https://github.com/GLEECBTC/gleec-wallet/issues/2762) Ludicrous digits on first chart loading
  - Status: Done (verified in codebase)
  - Details: Charts show absurd values before data settles.
  - Plan: Delay rendering until data is valid; clamp/format values during load.

- [x] [#2741](https://github.com/GLEECBTC/gleec-wallet/issues/2741) The Address Dropdown remains stuck on the screen on scrolling the page
  - Status: Done (verified in codebase)
  - Details: Dropdown overlay does not scroll/dismiss.
  - Plan: Close overlay on scroll and anchor overlay to scrolling container.

- [x] [#2722](https://github.com/GLEECBTC/gleec-wallet/issues/2722) Restore scrollbars
  - Status: Done (verified in codebase)
  - Details: Persistent scrollbars restored via DexScrollbar updates across scrollable views.
  - Plan: Re-enable persistent scrollbars on long pages.

- [x] [#2564](https://github.com/GLEECBTC/gleec-wallet/issues/2564) Log Out Button Shifts When Window is Resized
  - Status: Done (verified in codebase)
  - Details: Logout button moves out of view when resizing.
  - Plan: Apply responsive constraints and anchor to consistent layout regions.

- [x] [#2489](https://github.com/GLEECBTC/gleec-wallet/issues/2489) Allow scrolling of wallet screen from gap in the left part
  - Status: Done (verified in codebase)
  - Details: Scroll hit-testing now covers empty padding/left gap on desktop.
  - Plan: Extend scroll hit-testing to padding regions for consistent behavior.

- [x] [#3273](https://github.com/GLEECBTC/gleec-wallet/issues/3273) Improved animation while waiting for faucet
  - Status: Done (verified in codebase)
  - Details: Faucet wait state now shows animated progress dots with contextual text instead of a generic spinner.
  - Evidence: `lib/views/wallet/coin_details/faucet/faucet_view.dart`.

- [x] [#2599](https://github.com/GLEECBTC/gleec-wallet/issues/2599) Review app text elements for typography best practices
  - Status: Done (verified in codebase)
  - Details: High-traffic wallet, address, and topbar views now consistently use theme typography and improved hierarchy spacing.
  - Evidence: `lib/views/wallet/coin_details/coin_details_info/coin_addresses.dart`, `lib/views/main_layout/widgets/main_layout_top_bar.dart`, `lib/shared/widgets/coin_select_item_widget.dart`.

- [x] [#2944](https://github.com/GLEECBTC/gleec-wallet/issues/2944) Added copy buttons for commit hash etc in settings page
  - Status: Done (verified in codebase)
  - Details: Copying build metadata is cumbersome.
  - Plan: Add copy buttons with feedback (snackbar/toast).

- [x] [#2958](https://github.com/GLEECBTC/gleec-wallet/issues/2958) Inconsistencies in Buy/Sell tab
  - Status: Done (verified in codebase)
  - Details: Buy/Sell selection handling was stabilized to prevent unintended resets during dependent updates.
  - Evidence: `lib/views/market_maker_bot/market_maker_bot_form_content.dart`.

- [x] [#2987](https://github.com/GLEECBTC/gleec-wallet/issues/2987) Pin parents to top of coins lists
  - Status: Done (verified in codebase)
  - Details: Parent assets are buried in lists, reducing discoverability.
  - Plan: Pin parent rows above token children; keep search/filters consistent.

- [x] [#2601](https://github.com/GLEECBTC/gleec-wallet/issues/2601) Sortable table columns
  - Status: Done (verified in codebase)
  - Details: Portfolio/swap list headers now support deterministic column sorting behavior.
  - Evidence: `lib/views/wallet/coins_manager/coins_manager_list_header.dart`, `lib/views/dex/entities_list/history/swap_history_sort_mixin.dart`.

- [x] [#2803](https://github.com/GLEECBTC/gleec-wallet/issues/2803) Include extended app metadata in settings
  - Status: Done (verified in codebase)
  - Details: Missing build/version info hinders support.
  - Plan: Add metadata section with version, commit hash, build date, and copy actions.

- [x] [#2546](https://github.com/GLEECBTC/gleec-wallet/issues/2546) FR: Hide balances toggle (stealth mode)
  - Status: Done (verified in codebase)
  - Details: A persisted settings toggle now masks wallet balances and fiat values in primary balance surfaces.
  - Evidence: `lib/views/settings/widgets/general_settings/settings_hide_balances.dart`, `lib/bloc/settings/settings_bloc.dart`, `lib/model/stored_settings.dart`, `lib/shared/widgets/coin_balance.dart`, `lib/shared/widgets/coin_fiat_balance.dart`.

- [x] [#3097](https://github.com/GLEECBTC/gleec-wallet/issues/3097) UX: Wallet price tap opens charts (shortcut)
  - Status: Done (verified in codebase)
  - Details: Shortcut requested to open charts from price tap.
  - Plan: Add tap target on price, ensure it does not conflict with existing actions.

- [x] [#3346](https://github.com/GLEECBTC/gleec-wallet/issues/3346) Mention trezor supports just wallet mode currently
  - Status: Done (verified in codebase)
  - Details: Disabled tabs need a clear reason for Trezor mode.
  - Plan: Add tooltip on disabled tabs and helper text in the connect screen.

## Loading, data refresh, and responsiveness

- [x] [#3378](https://github.com/GLEECBTC/gleec-wallet/issues/3378) Slow display without spinner for long swap history
  - Status: Done (verified in codebase)
  - Details: History view now shows a loading state correctly, including initial empty-stream emissions.
  - Plan: Add loading indicator or skeleton; keep previous data during fetch.

- [x] [#3373](https://github.com/GLEECBTC/gleec-wallet/issues/3373) Represent the swap data from kdf accurately in the UI
  - Status: Done (verified in codebase)
  - Details: Swap model mapping now prefers fraction fields for amount accuracy and respects KDF `recoverable` state.
  - Evidence: `lib/model/swap.dart`.

- [x] [#3364](https://github.com/GLEECBTC/gleec-wallet/issues/3364) EVM tx history does not update until navigation
  - Status: Done (verified in codebase)
  - Details: New txs appear only after navigating away and back.
  - Plan: Trigger refresh on broadcast completion and update list in place.

- [x] [#3360](https://github.com/GLEECBTC/gleec-wallet/issues/3360) Unconfirmed transactions amount appears as zero until navigation
  - Status: Done (verified in codebase)
  - Details: Unconfirmed rows show 0 amount until a navigation refresh.
  - Plan: Use tx amount data immediately and update state on status change.

- [x] [#3359](https://github.com/GLEECBTC/gleec-wallet/issues/3359) Duplicated/incorrect tx data for ATOM
  - Status: Done (verified in codebase)
  - Details: ATOM history shows duplicate or incorrect entries.
  - Plan: Deduplicate by hash and verify mapping for internal/external txs.

- [x] [#3211](https://github.com/GLEECBTC/gleec-wallet/issues/3211) Slow address loading on tab change delays user action
  - Status: Done (verified in codebase)
  - Details: Address loading uses cached results and pubkey prefetching to reduce tab-switch latency.
  - Evidence: `lib/bloc/coin_addresses/bloc/coin_addresses_bloc.dart`.

- [x] [#2593](https://github.com/GLEECBTC/gleec-wallet/issues/2593) HD address list underpopulated after import
  - Status: Done (verified in codebase)
  - Details: HD pubkey refresh now runs a one-time `scan_for_new_addresses` task per wallet/asset before fetching balances, improving first-load address discovery for imported wallets.
  - Evidence: `sdk/packages/komodo_defi_rpc_methods/lib/src/strategies/pubkey/hd_multi_address_strategy.dart`, `sdk/packages/komodo_defi_rpc_methods/lib/src/rpc_methods/hd_wallet/scan_for_new_addresses_status.dart`, `sdk/packages/komodo_defi_sdk/lib/src/pubkeys/pubkey_manager.dart`.

- [x] [#3094](https://github.com/GLEECBTC/gleec-wallet/issues/3094) UX/Perf: Reduce wallet page jank during coin activation
  - Status: Done (verified in codebase)
  - Details: Activation flow now pre-seeds activating coins and reduces heavy synchronous refresh behavior.
  - Evidence: `lib/bloc/coins_bloc/coins_bloc.dart`.

- [x] [#3073](https://github.com/GLEECBTC/gleec-wallet/issues/3073) Balances: avoid transient zeroes while loading
  - Status: Done (verified in codebase)
  - Details: Temporary zero values confuse users during load.
  - Plan: Use skeletons/placeholders and transition directly to real values.

- [x] [#3121](https://github.com/GLEECBTC/gleec-wallet/issues/3121) Refresh transactions list after broadcast
  - Status: Done (verified in codebase)
  - Details: Tx list and balances do not update post-broadcast.
  - Plan: Trigger a delayed refresh after broadcast success and update cached data.

- [x] [#3302](https://github.com/GLEECBTC/gleec-wallet/issues/3302) Premature Swap page entry prompts competing activations
  - Status: Done (verified in codebase)
  - Details: Multiple activation triggers compete and fail.
  - Plan: Debounce activation requests and ensure a single activation per coin.

- [x] [#3229](https://github.com/GLEECBTC/gleec-wallet/issues/3229) Review of wasm-bindgen errors and impact on UI responsivity
  - Status: Done (verified in codebase)
  - Details: Web RPC calls now guard parse/transport failures and return bounded fallback error payloads to keep UI responsive.
  - Evidence: `lib/mm2/rpc_web.dart`.

- [x] [#2761](https://github.com/GLEECBTC/gleec-wallet/issues/2761) Avoid fruitless activation fail loops
  - Status: Done (verified in codebase)
  - Details: ARRR activation retries were narrowed to retryable errors and now honor explicit cancel flow.
  - Evidence: `lib/services/arrr_activation/arrr_activation_service.dart`.

- [x] [#3001](https://github.com/GLEECBTC/gleec-wallet/issues/3001) False "unrecoverable" failed swaps
  - Status: Done (verified in codebase)
  - Details: Failed swap UI now uses KDF `recoverable` state and avoids false unrecoverable labeling.
  - Evidence: `lib/model/swap.dart`, `lib/views/dex/entities_list/history/history_item.dart`.

- [x] [#2986](https://github.com/GLEECBTC/gleec-wallet/issues/2986) Misc unhandled errors in web console
  - Status: Done (verified in codebase)
  - Details: Web RPC and error parsing paths now handle malformed responses defensively to prevent noisy unhandled console errors.
  - Evidence: `lib/mm2/rpc_web.dart`, `lib/mm2/mm2_api/rpc/rpc_error.dart`.

## Error messaging and validation

- [x] [#3357](https://github.com/GLEECBTC/gleec-wallet/issues/3357) EVM send max error on HD
  - Status: Done (verified in codebase)
  - Details: Send-max fails when parent gas balance is missing.
  - Plan: Detect missing gas, show clear message, and disable max when invalid.

- [x] [#3356](https://github.com/GLEECBTC/gleec-wallet/issues/3356) [SDK] Implement Localised, Actionable Error Messaging System
  - Status: Done (verified in codebase)
  - Details: Error display normalization now maps common KDF error families to localized, actionable messages.
  - Evidence: `lib/shared/utils/kdf_error_display.dart`, `lib/bloc/withdraw_form/withdraw_form_bloc.dart`.

- [x] [#3292](https://github.com/GLEECBTC/gleec-wallet/issues/3292) Ambiguous error on connection fail
  - Status: Done (verified in codebase)
  - Details: "NoSuchCoin" hides real connection failures.
  - Plan: Map connection errors to user-friendly text and recovery steps.

- [x] [#3151](https://github.com/GLEECBTC/gleec-wallet/issues/3151) Add password length overflow error messaging
  - Status: Done (verified in codebase)
  - Details: Passwords over 128 chars get no warning.
  - Plan: Add inline validation and explain the length limit.

- [x] [#3081](https://github.com/GLEECBTC/gleec-wallet/issues/3081) Insufficient-gas and common errors: user-friendly messages
  - Status: Done (verified in codebase)
  - Details: Withdraw errors now normalize insufficient gas/fee and related transport errors into clearer user guidance.
  - Evidence: `lib/bloc/withdraw_form/withdraw_form_bloc.dart`.

- [x] [#2884](https://github.com/GLEECBTC/gleec-wallet/issues/2884) Trezor: `User cancelled action` shows as "something went wrong"
  - Status: Done (verified in codebase)
  - Details: User-cancel is treated as a generic error.
  - Plan: Map to a specific cancellation message.

- [x] [#2881](https://github.com/GLEECBTC/gleec-wallet/issues/2881) Improve Trezor PIN error message
  - Status: Done (verified in codebase)
  - Details: PIN error message is unclear.
  - Plan: Use explicit Invalid PIN messaging and guidance.

- [x] [#2766](https://github.com/GLEECBTC/gleec-wallet/issues/2766) Trezor hidden wallet passphrase should be non-empty
  - Status: Done (verified in codebase)
  - Details: Hidden wallet can be entered without a passphrase.
  - Plan: Require a non-empty passphrase before continuing.

- [x] [#2996](https://github.com/GLEECBTC/gleec-wallet/issues/2996) Custom fee input has misleading `$` prefix, bad defaults
  - Status: Done (verified in codebase)
  - Details: Custom fee inputs now use chain-appropriate units/defaults and no longer present misleading dollar-style prefixes.
  - Evidence: `lib/bloc/withdraw_form/withdraw_form_bloc.dart`, `sdk/packages/komodo_ui/lib/src/core/inputs/fee_info_input.dart`.

- [x] [#3331](https://github.com/GLEECBTC/gleec-wallet/issues/3331) Coin failing activation listed on portfolio page
  - Status: Done (verified in codebase)
  - Details: Active coins list now filters out inactive/suspended assets, so failed activations no longer appear as active.
  - Plan: Remove from active list or mark as failed with retry CTA.

- [x] [#2950](https://github.com/GLEECBTC/gleec-wallet/issues/2950) Coin wallet in failed activation state has active buttons
  - Status: Done (verified in codebase)
  - Details: Coin detail action buttons now disable correctly when activation has not succeeded.
  - Evidence: `lib/views/wallet/coin_details/coin_details_info/coin_details_common_buttons.dart`.

- [x] [#2801](https://github.com/GLEECBTC/gleec-wallet/issues/2801) Transaction modal has misleading confirmations
  - Status: Done (verified in codebase)
  - Details: Transaction detail modal now labels unknown confirmation/block-height values safely instead of implying finality.
  - Evidence: `lib/views/wallet/coin_details/transactions/transaction_details.dart`.

- [x] [#3303](https://github.com/GLEECBTC/gleec-wallet/issues/3303) [ux] Toggle visibility of seed / pw
  - Status: Done (verified in codebase)
  - Details: Sensitive key actions remain gated by explicit visibility controls.
  - Plan: Keep visible until user toggles off; add an explicit hide control.

- [x] [#3024](https://github.com/GLEECBTC/gleec-wallet/issues/3024) Enhancement: Granular privkey visibility toggle
  - Status: Done (verified in codebase)
  - Details: Per-key visibility exists and private-key copy/QR actions now respect the visibility gate.
  - Plan: Add per-row toggle with masked default and audit logging.

- [x] [#2985](https://github.com/GLEECBTC/gleec-wallet/issues/2985) Inactive coin remains on main wallet view appearing active
  - Status: Done (verified in codebase)
  - Details: Active coins list now filters out inactive/suspended assets to prevent stale entries.
  - Plan: Update state handling to mark inactive and remove from active list.

- [x] [#2994](https://github.com/GLEECBTC/gleec-wallet/issues/2994) Default enabled coins can't be disabled
  - Status: Done (verified in codebase)
  - Details: Disabled coins re-enable on re-login.
  - Plan: Persist disabled state in wallet preferences and apply on load.

- [x] [#3282](https://github.com/GLEECBTC/gleec-wallet/issues/3282) Cancel config for ARRR activation leaves toggle active
  - Status: Done (verified in codebase)
  - Details: User-cancelled ARRR configuration now rolls back toggle/selection state without surfacing a suspended failure state.
  - Plan: Roll back UI state when cancel occurs and sync with activation state.

## Workflow and interaction polish

- [x] [#3397](https://github.com/GLEECBTC/gleec-wallet/issues/3397) Mobile orientation change dismisses modals
  - Status: Done (verified in codebase)
  - Details: Dialog presentation now consistently uses root navigator + guarded close flow to avoid unintended dismiss during orientation/layout churn.
  - Evidence: `lib/shared/widgets/app_dialog.dart`, `lib/shared/widgets/connect_wallet/connect_wallet_button.dart`.

- [x] [#3340](https://github.com/GLEECBTC/gleec-wallet/issues/3340) Login popups sometimes show when they shouldnt
  - Status: Done (verified in codebase)
  - Details: Login popup triggers now include stronger session/auth guards and non-dismissible modal handling in connect flow.
  - Evidence: `lib/shared/widgets/connect_wallet/connect_wallet_button.dart`, `lib/shared/widgets/remember_wallet_service.dart`.

- [x] [#3231](https://github.com/GLEECBTC/gleec-wallet/issues/3231) Don't dismiss login/import modal for out of bound touch events
  - Status: Done (verified in codebase)
  - Details: Tapping outside modal discards user input.
  - Plan: Disable barrier dismiss and add explicit cancel/back actions.

- [x] [#3277](https://github.com/GLEECBTC/gleec-wallet/issues/3277) Makerbot sell list only contains activated coins
  - Status: Done (verified in codebase)
  - Details: Sell list excludes inactive coins, reducing discovery.
  - Plan: Show all coins with activation status or prompt to activate on select.

- [x] [#2497](https://github.com/GLEECBTC/gleec-wallet/issues/2497) Expose bot configuration options in settings
  - Status: Done (verified in codebase)
  - Details: Market maker trade configuration now exposes broader stale-price validity interval choices and persists selected interval per pair.
  - Evidence: `lib/views/market_maker_bot/update_interval_dropdown.dart`, `lib/views/market_maker_bot/trade_bot_update_interval.dart`, `lib/bloc/market_maker_bot/market_maker_trade_form/market_maker_trade_form_state.dart`.

- [x] [#2504](https://github.com/GLEECBTC/gleec-wallet/issues/2504) Export/import maker orders
  - Status: Done (verified in codebase)
  - Details: Trading-bot settings now include maker-order export/import actions and a persisted `Save orders` toggle; when disabled, stored maker-order configs are cleared on next app launch.
  - Evidence: `lib/views/settings/widgets/general_settings/settings_manage_trading_bot.dart`, `lib/model/settings/market_maker_bot_settings.dart`, `lib/services/initializer/app_bootstrapper.dart`, `assets/translations/en.json`.

- [x] [#3217](https://github.com/GLEECBTC/gleec-wallet/issues/3217) Bot order details view does not persist upon price adjustment loop
  - Status: Done (verified in codebase)
  - Details: Order details now track refreshed bot orders to avoid resets on price updates.
  - Plan: Preserve selected order state across refresh updates.

- [x] [#3178](https://github.com/GLEECBTC/gleec-wallet/issues/3178) Add cancel button in activation ARRR progress pane
  - Status: Done (verified in codebase)
  - Details: ARRR activation status pane includes a cancel action wired to a real cancellation path in the activation service.
  - Evidence: `lib/views/wallet/wallet_page/common/zhtlc/zhtlc_activation_status_bar.dart`, `lib/services/arrr_activation/arrr_activation_service.dart`.

- [x] [#3095](https://github.com/GLEECBTC/gleec-wallet/issues/3095) UX: Wallet name validation and rename-on-import
  - Status: Done (verified in codebase)
  - Details: Wallet naming lacks validation and rename during import.
  - Plan: Add inline validation and allow renaming in the import flow.

- [x] [#3089](https://github.com/GLEECBTC/gleec-wallet/issues/3089) UX: Persist HD mode across sessions
  - Status: Done (verified in codebase)
  - Details: HD/legacy mode does not persist across sessions.
  - Plan: Store mode preference and honor it during migration.

- [x] [#3083](https://github.com/GLEECBTC/gleec-wallet/issues/3083) DEX: Sell dropdown uses wallet coins list sorting
  - Status: Done (verified in codebase)
  - Details: Sell list ordering differs from wallet list.
  - Plan: Reuse wallet sorting logic for DEX dropdowns.

- [x] [#3078](https://github.com/GLEECBTC/gleec-wallet/issues/3078) Wallet list tags: HD/Iguana, Generated/Imported, Date
  - Status: Done (verified in codebase)
  - Details: Wallet metadata now stores mode/provenance/date and wallet list rows render corresponding quick tags.
  - Evidence: `lib/model/wallet.dart`, `lib/model/kdf_auth_metadata_extension.dart`, `lib/bloc/auth_bloc/auth_bloc.dart`, `lib/views/wallets_manager/widgets/wallet_list_item.dart`.

- [x] [#3071](https://github.com/GLEECBTC/gleec-wallet/issues/3071) Login import: show custom seed input only when BIP39 validation fails
  - Status: Done (verified in codebase)
  - Details: Custom-seed toggle now appears only after non-HD BIP39 failure and is hidden in HD mode.
  - Plan: Hide advanced input until validation fails; provide explicit "show advanced" option.

- [x] [#2517](https://github.com/GLEECBTC/gleec-wallet/issues/2517) Wallet Seed Field BIP39 Input Suggestions
  - Status: Done (verified in codebase)
  - Details: Seed import now provides live BIP39 word suggestions and selectable suggestion chips while keeping custom-seed and HD validation flows intact.
  - Evidence: `lib/views/wallets_manager/widgets/wallet_simple_import.dart`.

- [x] [#2984](https://github.com/GLEECBTC/gleec-wallet/issues/2984) Bulk disable & coin activation view consolidation
  - Status: Done (verified in codebase)
  - Details: Coins manager flow now unifies activation/bulk actions with corrected select-all state behavior and cleaner controls.
  - Evidence: `lib/views/wallet/coins_manager/coins_manager_list_wrapper.dart`, `lib/views/wallet/coins_manager/coins_manager_controls.dart`, `lib/views/wallet/coins_manager/coins_manager_select_all_button.dart`, `lib/bloc/coins_manager/coins_manager_bloc.dart`.

- [x] [#2749](https://github.com/GLEECBTC/gleec-wallet/issues/2749) Improve UX where user is expected to be patient
  - Status: Done (verified in codebase)
  - Details: Long wait states now provide contextual progress messaging and improved visual feedback instead of bare spinners.
  - Evidence: `lib/views/wallet/coin_details/faucet/faucet_view.dart`, `lib/views/wallet/coin_details/withdraw_form/withdraw_form.dart`.

- [x] [#2680](https://github.com/GLEECBTC/gleec-wallet/issues/2680) Option to input custom fees on Tendermint/IBC withdraw not available
  - Status: Done (verified in codebase)
  - Details: Tendermint/IBC withdraw flow now exposes custom gas/fee controls with corresponding UI inputs.
  - Evidence: `lib/bloc/withdraw_form/withdraw_form_state.dart`, `lib/views/wallet/coin_details/withdraw_form/widgets/fill_form/fields/fields.dart`, `sdk/packages/komodo_ui/lib/src/core/inputs/fee_info_input.dart`.

- [x] [#3241](https://github.com/GLEECBTC/gleec-wallet/issues/3241) Multi-Address Wallet Mode causes address/balance confusion
  - Status: Done (verified in codebase)
  - Details: Added an in-wallet notice explaining multi-address mode and balance differences.
  - Plan: Add explicit messaging, warnings, and a clear explanation of address set changes.

- [x] [#3092](https://github.com/GLEECBTC/gleec-wallet/issues/3092) UX: Withdraw fee priority selector (EVM/Tendermint)
  - Status: Done (verified in codebase)
  - Details: Withdraw flow supports user-selectable fee priority tiers where chain support is available.
  - Evidence: `lib/bloc/withdraw_form/withdraw_form_state.dart`, `lib/views/wallet/coin_details/withdraw_form/withdraw_form.dart`, `sdk/packages/komodo_ui/lib/src/defi/transaction/withdrawal_priority.dart`.
