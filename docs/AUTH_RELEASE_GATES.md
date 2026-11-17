# Onboarding release acceptance

This is the release checklist for instant creation, local device/passkey access,
and independent recovery backup. Use only disposable, unfunded wallets. Do not
send a PIN, wallet password, recovery phrase, private key or passkey output to a
chat, screenshot, support ticket or test report.

## Internal candidate integration — 2026-11-11

The dedicated onboarding branch is prepared in an isolated checkout on the
reviewed Solana parent. It retains that parent's transaction/session protections
and adds app-lock generation checks without carrying unrelated local swap UI
changes. The app pins SDK `34faf005`; its authentication prerequisite is now
reviewable in [SDK #445](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/445).
The source/SDK merge safeguard remains enforced for production promotion.

The pinned [internal tester handoff](AUTH_INTERNAL_TESTING.md) and PR record
identify the currently qualified source, full production-GasFree app results,
analysis, hosted preview, rollback checks and native artifacts. Each new candidate
must repeat the applicable checks before the handoff moves. The November 11 UX
follow-up adds optional inline passkey/device setup, provider-owned password
saving and separate recovery explanations; its primary-source basis and state
matrix are [recorded here](design/authentication/UX_RESEARCH.md).

The following tables retain the earlier November 8/9 validation history and
platform limitations; they are not substitute build identities for this new PR.

## Automated evidence and engineering gates

The follow-up found and corrected creation retry identity loss after final
metadata failure, incomplete passkey diagnostic filtering, a Linux storage-tier
shadow/downgrade path, Windows compile/library-loading failures, signing and
packaging configuration errors, inaccessible large-text controls, hidden
first-launch wallet setup, missing password-authorized passkey replacement after
provider loss, and accidental bundling of the ignored local debug-wallet fixture. The source fixture was not
changed; affected local test artifacts were removed and rebuilt. No affected
artifact was uploaded by this validation run.

The app now requires an explicit native debug/profile runtime file for local
developer-wallet automation. Release builds ignore that option. The artifact
privacy verifier inspects actual files and APK/AAB/IPA/ZIP members before CI
upload; known fixture and signing-file names fail the build. It is a targeted
check, not a claim that arbitrary application data can never contain a secret.

| Gate | Evidence / remaining work |
| --- | --- |
| App unit suite | Final production-configured GasFree aggregator after the inactive-only lock correction: **4,411 passed, 26 skipped**, 8m15s, zero failures. The 22 Linux-only cases passed separately on Linux; four remaining skips predate this work. A new rollback fixture initially blocked the shared operation gate after disposal; injecting its own gate fixed it, with 32 ordered regressions and the final full rerun passing. |
| SDK authentication and shared prerequisites | Published authentication follow-up `cf69f4611b83bba7e05831e1b20c2447337ce867`: 196 native tests and five Chrome tests passed in shared and isolated SDK copies. Mapped routing/remote dispatch/build-token/harness prerequisites passed 236 tests. The fixture-only `98e51d9` correction passes six focused lifecycle/deletion tests; the coordinating Solana chat reports full HD and Iguana runs of 227 passed/three opt-in process skips each. |
| Creation/protection/password persistence | Failure injection covers pre/post writes, engine creation, encrypted readback, final selection/sign-out metadata, vault rotation and enrollment. Restart resumes the original entry with a usable access path. |
| Browser security/recovery | Actual Chromium process restarts, multi-tab invalidation, cancellation, corruption, generated-password phrase backup/export, and separate seed/file imports exercised in isolated profiles. Final artifact `43f7b168…68eb79` passes export-before-backup (requested-only evidence), phrase confirmation, one-challenge cancellation/retry and active deletion/provider-loss recovery. Passkey cryptography uses a virtual authenticator; it does not certify a real provider. |
| Browser timing | Report semantic update, paint estimate and app-open time separately, including busy-host outliers. Local samples are not reference-device certification. |
| iOS packaging | Corrected-source unsigned arm64 release app rebuilt in 75.16s (152.6 MB); actual artifact passed privacy scanning and remains unsigned. Signing, entitlement continuity and physical-device installation are separate pending checks. |
| Android packaging/storage | Corrected normal and rollback APKs passed same signer/app ID/version, retained-reader and byte-identical native implementation checks. Actual API 36 emulator normal → rollback → normal passed for protected generated, unprotected generated and custom-password wallets, backup/export, cancellation and persisted sign-out. Temporary diagnostics were proven absent; disposable emulator/data/signing material were cleaned. Physical Keystore/biometric guarantees remain unverified. |
| Windows compilation | Production vault and window integration compiled with real Windows headers; native test harness linked as x64 PE. Full app/Hello/DPAPI runtime needs a Windows host. |
| Clean native build preparation | A clean Windows CI runner configured CMake before the Flutter asset transformer could fetch its DLL. Selected-platform prefetch now runs before native configure, using unchanged manifest hashes and SDK provenance rules. Thirteen offline fixture tests and actual pinned Windows DLL/PE/export verification pass. The coordinating Solana task subsequently confirmed Linux, Windows and macOS application builds in [desktop run 42542882336](https://github.com/GLEECBTC/gleec-wallet/actions/runs/42542882336), plus Android/iOS in [mobile run 42542882385](https://github.com/GLEECBTC/gleec-wallet/actions/runs/42542882385), all at wallet `c9f14d34dc793dd7680da72088ed06aea340b8ad` and SDK `34faf005b2e092419d0cb12b84f21b02a6c7f0d6`. Uploaded artifacts/provenance bind to that head; source `f963`, catalog `cc8249` and the SDK merge-pin gate remain unchanged. This is supporting native preparation/packaging evidence from the Solana branch, not certification of the complete onboarding UI or physical providers. |
| Linux storage | 22 tests passed on actual Linux. Five additional fresh-process checks exercised the real FlutterSecureStorage/libsecret/GNOME Keyring backend: persistence, reopen, provider loss failing closed without local fallback, provider restart and deletion. Secret canary scans passed. This is OS-account protection; no biometric enrollment is claimed. |
| Linux engine | Published immutable native-v1 archive from exact KDF `f9632e0ec771668a6f21b37aede01a30110141cb`: SHA-256 `beb961fe98dbb3d0b1542fb530c749317ecd573b57f94d63b720f4908841d899`. Independent HTTPS download, ordinary credential-free SDK prefetch, all eight engine lifecycle phases, 31 real ELF/CMake cases and 15 canonical-manifest/downloader tests passed. The final canonical Flutter package rebuilt in 83.5s, passed privacy scanning and opened onboarding offline with its exact bundled library. Original archive remains unchanged; executable argument fallback remains prohibited. |
| macOS engine | Published immutable native-v1 universal archive, SHA-256 `a77a26c9814008c958b4f57d928ef59ca01b04b3d0c2710ea49ed8a707cfabd8`. Exact-source locked build passed eight real lifecycle phases on arm64 and Rosetta x64, including password rejection, rotation and cold return. Independent HTTPS download and normal SDK prefetch passed. Canonical JSON/YAML admit only the verified new native-v1 artifact; the old archive remains unchanged. |
| macOS packaging | Final corrected-source package rebuilt in 69.94s (228.3 MB) using the canonical manifest and public cache, with no temporary manifest overlay. Exact universal library, required exports and absence of the obsolete helper were verified; privacy scanning passed. It carries an ad-hoc validation signature, no development/distribution identity or team, and no embedded entitlements. Signed app/Keychain/Touch ID checks remain deferred. |
| CI signing | Desktop/mobile build failures now fail their jobs. Apple bundle IDs match the app. Android release builds never silently debug-sign. Signing credentials are used only when explicitly supplied, outside pull-request builds. |
| Deployment log privacy | A later coordination report identified sensitive provider fields in the inherited raw Firebase debug output. The shared action now isolates and cleans credentials/all CLI logs, emits fixed diagnostics, validates URL output and avoids shell-source interpolation. Twenty-seven privacy/failure/cancellation tests, eight URL fixtures and ShellCheck pass; the actual pinned CLI preserves project/target paths from its private working directory. The coordinating Solana task adopted the exact separately reviewed patch as CI commit `c99278a770029fea91581580b111ba989e5a21b5` before another preview; its first protected hosted run exposed the normal combined live/preview URL case. Reviewed follow-up `c9f14d34dc793dd7680da72088ed06aea340b8ad` requires a channel URL for previews and passed hosted run [42542882339](https://github.com/GLEECBTC/gleec-wallet/actions/runs/42542882339). CI result and public build identity were independently verified; the coordinating task confirmed no provider-response fields in the new logs. Historical log cleanup remains an explicit decision; see [the logging record](AUTH_DEPLOYMENT_LOGGING_VALIDATION.md). |
| Update interruption | Optional update dismissal survives route remounts for the session. Newer releases and mandatory-policy escalation still notify. Eight new regressions plus sixteen existing update tests pass. |
| Native return and sensitive operations | A real Android HOME transition emitted only inactive → resumed, bypassing the earlier immediate-lock deadline. The coordinator now starts monotonic grace on unowned inactivity, invalidates queued authority, and preserves bounded owned-authentication returns. Focused coordinator/service/boundary checks passed 173 tests before the final additional regression; the final 4,411-test aggregator includes all corrections. Five exact short-background device-emulator repetitions and compiled-browser immediate/29/31-second checks passed. Secret views close on background; export still waits for fresh authorization after expired grace. |
| Hosting | Preview-only validation passed on immutable version `4a7943088d4ee536` ([run 42538745323](https://github.com/GLEECBTC/gleec-wallet/actions/runs/42538745323)). All 13 served paths match expected bytes and security headers; 12 non-icon paths revalidate and the coin icon keeps its 30-day cache. Actual HTTPS creation, sign-out and cold return passed with zero CSP violations and all 16 executable resources local. This is the exact live-source security rebuild, not a hosted new-onboarding demo; the new onboarding/rollback browser candidate is validated separately below. Deep-link/helper caching was corrected; 81 browser tests, two cache-policy checks and 21 local deployment-guard tests pass. Production main remains unchanged. Production promotion and the separately prepared edge block for Firebase-reserved helper pages are deferred; root-page CSP is not claimed to cover those platform-managed documents. |
| Rollout and rollback | Corrected sealed source candidate `7de39fbcd7507abed6ff7a46f7cef3c441633cf8b2e9c47554aaa2621ba30fc0` passed 60 cross-profile service tests, six actual browser credential transitions, five compiled-browser lifecycle rounds and same-install Android normal → rollback → normal. Both enrollment-disabled readers and stored normal grace preferences remain usable. Whole-artifact/execution-tool hashes, private-path exclusions and negative sealing controls are retained. Production-signing continuity and physical-provider checks remain pending; historical form-only builds are still unsafe rollback targets. |

Final scoped analysis of the credential service/platform adapters, sensitive
settings and file delivery reports no errors or warnings; two pre-existing iOS
share-API deprecation notices remain. Focused privacy tests and the changed SDK
authentication extension have clean analysis.
Whole-repository `flutter analyze --no-pub` still reports 20 errors, all in the
archived source under `docs/local-rc-2026-10-28/`, plus 63 warnings and 2,176 infos
across the repository. It is not a green whole-repository analysis result.

Native publication retained read-only repository permission in `kdf-internal`.
The wallet-only archive download temporarily used the explicitly approved write
permission; it was removed immediately afterward. Both final workflow commits
were independently checked as read-only. See the [gate evidence and workflow
record](../tool/auth_release_gates/README.md).

The final coordinating Solana report also confirms its separate 4,102-test
unit/coverage run (four skips, 47.7% line coverage), Chrome/Safari suites and
native builds at `c9f14d34`. These are supporting branch-specific results, not
replacements for this onboarding checkout's 4,411-test result. The SDK merged-pin
check remains deliberately red until the SDK/auth prerequisites merge and the
wallet is repinned; no gate was bypassed, no merge was performed, and the wallet,
SDK and coins PRs remain drafts. Exact runs and remaining browser-test limits are
in the [coordination evidence](../tool/auth_release_gates/evidence/coordinating-native-ci.json).

Detailed evidence: [native](AUTH_NATIVE_VALIDATION.md),
[Windows](AUTH_WINDOWS_VALIDATION.md), [Linux](AUTH_LINUX_VALIDATION.md),
[browser](AUTH_WEB_VALIDATION.md), [rollback](AUTH_ROLLBACK_VALIDATION.md),
[prepared edge configuration](AUTH_HOSTING_EDGE.md), and
[accessibility](design/authentication/README.md).

## Device access needed

| Device/session | Why it is still needed | Access/setup |
| --- | --- | --- |
| Current Mac with Touch ID | Real Keychain ACL, Touch ID/password fallback and session-lock behavior | **Deferred to a hands-on check at the user's request.** Hardware and a development signing identity are available; Xcode could not provide the matching team/profile for the isolated probe. Later make team `AG6C7BXAD6` available and provision only the unique test namespace documented in the native checklist. Do not use the production wallet keychain group. |
| iPhone/iPad | Face ID/Touch ID, device-passcode fallback, protected-data events, password-manager association and app-switcher privacy | A trusted signed test build and a connected/unlocked device. Cover both Face ID and Touch ID before claiming both; an iPad can supply the second hardware type. |
| Android 11+ | Strong biometric plus PIN per-operation Keystore authorization | A physical device with strong fingerprint/face hardware and a known screen-lock PIN; USB debugging/installation consent if using connected testing. |
| Android 9 and 10 | Separate strong-biometric and time-limited device-credential paths | Physical API 28 and 29 devices if these versions ship with new enrollment enabled. Emulator/API 36 success does not validate them. |
| Windows 11 x64 | Hello, DPAPI account isolation, WTS lock notifications and native engine stability | Interactive desktop with Hello PIN and biometric hardware; a second disposable OS account. Include an NVIDIA-equipped machine because of the historical native-library issue. |
| Linux desktop session | Interactive desktop, locked keyring and login-session behavior | Real Secret Service persistence/loss/restart/delete and offline app startup passed in Docker. A desktop VM is sufficient for the remaining interactive session checks; no biometric promise is made. |

## Exact hands-on rounds

### 1. Normal creation and return — each supported device

1. Start a clean test profile. Create from the opening screen without typing a
   name/password. Count application actions separately from OS confirmations.
2. Accept device protection. Confirm the displayed protection matches the
   capability. In a compatible browser, create the passkey directly from the
   setup card; the explanation must precede any system confirmation. Cancel and
   retry it once. Cancel the provider’s password-save prompt if offered, then
   repeat with acceptance. There must be no application Save action; its status
   must not claim independent wallet backup or guaranteed sync.
3. Quit/force-stop and reopen. The same last-used wallet should be selected with
   at most one automatic challenge. Cancel it: the screen must remain stable,
   with explicit unlock/password/switch/recovery actions and no prompt loop.
4. Unlock using the biometric, then explicitly choose the device PIN/passcode
   fallback. Enter the PIN yourself. Never disclose it to the test operator.
5. Create a second test wallet, switch between them and rename one. Reopen after
   each choice: identity and enrollment must follow the wallet, not its label.
6. Explicitly sign out and restart twice. Automatic entry must remain suppressed
   until an explicit successful unlock.

### 2. Lock timing, OS dialogs and privacy — each device

1. After unlock, background for **29 seconds** and return; the existing session
   may resume. Repeat for **31 seconds**; fresh configured authorization is
   required. Repeat with immediate locking enabled.
2. Lock the OS/device itself (power/lock button, macOS Lock Screen or Win+L).
   Return must require fresh authorization even inside the grace interval.
3. Repeat while a biometric/passcode/password-manager dialog is open. Cancel
   and switch wallets. A late response must not reopen the old wallet or cause
   another automatic prompt. On Android 9/10, specifically return from an old
   canceled credential activity after starting another action.
4. Reveal recovery words/private keys, then background immediately. The secret
   view must close even within 29 seconds, and the app-switcher preview must
   not expose the words. Return must require a new reveal authorization.
5. On a test device, exercise clock changes and a sufficiently suspended app.
   Wall-clock changes or suspended timers must not extend the unlock grace.

### 3. Fresh authorization and recovery — disposable wallets only

1. Back up/confirm the phrase, export the encrypted wallet, replace a password,
   change protection, and delete a test wallet. Each protected action must ask
   for fresh configured authorization. Cancel each before completing it.
   Generated-password flows must not demand that unknown password.
2. After phrase confirmation, there must be no forced custom-password step.
   Sending/swapping must not be blocked by backup status and must not introduce
   another authentication prompt after ordinary review and confirmation.
3. Restore from the phrase into a separate clean profile. Separately restore an
   encrypted file using its actual encryption password. Compare addresses and
   derivation mode; preserve other wallets even if names match.
4. On a clean profile without the encrypted wallet and envelope, a password or
   synced passkey alone must not claim to restore funds. A file export alone is
   not independent recovery without its password.
5. For passkeys, remove/disable only the test credential/provider. Verify stable
   fallback, explicit known-password replacement, and deletion after fresh
   password proof. Cancel replacement: the old envelope must survive. Use a
   fresh browser profile for eviction tests, never clear a personal profile.

### 4. Lockout, enrollment changes and destructive recovery — spare devices

Use a spare device and an independently backed-up empty test wallet. Removing a
device passcode or resetting a keyring can affect every application on that
device; do not perform this round on a personal device containing real wallets.

1. Use an unrecognized biometric until biometric lockout, then the **correct**
   PIN fallback. Do not repeatedly enter wrong PINs or trigger device erasure.
2. Add/remove a test fingerprint/face, remove/reset the test screen lock and
   restart. Follow the actual platform policy: Apple user-presence access may
   remain valid after biometric changes. Failed/invalidated access must preserve
   the wallet and offer recovery, never silently downgrade or replace it.
3. Force-stop during initial setup, protection changes and password replacement;
   repeat with low-storage conditions. Reopen and verify the same wallet and a
   valid access path. Record the boundary reached, not just “it crashed.”
4. Prepare deletion, then lock/cancel/wait over 60 seconds. Expired or stale
   authorization must not delete a replacement wallet. A successful deletion
   must not require another prompt after the engine wallet has been removed.
5. Reinstall/restore the test app and exercise provider loss. Distinguish missing
   wallet data from a missing credential. Never treat an OS/cloud app restore
   as proof that device-only Keychain or Keystore secrets were restored.

### 4a. Native backup destination dialog

1. Start an encrypted-file export and choose a destination within 29 seconds.
   The selected file should be written only after the app has returned; a
   normal chooser must not cause a false password error.
2. Repeat after 31 seconds and with immediate locking. Expect one fresh
   configured unlock before writing. A password-only wallet uses the normal
   lock-screen password entry, not an internally generated password.
3. Cancel the chooser and the return authorization separately. Neither should
   leave backup-complete evidence or export secret bytes. An empty Android
   destination created by the chooser must be discarded on rejection.
4. Lock the device or switch wallets while choosing. The pending destination
   must be discarded; unlocking another wallet must not complete the old save.
5. A browser download request is not confirmed file persistence. Verify the UI
   and metadata do not mark a recovery backup complete solely from that request.

### 5. Screen readers, providers and background engine work

- With VoiceOver/TalkBack (and Windows/Linux desktop assistive tools), check
  reading order, named controls, hidden credential semantics, 200–300% text,
  keyboard-open fallback, reduced motion, and focus returning from OS dialogs.
  Capture screenshots only while no secrets are visible.
- Check the real browser/provider combinations used for rollout: Safari and
  Apple Passwords, Chrome/Android and its selected provider, Edge/Windows Hello,
  and any supported third-party manager. Confirm actual PRF support through a
  completed enrollment, not the existence of a passkey API.
- Run the Windows DPAPI cross-account harness from
  [the Windows checklist](AUTH_WINDOWS_VALIDATION.md). Its synthetic encrypted
  probe must fail under the second Windows user; no real credential is copied.
- One separate funded/testnet round must verify an already-submitted swap or
  authorized automation survives app lock without duplicate execution. A person
  presses every control that commits funds, following
  [the live test brief](SWAP_LIVE_TEST_BRIEF.md). New requests must be blocked
  while locked; mobile OS suspension may pause background execution.

## Evidence to return

For each row record the build/commit, device model, OS version, provider,
pass/fail, number of application actions and system challenges, and timing with
OS-confirmation time separated. Report only non-secret wallet identity/address
comparisons or pass/fail results. Keep OS PINs, wallet passwords, phrases,
private keys, passkey material, and secret-screen captures out of the report.

Failure in identity, recovery, stale authorization, private-data handling or
protection guarantees blocks that platform's rollout. Flags may stop new
enrollment, but must keep existing readers and unlock/recovery paths available.
