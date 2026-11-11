# Authentication state reference

This implementation uses the existing application theme, shared buttons, form
fields and dialog shell. The canonical `DESIGN.md` and Purple Vault design
language files are absent from this checkout; inheriting the current application
styles is the recorded design exception, rather than introducing a new theme.

## Design review

- Basis: the repository design-system search, Flutter accessibility guidance,
  and form/error-recovery guidance were run during planning.
- Gate status: **exception** for the missing canonical design documents.
- Owner: authentication implementation and product design.
- Follow-up: capture phone and desktop, light and dark screenshots, large text,
  keyboard navigation and screen-reader behavior before visual sign-off.

## States and actions

| Surface | State | Primary action | Secondary actions |
| --- | --- | --- | --- |
| Entry | New user | Create wallet | Import wallet, hardware wallet where supported |
| Entry | Creation pending | Creating your wallet | Cancel when safe; duplicate submission disabled |
| Entry | Creation failed | Try again on the same pending operation | Import wallet, cancel |
| Unlock | Managed wallet | Unlock with device/passkey, or open unprotected wallet | Use password, switch wallet, recover wallet |
| Unlock | Password fallback | Unlock | Return to device/passkey, switch wallet |
| Unlock | Canceled or failed | Try again | Password and recovery remain visible |
| Wallet setup | Protection or backup incomplete | Protect this device / back up recovery phrase | Save password, settings |
| Security | Protected | Device/passkey status | Immediate/30-second app lock, optional password |
| Wallet name | Current display label | Rename wallet | Existing engine identity stays fixed |
| Wallet name | Editing or validation error | Save name after authorization | Cancel preserves the existing label |
| Authorization | Managed credential | Continue with enrolled method | Use password, cancel |
| Authorization | Unprotected credential | Explicitly continue | Cancel |
| Password change | Managed credential | Set a personal password | Cancel; no unknown old-password field |

Creation has no name or password fields. Renaming lives in settings and changes
only the visible label; authentication, passkeys and password-manager usernames
retain the original wallet identity. The existing legal notice stays beside
the create action and records the displayed document version. No artificial
delay is added. Provider saves and device prompts are separate outcomes: a
requested save is never displayed as confirmed backup.

Use one primary action per moment, 48-pixel touch targets, visible keyboard
focus, wrapping text at large text scales, explicit loading/error semantics and
no decorative motion. Protection and recovery are independent statuses; neither
uses color as its only indicator. Secret screens close when backgrounded even
within the app's return grace period.

This state reference is implementation guidance, not a record that physical
device, screenshot or accessibility validation has passed.

## Automated accessibility and layout evidence

The release follow-up uses the existing light and dark application themes.
UI-Pro basis was rerun using the repository design-system search for
`Gleec Wallet crypto wallet fintech mobile`, Flutter stack search for
`flutter financial app navigation accessibility`, and UX search for
`financial data display forms error recovery`. The canonical-design exception
above remains in effect; the checks below do not replace visual sign-off.

| Surface | Automated checks |
| --- | --- |
| Entry, managed unlock, setup, device enrollment and rename | Both themes; 320×568 at 200% text, 844×390 at 300%, and 1280×900 at 100%; rendered label bounds and reachable actions |
| Password-manager compatibility dialog | Both themes; 320×568 at 200% and 844×390 at 300%; obscured credential semantics, reachable content, Escape cancellation and declined outcome |
| Root lock and password fallback | Wallet content excluded from semantics; recovery remains reachable with a 300-pixel keyboard inset and 200% text |
| Recovery reveal and confirmation | Both themes; recovery field line height at 200%, hidden words absent from field semantics, switch state, 48-pixel confirmation targets, full selection/clear at 300%, keyboard activation |
| Recovery completion | Both themes and all three viewport profiles; full completion label and return to security settings without a password step |
| Protection settings and fresh authorization | Both themes at 320×568 and 200%; selected grace interval announced, hidden autofill username excluded from keyboard focus, named Show/Hide password controls |
| Setup-card accessibility | Flutter labeled-target, Android target-size and text-contrast guidelines in both themes |
| Pending creation | Reduced-motion media preference suppresses the indeterminate ticker while progress remains announced |

