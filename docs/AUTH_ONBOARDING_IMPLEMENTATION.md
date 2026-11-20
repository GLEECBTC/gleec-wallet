# Instant wallet creation and device access

This change implements instant, locally recoverable wallet provisioning and a separate application lock. The lock does not shut down KDF: accepted swaps and authorized automation retain their existing execution policy, subject to OS suspension. An unlocked app session permits ordinary transactions after their normal review. Device authentication does not replace recovery-phrase backup.

## User behavior

- Create accepts the displayed versioned legal notice and generates a collision-safe display name and a secure 32-character password. No name/password form is required.
- Creation journals its immutable entry identity and credential before SDK registration. Retries resume that entry; success follows credential and encrypted-wallet verification.
- Supported native devices can protect the credential during setup. A declined initial setup can continue unattended with accurate status. Browser passkey enrollment is optional after creation.
- Returning users select the last successfully used immutable wallet entry. Automatic challenges occur once, with password, switch and recovery alternatives. Explicit sign-out persists suppression across launches.
- A compact setup card tracks phrase recovery and device access independently. Funding, sending and swapping remain available before backup. The funding reminder is dismissible for the current authenticated session.
- Settings can change the wallet's display name after fresh authorization. Engine identity, credential enrollment and last-wallet selection stay unchanged; generated names also avoid existing display labels.
- Phrase/private-key reveal, export, password replacement, protection changes and deletion request fresh authorization; unattended wallets use explicit confirmation. Backing up the phrase does not require choosing a personal password.
- App inactivity hides wallet content and closes secret screens immediately. New user operations are blocked in the background. A monotonic 30-second grace restores the existing session; immediate locking is configurable. No unlocked state survives process restart.
- The startup overlay is removed immediately when ready, without an artificial animation delay. Balance and network loading continue progressively.

## Implementation map

| Responsibility | Main implementation |
| --- | --- |
| Credential/provisioning/rotation coordination | `lib/services/wallet_access/wallet_access_service.dart` |
| Versioned non-secret state | `wallet_access_record.dart`, `wallet_credential_cleanup.dart` |
| Password-change recovery envelope | `password_rotation_envelope.dart` |
| Lifecycle and prompt ownership | `unlock_coordinator.dart` |
| Financial dispatch admission | `wallet_operation_gate.dart`, SDK `RpcDispatchGuard` and withdrawal pre-broadcast checks |
| Root privacy/unlock surface | `lib/views/common/wallet_access/wallet_access_boundary.dart`, `app_lock_boundary.dart` |
| Native storage | Platform runners; see [native implementation and checks](AUTH_NATIVE_VALIDATION.md) |
| Browser PRF vault | `web/services/wallet_credentials.js`, `platform/web_credential_backend.dart` |
| Recovery evidence | `WalletConfig.recoveryEvidence`; legacy `has_backup` is not independent evidence |
| UI state reference | [Authentication design reference](design/authentication/README.md) |

Credentials are bound to immutable wallet entries and verified wallet identities. Native storage policy and browser ciphertext determine the actual protection; an application Boolean cannot authorize protected reads. Password-manager outcomes are independent and never establish backup or synchronization. Raw credentials stay out of ordinary BLoC states, analytics and broadcasts. Dart strings and KDF process memory cannot be promised zeroized.

Password rotation journals the former credential encrypted under the new password with authenticated encryption, then coordinates KDF, the vault and metadata. Interrupted work remains recoverable. External password-manager updates happen afterward. Deletion preauthorizes credential removal before destructive wallet deletion and retains a durable cleanup journal if local removal cannot finish.

## Browser deployment

Build with `flutter build web --release --csp --no-web-resources-cdn`. The hosting configuration and HTML apply a self-only executable script policy with WebAssembly permission; the application ships local Flutter/CanvasKit startup resources. Firebase web analytics initialization is disabled because its module injection violates this policy; native analytics remains unchanged. Browser data-only analytics does not receive credentials.

Passkeys use the exact current hostname: production `dex.gleec.com`, with isolated preview origins. Required user verification, registration plus a subsequent verified PRF assertion, authenticated ciphertext and durable readback precede removal of unattended access. Cross-tab messages contain only lock/revision notifications. Synced passkeys cannot recover an absent encrypted wallet and envelope. Browser storage persistence requests remain best effort, and hostile code executing within the wallet origin remains a material threat.

