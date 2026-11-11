# Native credential storage implementation and validation

The `gleec.wallet/credential_vault` channel is implemented in the native
application runners. It is independent of KDF and stores only the wallet's
unlock credential, not its recovery phrase. Device unlock is not a backup.

## Channel contract

| Method | Arguments | Result |
| --- | --- | --- |
| `capabilities` | None | `available`, `deviceAuthentication`, `protection` |
| `metadata` | `key` | `null`, or `protection`, `enrolled`, positive `revision` |
| `write` | `key`, `value`, `requireAuthentication`; optional `reason` | `null` |
| `read` | `key`, `requireAuthentication`; optional `reason`, `purpose: "delete"` or `"verifyWrite"` | Credential string or `null` |
| `prepareDelete` | `key`; optional `reason` | One-use opaque authorization token |
| `delete` | `key`; optional `reason`, `authorization` | `null` |
| `repairInvalidated` | `key`, `value`, `requireAuthentication: true` | `null`, or `unavailable` where safe repair is unsupported |
| `cancel` | None | `null` |
| `savePassword` | `username`, `password`; optional `title` | `accepted`, `unknown`, `declined`, `unavailable` |

Native lock notifications invoke `deviceLocked` on the same channel. Errors
have a closed code (`canceled`, `unavailable`, `invalidated`, `lockedOut`,
`storageFailed`, `busy`), generic text and no platform details or credentials.
An Android Keystore authorization that has expired is reported unavailable;
only explicit biometric lockout results are classified as `lockedOut`.
Unknown methods return not-implemented. A protected record cannot become
unprotected merely because a subsequent caller supplies
`requireAuthentication: false`.

`metadata` does not prompt or return a credential. Apple reads Keychain
attributes; Android inspects the actual Keystore key policy; Windows verifies
the envelope's metadata against its DPAPI-protected payload and wipes the
temporary native plaintext. Windows metadata inspection is not Hello-bound.

The Dart coordinator must verify a protected read before declaring enrollment
complete. Apple enrollment explicitly obtains device-owner authorization before
inserting a new protected item or upgrading an unattended item. Cancellation
therefore leaves the old state intact. For `read(purpose: "verifyWrite")`, Apple
reuses only that operation's authorized `LAContext`, bound to the exact stored
record, once and for at most 30 monotonic seconds. The read still goes through
the Keychain item's access control with interaction disabled; no credential is
cached for this handoff. Cancellation or device lock revokes the context.
Cancellation and storage errors never justify a fallback read of an existing
protected record.

`prepareDelete` authorizes the current record before irreversible engine
deletion. Its in-memory token expires after 60 monotonic seconds, is bound to
the exact key and record snapshot, and is consumed once by `delete`. Cancellation
or device lock revokes outstanding tokens. A valid token avoids a second prompt
during cleanup; passing a bad, expired or wrong-record token fails closed.
Ordinary deletion without a token retains its authorization requirement. The
Dart service must journal cleanup before deleting the engine wallet: an expired
token or process restart requires explicit cleanup, never a hidden prompt or a
false report that all credentials were removed.
When deletion first needs the wallet password, a successful `read` with
`purpose: "delete"` saves only a short-lived record-bound authorization (no
plaintext password). `prepareDelete` consumes that authorization without a
second challenge. Ordinary unlock reads do not authorize later deletion.

## Platform implementation

### iOS and macOS

`ios/Runner/WalletCredentialVault.swift` is shared by both Xcode projects.
Protected generic-password items use `SecAccessControl.userPresence`, a fresh
`LAContext` and no Touch ID reuse window. iOS uses
`WhenPasscodeSetThisDeviceOnly`; macOS uses the data-protection Keychain and
`WhenUnlockedThisDeviceOnly`. Unattended initial credentials remain device-local
but are classified `osAccountProtected`, not biometric-protected.

Keychain policy and revision metadata are stored on the item. Protected
replacement and deletion perform a protected read first. Item updates do not
delete the previous value before attempting the new write. Work runs on a
serial queue, with completion delivered on Flutter's main thread. Cancellation
and durable mutation share an operation-generation lock. A canceled queued write
or delete cannot later commit. After authorization, the commit checks the same
metadata and persistent Keychain reference and uses a conditional, noninteractive
update/delete, rejecting records changed during the prompt. Cancellation also
invalidates the context and ignores stale completions. Mutable native buffers
are wiped where practical; Swift/Dart string zeroization is not guaranteed.

iOS observes protected-data unavailability. macOS observes session resignation
and screen sleep. These are conservative OS signals, not a claim that every
platform exposes an instantaneous screen-lock callback. The application must
still obscure content on inactivity and evaluate its grace timer on return.

On iOS 26.2+ with a supporting build SDK, password saving uses
`ASCredentialDataManager.save`. Older iOS builds use the shared-web-credential
compatibility API. macOS returns `unavailable` for the application's autofill
fallback. Both iOS save paths require the verified associated domain
`webcredentials:dex.gleec.com`. The production website must serve an AASA file
whose `webcredentials.apps` includes `B52ZCS7TMQ.com.GleecDEX.wallet` and the
release provisioning profile must permit Associated Domains. An accepted save
does not prove that a password manager synchronized it to another device.

