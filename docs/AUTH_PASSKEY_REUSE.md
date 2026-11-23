# Reusing a web passkey in the native apps

A user who protects the web wallet with a passkey can choose **Use existing
passkey** in the iOS, iPadOS, macOS, Android or Windows app, or in the Linux
app when that passkey is on a FIDO2 security key. The app then
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
decorator), the service's `useExistingPasskey`, one `gleec.wallet/passkey`
bridge per platform, and on Linux `gleec.wallet/security_key` (see
[Linux](#linux-fido2-security-keys)). The device vaults are unchanged.

### Ways back

| Situation | What the user can do |
| --- | --- |
| Passkey still works | **Use device unlock instead** (authorized by the passkey). |
| Passkey still works, no device unlock (Linux) | **Open without the passkey** (authorized by the passkey): the keyring or app-local record governs again. It is never behind a rollout flag. |
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
| Linux (Ubuntu 22.04+) | libfido2 1.10+, loaded at runtime (`linux/security_key_channel*.cc`), with the PIN and the choice of key asked in the app. USB security keys only: no phone hand-off, NFC or BLE. | `libfido2-1` installed, and udev access to the key for the session (systemd's `uaccess` gives it to the local seat). A key whose web passkey was made with PRF, which the web wallet requires. |

Security-key PRF on Apple platforms needs iOS and macOS 26.4 APIs. CI's
latest-stable Xcode cannot yet be relied on to have them, so it is not used.

### Linux: FIDO2 security keys

The web wallet makes discoverable, user-verified passkeys with PRF, so on a
security key they carry hmac-secret and an empty allow-list finds them.

- **PRF.** libfido2 passes its salt to the key raw. The Dart side sends
  `SHA-256("WebAuthn PRF" || 0x00 || salt)`, as browsers and `webauthn.dll`
  do, and the 32-byte output is the PRF result. The binding's salt is its
  own, so nothing depends on matching the browser's output. The transform
  keeps `salt` meaning a PRF input on every bridge. User verification is
  always requested: hmac-secret keeps a separate secret without it.
- **Client data** is composed exactly as the Windows bridge does, so the same
  assertion checks apply.
- **The sheet** (`SecurityKeyPromptHost`, above the lock cover) asks for each
  step: insert a key, touch the one to use when several are inserted, the PIN,
  the touch, and which passkey when a key holds several. A PIN is never sent
  to a key the user did not pick: a wrong guess spends that key's tries. A
  key with built-in verification is tried without a PIN and falls back to it.
  Tries left show from three down, with a warning at the last: a blocked PIN
  means a reset, which erases the key's passkeys. Three wrong PINs in a row
  need the key reinserted, and the sheet waits for that.
- **The PIN** is checked for CTAP's bounds before it is sent, sent once as
  bytes, wiped after the call on both sides, never kept between assertions
  and never logged. Binding therefore asks PIN and touch twice, as Windows
  does. The field holds it as a Dart string until garbage collection, as it
  does the wallet password, and the platform channel's own copies are not
  wiped. It is sent as typed, without NFC normalisation, so a non-ASCII PIN
  typed in decomposed form would be refused and spend a try.
- **Cancel** from outside (lock, sign-out) also ends a step waiting on the
  user, so the wallet-access lock is never held by an open sheet.
- **No key, no access.** Keys are listed from sysfs, so one the session may
  not open is reported as such rather than missing. A key without
  hmac-secret, or a U2F-only key, cannot unlock wallets. A key with neither
  PIN nor fingerprint cannot hold the web passkey.
- **Build and runtime.** Only libfido2's headers are used to build
  (`libfido2-dev`); `tool/verify_linux_runtime.py` refuses a bundle without
  the bridge or with libfido2 as an ELF dependency. A missing library only
  hides the option. libfido2 1.14's raw authenticator-data accessor is not
  relied on: the bridge strips the CBOR header itself.
- **Cancel** answers at once and sends CTAPHID_CANCEL from the platform thread
  while the worker waits on the key. libfido2 does not document that as
  thread-safe; if a key misbehaves, the key's own touch timeout still ends the
  request, and the next one reports `busy` until then.
- **udev.** systemd 244+ tags FIDO hidraw nodes (`ID_SECURITY_TOKEN`) and
  grants the active local session access. A session without a seat needs a
  group rule such as
  `SUBSYSTEM=="hidraw", ENV{ID_SECURITY_TOKEN}=="1", GROUP="plugdev", MODE="0660"`;
  other init systems set no such tag and need the key vendor's rules (Debian:
  `libu2f-udev`). The app never asks for root.

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
   Count the prompts: one for the current lock, then the passkey twice
   (choose, then verify). Then cold-restart and unlock. Each unlock should
   need exactly one passkey prompt.
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
7. Linux (Ubuntu 22.04 and a current Fedora), with the web passkey on a
   PIN-protected key: bind, cold-restart and unlock. Then check each of
   these: no key until prompted; two keys inserted; a wrong PIN, then three in
   a row (reinsert); a key holding two web passkeys (picker); a bio key if one
   is available; a session without uaccess (the "can't open your key"
   message); and **Open without the passkey**, after which the wallet opens
   with no prompt.

## Automated evidence

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
- Linux adds 58 Dart tests:
  - 29 for the authenticator, including the PRF salt and client data
    against vectors computed with Python's `hashlib`;
  - 12 for the channel and the prompt broker;
  - 6 for the sheet;
  - 9 for the way back to unattended storage, through the decorator and
    the service;
  - 2 for Security settings.

  Each of these mutations fails exactly the test aimed at it: removing the
  salt transform, the PIN wipe, the guard against unattended writes on a
  vault that can protect, or the sheet cancel that ends a waiting step.
- The Linux bridge compiled with `-Wall -Werror` in a release
  `flutter build linux` against libfido2 1.10 on Ubuntu 22.04 (arm64), and
  as a syntax check on x86_64. `linux/test/check_security_key_bridge.sh`
  passed its 76 checks on both. Dropping the UV request or the PIN wipe
  fails it. Without `libfido2-dev` the build is a stub that
  `verify_linux_runtime.py` refuses.
- None of this exercises a real provider, a signed build or a device. Those are
  the acceptance round above.