Apple password-manager integration additionally needs the deployed AASA file and a release provisioning profile with the Associated Domains entitlement. Provider acceptance does not establish cloud synchronization.

## Rollout and rollback

- `WALLET_DEVICE_ENROLLMENT_ENABLED` and `WALLET_PASSKEY_ENROLLMENT_ENABLED` default to `true` and can stop new enrollment. Existing credential readers/unlock paths remain available.
- `WALLET_IMMEDIATE_LOCK_REQUIRED` defaults to `false`; enabling it overrides the grace period to zero.
- Retain this version's vault readers, provisioning and rotation journals, cleanup handling and SDK catalog migration in rollback builds. A pre-feature build can strand generated-password wallets and is not a compatible rollback.
- Stage platform enrollment only after the physical-device matrix passes. Do not infer production certification from compilation or mock/virtual-authenticator tests.

## Release acceptance still requires devices

Physical-device testing must cover biometric enrollment changes, passcode removal, PIN fallback, lockout, interrupted OS dialogs, protected-data/device-lock notifications, reinstall, provider loss, and release signing. Windows native bridge compilation/linking passed against real Windows headers/libraries; full app and Hello/DPAPI runtime still require a Windows host. Clean unsigned Android and iOS release packages now build and pass artifact privacy checks. Test real browser eviction and passkey-provider changes independently of virtual-authenticator coverage. The exact remaining checks and device access are tracked in [the release checklist](AUTH_RELEASE_GATES.md).

The five-second creation and 100-ms feedback goals need end-to-end measurements on reference devices, reporting OS confirmation time separately. Native KDF startup uses the bundled library; credential-bearing executable argv transport is refused in production. Cloud recovery is deferred. Immediate app lock does not remove KDF signing material needed for already-authorized engine work.

## Initial implementation validation record

Validation uses the repository-pinned Flutter 3.41.4 toolchain. Authentication tests are imported into `test_units/main.dart`.

- Service/lifecycle/cleanup: **87 tests passed** (48 service/model, 18 lifecycle, 21 cleanup), including 27 display-name and identity regressions.
- Pure credential/lock regression group: **46 tests passed**, including authenticated rotation-envelope corruption and identity checks and the browser bridge test wrapper.
- Final unlock/managed-access/checkout widget group: **35 tests passed**, including delayed legal-acceptance automatic return and failure/cancellation alternatives.
- Recovery-flow group: **59 tests passed**, including separate phrase/file evidence, secret-screen inactivity and same-wallet session replacement.
- SDK authentication suite: **138 passed**; framework suite: **104 passed** at the SDK hardening checkpoint. Dispatch additions separately passed four authorization races, nine legacy/SIA cases and four dispatch-scope cases.
- Automated diagnostic canaries passed for executable startup rejection, password-rotation errors and RPC request/response logging. Executable-start tests reject wallet passwords, RPC passwords and passphrases before finding/spawning a process. This does not constitute a physical-device process-table or end-to-end support-export scan.
- Native Swift typechecks passed for iOS/macOS. Offline Android Gradle `:app:compileDebugJavaWithJavac` passed with pinned Flutter 3.41.4 in 36 seconds, including Flutter debug compilation. These do not substitute for packaged-app/device tests.
- Real Chromium/IndexedDB/WebAuthn PRF and compiled Flutter credential-bridge scenarios passed. Full-app creation without typing, automatic return, persistent explicit sign-out, passkey enrollment, one-challenge cold return and cancellation/retry passed with no CSP violations. The passkey store contained no unattended or staging credential after enrollment.
- The final combined GasFree-enabled app suite passed **4,145 tests with four skipped** in 5m25s, including the display-name regressions and concurrent Solana work.
- The final production web build with CSP and locally bundled resources passed in 53.1s. The renamed passkey wallet reopened with exactly one assertion and unchanged enrollment. Native/browser device matrices and reference-device timing remain release requirements.

Whole-repository analysis also encounters archived standalone Dart source under `docs/local-rc-2026-10-28/` and existing unrelated warnings; changed authentication sources have scoped clean analysis. Detailed browser/native release matrices are in [AUTH_WEB_VALIDATION.md](AUTH_WEB_VALIDATION.md) and [AUTH_NATIVE_VALIDATION.md](AUTH_NATIVE_VALIDATION.md).