### Android

`WalletCredentialVault.java` uses independent Android Keystore AES-256-GCM keys
and authenticated envelopes in private preferences. Key identity, record
revision, role and protection mode are authenticated as additional data.
Credentials never appear unencrypted in preferences. Reads never generate a
missing key. Writes create a new key, commit the envelope and only then remove
obsolete aliases. Ambiguous commit failures retain keys for reconciliation.

Android 11/API 30+ uses a per-operation key and `BiometricPrompt.CryptoObject`
with strong biometrics or device credentials. The key's policy, rather than an
application Boolean, controls decryption. No assertion of StrongBox or hardware
backing is made solely from this capability.
Canceling a live biometric ceremony retains its pending operation until the
terminal AndroidX callback has drained. Terminal handling is deferred to the
next main-loop turn and bound to that particular ceremony; a queued success
after cancellation cannot decrypt, commit or invoke a fallback. This prevents
the dismissed prompt's cancellation from being delivered to an immediately
started enrollment. Disposal settles the canceled operation even if the
destroyed Activity can no longer deliver a callback.

Android 9–10/API 28–29 cannot combine device credentials with a CryptoObject.
Enrollment first creates a separate credential wrapper whose key is authorized
for 30 seconds following the OS device-credential ceremony. Where strong
biometrics are enrolled, an additional auth-per-use biometric wrapper is
created. The biometric prompt's device-PIN action uses the credential wrapper;
no-biometrics and lockout paths use that same fallback. The overall capability
is `recentDeviceAuthenticationBound`. Initial enrollment/readback may require
more than one OS confirmation on these older releases. Removing the screen
lock can invalidate these keys; the code never substitutes an unattended key.
An outstanding legacy device-credential Activity retains its original operation
identity even after cancellation. New operations receive `busy` until that old
Activity result has been drained; it cannot complete a newer continuation.

Android's explicit `repairInvalidated` is available only when all recorded
protected wrapper keys are missing or the OS explicitly reports permanent
invalidation. Lockout, user refusal and generic platform errors do not qualify.
The service must first verify the replacement wallet password with KDF. Repair
then creates fresh authentication-bound protection and compares the original
record before committing; it never reads the old secret or weakens protection.
Failed or declined enrollment preserves the old record and must not prevent
manual-password sign-in. Apple and Windows return `unavailable` for this API;
they do not infer a safe repair from ambiguous storage errors.

When all old Android wrapper keys are proven invalidated, explicit
`prepareDelete` can still authorize their removal through a fresh ephemeral
authentication-bound key operation (the legacy PIN path on API 28/29). This
issues only a record-bound deletion token: it never reads or replaces the old
secret. The temporary key is removed, and commit still compares the original
record. Missing device credentials or declined authentication leave cleanup
pending; the app must not preempt a valid token with an old-key metadata read.

Android 14/API 34+ invokes the framework Credential Manager password-save API.
The password is absent from provider-query candidate data. Older Android
releases return `unavailable` for autofill fallback. `ACTION_SCREEN_OFF`
cancels outstanding authentication and notifies Dart. Existing backup and
device-transfer exclusion rules remain in place.

### Windows

The runner stores versioned, identity-bound envelopes with user-scoped DPAPI
and atomic replacement/readback verification. A per-record, nonblocking named
mutex protects compare/write/delete across app processes. Protected records
use window-bound Windows Hello verification before read, replacement or
deletion. Cancellation and session lock invalidate pending completions; results
are delivered on Flutter's owning thread.

The classification is always `osAccountProtected`: Hello is an application
gate, not a key-release policy cryptographically enforced by DPAPI. Available
Windows 11 desktop interop is required for advertising device authentication;
older systems retain DPAPI storage without that claim. Password-manager saving
returns `unavailable`; Credential Locker is not silently substituted for the
user's selected password manager. Session lock is observed through Windows
Terminal Services notifications.

## Validation performed

- Shared Swift bridge typechecked against the installed macOS SDK and iOS
  target 15.6, including both compile-time branches.
- Xcode project files, iOS Info.plist and the Associated Domains entitlement
  passed property-list validation.
- New Android vault and the changed MainActivity compiled with `javac` against
  installed Android API 36 and cached Flutter/AndroidX artifacts. The only
  deprecation notice is the existing SAF activity-result flow.
- The final bounded offline Gradle retry passed
  `./gradlew :app:compileDebugJavaWithJavac --offline --console=plain` with
  `android/local.properties` selecting pinned Flutter 3.41.4: `BUILD SUCCESSFUL`
  in 36 seconds, 305 actionable tasks (10 executed, 295 up-to-date). This includes
  the Flutter debug build and app Java compilation; it is not an APK/device test.
  The earlier attempt with Flutter 3.44.0 stopped on uncached Kotlin 2.2.20
  `gradle813` assignment/SAM plugin artifacts. The pinned-toolchain retry resolved
  that validation blocker without downloading dependencies. Existing Gradle and
  MainActivity deprecation notices remain.