The regression suites are `auth_accessibility_test.dart`,
`auth_recovery_accessibility_test.dart`, and
`auth_settings_accessibility_test.dart` under
`test_units/views/common/wallet_access/`; they run alongside the existing
managed-access, legal-consent, wallet-deletion, rename and seed-export checks.

Findings fixed during this pass: clipped primary-action labels; an overflowing
large-text save dialog; hidden username focus stops; an unlabeled password
visibility control; a no-op heading exposed as an action; root authentication
content behind the software keyboard; insufficient dark-theme secondary-action
contrast; a 31-pixel recovery-field cap that clipped large words; undersized
recovery controls; and progress animation despite reduced-motion preference.
Primary-button content sizing is opt-in, and its legacy fixed-height behavior
has a regression check.

On 2026-11-08, the focused run passed **125 widget tests**, including **45 new
accessibility regressions**, using pinned Flutter 3.41.4. Scoped analysis and
whitespace validation passed. The selected recovery-word contrast check also
caught an enabled control rendered at disabled opacity; selection now keeps
readable text and uses its remove icon and selected semantics. These are
automated checks, not physical screen-reader certification.

## Remaining device and visual checks

Product design owns phone/tablet/desktop screenshots and comparison with the
eventual canonical design reference. Capture real application light/dark
screens, including enlarged text, keyboard-open fallback and canceled system
authorization. Widget rendering assertions alone do not establish visual
sign-off or contrast on every platform-rendered system dialog.

Accessibility QA must still exercise physical VoiceOver and TalkBack reading
order, focus restoration after biometric/passcode and password-manager sheets,
large system fonts, switch controls, system magnification, hardware keyboards,
and reduced motion. Check that hidden credentials are not spoken; revealed
recovery words are spoken with their positions only after authorization; and
backgrounding immediately removes sensitive screens. Native OS authentication
and password-manager dialogs require their own device checks.

For a fresh onboarding check, leave `DEBUG_WALLET_FILE` unset. Ignored local
fixtures are no longer bundled. A deliberately supplied native debug/profile
runtime fixture can still restore a development wallet; release builds ignore
that option. Never include fixture contents in screenshots or reports.

## Cold-launch and lost-provider follow-up

A clean Android release launch exposed public prices with wallet setup hidden
behind the header control. The shared wallet root now presents the existing
Create/Import entry on both phone and wide routes. **Explore prices** explicitly
opens guest browsing, and **Set up wallet** returns to the entry. Process-local
presentation state preserves that choice across coin navigation and shell
remounts; authentication identity changes reset it. Asset/action deep links keep
their destinations. Legal consent and the no-form creation action are unchanged.

Explicit Create, Import, wallet selection, hardware entry or Explore cancels a
pending remembered-wallet lookup. The lookup checks its presentation generation
and current authentication again before opening a dialog, preventing a late
startup prompt from covering an already chosen flow.

Passkey-protected browser wallets offer **Replace passkey using password** only
when passkey enrollment is available. The action explains its local scope and
opens a password-only fresh-authorization dialog, without challenging the lost
provider. Cancellation and failure retain the previous status; success appears
only after the service completes replacement. Dismissing an authorization dialog
with Escape or its barrier now completes the waiting caller, allowing a retry.

On 2026-11-08, the focused follow-up passed **44 tests** with Flutter 3.41.4,
including **15 new regressions** for both real wallet-root router delegates,
one-action creation, guest navigation/shell remounts, delayed startup lookup
versus Create/Import, password-authorized replacement, cancellation, errors,
capability gating, 200% text in both themes, and inactive-wallet deletion
guidance. Scoped analysis passed. These checks do not establish physical
authenticator behavior or native visual acceptance; the clean Android release
entry and real browser-provider replacement are separate runtime checks.

Security settings also exposes **Review wallet removal** for the open software
wallet. It reuses the existing `WalletDeleting` review and repository path,
including recovery/payment warnings, and adds the effect on open orders,
automation and swaps. The widget does not sign out before password proof; the
SDK owns the reviewed engine transition. The focused removal run passed **15
tests**, including **seven new settings regressions** for light/dark large text,
cancel, wrong password, canceled provider authorization, unchanged review
delegation and closing the deleted-wallet UI on completion. A typed committed
deletion with remaining local-settings cleanup closes the review and shows a
nonsecret notice; it never offers Delete again. This widget evidence
does not substitute for the SDK or browser end-to-end deletion checks.
