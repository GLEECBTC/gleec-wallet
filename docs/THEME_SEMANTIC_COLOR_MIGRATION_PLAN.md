# Theme semantic color migration plan

## Status and trigger

The legacy Gleec themes use Material's `ColorScheme.onSurface` as the page
background:

- dark: `#000000`;
- light: `#FBFBFB`.

Material defines `onSurface` as foreground content rendered on a surface. The
GasFree balance breakdown followed that contract for its primary values, which
made the values black on a dark card. The targeted fix now inherits the
established `bodyMedium` foreground and leaves the global theme unchanged.

The current app theme is the committed source of truth for this fix. There is
no committed `docs/design` pack for this component; any external reference
screenshot should be attached to the implementation PR.

## UI-Pro gate record

- **UI-Pro Basis:** the Gleec Wallet crypto/fintech design-system search,
  Flutter accessibility/theming guidance, and the financial data-display UX
  checklist.
- **Gate Status:** `exception` after the targeted GasFree fix. Focused
  light/dark coverage verifies the foreground roles, but visual/contrast
  baselines and the global token migration remain outstanding.
- **Findings/Exceptions:** `onSurface` is a background token in the legacy
  theme but a foreground token to standard Flutter components. New or migrated
  components can therefore render unreadable text or incorrect backgrounds.
  The owner is the Wallet UI/theme maintainers. The exception is intentionally
  limited to compatibility with existing screens.
- **Required Follow-up:** execute the staged migration below, including
  contract tests, light/dark visual baselines, consumer migration, the token
  flip, and an automated role check.

## Target contract

| Role | Target |
| --- | --- |
| App canvas | Keep `ThemeData.scaffoldBackgroundColor` explicitly `#000000` in dark mode and `#FBFBFB` in light mode. Do not derive it from `onSurface`. |
| Component surfaces | Use `surface` or the appropriate surface-container role for cards, panels, list rows, selectors, and dialogs. |
| Primary surface foreground | Set `onSurface` to `#FFFFFF` in dark mode and `#456078` in light mode. |
| Secondary foreground | Use `onSurfaceVariant`; use opacity only for a real disabled/de-emphasized state. |
| Inputs | Prefer `InputDecorationTheme.fillColor` and its foreground styles. |
| Modal barriers | Use the shared dialog barrier token backed by `scrim`, not a surface or foreground token. |
| Domain colors | Keep product-specific colors in the existing theme extensions rather than overloading Material roles. |

This is a semantic behavior change, not a public widget or BLoC API change.
Background consumers must move first so the `onSurface` value can be restored
without turning canvases and cards into foreground colors.

## Audit method and baseline

Run from the repository root:

```sh
rg -n -S "colorScheme\.onSurface\b|onSurface:" \
  app_theme lib packages/komodo_ui_kit sdk/packages/komodo_ui \
  --glob "*.dart" --glob "!build/**" --glob "!.dart_tool/**"
```

The baseline captured on July 30, 2026 contained 61 occurrences:

| Area | Before targeted fix | After targeted fix |
| --- | ---: | ---: |
| `app_theme` | 6 | 6 |
| Wallet app (`lib`) | 37 | 36 |
| `packages/komodo_ui_kit` | 5 | 5 |
| `sdk/packages/komodo_ui` | 13 | 13 |
| **Total** | **61** | **60** |

The counts include two stale commented references because they should be
removed rather than left as examples of the inverted contract.

## Exhaustive migration ledger

### Theme definitions

| Occurrence | Classification | Intended replacement | Phase |
| --- | --- | --- | --- |
| `app_theme/lib/src/dark/theme_custom_dark.dart:13` | Domain-specific extension | Initialize `suspendedBannerBackgroundColor` from `scaffoldBackgroundColor` or a dedicated banner surface token. | 2 |
| `app_theme/lib/src/dark/theme_global_dark.dart:22` | Foreground (token definition) | Set `onSurface` to `#FFFFFF`. | 3 |
| `app_theme/lib/src/dark/theme_global_dark.dart:79` | Scaffold/background | Set `scaffoldBackgroundColor` explicitly to `#000000`. | 2 |
| `app_theme/lib/src/light/theme_custom_light.dart:12` | Domain-specific extension | Initialize `suspendedBannerBackgroundColor` from `scaffoldBackgroundColor` or a dedicated banner surface token. | 2 |
| `app_theme/lib/src/light/theme_global_light.dart:20` | Foreground (token definition) | Set `onSurface` to `#456078`. | 3 |
| `app_theme/lib/src/light/theme_global_light.dart:77` | Scaffold/background | Set `scaffoldBackgroundColor` explicitly to `#FBFBFB`. | 2 |

### Komodo UI kit

