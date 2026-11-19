# Moving a wallet between devices, and passkey backups

Two ways to get a wallet onto a new device without typing its recovery phrase.
Both ship switched off.

1. **Move to another phone** (`WALLET_MOVE_ENABLED`): two QR scans between the
   old and the new phone. No network, server or password manager is involved,
   and it works between iPhone and Android in either direction. The old phone
   must be at hand.
2. **Passkey backup** (`WALLET_PASSKEY_BACKUP_ENABLED` plus
   `WALLET_BACKUP_RP_ID`): an opt-in encrypted copy of the seed that a passkey
   unlocks. It is kept in the user's own iCloud Keychain, their Google Drive, or
   a file they save. It covers a lost phone, but only where that passkey can be
   used.

The recovery phrase stays the root of recovery. A passkey backup never counts
as having backed up the phrase, and the phrase prompts are unchanged.

## Move to another phone

1. On the new phone, **Move from another phone** shows a QR code with a
   one-time P-256 public key and a random session ID. Nothing else is in it.
2. On the old phone, **Settings → Security → Move to another phone** scans
   that code first. Only once it reads as a valid code does the old phone ask
   for the wallet's lock, exactly as revealing the phrase does. It then seals
   the wallet to the new phone's key at once, so the seed is never held while
   the camera is open. It shows a second QR code and an 8-digit check code.