- Windows native channel and runner sources cross-compiled with Homebrew
  clang-cl 23.1.4, `/W4 /WX /std:c++20`, cached Windows SDK 10.0.26100/MSVC
  14.44, and pinned Flutter 3.41.4 headers. The standalone native harness linked
  as an x64 PE using real DPAPI/WinRT/WTS imports. The reproducible command is
  `windows/runner/test/check_windows_vault.py --flutter-sdk <3.41.4-root>
  --xwin-sdk <xwin-root> --compiler <clang-cl> --linker <lld-link>
  --output <temporary-directory>`. No Windows executable was run; release
  packaging and Windows Hello/device behavior remain unverified. See
  [Windows validation](AUTH_WINDOWS_VALIDATION.md) for the final cross-compile
  evidence and physical-device checklist.

### Native package and local-device follow-up

All Flutter builds use `/Users/charl/fvm/versions/3.41.4/bin/flutter` and
`--no-pub`. No dependency version or lockfile was upgraded.

The frozen merged-SDK/updater snapshot compiled successfully on all three
available native targets: Android release in 1 minute 21 seconds (699 tasks),
unsigned iOS in 48.4 seconds (152.6 MB), and isolated macOS without
development/distribution signing (228.3 MB).
All three actual final artifacts passed the private-fixture/signing-file scan.
The Android artifact was installed over the existing synthetic wallet and
retained its enrollment. Optional-update dismissal now survives Settings and
Security navigation. **Active generated-password deletion initially failed
at runtime on this snapshot:** after successful device authorization, the
UI reports "Password not accepted" and preserves the wallet. Typed diagnosis
identified `WalletAccessException/staleOperation`: the prepared proof,
revision, generation and expiry checks pass, but Flutter still reports
`foreground=false` immediately after native authorization. Foreground handoff
coordination was required; compilation and unit suites alone did not close
this gate. Temporary opt-in diagnosis contained only closed types/enums and
guard booleans, with no raw exception payload or credential. The subsequent
bounded foreground handoff preserves the foreground guard and passed actual
active-wallet removal with both the default 30-second grace and immediate
locking: one fingerprint challenge, no generated-password typing, and no
second cleanup prompt. Cold restart showed Create/Import without another
wallet challenge in both cases.

On the subsequent normal Android build, changing to immediate locking required
fresh device authorization. A 1.06-second background return required unlock;
canceling remained stable for more than 10 seconds and explicit retry worked.
Backup-entry cancellation remained stable for more than 22 seconds. One
explicit retry reached the masked backup screen; no phrase/private-key reveal,
clipboard operation or backup confirmation was performed. Backgrounding for
1.03 seconds closed that screen, and authorized return opened Security main.
Both temporary diagnostic markers were absent from both packaged Android
`libapp.so` architectures; a retained diagnostic build was a positive control.
The final frozen dialog/export source compiled on Android in 1 minute
7 seconds (699 tasks), on iOS in 42.8 seconds (152.6 MB), and in the isolated
macOS staging copy (228.3 MB). All three actual artifacts passed the private
fixture/signing-file scan. iOS is unsigned. `codesign` identifies the Mac app as
**ad-hoc signed**, with no Authority or team: it is not a development-signed or
distribution-signed build, and no matching profile or Touch ID ceremony was
used. This signing-disabled validation app has no embedded entitlements;
release sandbox/network/Keychain behavior must be checked in the separately
provisioned signed build. The source release entitlements retain client/server
networking and sandbox protection and exclude JIT. Its packaged universal
native library exactly matches the verified staged artifact, and the obsolete executable helper is absent. Canonical
artifact publication was pending at that checkpoint; the completed publication
and public-prefetch evidence is recorded below.

Encrypted-wallet export passed on the final Android APK using only an empty
synthetic wallet and disposable destinations. Canceling the default chooser
returned normally. Holding the chooser beyond the 30-second grace required
exactly one fresh device challenge on return; the destination was zero bytes
before authorization and 774 bytes after it. Immediate locking likewise kept
the selected destination empty until one fresh return challenge succeeded
(798 bytes afterward). Canceling that immediate-lock return challenge removed
the empty destination and left a stable locked screen with explicit unlock.
The recovery-phrase reminder stayed visible after both completed exports and
cancellation. No generated password was typed, no export contents were read,
and no phrase/private-key reveal or screenshot was performed. These are
emulator functional checks, not physical hardware assurance.

Final artifact fingerprints (Apple tree hashes combine each sorted relative
file path, a NUL separator, and its SHA-256 bytes; they are validation snapshot
identifiers, not signing identities):

| Artifact | SHA-256 |
| --- | --- |
| Android unsigned APK | `3923358f361348adf0015cefa9da5e264151097f3c6391d6bfde3bf11a9fa922` |
| iOS app tree | `ecdd8e51657cddd759426ef08264f260ab79b8da1689ab25da9162358d8998fc` |
| Isolated macOS app tree | `3be5bbeb0694ed5aac4516e802176e6db0f62a9402698f0c86f8602ffaf327aa` |

