# TRON GasFree V0 UI handoff

## UI-Pro Basis

- `ui-ux-pro-max` design-system search: Gleec Wallet crypto wallet fintech mobile.
- Flutter stack search: financial navigation and accessibility.
- UX search: financial data display, forms, feedback, and error recovery.
- Code source: current Receive, Send, pending-transfer, receipt, and recovery surfaces.

## Gate Status

**Rollout switches default on; release approval remains pending.** This
checkout has no canonical
`docs/design/DESIGN.md`, Purple Vault design-language file, exported state
pack, approved screenshot matrix, or named Product/Design approval. The
implementation therefore uses the existing Gleec theme, `NoticeBanner`,
button, typography, and address components without introducing new visual
tokens.

The automated checks below demonstrate behavior and selected accessibility and
responsive constraints. They are not golden tests and do not constitute visual
approval.

## Implemented state contract

| Surface | State | Required presentation |
| --- | --- | --- |
| Receive | checking | Standard address remains usable; stable GasFree progress banner; no QR/copy. |
| Receive | ready | GasFree QR/copy, custody balance, token-fee/no-TRX explanation, Standard disclosure. |
| Receive | paused | Truncated custody address and on-chain balance remain visible; QR/copy disabled; Standard remains usable. |
| Receive | unsupported | Standard is primary; official recovery link is shown only for provider-reported unsupported tokens. |
| Receive | security blocked | No GasFree QR/copy or blind retry; retained balance and Standard remain visible. |
| Send | quote | Status balance/fees are estimates; fresh KDF preview is the sole monetary authority. |
| Send | submitted/unknown | Inputs lock; unknown acceptance remains pending and is never offered as a safe retry. |
| Send | final | Confirmed receipt or typed final failure with durable reservation cleared only after authority. |

## Implemented automated UI matrix

| Area | Automated coverage | Evidence |
| --- | --- | --- |
| Receive ready | Custody address, variant tag, custody-only balance, copy action, and no faucet; an absent custody snapshot never falls back to an aggregate or EOA balance. | `test_units/tests/wallet/coin_details/receive_address_faucet_widget_test.dart` |
| Receive checking and degraded | Stable checking state; paused balance/address remain readable while QR and copy are disabled; remote-disabled, malformed/security-blocked, zero-fee unsupported, and pending-transfer guidance remain distinct. | `test_units/tests/wallet/coin_details/receive_address_faucet_widget_test.dart` |
| Standard Receive escape hatch | The Standard sibling uses the EOA and its own balance, and opening its dialog pins the Standard address and caveat. | `test_units/tests/wallet/coin_details/receive_address_faucet_widget_test.dart` |
| Receive responsive/accessibility probes | A GasFree dialog is exercised at 320x568 with 200% text, bounded QR sizing, disclosure semantics, and action-time copy revalidation. Ready/paused rows are also exercised at 375px light and 768px dark; reduced motion removes the animated checking indicator; mobile and desktop actions are checked at 48dp. | `test_units/tests/wallet/coin_details/receive_address_faucet_widget_test.dart` |
| Send source and rail state | GasFree and Standard source selection, native/GasFree switching, status-chip behavior, first-load checking, preview blocking, and the Advanced native control are widget-tested. | `test_units/tests/wallet/coin_details/withdraw_form_fill_section_test.dart` |
| Send degraded state | Inactive-account activation guidance, provider-unavailable blocking and retry, and the honest hardware-wallet limitation are widget-tested. | `test_units/tests/wallet/coin_details/withdraw_form_fill_section_test.dart` |
| Send responsive/accessibility probes | Approval, confirmed receipt, request-only unknown acceptance, and trace-backed pending states are exercised at 375px light and 768px dark without overflow. The existing 320px/200% probe checks wrapping and 48dp targets. Reduced motion replaces relay and pending indeterminate animation with static status icons. | `test_units/tests/wallet/coin_details/withdraw_form_confirm_receipt_test.dart` |
| Receive policy lifecycle | Legacy status is receive-only evidence; strict parsing, provider pause, unsupported and security-blocked outcomes, zero-fee rejection, pending transfer, 60-second expiry, 30-second refresh, and wallet/config/address invalidation are unit-tested. The SDK retains only the last KDF custody snapshot during outages; it has no independent custody REST reader. | `test_units/tests/gasless/tron_gasfree_orchestrator_test.dart`; SDK balance-cache tests |
| Send authority and lifecycle | BLoC tests cover fresh-preview authority, requoting/expiry, provider outage, pending or unknown acceptance, authorization loss, and finality transitions. Legacy account status is never transaction authority. | `test_units/tests/wallet/coin_details/withdraw_form_bloc_test.dart` |

## Review matrix still required

- The complete light/dark cross-product at 320, 375, and 768 logical pixels;
  automated probes currently cover 320/200%, 375/light, and 768/dark.
- 200% text scaling, keyboard focus order, TalkBack/VoiceOver labels, and 48dp actions.
- Checking, ready, provider outage, unsupported, security mismatch, pending,
  quote refresh, unknown acceptance, confirmed, and final-failure artifacts.
- Reduced-motion and safe-area verification with no overflow or horizontal scrolling.

There are currently no golden or screenshot assertions for that complete
matrix. Physical assistive-technology behavior, focus order, the complete
reduced-motion cross-product, device safe areas, final copy, and visual polish
therefore remain manual review items.

## Named Product/Design sign-off — pending

| Approval | Named approver | Status | Evidence and date |
| --- | --- | --- | --- |
| Product flow, recovery language, and customer-facing copy | **Unassigned — an actual person is required** | Pending | — |
| Visual design, responsive matrix, and accessibility review | **Unassigned — an actual person is required** | Pending | — |

A role or team name is not a named approval. Replace `Unassigned` with each
approver's full name and record dated evidence only after that person completes
the review. Neither row is approved in this checkout.

`TRON_GASLESS_LEGACY_STATUS_RECEIVE_ENABLED` and the other rollout switches now
default to `true`. This does not constitute Product/Design approval: the
complete screenshot/device matrix and the Nile and mainnet canary checklist in
the production runbook remain required before distribution. Automated widget
and unit coverage does not waive those release gates.