| Occurrence | Classification | Intended replacement | Phase |
| --- | --- | --- | --- |
| `packages/komodo_ui_kit/lib/src/inputs/ui_date_selector.dart:47,49` | Component surface | Use the dialog theme background and `colorScheme.surface`. | 2 |
| `packages/komodo_ui_kit/lib/src/inputs/ui_date_selector.dart:50` | Foreground | Forward the restored outer `colorScheme.onSurface`. | 3 |
| `packages/komodo_ui_kit/lib/src/buttons/ui_primary_button.dart:93` | Foreground | Use `onPrimary` for the default primary background and the component's contrast helper for custom backgrounds. | 2 |
| `packages/komodo_ui_kit/lib/src/tips/ui_tooltip.dart:31` | Foreground | Keep the semantic `onSurface` role after the token is restored. | 3 |

### SDK Komodo UI

| Occurrence | Classification | Intended replacement | Phase |
| --- | --- | --- | --- |
| `sdk/packages/komodo_ui/lib/src/defi/withdraw/recipient_address_field.dart:249` | Foreground | Use `onSurfaceVariant` for the secondary network label. | 2 |
| `sdk/packages/komodo_ui/lib/src/defi/withdraw/source_address_field.dart:355,362` | Foreground | Use `onSurfaceVariant` for locked-balance secondary text. | 2 |
| `sdk/packages/komodo_ui/lib/src/composite/cards/collapsible_card.dart:278,279` | Icon | Use `IconTheme` with restored `onSurface`; retain disabled opacity only for the unavailable state. | 3 |
| `sdk/packages/komodo_ui/lib/src/core/inputs/searchable_select.dart:251,720` | Component surface | Use `outlineVariant` for input borders instead of a foreground color with opacity. | 2 |
| `sdk/packages/komodo_ui/lib/src/core/inputs/searchable_select.dart:313,330,419,672,773` | Foreground | Use restored `onSurface`; use the input label style or `onSurfaceVariant` only where the text is secondary. | 3 |
| `sdk/packages/komodo_ui/lib/src/core/inputs/address_select_input.dart:143` | Icon | Remove the stale commented override; use `IconTheme` if an override is reintroduced. | 4 |

### Wallet app

| Occurrence | Classification | Intended replacement | Phase |
| --- | --- | --- | --- |
| `lib/views/wallets_manager/widgets/wallets_list.dart:69` | Component surface | Use `colorScheme.surface`. | 2 |
| `lib/views/fiat/custom_fiat_input_field.dart:65` | Input fill | Use `inputDecorationTheme.fillColor`. | 2 |
| `lib/shared/widgets/coin_select_item_widget.dart:78` | Foreground | Use restored `onSurface` through the component's `DefaultTextStyle` and `IconTheme`. | 3 |
| `lib/views/dex/entities_list/orders/order_item.dart:67` | Component surface | Use `colorScheme.surface`. | 2 |
| `lib/views/fiat/fiat_payment_method_group.dart:27` | Component surface | Use `colorScheme.surface`. | 2 |
| `lib/shared/widgets/update_popup.dart:46` | Component surface | Use `colorScheme.surface`. | 2 |
| `lib/views/fiat/fiat_payment_method_card.dart:42` | Component surface | Use `colorScheme.surface` or the card theme color. | 2 |
| `lib/views/dex/entities_list/history/history_item.dart:71` | Component surface | Use `colorScheme.surface`. | 2 |
| `lib/views/fiat/fiat_select_button.dart:70` | Component surface | Use the selector's surface-container role. | 2 |
| `lib/views/fiat/fiat_inputs.dart:191` | Component surface | Use the card theme color or `colorScheme.surface`. | 2 |
| `lib/views/dex/entities_list/in_progress/in_progress_item.dart:60,284` | Component surface | Use `colorScheme.surface`. | 2 |
| `lib/views/nfts/nft_main/nft_main_controls.dart:90` | Barrier/scrim | Remove the ignored deprecated dispatcher argument and rely on the shared dialog barrier token backed by `scrim`. | 2 |
| `lib/views/settings/widgets/general_settings/settings_theme_switcher.dart:25` | Component surface | Use `colorScheme.surface`. | 2 |
| `lib/views/settings/widgets/security_settings/private_key_settings/private_key_actions_widget.dart:224` | Icon | Use restored `onSurface` with the standard disabled opacity. | 3 |
| `lib/views/settings/widgets/general_settings/settings_reset_activated_coins.dart:51` | Barrier/scrim | Remove the ignored deprecated dispatcher argument and rely on the shared dialog barrier token backed by `scrim`. | 2 |
| `lib/views/settings/widgets/security_settings/seed_settings/seed_show.dart:131` | Component surface | Use the card theme color or `colorScheme.surface`. | 2 |
| `lib/views/common/main_menu/main_menu_desktop_item.dart:105` | Component surface | Use the menu surface role; use transparency when the parent surface should show through. | 2 |
| `lib/views/dex/simple/form/taker/coin_item/coin_group_name.dart:25` | Foreground | Use restored `onSurface`. | 3 |
| `lib/views/common/hw_wallet_dialog/hw_dialog_wallet_select.dart:175` | Component surface | Use the dialog/card surface role. | 2 |
| `lib/views/dex/dex_list_filter/desktop/dex_list_filter_desktop.dart:52` | Component surface | Use `colorScheme.surface`. | 2 |
| `lib/views/wallet/coin_details/transactions/transaction_list.dart:68` | Component surface | Use the card theme color or `colorScheme.surface`. | 2 |
| `lib/views/dex/simple/form/taker/available_balance.dart:86,91` | Foreground | Use the active body text foreground; it will resolve to restored `onSurface`. | 3 |
| `lib/views/wallet/coin_details/transactions/transaction_table.dart:151` | Component surface | Use `colorScheme.surface`. | 2 |
| `lib/views/wallet/coin_details/transactions/transaction_list_item.dart:99` | Component surface | Use the mobile row surface role. | 2 |
| `lib/views/wallet/coin_details/transactions/transaction_list_item.dart:308` | Icon | Use restored `onSurface`. | 3 |
| `lib/views/wallet/wallet_page/common/grouped_assets_list.dart:45` | Component surface | Remove the stale commented zebra-color override. | 4 |
| `lib/views/wallet/wallet_page/common/wallet_coins_list.dart:23` | Component surface | Use a surface-container role for the alternate zebra row. | 2 |
| `lib/views/wallet/wallet_page/charts/price_chart_tooltip.dart:65` | Foreground | Use restored `onSurface`. | 3 |
| `lib/views/wallet/coin_details/coin_details_info/coin_details_info.dart:865` | Component surface | Use the header/primary tint as the skeleton fallback, not a foreground token. | 2 |
| `lib/views/wallet/wallet_page/common/expandable_private_key_list.dart:289` | Foreground | Use `onSurfaceVariant` for the secondary label. | 2 |
| `lib/views/wallet/wallet_page/common/assets_list.dart:47` | Component surface | Use a surface-container role for the alternate zebra row. | 2 |
| `lib/views/wallet/wallet_page/wallet_main/wallet_main.dart:420` | Barrier/scrim | Remove the ignored deprecated dispatcher argument and rely on the shared dialog barrier token backed by `scrim`. | 2 |
| `lib/views/wallet/coins_manager/coins_manager_list_item.dart:90` | Component surface | Use `colorScheme.surface`. | 2 |
| `lib/views/wallet/coin_details/withdraw_form/widgets/fill_form/fields/fields.dart:402` | Foreground | Use `onSurfaceVariant` for the secondary field label. | 2 |