## Release-gate follow-up — 2026-11-08/09

The final GasFree-enabled app aggregator passed **4,411 tests with 26 skipped**
in 8m15s, with zero failures. The skips include 22 Linux-only credential tests, which separately
passed on actual Linux as an unprivileged user; the other four are pre-existing
skips. New tests are included in the main CI aggregator.

Follow-up fixes keep creation retries on the original identity after final
metadata failures, prevent Linux storage-policy downgrade through stale local
copies, cover passkey material in diagnostic redaction, expose setup on actual
mobile/desktop entry, and allow explicit fresh-password replacement/deletion
when a browser passkey provider is lost. Generated-password backup/export and
separate seed/encrypted-file imports were exercised in the full browser app.

Local developer wallet fixtures are no longer bundled as assets. Debug/profile
automation requires an explicit native runtime file; release builds ignore that
option. An artifact privacy check now rejects the identified fixture/signing
files before CI upload. Clean web, Android and iOS packages pass this check.
No affected artifact was uploaded by this validation run.

The final CSP/local-renderer browser build passed in 57.3s. Scoped authentication
analysis has no errors or warnings (two existing general iOS share-API deprecation
notices remain). Whole-repository analysis still has 20 errors in the archived
source plus existing warnings/infos; this is not reported as a passing global
analysis gate. Browser/provider runtime, native packaging and remaining physical
checks are recorded in [AUTH_RELEASE_GATES.md](AUTH_RELEASE_GATES.md).

Actual Android testing exposed a native authorization callback arriving before
Flutter's foreground notification. The app now retains only the successful
owned ceremony through a bounded return, checks both callback orders, and
preserves immediate locking, cancellation and stale-wallet rejection. Actual
generated-password removal passed with both default and immediate locking;
protected backup entry and background closure passed without revealing words.

Sensitive work also retains app-lock authority after password verification:
phrase/private-key access, encrypted export and password replacement cannot
dispatch or publish a late result after inactivity or a wallet change. A native
file destination dialog never acts as authentication. Its continuation retains
the original wallet/SDK session, waits for foreground, and obtains a fresh
configured unlock if normal grace or immediate locking requires it. Canceled
saves establish no recovery evidence; an unconfirmed browser download records
an export request only. The focused service/lifecycle matrix passes 155 tests,
the sensitive UI matrix passes 117, and the final combined suite above includes
the completed screen wiring. The earlier full browser runtime checks passed on artifact
`43f7b16897e483f75def9c154bb91b837333e2fab20d5173095659224568eb79`;
the later corrected normal/rollback builds and lifecycle checks are bound in
[the rollback validation record](AUTH_ROLLBACK_VALIDATION.md).
Actual Android default/immediate file-picker returns and cancellation verify
that no bytes are written before required fresh authorization. Final Android,
unsigned iOS, and ad-hoc macOS validation packages pass privacy scanning;
macOS has no provisioned team or embedded entitlements in this validation build.

Windows native preparation now passes actual CI. Linux native-only packaging
and absolute library loading pass 31 ELF/CMake cases and seven Flutter tests.
The exact-source Linux and universal macOS native-library archives are now
published under immutable new names, pinned in the canonical SDK manifests and
verified through ordinary credential-free downloads. Both final app packages
pass artifact privacy checks; Linux opens onboarding offline with the bundled
library. Real Linux Secret Service persistence, provider loss, recovery and
deletion passed in fresh processes. The Mac signing/Touch ID check remains
deferred to the user as requested.

An Android HOME transition exposed another lifecycle gap: inactive → resumed
can occur without hidden/paused. Monotonic grace now starts at unowned
inactivity, and stale operation authority is revoked there. The exact failing
short-background sequence, five prompt-adjacent repetitions, compiled browser
29/31-second and immediate-lock rounds, and the full app suite now pass.

A sealed rollback candidate preserves existing readers while disabling new
enrollment. Browser and same-install Android normal → rollback → normal rounds
passed for generated, passkey/device-protected and custom-password access as
applicable. Production signing and actual hardware/provider continuity remain
pending. See [the release checklist](AUTH_RELEASE_GATES.md) for current evidence
and [the hosting record](AUTH_WEB_VALIDATION.md) for preview-only browser policy
validation; production hosting and its separate reserved-page edge change have
not been activated.