3. The new phone scans it, shows the same 8 digits, and imports only after
   the user confirms **Codes match** (see [Check code](#check-code)). The
   wallet opens with a password the new phone generates and keeps (see
   [Opening the wallet](#opening-the-wallet)).

Both screens stay awake while a code is shown. The reply clears itself after
two minutes, when the app goes to the background, or on a lock. The new phone
drops what it opened if it goes to the background, or once its code has
expired.

Construction:
- ECDH on P-256 with ephemeral keys on both sides; keys travel as compressed
  points and are validated.
- HKDF-SHA256 over the shared secret, salted with the session ID and bound to
  both public keys.
- AES-256-GCM, with associated data covering the protocol label, the session
  ID and both keys.

The plaintext is the wallet's name, its type (HD or legacy), the exact phrase
and whether the user confirmed holding it. A camera that sees both codes learns
nothing: the new phone's private key never leaves its memory. A reply sealed
for another offer, an altered code or one older than 10 minutes is refused with
a specific message.

### Check code

Anyone who sees the new phone's code can seal a wallet of their own to it. If
their reply were scanned first, the new phone would open a wallet whose seed
they know, and the user would fund it.
- The check code closes that route: 8 digits over every field of the reply,
  shown on both phones.
- **Codes don't match** discards what was opened and shows a fresh code.
- The digits come from Argon2id (16 MiB, three passes) over the reply.
  Someone filming the old phone sees the real digits; to pass a reply of their
  own off, they would have to seal about 10⁸ replies until one matched. That is
  far beyond the seconds before the user scans.

The one thing no key exchange can stop is the user pointing their old phone at
someone else's phone. The old phone warns before scanning: only scan a code
shown on a phone you own, and Gleec will never ask you to scan or show one.

## Passkey backup

### What a backup is

A JSON record, kept in one store, that seals the wallet to one passkey:
- a random data key encrypts the wallet with AES-256-GCM;
- a key derived from the passkey's PRF output (HKDF-SHA256, salted with the
  record ID) wraps the data key;
- a key commitment (HMAC of the data key) is checked in constant time before
  anything is decrypted;
- every public field is bound as associated data: relying party, credential,
  user handle, creation time, backup flags and transports.

The record holds no wallet name or address in clear. The PRF input is a fixed
value used for nothing else, so restoring needs one passkey prompt and no lookup
first. Each passkey gets its own record. A second passkey (for example one that
reaches Android) is a second, independent backup.

### Creating one

1. The wallet's own lock authorizes reading the seed, as for revealing the
   phrase.
2. **Create:** a passkey for the backup relying party, with a fresh random user
   ID (re-using one would replace an earlier passkey on every synced device).
   PRF is requested at creation.
3. The signed authenticator data is checked: relying-party hash, user presence
   and verification, the credential ID, and the backup flags. A passkey that
   can never leave the device (not synced, not a portable security key) is
   refused, because it could not restore anything elsewhere.
4. **Confirm:** one sign-in with that passkey must reproduce the key from
   creation, or two sign-ins must agree when the provider gave none at creation.
   A provider whose PRF does not reproduce never holds a backup.
5. The record is written, read back from the store, and opened with the
   in-memory key. Only then is the backup shown as ready. Any failure removes
   what was written and tells the password manager the passkey is unused.

The person sees the system prompts only for the lock, the creation and the
confirmation. Each is announced on screen before the system takes over.

### Restoring

**Restore from a passkey backup** on the new device:
1. Look in iCloud Keychain (Apple devices), Google Drive (after Google sign-in)
   or a chosen file.
2. Pick the backup, by date and store.
3. One passkey prompt. A passkey that does not open it says so and suggests the
   passkey it was made with, a system update, or the phrase.
4. Preview the wallet, then open it as in [Opening the wallet](#opening-the-wallet).

**Check on this device** runs the same steps without importing, so a person can
prove a backup opens on their iPad or new phone before they need it.

### Who can restore

Anyone who can use the passkey and reach the record:
- you, on any device where the passkey is available;
- anyone you share the passkey with: Apple shared groups and 1Password both
  allow sharing, and apps cannot prevent it;
- anyone who takes over the account that syncs the passkey together with its
  recovery factor:
  - **Apple:** Apple Account, two-factor, and a device passcode (10-try escrow);
    Stolen Device Protection demands Face ID away from familiar places.
  - **Google Password Manager:** Google Account plus the PIN, or the screen lock
    of any enrolled Android phone; a removed screen lock still works for 64
    days.

The setup screen says this in plain words. Removing a backup stops new restores
from it, but a copy someone already made, or a passkey exported with its PRF
secret, keeps working. The removal screen says so and tells the user to move
their funds if they think someone has the passkey.

### Why its own domain

A passkey's PRF follows its relying party, not the caller. Under the web
wallet's domain, any code running on the web wallet could ask for the backup
key during an ordinary unlock prompt (one prompt can evaluate two inputs). The
backup relying party is therefore:
- **a host only the native apps use.** `WalletTransferConfig.isAllowedBackupRpId`
  refuses `dex.gleec.com`, any parent of it, and anything under `gleec.com`.
  This follows Trail of Bits' review of Kraken's passkey seed backup, which
  recommends a dedicated root domain.
- **served from `hosting/passkey-backup/`:**
  - only the association files and an explanation page;
  - every response carries a `sandbox` CSP (pages get an opaque origin, and
    WebAuthn refuses opaque origins);
  - a Permissions-Policy that disables passkey calls;
  - no related-origins file.
- **given its own DNS and hosting credentials,** no wildcard certificate, and
  certificate-transparency alerts.

### Where it works

PRF across devices is not yet reliable, so nothing below is promised before the
acceptance round passes.
- **Apple Passwords:** Apple devices only.
  - In 2026 developers report one synced passkey giving a different PRF value
    on a second device (iPhone-created passkeys on a Mac; iOS 26 to iOS 18.6).
  - Over QR, iOS 18.0–18.3 returned wrong values; 18.4 fixed that, and a 2026
    recurrence report is unconfirmed.
  - Backups are therefore never created or confirmed over QR, and **Check on
    this device** exists for exactly this.
- **Google Password Manager:**
  - iPhone (iOS 18+, with Chrome turned on as the AutoFill provider), Android
    and desktop Chrome.
  - Android's PRF is closed source, so equal values across devices need proof.
  - It returns the same PRF with or without user verification; the app requires
    the signed UV flag anyway.
- **1Password and Proton Pass:** PRF on iOS; Proton on Android too; 1Password's
  stable Android support is undocumented.
- **Not usable:**
  - Bitwarden and Dashlane return no PRF.
  - Microsoft Password Manager fails PRF at sign-in.
  - Windows Hello and other device-only passkeys are refused.
- **Android 9–13 with older Play services** drops PRF silently; the app refuses
  instead of saving a backup that cannot open.

## Opening the wallet

`AuthManagedImportRequested` → `WalletAccessService.importWallet`:
- generates a 32-character password, stores it in the device vault under the
  protection the user chose (as quick create does), and registers the seed with
  the engine;
- the engine must then return exactly the seed handed over before anything
  counts;
- an interrupted import resumes only for the same name and type;
- a name already taken here fails with `walletAlreadyExists` and the user picks
  another; it is never renamed silently.

## Rollout and setup

| Define | Default | Meaning |
| --- | --- | --- |
| `WALLET_MOVE_ENABLED` | false | Shows both halves of the move (iOS and Android). |
| `WALLET_PASSKEY_BACKUP_ENABLED` | false | Enables passkey backups. |
| `WALLET_BACKUP_RP_ID` | empty | The backup relying party. Empty or disallowed disables backups. |
| `WALLET_BACKUP_GOOGLE_DRIVE_ENABLED` | false | Offers Google Drive as a store. |
| `WALLET_BACKUP_GOOGLE_IOS_CLIENT_ID` | empty | iOS/macOS OAuth client for Drive's app-data folder. |

Before a backup build can work:
1. **Register the backup domain** and point it at a hosting site of its own.
   Deploy `hosting/passkey-backup/`, after replacing:
   - `BACKUP_DOMAIN` in `.well-known/passkey-endpoints`;
   - `PLAY_APP_SIGNING_SHA256_FINGERPRINT` in `.well-known/assetlinks.json`
     (Play Console → App integrity → app signing key; add the internal build's
     key on a test host).
2. **Add `webcredentials:<backup domain>`** to `ios/Runner/Runner.entitlements`
   and the macOS release entitlements (macOS also needs the Associated Domains
   provisioning profile, as for #3622).
3. **Google Drive:**
   - in Google Cloud, an Android OAuth client (package `com.gleec.gleecdex`,
     signing SHA-1) and an iOS client (bundle `com.GleecDEX.wallet`);
   - the `drive.appdata` scope on the consent screen, with its verification;
   - the iOS client ID in `WALLET_BACKUP_GOOGLE_IOS_CLIENT_ID`.

None of these steps has been done.

## Acceptance round

Use disposable wallets with small balances. Every restore must reach identical
addresses with the original device switched off.

1. **Move:**
   - iPhone → Android and Android → iPhone, for an HD and a legacy wallet;
   - both screens stay on while their code shows;
   - a reply scanned after 10 minutes and a code from another app, each
     refused with its own message;
   - a reply a second phone sealed to the same code: it shows other digits,
     and **Codes don't match** imports nothing;
   - camera access denied, then **Open Settings**.
2. **Passkey backup with Apple Passwords:**
   - create on iPhone, check on an iPad and a Mac, then restore on a second
     iPhone;
   - repeat with the creating and restoring devices on different OS versions.
3. **Google Password Manager:**
   - on iPhone (Chrome as AutoFill provider) create a backup in Google Drive,
     then restore on Android;
   - the reverse direction;
   - an Android 10 device on older Play services must refuse at setup.
4. **1Password and Proton Pass:** both directions.
5. **Removal:**
   - remove a backup and confirm the record is gone and the password manager
     hides the passkey (iOS 26 / Android 15);
   - delete the passkey in the password manager and confirm the restore
     message.
6. **Cancellation:** cancel at each system prompt; nothing is left behind and
   the existing lock still opens the wallet.

## Automated evidence

- **330 new tests,** all registered in `test_units/main.dart`:
  - the transfer secret and config (17);
  - the move protocol (39, with an independent vector computed in CryptoKit
    and reference ECDH, HKDF, GCM and Argon2id);
  - passkey registration checks (26);
  - the backup record (15, with a vector computed in OpenSSL);
  - the backup service and its stores (77);
  - the screens (141);
  - a missing-string check (3);
  - managed import (8 service cases, 4 AuthBloc cases).
- **Full suite:** `flutter test test_units/main.dart` with the four GasFree
  defines (Flutter 3.50.0) passed 5,696 tests, with 28 skipped.
- **Mutation checks:** each safeguard removed in turn, and its test caught it:
  - the key commitment;
  - PRF reproduction;
  - the user-verification flag;
  - the backup-domain rule;
  - the engine-seed check on import;
  - stopping a seed read when the app is left.
- **Native:**
  - the iOS Runner Swift type-checks for iOS 15.6 with no errors or warnings;
    macOS type-checks at 13.5;
  - Android `:app:compileDebugJavaWithJavac` passes;
  - `play-services-auth` 21.1.1 is the version already resolved, unchanged.
- **Independent reviews:**
  - **Security:** no Critical or High findings; its seven findings are fixed.
  - **Screens (UX, accessibility, UI security):** no High findings; its Medium
    findings are fixed.
  - Not changed: analytics still count these imports as phrase imports, and on
    macOS the flows open as full pages.
- **Not run:** no device, signed build, real password manager, Google account
  or camera has exercised any of this. That is the acceptance round above,
  after the setup steps.
