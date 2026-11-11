# Authentication UX research and implementation brief

Date: 2026-11-11. Baseline candidate: `6d2ca1f4a742df9a52de879900965bad66bd8fbd`.
This is an implementation follow-up, not physical-provider certification.

## Product decisions

Keep wallet creation to one app action without typing. Present passkeys as the
recommended local unlock setup in the normal browser wallet experience where
supported, after durable creation. The wallet is already usable; the setup card
must not become a mandatory wizard. Native apps retain their capability-aware
system authentication rather than adding a redundant browser-passkey ceremony.

A concise explanation precedes a user-initiated passkey ceremony. Show success,
cancellation or a useful fallback afterward. Do not automatically launch an
unexplained enrollment prompt, repeat it after cancellation, or make unsupported
providers look like a wallet-creation failure. Keep required user verification
and the second assertion/decryption check. A passkey API alone is not proof of
PRF support. Feature detection only controls new offers, never existing readers.

The provider owns password-saving confirmation. Remove the application Save
button, snackbar action and credential-reveal compatibility dialog. Request the
available provider save API after creation; submitted password forms request
normal autofill saving/updating. Do not create invisible focused forms to force
an OS dialog. Report unavailable/unknown outcomes honestly.

Keep three concepts distinct: local unlock protection, the provider's saved
credential, and independent recovery. Neither a synced passkey nor a password
can restore this release's wallet without its local encrypted data. Backing up
recovery words never requires choosing a personal password. Sending and swapping
remain usable before backup with the previously agreed reminders.

## Research basis