The final password-dialog source hash is
`8bee1614fbfc57d95898eced48bb4413127b42f15b813ad6d25d6ed7b2781d4f`.
Both temporary diagnostic markers remain absent from both Android application
library architectures. Final package and sanitized runtime evidence are kept
in `/private/tmp/gleec-native-final-package-evidence.json` and
`/private/tmp/gleec-auth-main-runtime-evidence.json`.
After the export checks, active-wallet deletion passed once more on this final
APK with immediate locking and one fingerprint. Cold restart returned to
Create/Import with no removed-wallet challenge. The synthetic export files and
test app were removed, the dedicated emulator was stopped, and only its
temporary AVD data and test signing copies were deleted. The original ignored
fixture, existing wallets and personal devices were untouched. Cleanup evidence
is `/private/tmp/gleec-native-cleanup-evidence.json`.

- Unsigned iOS release compilation passed in 72.2 seconds using
  `flutter build ios --release --no-codesign --no-pub`. The arm64 app used
  `com.GleecDEX.wallet`, contained the Face ID usage description, and linked
  `komodo_defi_framework.framework` with exported `mm2_main`, `mm2_main_status`
  and `mm2_stop` symbols.
- Android debug APK compilation passed in 31 seconds. The unsigned release APK
  also compiled, including release lint and R8, in 1 minute 22 seconds (699
  actionable tasks). Both arm64-v8a and armeabi-v7a KDF libraries were packaged.
  Release signing now uses explicit `android/key.properties` when supplied;
  otherwise the artifact is unsigned. It never silently uses a debug key.
  `-PgleecUnsignedRelease=true` performs packaging validation without reading
  configured signing credentials.
- These initial iOS/Android package checks exposed a separate privacy blocker:
  the ignored local `assets/debug_data.json` was bundled into the artifacts.
  The generated packages were removed, and the fresh emulator app was stopped,
  cleared and uninstalled. No seed or password was read from the source fixture;
  the source file was not changed or deleted. After the asset exclusion fix,
  clean iOS (45.4 seconds) and Android release (64 seconds) packages rebuilt
  successfully. `python3 tool/verify_wallet_artifacts.py` passed against both
  actual packages, including stale-file detection. The Android release APK was
  independently confirmed unsigned; its arm64 KDF library exports the required
  engine entry points and uses `0x4000` ELF load-segment alignment.
- The final Android release rebuild after the first-launch UI correction and
  native authorization-error classification passed in 1 minute 13 seconds
  (699 tasks), including release lint and R8. Its actual APK and the separately
  test-signed emulator copy passed the artifact privacy scanner. On a clean
  installation, dismissing the update notice exposed Create a new wallet,
  recovery-phrase import, legal links and Explore prices directly. No wallet
  was created or imported during this entry-screen check.
- The macOS build with development/distribution signing disabled was attempted with
  `OVERRIDE_DEFI_API_DOWNLOAD=false`, `FLUTTER_XCODE_CODE_SIGNING_ALLOWED=NO` and
  `FLUTTER_XCODE_CODE_SIGNING_REQUIRED=NO`. It correctly stops at the native
  artifact guard because no verified `bin/libkdflib.dylib` is available. An
  executable-only artifact cannot satisfy credential-bearing startup. The
  obsolete executable-helper signing phase was removed; CocoaPods handles the
  native library's embedding/signing. Release configurations now select
  `Release.entitlements`, without JIT permission, while retaining USB and
  network client/server permissions for hardware wallets and the engine's
  authenticated loopback HTTP RPC.
- A separate source copy subsequently built the full ad-hoc signed macOS validation release
  successfully with the exact pinned-commit universal library built from
  source. Only that copy's macOS archive checksum changed, to
  `a77a26c9814008c958b4f57d928ef59ca01b04b3d0c2710ea49ed8a707cfabd8`;
  canonical release pins were unchanged for that initial validation. The 228.2 MB app passed the artifact
  privacy scanner. Its actual embedded `Contents/Frameworks/libkdflib.dylib`
  contains arm64 and x86_64 slices, the required engine exports and
  `@rpath/libkdflib.dylib` install names. Loading that packaged library on this
  Mac returned engine status zero without starting KDF or touching wallet data.
  The obsolete `Helpers/kdf` executable is absent. The subsequent immutable
  publication and canonical public prefetch are recorded below. This initial
  isolated build did not establish distribution signing, notarization or
  Touch ID runtime acceptance.
- On 2026-11-08, the same universal library passed the full native lifecycle on
  both arm64 and x86_64 under Rosetta, using the exact source commit
  `f9632e0ec771668a6f21b37aede01a30110141cb`, Rust 1.98.0 and unchanged
  `Cargo.lock`. All eight phases passed: load; no-login start/status/stop;
  generated HD wallet creation; fresh password verification and rejection;
  failed cold login preserving the original wallet; password rotation and cold
  return with unchanged identity; persistence canaries; and password-verified
  deletion. These checks used temporary unfunded wallets, native FFI, loopback
  RPC, no enabled coins and disabled P2P. They did not launch a production
  wallet profile. The runtime harness is
  `tool/auth_native_artifacts/runtime_smoke.py`; its recorded SHA-256 is
  `33e6999fb5c02f4d0f16354eb78ffaa15d80c1323cb9c481773f79f220c9bd28`.
  Persisted-file canaries passed on both architectures. Linux `/proc` argument
  and environment scans are not available on macOS and were not counted as
  executed there. This engine validation does not exercise Keychain or Touch ID.
