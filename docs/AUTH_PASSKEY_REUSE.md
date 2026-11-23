# Reusing a web passkey in the native apps

A user who protects the web wallet with a passkey can choose **Use existing
passkey** in the iOS, iPadOS, macOS, Android or Windows app. The app then
unlocks that device's copy of the wallet with the same passkey. Nobody creates
a second passkey, and no account or server is involved.

The passkey only unlocks a wallet that is already on the device. A fresh
install still needs the recovery phrase or an encrypted backup and its
password. A synced passkey cannot restore a wallet that is missing.

## How it works

1. The user authorizes the change with the wallet's current lock (device
   unlock, a typed password, or nothing for an unattended wallet). This read
   also lets the device vault remove its record later without another prompt.
2. One user-verified WebAuthn assertion for `dex.gleec.com` lets the user pick
   any passkey they hold. It evaluates the PRF extension with a new random
   32-byte salt that belongs to this device's binding only. The web record's
   salt is never used, so the native key and the browser key are unrelated.
   A second assertion for exactly that passkey and salt must reproduce the
   key. Otherwise nothing changes: an envelope that later unlocks could not
   open would strand a generated password nobody has seen. The browser's
   verified enrollment guards against the same failure.
3. HKDF-SHA256 turns the PRF output into an AES-256-GCM key. The key encrypts
   the wallet password into an envelope. The key, credential ID, user handle,
   salt, relying party, revision and wallet key are all bound as associated
   data.
4. The envelope is written beside the wallet's record in the device vault's
   unattended tier and read back. It is decrypted with the same ceremony's key
   and compared before anything relies on it.
5. The device record is removed. **This is the switch.** While a device record
   exists it governs the wallet and the envelope is inert. An interruption
   before this step therefore leaves the wallet opening exactly as before. The
   inert envelope is discarded then, or by the next binding. If the user takes
   longer than the device vault's 60-second deletion grant, removal asks for
   device unlock once more.

Unlocking repeats the assertion with the stored credential ID and salt. A
password change reseals under the same key: one assertion authorizes it, and
the readback reuses that key for up to 30 seconds before it is wiped. Deletion
takes a single-use, revision-bound permit from an unlock with purpose
`delete`, or from engine password verification when the provider is lost.

Only an `invalidated` answer from the device vault counts as its record
governing. Any other failure, such as a busy vault while the UI refreshes,
fails the operation, so a write can never land in front of a governing
envelope. A test build for another relying party keeps its envelopes under
its own slot name.

The passkey's public key stays with the browser that created it, and an
assertion never carries one. The signature therefore cannot be verified here.
The authenticated decryption is the cryptographic gate. Only the passkey that
produced the PRF output for that salt can open the envelope. The app still
rejects a response with the wrong relying-party hash, without user presence and
verification, with another challenge, from an unexpected origin, for another
credential or user, or without a 32-byte PRF output.
On Android the bridge checks that the origin identifies the installed APK's
signing certificate.

In Settings an existing passkey is always an alternative, never the primary
way to lock a wallet: most people hold no passkey for the web wallet, so the
device unlock or wallet password offer stays first.

Code: `lib/services/wallet_access/platform/passkey/` (envelope, checks,
decorator), the service's `useExistingPasskey`, and one `gleec.wallet/passkey`
bridge per platform. The device vaults are unchanged.

### Ways back

| Situation | What the user can do |
| --- | --- |
| Passkey still works | **Use device unlock instead** (authorized by the passkey). |
| Provider lost, password known | **Switch to device unlock using password**, **Choose another passkey using password**, or **Use only the wallet password**. The last one is never behind a rollout flag. |
| Provider lost, generated password unknown | Recover with the phrase. The settings copy points to the password manager first. |
| Envelope unreadable (damaged, or written by a later build) | It reports `invalidated`. It can be replaced or removed after password verification, never opened. |

## Platforms