## Staged rollout

### Phase 1: contract tests and visual baselines

1. Add theme-contract tests asserting the canvas and foreground values listed
   above and WCAG contrast of at least 4.5:1 for normal primary text.
2. Capture light and dark screenshots at phone and desktop widths for:
   wallet lists, DEX order/history rows, transaction history, fiat inputs and
   cards, dialogs/date picker, SDK searchable selects, buttons, and tooltips.
3. Add focused component tests for secondary/disabled foreground roles and
   surface-container selection.

No production token values change in this phase.

### Phase 2: decouple non-foreground consumers

1. Set scaffold backgrounds explicitly while keeping the legacy `onSurface`
   values temporarily unchanged.
2. Migrate every ledger row marked phase 2: cards/panels to surface roles,
   inputs to their decoration theme, borders to outlines, secondary text to
   `onSurfaceVariant`, and dialog barriers to the shared scrim-backed token.
3. Update the date selector and primary button special cases before the token
   flip.
4. Compare every affected screenshot with its phase 1 baseline. Any intentional
   tonal change requires a reviewed screenshot note; scaffold and established
   surface colors must otherwise remain stable.

### Phase 3: restore `onSurface`

1. Change dark `onSurface` to `#FFFFFF` and light `onSurface` to `#456078`.
2. Validate every foreground and icon row marked phase 3 in both themes.
3. Run root and package-level static analysis and the theme/component contract
   tests.
4. Repeat phone, desktop, and 200% text-scale screenshot review. Primary text
   must meet 4.5:1 contrast and large text/non-text UI must meet 3:1.

### Phase 4: cleanup and enforcement

1. Remove the compatibility comment from `GaslessBalanceBreakdown` and the two
   stale commented references in the ledger.
2. Update theme-extension initialization and documentation to reflect the
   restored contract.
3. Add `.github/scripts/check_theme_color_roles.py` and run it in CI. The check
   must reject `onSurface` in background, fill, border, and barrier assignments,
   with a narrow reviewed allowlist for legitimate foreground uses.
4. Re-run the audit command; remaining occurrences must all be foreground or
   token definitions, and every exception must be documented.

## Per-phase acceptance gate

- Format only changed Dart files, run root `flutter analyze`, and resolve every
  issue reported in the changed files while the repository-wide baseline
  remains non-zero.
- Pass affected package analysis and focused theme/component tests.
- Review light and dark screenshots at 375 px and desktop/tablet widths, plus
  200% text scale for data-heavy surfaces.
- Preserve app canvas colors and established surface hierarchy unless a visual
  change is explicitly approved.
- Record contrast results and screenshot paths in the phase PR.
- Do not combine the phase 2 consumer migration and phase 3 token flip in one
  unreviewable change.