- [FIDO principles](https://www.passkeycentral.org/design-user-journeys/principles):
  offer enrollment in account-related moments; connect passkeys to familiar
  device unlock; explain the OS handoff; preserve choice and accessible fallback.
- [FIDO new-account pattern](https://www.passkeycentral.org/design-user-journeys/optional-patterns/new-account-creation-with-a-passkey):
  remove password-creation friction. Its generic synced-account recovery claims
  do not apply to Gleec's local encrypted wallet.
- [FIDO sign-in pattern](https://www.passkeycentral.org/design-user-journeys/required-patterns/sign-in-with-a-passkey):
  discoverable access and graceful fallback. Gleec already knows the last wallet,
  so an unnecessary username form would add friction; retain one explicit unlock
  control and at most one automatic return challenge.
- [FIDO passkey management](https://www.passkeycentral.org/design-user-journeys/required-patterns/create-view-and-manage-passkeys-in-account-settings):
  give the passkey a visible status and place it before password settings. Do not
  invent a provider name, sync status or multiple enrollment records.
- [Google user journeys](https://developers.google.com/identity/passkeys/ux/user-journeys)
  and [messaging](https://developers.google.com/identity/passkeys/ux/communicating-passkeys):
  explain the practical benefit, name the method, make cancellation recoverable,
  and establish a genuine recovery path. Do not copy email/SMS account recovery
  into a self-custody wallet.
- [Apple account guidance](https://developer.apple.com/design/human-interface-guidelines/managing-accounts):
  minimize entry and describe only methods actually available. A native device
  unlock and a passkey are distinct mechanisms and must have distinct labels.
- [WebAuthn Level 3](https://www.w3.org/TR/webauthn-3/#prf-extension):
  PRF support/output and credential verification remain security prerequisites;
  an OS-created passkey alone does not prove it can decrypt the wallet.
- [Flutter autofill completion](https://api.flutter.dev/flutter/services/TextInput/finishAutofillContext.html):
  submit the completed form to the platform without an extra app save action;
  requesting saving returns no confirmation that it was saved.
- [Exodus passkey backup](https://www.exodus.com/support/en/articles/8598900-backup-vault-in-exodus-mobile):
  its cloud-backed recovery is a separate capability. Match the simplicity,
  without borrowing a backup claim this release cannot deliver.

## Observed baseline and scope

Current-run browser captures were saved and inspected at
`/private/tmp/gleec-auth-internal-20261111/ux-audit-20261111/`:

1. `01-entry-before.png`: clear primary Create control and visible hardware
   access, but the import entry names only recovery words and omits wallet files.
   Supporting copy foregrounds internal generated credentials before the benefit.
2. `02-import-before.png`: the file action says “Upload seed phrase file”,
   although encrypted wallet-file restoration is a different recovery method.
   Wallet type is presented without explaining its effect on finding addresses.

These are actual preview captures, not an audit of native OS dialogs. Other
states are grounded in source and existing automated journey evidence, then
must be rendered and exercised again after implementation. Never capture
recovery words, private keys or actual credentials for the report.

## State coverage and implementation acceptance

| Moment | Required experience |
| --- | --- |
| First entry | Clear benefit, one Create action, visible phrase/file import, hardware access and legal notice |
| Creating | Immediate announced progress; duplicate creation disabled; retry resumes the same operation |
| First wallet | Inline recommended passkey/device setup with direct action; independent recovery reminder; full wallet use |
| Enrollment | Explain face/fingerprint/screen lock and local scope before the OS prompt; prevent duplicate operations |
| Enrollment canceled/unsupported | Preserve the wallet and current protection; stable retry or password/settings fallback |
| Enrolled | Accurate method-specific status; never label local unlocking as recovery backup |
| Cold return/app lock | Wallet identity, method-specific Unlock, password/switch/recovery fallbacks, no prompt loop |
| Import/recovery | Distinguish phrase and encrypted file; explain derivation; never replace a same-name wallet |
| Sensitive settings | Fresh authorization; optional personal password; no generated-password typing or extra Save step |
| Password change | Submit once; let autofill offer an update; external save failure cannot undo rotation |
| Passkey loss/replacement | Keep existing records; known-password replacement and recovery remain clear |
| Removal/sign-out | Explain local removal and ongoing work; preserve explicit sign-out across relaunches |

## Design gate

UI-Pro basis: reran the repository design-system query for Gleec Wallet, the
Flutter accessibility/navigation query, and the UX forms/error-recovery query.
Reviewed accessibility, touch targets, responsive layout, typography, motion,
feedback, navigation, independent state presentation and secret privacy.

Gate status: **exception**, retaining the already accepted current-theme source
because canonical design files are absent. Owners: authentication implementation
and product design. User impact: no new visual language or extra onboarding
wizard. Required follow-up: inspect current-theme phone/wide and light/dark
renders, large text, keyboard/focus, and actual provider cancellation. Physical
VoiceOver/TalkBack/provider and signing checks remain pending separately.

## Validation of the implemented follow-up

On November 11, pinned Flutter 3.41.4 passed the complete production-GasFree
app aggregator after the contrast and target fixes: **4,555 passed, 26 skipped, zero failures**.
The final PR handoff binds the subsequent full CI run to the finished source. Whole-project analysis
reported **zero errors**, with the inherited 55 warnings and 2,143 informational
notices unchanged. The focused new presentation/password-provider round passed
52 cases; subsequent race regressions are included in the complete aggregator.
The dedicated rendering round passed 25 cases and produced 12 public setup-state
PNGs, inspected across ready/canceled/protected, light/dark and phone/wide states.

The real release-browser round exercises durable creation, process restart,
optional passkey enrollment, loss/cancellation, corrupted data, tab invalidation,
phrase/file recovery, missing data and unsupported-browser behavior. It uses
virtual PRF authenticators and disposable profiles. The same runner enables
frozen-renderer lifecycle checks locally and in CI, pins the compiled bundle,
and retains only public per-suite pass/fail metadata. Passkey enrollment uses
a single real pointer activation after the rendered route settles; completion
requires committed protection metadata and authenticated readback, not merely
a simulated accessibility click. Local provider/OS behavior,
reference-device timing, screen-reader focus and signed-device key protection
remain separate acceptance gates. The PR handoff records the exact accepted
bundle, hosted run and installer identities after CI qualification.

Corrections found by the new checks include the password form losing its new
value across a device confirmation, late optional-save status after locking,
and an import controller notifying its disposed screen. The form now hands the
committed value to the provider, its ordinary autofill fallback remains obscured,
and save failure never rolls back a completed password change. Recovery and
password inputs remask on background; keyboard learning/suggestions are disabled
without removing paste or autofill. Source and packaged copies retain the
Apache license for the official passkey icon. Real light/dark screen review also
identified low-contrast supporting text; security descriptions and secondary
controls now use readable theme foregrounds, with contrast and target checks in
both themes.

Local browser samples report application feedback and total opening separately
from system confirmations. They are development-host measurements and do not
establish the 100 ms/reference-device target or a physical-provider benchmark.