| Platform | Bridge | Needs |
| --- | --- | --- |
| iOS / iPadOS 18+ | AuthenticationServices platform provider with PRF (`ios/Runner/WalletPasskeyBridge.swift`). Covers iCloud Keychain, third-party passkey managers and phone hand-off. Offered only with a passcode set. | The `webcredentials:dex.gleec.com` entitlement (already in `Runner.entitlements`) and a live AASA file listing the app. |
| macOS 15+ | The same Swift file. It is offered only when the running app carries an associated-domains entitlement. | A provisioning profile with Associated Domains and the entitlement added to `Release.entitlements` (not done here: without the profile, macOS refuses to launch an app that claims it). |
| Android 9+ | Credential Manager 1.6.0 (`PasskeyAuthenticatorChannel.java`). Offered only with a screen lock set. | `assetlinks.json` for the package and **release** signing certificate. The provider must return PRF through Credential Manager. On Android 13 and earlier with older Play services, the library's non-JSON request path drops extensions, so PRF fails as unsupported after the user verifies. |
| Windows 10 1903+ | `webauthn.dll` API v4+, loaded from System32 (`windows/runner/passkey_channel.cpp`). | A provider whose assertions return hmac-secret/PRF: a FIDO2 security key, or Windows Hello or a plug-in passkey manager where they support it. |
| Linux | Not offered. | Reuse would mean libfido2 with a PIN prompt in the app, udev access to security keys, and no phone hand-off. That deserves its own design. |

Security-key PRF on Apple platforms needs iOS and macOS 26.4 APIs. CI's
latest-stable Xcode cannot yet be relied on to have them, so it is not used.

## Rollout

- `WALLET_EXISTING_PASSKEY_ENABLED` defaults to **false**. It gates new
  bindings and "choose another passkey" on native builds. Readers, unlock,
  rotation, the way back to device unlock and deletion work whatever its value.
  Any rollback build must keep them.
- `WALLET_PASSKEY_RP_ID` (default `dex.gleec.com`) lets a test build bind
  passkeys made on a staging host that serves its own association files. The
  app's entitlements must name the same host. Envelopes record their relying
  party, so a build for one host never opens another's.
- The browser flags and flows are unchanged. The browser still creates its own
  passkeys.

## Hosting prerequisites (not changed here)

On 2026-11-18 production served neither association:

- `https://dex.gleec.com/.well-known/apple-app-site-association` returned
  `{"applinks":{"apps":[],"details":[]}}` (Apple's CDN matched it). The
  repository's file, which lists `B52ZCS7TMQ.com.GleecDEX.wallet` under
  `webcredentials`, is not what production deploys.
- `https://dex.gleec.com/.well-known/assetlinks.json` returned `[]`.

Android needs this file, served as `application/json` without redirects:

```json
[
  {
    "relation": ["delegate_permission/common.get_login_creds"],
    "target": {
      "namespace": "android_app",
      "package_name": "com.gleec.gleecdex",
      "sha256_cert_fingerprints": ["<SHA-256 of the app signing key, AA:BB:…>"]
    }
  }
]
```

With Play App Signing, use the **app signing** key's SHA-256 from Play Console
(App integrity), not the upload key. The internal build
(`com.gleec.gleecdex.onboardinginternal`) is debug-signed and needs its own
entry on whichever host it tests against. Firebase's `**` rewrite answers
missing `.well-known` paths with `index.html`, which fails verification closed.

## Acceptance round

This is the round from the auth release checklist. Use disposable wallets and
record no secrets.

1. On the web, create a wallet, protect it with a passkey, and back up the
   phrase. Import the same wallet in the app.
2. In Settings, choose **Use an existing passkey** and pick the web passkey.
   Expect authorization with the current lock, then two passkey assertions to
   choose and verify the binding. Cold-restart the app and confirm that one
   assertion opens the restored wallet. Return to the updated web build and
   confirm that the original passkey still opens the wallet.
3. Repeat with cancellation at each prompt. The previous lock must still open
   the wallet.
4. Change the wallet password while the wallet is passkey-protected. Expect
   one passkey prompt for authorization and one for the reseal, and then a
   successful unlock with the new password.
5. Remove the passkey from the provider and confirm that unlock fails with a
   clear message. Use the password to switch to device unlock, and separately
   to choose another passkey. Then delete the wallet and confirm that no
   envelope remains.
6. Platform matrix: iPhone with Apple Passwords, iPad, a provisioned Mac,
   Android 11+ with Google Password Manager, Android 9/10, and Windows 11 with
   a FIDO2 key and with Hello. Record which providers returned PRF. A provider
   that returns none must show the "can't unlock wallets in this app" message
   and change nothing.

## Automated regression checks

The Dart unit suite covers binding, cancellation, rollback, cold unlock and
recovery. The browser release gate uses disposable Chrome profiles and the
app's Dart vault for storage-level checks.

### Web migration

Build the JavaScript web bundle from the parent of #3641 (`14d6f9b4a`) in a
separate checkout. Build the current JavaScript and Wasm bundles as described in
[Testing](TESTING.md). Use the same public asset preparation for each build.

```bash
for compiler in javascript wasm; do
  GLEEC_TEST_WEB_COMPILER="$compiler" node \
    test_units/services/wallet_access/web_passkey_migration.browser.test.js \
    /path/to/legacy/build/web
done
```

The test enrolls through the legacy runtime, changes the served bundle at the
same origin and reopens the wallet twice. It checks the wallet identity,
credential record, fresh assertions, absence of new registrations, and that
healthy unlock never requests a saved password or shows the lost-unlock
recovery button. The missing-vault case in the regular browser gate checks that
the recovery button appears after vault loss when the password manager may
hold the generated password. It also checks that the app waits for the user's
choice before asking for a password.

### Android bridge on an emulator

Build the signed internal release and the instrumentation APK with the pinned
Flutter and Android SDKs and JDK 21, as used in Android CI. Start a disposable
emulator with a compatible ABI. Disable shrinking for this instrumentation
build so the runner can inspect AndroidX request fields.

```bash
(
  cd android
  ./gradlew --offline -PgleecInternalTesting=true -PgleecPasskeyTests=true -Pshrink=false \
    -Ptarget-platform=android-arm,android-arm64 \
    :app:assembleRelease :app:assembleReleaseAndroidTest
)
python3 tool/run_android_passkey_bridge.py \
  --serial emulator-5554 \
  --apk build/app/outputs/apk/release/app-release.apk \
  --test-apk build/app/outputs/apk/androidTest/release/app-release-androidTest.apk
```

Use the selected emulator's serial and put the Android SDK's platform-tools and
command-line tools on PATH. The runner validates both package names and the
emulator before installing. It checks the production AndroidX request, PRF
parsing with valid and missing output, the installed APK's signing origin,
and provider error classification. This check uses synthetic responses.

### Device-provider acceptance

Use a signed APK with the reuse flag and the exact preview RP ID baked in.
Verify the linked host and installed signer. For an emulator round, first
confirm that the configured browser and provider can enroll and return a PRF
assertion for a disposable credential. Then start the acceptance round from
the pre-#3641 browser bundle and retain the same browser origin and data when
switching to the current bundle.

Record the OS, provider, APK identity and result at each step. During enrollment
and unlock, record which UI appears (Gleec recovery, browser autofill, or OS
credential picker) and when. A real provider test is needed to verify any
password prompt that appears outside the web page.

For an Android binding failure, set the device's `log.tag.GleecPasskey` to
`DEBUG` before reproducing and read `adb logcat -s GleecPasskey:D` with that
device selected. The bridge records discovery or allow-listed assertion, the
request stage, and the result code. The marker contains no provider response
details, credential IDs, or PRF bytes.

## Automated evidence at initial rollout

- 64 new Dart tests: 15 for the envelope, checks and channel, 30 for the
  decorator's state machine, 10 end-to-end through `WalletAccessService` over
  the real decorator, and 9 Security-settings widget states. All are imported
  in `test_units/main.dart`. The full aggregator passed with the four GasFree
  defines: 5,322 passed and 28 skipped (Flutter 3.50.0).
- Mutation checks: removing the one-prompt switch, the passkey-to-device
  branch, the reproduce-the-key check, the busy-vault guard or the inert-slot
  cleanup each fails exactly the tests aimed at it.
- Swift type-checked against the iOS 18 and macOS 15 SDK APIs at deployment
  targets 15.6 and 13.5. Android `:app:compileDebugJavaWithJavac` passed with
  Credential Manager 1.6.0. The Windows channel and window integration compiled
  with `/W4 /WX` against the real Windows SDK headers
  (`windows/runner/test/check_windows_vault.py`). No iOS, macOS, Android or
  Windows app was built or run end to end.
- None of this exercises a real provider, a signed build or a device. Those are
  the acceptance round above.