- The verified universal archive is now published as
  [`kdf-macos-universal2-f9632e0ec771668a6f21b37aede01a30110141cb-native-v1.zip`](https://devbuilds.gleec.com/main/kdf-macos-universal2-f9632e0ec771668a6f21b37aede01a30110141cb-native-v1.zip),
  SHA-256 `a77a26c9814008c958b4f57d928ef59ca01b04b3d0c2710ea49ed8a707cfabd8`
  (116,155,484 bytes). Independent full HTTPS verification and the normal
  shipped Dart prefetch both passed. The SDK's canonical JSON and reference
  YAML now select only the full-commit `native-v1` Mac/Linux filenames and their
  exact new checksums; the source commit, other platform pins and coin settings
  were preserved. No SDK HTTP-client change or download credential was needed.
  The old `kdf_f9632e0-mac-universal.zip` was independently downloaded again and
  remains byte-identical: SHA-256
  `6dfc9149ac7b1017e518163788fe8c8a6d45c1270aae66cc74b83f8e20d34835`.
  Sanitized engine provenance is retained in
  `tool/auth_native_artifacts/provenance/macos-f9632e0-native-v1.json`.
- The final macOS release package refresh passed in **69.94 seconds** using the
  published canonical configuration and corrected lock coordinator, with no
  configuration overlay. Its 228.3 MB app passed the artifact privacy scan;
  the 914-file tree SHA-256 is
  `bbb6d2b9598b6b757b222bfa8683b552bb995556b2cce936d8511fec7cd2c79e`.
  The embedded universal library remains byte-identical to the public archive
  (SHA-256 `ea86d0c5f49b48c067e21d658c43a95fa5f0c13000266397064b13c38af58ce4`),
  with both export sets present and no `Helpers/kdf`. Signing was explicitly
  disabled for validation: the resulting signature is ad-hoc, with no
  development/distribution authority or embedded entitlements. The app was not
  launched and no hands-on authentication was performed by this package check.
- No Android physical device was connected. The remembered iPhone 11 was
  unavailable. Available iOS simulator runtimes do not provide the required
  device KDF build; repository instructions explicitly exclude iOS simulators.
  A fresh Android API 36 arm64 emulator profile was created separately from all
  existing profiles. Its initial debug-app launch was contaminated by the local
  debug auto-login fixture and is not evidence of onboarding success. The clean
  release APK was separately copied and signed with a disposable local test key
  for this empty emulator; the unsigned release artifact remains unchanged.
- A separate Android native probe copied the production Java bridge unchanged
  into a unique application ID, without Flutter assets, KDF or internet
  permission. All 22 noninteractive checks passed on the API 36 emulator:
  encrypted local storage/readback, actual key-policy metadata, rejection of
  falsely requested protection, wrong-key/stale-revision/canceled/one-use
  deletion grants, and ordinary deletion. Synthetic canaries were absent from
  the probe's preferences and process logs. Final preference/Keystore cleanup
  passed and the probe was uninstalled. This noninteractive run used no PIN,
  biometric enrollment or authentication prompt, so it does not validate
  protected hardware decryption or the Android 9/10 fallback. Temporary probe
  dependencies were limited to already cached versions; the application's
  dependencies were not changed.
- After configuring a synthetic PIN and virtual fingerprint only on the fresh
  emulator, the unchanged production bridge passed 28 fingerprint assertions
  and a separate 28-assertion device-PIN run. The PIN run used the observed
  system Use PIN flow with a masked credential screen for enrollment, protected
  read and deletion authorization.
  Actual OS prompts guarded encrypted enrollment and a read whose caller set
  `requireAuthentication: false`; native metadata reported
  `authenticationBound`. Protected-to-unattended replacement was rejected.
  The first run exposed an AndroidX prompt-cancellation race; after the native
  drain fix, the original sequence passed, including immediate new enrollment
  after cancellation, original-record preservation, absent canceled new
  records, and purpose-bound deletion with no second challenge. Preference,
  Keystore and internal canary checks passed. These are emulator functional
  results, not proof of physical biometric sensors or secure hardware.
- An actual unfunded wallet was created in the release app with one Create
  action and no typing. Canceling initial OS protection continued to the wallet
  with accurate independent setup reminders and an optional password-save
  offer. Unprotected process restart returned automatically. Enabling device
  protection later required no generated-password entry and used two serialized
  OS confirmations (enrollment and protected readback). Protected cold launch
  selected the remembered wallet and showed one automatic challenge;
  cancellation remained stable for over 11 seconds with usable fallback
  controls. Explicit retry used one challenge and reopened the same named
  wallet; only its backup reminder remained. No phrase or private key was
  revealed and no funds were used.
  UI polling observed the first OS prompt 2.41 seconds after Create and the
  dashboard 4.97 seconds after cancellation. The 20.58-second total included
  13.20 seconds of operator dwell at the observed system prompt. The remaining
  7.38-second upper bound includes UI polling overhead; it is not a validated
  five-second reference-device benchmark or 100 ms feedback measurement.
  A measured 29.03-second background return restored that session without a
  challenge; a 31.03-second return required one device-unlock prompt. These
  checks did not simulate OS process suspension, wall-clock changes or a
  physical device-lock notification.
- This Mac reports Touch ID and device-owner authentication available without
  prompting. An isolated probe copied the production Swift bridge with only
  its Keychain service namespace changed and passed eight noninteractive
  channel/empty-record checks. Apple Development signing and strict signature
  verification passed. Actual Keychain writes require a development
  provisioning profile for the probe's unique app ID/group; neither installed
  profile permits it. No test item or authentication prompt was created. The
  probe never uses the production wallet's identity or Keychain group.

The Android release build initially lacked exact pinned runtime artifacts.
Only the five reported missing modules below were fetched from their existing
official Flutter/Google Maven repositories into a temporary local repository;
all subsequent Gradle resolution remained `--offline`. Published object
digests were verified and SHA-256 recorded. Flutter engine version is
`1.0.0-e4b8dca3f1b4ede4c30371002441c88c12187ed6`.

| Artifact | SHA-256 |
| --- | --- |
| `io.flutter:flutter_embedding_release` JAR | `0e8b39758a5fe6e3f62523935e654e096f021bc4611747ed19a13c494c0d37fa` |
| `io.flutter:armeabi_v7a_release` JAR | `c6fec88c1afdaf2235a40b765d28c88060846999058acbd2e77039eac9b2ff2b` |
| `io.flutter:arm64_v8a_release` JAR | `1a6e8693a314dc88a36dc8d7a16d532941fe8355fdb37cf6efbf697cd707558b` |
| `androidx.appcompat:appcompat:1.2.0` AAR | `3d2131a55a61a777322e2126e0018011efa6339e53b44153eb651b16020cca70` |
| `androidx.appcompat:appcompat-resources:1.2.0` AAR | `c470297c03ff3de1c3d15dacf0be0cae63abc10b52f021dd07ae28daa3100fe5` |

No physical-device biometric ceremonies, provider saves, passcode changes or
recovery tests have been claimed as completed.

## Current Mac Touch ID handoff

This is separate from full-app packaging without development/distribution signing. The current Mac already
reports Touch ID available and has a usable Apple Development signing identity.
The isolated native probe needs a **Mac App Development** provisioning profile
with the following values; no production wallet identity or Keychain group may
be substituted.

| Field | Required value |
| --- | --- |
| Bundle ID | `com.gleec.wallet.credential-vault.probe.4fa56cc4-75db-478a-96c5-5f53385e7a86` |
| Development team | `AG6C7BXAD6` |
| Application identifier / Keychain group | `AG6C7BXAD6.com.gleec.wallet.credential-vault.probe.4fa56cc4-75db-478a-96c5-5f53385e7a86` |
| Local entitlement file | `/private/tmp/gleec-native-vault-probe/Development.entitlements` |
| Embedded profile destination | `/private/tmp/gleec-native-vault-probe/GleecVaultProbe.app/Contents/embedded.provisionprofile` |

The profile must include the installed development certificate and this Mac as
a registered development device. For this Apple silicon Mac, register its
**provisioning UDID**, as specified by Apple's
[device-registration instructions](https://developer.apple.com/help/account/devices/register-a-single-device/),
then create the matching
[development profile](https://developer.apple.com/help/account/provisioning-profiles/create-a-development-provisioning-profile).
Neither installed profile authorizes the isolated probe. No certificate private
key, account credential, device identifier or production profile needs to be
exported into this repository.

Automatic provisioning was also attempted with a minimal isolated Xcode
project, the same unique bundle/group and `xcodebuild
-allowProvisioningUpdates`. Xcode has one configured developer account, but
the installed Apple Development identity's team is unavailable to that account.
There is only one installed Development identity and none matching the cached
configured team. The bounded automatic attempt returned the closed findings
`accountUnavailableForTeam` and `matchingProfileUnavailable`; it did not create
an embedded profile. No app was launched, no Touch ID operation was invoked,
and no account was switched or credentials entered. Device registration was
not enabled. The remaining prerequisite is therefore an authorized profile
for the prepared team/device, or making that team available in Xcode through
the account owner's normal sign-in flow; a missing local profile alone was
not treated as sufficient evidence of a blocker. Sanitized results are in
`/private/tmp/gleec-native-vault-probe/provisioning/provisioning-result.json`.
Mac signing and Touch ID are retained as a hands-on acceptance check; no further
account/profile setup or interactive authentication is being attempted.

After embedding that profile, rerun the prepared `sign-development.py` with
`Development.entitlements`, verify the signature, and run the probe's default
noninteractive storage checks. Its explicit `--interactive` mode is then ready
for a user-present Touch ID/device-credential confirmation, protected enrollment
and real Keychain ACL readback. It creates only synthetic credentials under the
unique test namespace. This interactive mode has not yet been run.

## Required release validation

Use disposable, unfunded wallets for every device test.

Physical prerequisites are a signed iPhone/iPad test build, Android 11+ hardware
with strong biometrics and device credentials, Android 9/10 hardware for the
separate fallback path, and a Windows 11 machine with Hello. The current Mac is
suitable for Touch ID once an isolated test-app development profile is supplied.
User interaction is required at genuine OS authentication/password-manager
prompts. Enrollment changes, passcode removal, reinstall/provider-loss and
cross-account isolation tests must use designated test devices/accounts; they
have not been performed on personal devices.

1. Create and reopen unprotected/protected records; change the caller's
   authentication Boolean and prove an enrolled record still requires its OS
   policy. Exercise cancellation, hardware absence, weak-only biometrics and
   lockout, then verify the original record remains intact.
2. Exercise API 28/29 biometric and PIN wrappers separately, plus API 30+
   biometric/PIN per-operation paths. Change enrollment, remove/reset the
   screen lock and verify no automatic downgrade or regenerated credential.
3. Interrupt writes, kill the process, exhaust storage, replace a record during
   a prompt and reopen after each boundary. Verify surviving credential identity
   and revision. Test Windows concurrent processes and stale Hello completions.
   Cancel queued Apple writes/deletes before their commit, then start another
   operation. On Android 30+, cancel a biometric prompt and immediately start
   enrollment when its result settles; the new operation must show its own
   challenge and must not receive the old prompt's cancellation. Also cancel
   after success is queued and verify that no decryption or write completes.
   On Android 28/29, cancel device credentials and deliver the old
   Activity result after another request; confirm that no new request completes.
4. Test iOS/macOS protected read, overwrite/delete, device-only restoration,
   screen/session lock, and separate app-lock/grace behavior.
   Cancel initial enrollment before insertion and verify no protected scratch
   credential exists; creation may continue unattended only for that new wallet.
   Accept enrollment and verify the immediate `verifyWrite` read is checked by
   the actual item ACL without a second OS challenge. Replace the record or
   expire/revoke its context and confirm the old authorization cannot read it.
5. Verify native save accepted/declined/unavailable outcomes with multiple
   providers. Verify AASA and release signing on a real iOS installation; do not
   infer provider acceptance from an autofill request.
6. Compile Windows on the supported SDK/OS matrix, verify DPAPI isolation
   between Windows accounts, and verify Windows Hello, cancellation and WTS
   lock events on a physical Windows 11 device.
7. Inspect canary values in preferences/files, process arguments and diagnostic
   exports. No credential plaintext may appear there. Runtime memory exposure
   after authorized decryption remains part of the documented threat model.
8. Prepare deletion, then change the record, expire the token, cancel, lock the
   device or restart. Each stale grant must fail without deleting the new record.
   A valid grant must remove the original record without another prompt. Force
   cleanup failure after engine deletion and verify the service retains and
   surfaces its cleanup journal.
9. Remove Android's old Keystore keys, verify a known wallet password, and
   exercise successful/declined/failed protected repair. Verify lockout and
   wrong passwords never trigger repair, and unsuccessful repair leaves the
   manual-password access path usable.
   Retry explicit deletion after key invalidation; require fresh device
   authorization and verify it removes only the unchanged old record without
   reading or replacing its credential.

References: [Apple access control](https://developer.apple.com/documentation/security/secaccesscontrolcreateflags/userpresence),
[Keychain authentication contexts](https://developer.apple.com/documentation/security/ksecuseauthenticationcontext),
[Keychain conditional queries and persistent references](https://developer.apple.com/documentation/security/updating-and-deleting-keychain-items),
[Apple default access groups](https://developer.apple.com/documentation/security/ksecattraccessgroup),
[Android cryptographic authentication](https://developer.android.com/identity/sign-in/biometric-auth),
[Android key authorization](https://developer.android.com/reference/android/security/keystore/KeyGenParameterSpec.Builder),
[Android expired authorization](https://developer.android.com/reference/android/security/keystore/UserNotAuthenticatedException),
[Windows DPAPI](https://learn.microsoft.com/en-us/windows/win32/api/dpapi/nf-dpapi-cryptprotectdata).


## Android rollback acceptance follow-up (2026-11-09)

The clean Android pair below supersedes the earlier Android package checkpoint
for the inactivity correction. It was built from the immutable rollback source
`7de39fbcd7507abed6ff7a46f7cef3c441633cf8b2e9c47554aaa2621ba30fc0`,
using pinned Flutter 3.41.4, cached offline Gradle dependencies, and identical
GasFree production defines. Normal uses device/passkey enrollment enabled and
the saved grace preference. Rollback disables both new enrollment paths and
forces immediate locking while retaining the same credential readers.

Both packages use `com.gleec.gleecdex`, disposable version code `1`, and the
same newly generated test signing certificate. These are validation packages,
not production-signed releases. No personal signing key, wallet, device or
funds were used. Normal packaging took 81.44 seconds; rollback took 75.47 seconds.

| Corrected artifact | SHA-256 |
| --- | --- |
| Normal unsigned APK | `3a48fce796c84996b8e010a3a44518d190eab5b1ff289ca3c6f55f315551463f` |
| Normal test-signed APK | `94ab4de2754cc3b89d98dd7f98b996a6f3b1134cf18b6188f9d2e12f743fcda3` |
| Rollback unsigned APK | `0852d36f434d45cc75b7b63ddf2a908cb9fde06ed33df9848aab3f8cc2ded28b` |
| Rollback test-signed APK | `2194ec61147f5a14cfba9b731d1a17a26069a3b9127fab242812f98589fc7174` |

The [packaged-reader checker](../android/rollback_test/README.md) passed on the
actual pair for arm64 and armv7. It verifies persistent-access and rotation
reader markers, Android Keystore/envelope/cleanup readers, identical native
DEX and KDF bytes across profiles, matching installation identity, required
native exports, and absence of executable fallback, private fixtures, signing
files and temporary diagnostics. Its eight negative/positive unit cases pass.
The private-artifact scanner also passed on both APKs. A separate diagnostic
APK provides a positive control for lifecycle-marker detection; neither clean
package contains that marker. Marker retention is packaging evidence, not a
substitute for cryptographic or restoration tests.

Actual rollback testing found an immediate-lock omission: a short switch to
the Android launcher can emit `inactive` followed by `resumed` without a
`hidden`/`paused` callback. The old coordinator only started its deadline for
full backgrounding. A closed, nonsecret lifecycle trace established this
cause, including a confirmed launcher transition with no outstanding prompt,
completed handoff or background event. The correction starts the original
monotonic deadline on unowned inactivity, preserves owned authentication
handoffs, and counts ordinary file-picker elapsed time. It also bounds access
when an owned prompt finishes while the app stays inactive. No passwords are
cached by the coordinator.

The correction passed 49 coordinator tests plus the broader 173-test
coordinator/service/app-boundary run; the reviewer's additional nested-scope
regression passed separately (50 coordinator cases total). Scoped analysis is
clean, and independent read-only review found no blocker. Five corrected
emulator launcher returns of 1.031–1.041 seconds each required a fresh device
challenge, including the exact previously failing inactive-only path. On the
clean normal APK, a confirmed 29.029-second launcher return restored the
session, while a 31.027-second return required device authentication. Returning
to the normal profile retained the saved 30-second preference; rollback's
immediate override did not rewrite it.

The complete normal → rollback → normal installation round passed on the
same fresh API36 arm64 emulator and app data, using three unfunded wallets:
generated/unprotected, generated/device-protected, and custom-password-only.
All three remained accessible after both profile changes. The protected
wallet retained its enrollment and last-successful-wallet selection. Cold
launch required authentication and bypassed selector navigation; explicit
sign-out survived both restart and upgrade without automatic re-entry.
The custom-password wallet accepted its known password without a managed
credential fallback. The unprotected wallet reported its actual status, and
rollback offered no new device enrollment.

On the clean rollback APK, canceling the cold challenge stayed usable for
12.099 seconds without another prompt. Device-authorized masked backup opened
without typing the generated password, closed immediately on backgrounding,
and required fresh unlock on return. Encrypted export produced zero bytes
before return authorization and 798 bytes after one fresh challenge. Its
recovery-phrase reminder remained. Canceling a second export's return challenge
removed the empty destination and left stable explicit-unlock fallbacks. No
phrase/private-key reveal, clipboard operation or export-content read occurred.
The dedicated app, exports, emulator, AVD, test signing key and test-password
files were removed; disconnection and absence of the disposable state were
verified. Personal devices and the original ignored fixture were untouched.

The retained [sanitized evidence](../android/rollback_test/evidence/2026-11-09.json)
contains actual package/code digests, per-case outcomes and cleanup assertions.
Full local checkpoint evidence remains in
`/private/tmp/gleec-rollback-android/evidence/`; the original failing
source/artifacts and sanitized traces are separate from the corrected pair.
Exact immutable metadata identities and recovery-evidence transitions are
asserted by the separate cross-process service suite, not inferred merely
from matching display names. The prescribed main app suite subsequently
passed 4,411 tests with 26 skips and no failures, including this correction
and the nested-scope regression.

Android 28/29, physical biometric hardware, provider loss and the Apple/Windows
hands-on matrix remain distinct release gates; emulator results do not establish
hardware-backed security assurance.


### Apple packaging after the inactivity correction

The same corrected source compiled as an unsigned iOS release in 75.16 seconds
(68.4 seconds in Xcode), using pinned Flutter 3.41.4 and `--no-pub --no-codesign`.
The actual 152.6 MB app passed the private-artifact scan, retains
`com.GleecDEX.wallet`, and is confirmed unsigned by `codesign`.
Its 960-file tree SHA-256 is
`850ae6a199c990f7b0dffcf6432b82b53874defd4fc324beb393a5c7b2a5f905`.
This supersedes the earlier iOS compilation checkpoint for the coordinator fix;
it does not complete signing, entitlements-on-device, Keychain or biometric
acceptance. Evidence is
`/private/tmp/gleec-ios-inactive-fix-package-evidence.json`.
