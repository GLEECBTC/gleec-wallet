# Authentication journey review — 12 November 2026

## Root cause and security contract

The compiled-app regression reproduced one registration followed by **two**
assertions. The browser vault already registered the passkey, verified a fresh
user-verified PRF assertion, decrypted its staged envelope and atomically promoted
it. `WalletAccessService._enroll` then performed a generic authenticated readback,
which opened another WebAuthn assertion. This was duplicate orchestration across
service and backend boundaries, not a provider retry or an unavoidable OS dialog.

The passkey backend now owns the complete verified-enrollment contract. It checks
the promoted record using the same ceremony's non-exportable key. The shared
service checks protection metadata, wallet/session/generation and the real engine
password without requesting another passkey unlock. Native enrollment retains its
independent authenticated readback. Ordinary unlock and sensitive-secret access
still require fresh authorization; no reusable plaintext or PRF cache was added.

The expected app-issued sequence for a newly created wallet is one registration
and one verification assertion. Provider sheets may contain their own selection
or consent steps, so this is not a promise of one OS dialog. The verification
assertion remains required: registration alone cannot establish a usable PRF
return path. See [WebAuthn PRF](https://www.w3.org/TR/webauthn-3/#prf-extension).

## Competitor and standards research

Official documentation was checked on 12 November 2026. These are documented
journeys, not timings or hands-on measurements of competitor apps.

| Source | Relevant behavior | Gleec decision |
| --- | --- | --- |
| [Exodus passkey backup](https://www.exodus.com/support/en/articles/8598900-backup-vault-in-exodus-mobile) | Passkey setup has a clear successful completion. Recovery also requires an encrypted secret in iCloud or Google Drive. | Show a definite setup result and recovery as a separate action. Never describe our local passkey as equivalent cloud backup. |
| [Phantom Google/Apple onboarding](https://help.phantom.com/articles/how-to-create-a-phantom-wallet-using-your-apple-or-google-account-32775281256851) | Device authentication is optional on mobile and applies to the current device; cross-device account sign-in is separate. Its documented journey also includes a username and optional social steps. | Keep wallet creation free of mandatory typing and offer local protection immediately in the wallet. Keep optional profile work out of this path. |
| [MetaMask creation](https://support.metamask.io/start/creating-a-new-wallet) | Social onboarding still requires a wallet password; social credentials plus that password support recovery. | Generated-password users need usable backup and settings without discovering or typing the generated password. Explain the different recovery model. |
| [Base account sign-in](https://help.coinbase.com/en-ca/wallet/getting-started/smart-wallet-passkeys) | Current documentation recommends email OTP and also supports passkeys and recovery phrases. Its account and cross-device model differs from local seed storage. | Do not copy account-recovery promises or assume passkeys are every competitor's current default. Keep visible alternate unlock and recovery routes. |
| [FIDO principles](https://www.passkeycentral.org/design-user-journeys/principles) and [Google journeys](https://developers.google.com/identity/passkeys/ux/user-journeys) | Offer passkeys at account-related moments, explain their familiar device-unlock benefit, preserve choice and communicate status around OS dialogs. | Optional inline recommendation, recognizable icon, clear creation/verification handoff, specific pending feedback and stable cancel/retry. No surprise enrollment on launch or focus. |

The measurable improvement target is fewer mandatory application steps, exactly
one app-issued verification assertion during setup, no repeat prompts from status
refresh/navigation, one automatic enrolled return attempt and clear independent
recovery. This review does not establish superiority over every competitor.

## Current flow audit and changes

Fresh preview screenshots of the welcome and import screens were inspected in
the in-app browser before implementation. The public welcome screen had a clear
primary create action and visible import/hardware alternatives, but its supporting
copy described form mechanics and password-manager behavior before either was
relevant. Import retained wallet-type guidance and a distinct encrypted-file path.
No secret screen was captured. Public setup-state renders cover the additional
ready, password-provider waiting, creating, canceled and protected states.

| Stage | Finding | Result and validation requirement |
| --- | --- | --- |
| Welcome | Supporting text spent attention on implementation mechanics. | Lead with starting immediately, then secure unlock and recovery. Preserve the single create action and existing legal notice. |
| Creation | Optional provider save can overlap a user's protection intent. | Existing serialization remains enforced; protection waits for completion without an app Save action or queued surprise ceremony. |
| Protection | Duplicate service/backend readback caused a second unlock. Generic waiting feedback did not explain the handoff. | Backend verifies once. Explain create, then use once, before the OS takes over; show action-specific live feedback while pending. |
| Completion | Protection can be mistaken for independent recovery. | Keep the browser scope visible and the recovery-phrase action independent. Protection success never marks recovery complete. |
| Cancellation/failure | Focus return and repeated taps can become prompt loops. | Requests remain droppable and wallet-bound. Status refresh never enrolls; cancellation leaves existing access and an explicit retry. |
| Return | Unannounced selector navigation or challenge retries undermine effortless return. | Last successful immutable identity, at most one automatic challenge, stable password/switch/recover alternatives and persistent explicit sign-out. |
| Backup/settings | Generated passwords can make ordinary password forms unusable. | Existing fresh device/passkey authorization covers phrase/export/change/delete; backup does not mandate a custom password. |

## Design gate and acceptance

**UI-Pro Basis:** repository UI-Pro design-system search for Gleec Wallet crypto
wallet/passkey onboarding; Flutter accessibility/navigation stack search; UX
search for onboarding, authentication, forms, error recovery and progressive
disclosure. Reviewed accessibility, touch, responsive layout, typography/color,
reduced motion, forms/feedback, navigation, atomic state and secret safety.

**Gate Status: exception.** The canonical design files remain absent from this
checkout. The previously accepted exception uses the current Gleec theme and
shared components. Owner: design owner; follow-up: retain the tested auth state
reference as the design source and review the rendered states. Generic UI-Pro
visual suggestions do not override the existing app. No new visual language or
mandatory wizard is introduced.

Release evidence must identify the exact candidate. The old compiled build fails
the new assertion-count test (2 versus 1), so previous green journeys alone cannot
qualify this fix. Required automated checks include protocol corruption tests,
service/session races, duplicate taps/cancellation, main CI aggregator, analysis,
public light/dark phone/wide renders, compiled browser journeys and rollback
reader compatibility. The full flow must still satisfy large text, keyboard,
screen-reader semantics, targets and reduced-motion checks.

Physical biometric/PIN behavior, real provider sheet counts and cancellation,
provider loss, OS lock/invalidation and assistive technology remain pending in
[AUTH_RELEASE_GATES.md](AUTH_RELEASE_GATES.md). Virtual authenticators prove the
application's ceremony count, not a provider's exact sheets or physical security.
