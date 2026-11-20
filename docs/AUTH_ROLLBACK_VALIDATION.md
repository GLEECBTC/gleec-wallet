# Reader-preserving authentication rollback

The rollback candidate retains the current wallet, vault and journal readers.
It disables **new** device/passkey enrollment and requires immediate locking:

```json
{
  "WALLET_DEVICE_ENROLLMENT_ENABLED": "false",
  "WALLET_PASSKEY_ENROLLMENT_ENABLED": "false",
  "WALLET_IMMEDIATE_LOCK_REQUIRED": "true"
}
```

An older form-only application is not a compatible rollback. Generated-password
wallets must retain managed credential access, including when enrollment is
disabled. Passkey replacement is new enrollment and is intentionally disabled;
existing passkey unlock, password fallback, authorization, rotation repair and
deletion remain available.

## Frozen candidate

`tool/prepare_auth_rollback.py` freezes explicitly enumerated tracked files and
nonignored source additions from the application and dirty SDK submodule. It
excludes private wallet fixtures, support exports, `.env`, signing files, build
caches, profiles and Git metadata. It does not stage or reset either repository.
The manifest contains a SHA-256 for every copied file, its byte count, base commit
identifiers for provenance, Flutter version and both complete define profiles.
The source digest identifies a **mixed working-tree snapshot**, not a clean Git
commit or an auth-only patch.

The current local candidate is
`/private/tmp/gleec-auth-rollback-candidate-20261109-inactive-fix`, with source digest
`7de39fbcd7507abed6ff7a46f7cef3c441633cf8b2e9c47554aaa2621ba30fc0`
over 4,909 files. Build copies are separate from `source/`; generated build files
cannot alter the frozen source. Public SDK web/coin caches used for the web build
are enumerated and hashed separately in `web-build-inputs.json`. In that disposable
build copy only, automatic asset fetching is disabled; runtime wallet code and
the pinned engine/catalog identities remain unchanged.

`tool/seal_auth_rollback.py` verifies every frozen source byte, binds both browser
artifacts to their successful reader and lifecycle reports, hashes every served file, and
creates a deterministic `source.tar.gz` plus `candidate-evidence.json`. These are
local unsigned candidates. Neither the source archive nor the browser result
claims that a production-signed native rollback has been retained or deployed.

The source archive also retains the 456 explicitly hashed public web/coin build
inputs, so rebuilding the tested browser profiles does not require downloading
those assets again. The corrected snapshot records exactly three deltas from its
parent: the reviewed inactive-only lifecycle correction, its coordinator tests,
and the isolated operation gate in the synthetic rollback fixture. No other
working-tree change was folded into the new candidate. The manifest records the
parent digest and every before/after file hash.

The previous candidate remains intact at
`/private/tmp/gleec-auth-rollback-candidate-20261108`, source digest
`7ff5ac03bc481bbd35918ed4d6a228ffe0d10c9cfd5ac08676cfd621d94cd7ab`.
Its sealed archive SHA-256 is
`1e51b3f519edf9b4f2057a4416d9cd99b8af440d629b0feed91b804bfd187041`,
and evidence SHA-256 is
`733096b2f8633517b4c060e73af4e7c0a974c13cf7049a1bc46e4bc2ff2afe04`.
It is a **pre-fix checkpoint**: its successful credential-reader checks remain
evidence of format compatibility, but Android HOME exposed an inactive→resumed
sequence that failed immediate/grace locking. It must not be selected as the
final lifecycle-qualified rollback artifact. The corrected candidate has passed
new compiled-browser lifecycle checks and is sealed only with their matching
artifact and executing-tool fingerprints.

The corrected sealed source archive is **29,221,756 bytes**, SHA-256
`914f5450754efe84f0fdd52f463be02bc507fdf2bf9d303088cc05590fe9b8bd`.
Its `candidate-evidence.json` SHA-256 is
`365565d615fca2db5cdbb7380d09bbae42f3bf002c2637b48c0c732486cef299`.
All 5,378 archive entries passed the private-fixture/signing/cache/Git path
exclusions. The archive retains 11 exact validation tools and browser helpers in
`validation-tools/`, separately hashed from the immutable runtime source.

## Persisted compatibility contract

| Store | Reader that must remain available |
| --- | --- |
| App v1 | `wallet_access_records_v1`, `wallet_access_pending_v1`, `wallet_access_last_v1`, `wallet_access_signed_out_v1`, `wallet_access_grace_seconds_v1`, `wallet_access_cleanup_v1` |
| Credential identity | `gleec.wallet.<immutable entry ID>`, bound to expected wallet public identity; editable names cannot transfer enrollment |
| SDK catalog | `user_<walletName>`, `wallet_provisioning_<walletName>`, `lastActiveWalletName`; `_wallet_entry_id` and reservation-aware catalog repair |
| Rotation v1 | PBKDF2/SHA-256/600000 + AES-GCM recovery envelope, AAD `gleec.password-rotation.v1:<entryId>`; old password encrypted under the new password |
| Cleanup v1 | Stored record and `engineDeleted` intent; deletion authorizations remain memory-only |
| Recovery | Separate `none`, `phraseConfirmed`, `phraseSupplied`, `encryptedFileExported`, `legacyUnknown`; export-requested and export-confirmed fields remain distinct |
| Browser v1 | IndexedDB `gleec-wallet-credentials-v1`, store `credentials`, active/staged records, revision and origin checks; `browserLocal` nonextractable CryptoKey and `passkeyPrf` envelopes |
| Apple v1 | Keychain service `com.gleec.wallet.credential-vault.v1`, metadata version/protection/revision/record identity; same signing/access-group identity |
| Android v1 | Preferences `gleec_wallet_credential_vault_v1`, local/perUse/legacy envelopes; Keystore alias prefix `gleec.wallet.credential.v1.` and identity/revision/mode-bound AAD |
| Windows v1 | `GLEECV01` DPAPI envelope in the same user/app data namespace |
| Linux v1 | Secret Service or explicitly classified app-local record; retain the durable `.secret-service` policy marker so a missing service never revives a stale local credential |

No unlocked session is persisted. A reader must never reinterpret an absent,
unknown or invalidated protected record as permission to use unattended storage.

## Automated evidence

The cross-process service test executes the real `WalletAccessService`, record,
cleanup and cryptographic rotation-envelope implementations with synthetic
engine/vault adapters. Each phase is a separate Flutter test invocation with
compile-time profile assertions. The writer creates persisted fixtures; the
rollback process reads and repairs them with enrollment disabled; the upgraded
normal process reads the rollback writes. Synthetic credentials reside only in
an owner-only temporary directory that the runner removes on exit.

The corrected snapshot passed **60 tests**: 19 persisted scenarios plus one compile-profile
assertion in each of three processes. The ordinary CI invocation passed 20 tests,
and its file is imported by `test_units/main.dart`. Scoped Flutter analysis found
no issues. The source-selection privacy suite passed six tests, including tracked
private files, ignored assets, symlink escapes and dirty source retention.
The full-suite reviewer found the synthetic fixture was changing the global
operation gate used by later tests. The private-coordinator correction passed
the focused 20 tests and an ordered 32-test rollback/dialog/seed/Solana regression
round. The corrected service report binds 2,033 source inputs directly to the
new frozen candidate, including the fixture isolation correction.

Scenarios cover generated unattended access; existing device enrollment; passkey
service policy; custom password without a managed fallback; provisioning before
and after engine commit; rotation before/after engine update and at vault write;
deletion after engine removal; persisted explicit sign-out; rename; missing
protected credentials; mismatched public identity; unknown record schema; legacy
backup status; confirmed/imported phrase evidence; and encrypted-file evidence.
The rollback process also proves that existing fresh authorization works while
both new-enrollment entry points reject enrollment. Pending protected creation
resumes the original identity without generating another wallet.

The synthetic adapters do **not** prove OS cryptography, signing continuity,
browser CryptoKey persistence or PRF behavior. Actual browser validation is a
separate full-app round using two independently compiled artifacts on the same
origin, Chrome profile, IndexedDB and virtual PRF provider. It checks browser-local
access, verified passkey access and custom-password access through
normal → rollback → normal, exact immutable/public identity and recovery evidence,
unchanged credential envelopes, at most one return challenge, disabled new
enrollment, and explicit sign-out suppression. The browser harness never writes
raw generated passwords, seeds, PRF results or provider credentials to evidence.
Its envelope comparison hashes ciphertext, IV and binding metadata in page
memory. Nonextractable CryptoKeys are never exported; successful real decryption
checks their retained handles. Only digests and whitelisted results leave the page.

The full browser matrix passed on Chrome 156.0.8078.80: all six profile transitions
preserved wallet identity, recovery evidence and the credential envelope. Both
passkey returns performed exactly one challenge. Explicit sign-out remained
suppressed through both transitions. The custom-password scenario also passed
separately; the full harness waits for Flutter to process synthetic field input
before submitting the password form.

| Compiled browser profile | `main.dart.js` SHA-256 |
| --- | --- |
| Normal | `b8f42b368c10e4fa95682461d4e73ea09267d3c37d77cfd80afeb818ff48baad` |
| Rollback | `8f83198e761cca0357082c71387653990d0ae78f68ad21ce809c85c5e095d551` |

These are independently recompiled profiles containing the reviewed lifecycle
correction. Directory manifests in `candidate-evidence.json` additionally bind
deferred Dart code, WebAssembly, worker scripts and all other served files.
Both browser harnesses hash complete source and copied artifact directories before
use, verify unchanged artifacts at completion, and record the exact executing
harness/helper hashes. The service runner checks its input and runner hashes
before and after all three processes. Sealing rejects missing source inputs,
false preservation results, incomplete/duplicate rounds, changed helpers or
artifacts, and Python optimization that would disable assertions.
The source-selection suite passed six tests. The sealing suite passed eight tests:
22 deliberately invalid sealing attempts were rejected before an archive or
evidence file was written, and one valid synthetic candidate sealed successfully.
Independent review confirmed that the identified provenance gaps were resolved.

The separate compiled-app lifecycle round passed with actual monotonic waits:

| Profile and configured grace | Observed inactive time | Return |
| --- | --- | --- |
| Normal, 30 seconds | 29,000 ms | Existing session, no challenge |
| Normal, 30 seconds | 31,001 ms | Locked, one automatic challenge |
| Normal, immediate | 1,001 ms | Locked, one automatic challenge |
| Rollback, forced immediate | 1,001 ms | Locked, one automatic challenge |
| Upgraded normal, retained 30 seconds | 1,002 ms | Existing session, no challenge |

All five interruptions were `blur → focus` while the document remained visible,
with no visibility-change event. Every protected expiry allowed cancellation
and a stable explicit unlock without a prompt loop. The wallet identity and
credential binding remained intact. Rollback enforced immediate locking without
overwriting the stored 30-second preference.

Wallet controls disappeared and an opaque privacy cover was observed in 77–161 ms
in this local headless run; this is observed test timing, not a device performance
guarantee. Each cover matched the first semantically identified cover's PNG bytes
exactly; image data stayed in process memory and was neither saved nor logged.
Flutter's repeated inactive view sometimes omitted its privacy label from the
browser semantic tree, while the pixels and exclusion of wallet controls were
unchanged. Focused/resumed controls returned correctly. This observation alone
does not establish a product screen-reader defect; real assistive-technology
behavior remains part of the hands-on checks.

Native package continuity is validated separately by the Android emulator lane;
see `android/rollback_test/` and `docs/AUTH_NATIVE_VALIDATION.md`. The corrected
clean Android normal → rollback → normal round passed for generated unattended,
device-protected and custom-password wallets without clearing app data. It also
checked retained last-wallet enrollment, sign-out, cancellation, protected backup
and export authorization. Sanitized evidence is
`android/rollback_test/evidence/2026-11-09.json`, SHA-256
`9a51623dffbab29373ec90b5cd503ca95e7b465c6c359a1612f8f8726f730e28`.
Those APKs use a disposable test signer; physical-device key release and
production signing remain distinct from synthetic or emulator evidence.

## Reproduction

Use Flutter 3.41.4 and the locked dependencies. Create a new snapshot directory;
the snapshot tool refuses to overwrite an existing candidate:

```sh
python3 tool/prepare_auth_rollback.py --output /tmp/gleec-auth-rollback-candidate
python3 tool/validate_auth_rollback.py --flutter /path/to/flutter \
  --report /tmp/gleec-auth-rollback-service-report.json
python3 -m unittest discover -s tool -p test_prepare_auth_rollback.py
python3 -m unittest discover -s tool -p test_seal_auth_rollback.py
```

Build `normal-web/` and `rollback-web/` from a disposable copy of the same frozen
source with `flutter build web --release --csp --no-web-resources-cdn`, the manifest's
matching define profile, and verified public build inputs. Do not use the shared
working tree's `build/web` or a personal browser profile.

```sh
GLEEC_ROLLBACK_CANDIDATE=/tmp/gleec-auth-rollback-candidate \
GLEEC_ROLLBACK_REPORT=/tmp/gleec-auth-rollback-browser-report.json \
  node test_units/services/wallet_access/web_rollback_release.browser.test.js
GLEEC_ROLLBACK_CANDIDATE=/tmp/gleec-auth-rollback-candidate \
GLEEC_ROLLBACK_LIFECYCLE_REPORT=/tmp/gleec-auth-rollback-lifecycle-report.json \
  node test_units/services/wallet_access/web_rollback_lifecycle.browser.test.js
python3 tool/seal_auth_rollback.py /tmp/gleec-auth-rollback-candidate \
  --service-report /tmp/gleec-auth-rollback-service-report.json \
  --browser-report /tmp/gleec-auth-rollback-browser-report.json \
  --lifecycle-report /tmp/gleec-auth-rollback-lifecycle-report.json \
  --public-build-input-root /tmp/build-copy/sdk/packages/komodo_defi_framework
```

The harness uses localhost port 18770 and Chrome debugging port 9225. It replaces
only its own copied server root between profiles and keeps the actual browser
storage intact. Changing hostname, copying IndexedDB as JSON, or launching a new
provider without importing its test credentials would invalidate that claim.
The separate lifecycle harness uses ports 18771/9226 and actual monotonic waits;
it never changes the system clock or bypasses the application coordinator.

## Remaining hands-on checks

Retain production-signed rollback artifacts with the same app ID, signing team,
entitlements/access groups, Android signing certificate and OS account context.
Install normal → rollback → normal without uninstalling or clearing app data, and
unlock the same generated and protected wallets. On Apple hardware this includes
the user-deferred developer-team/signing/Touch ID check. Exercise the physical
biometric/PIN/passcode, invalidation and provider-loss matrix in the platform
validation documents. Those checks remain pending and are not inferred from this
source/reader validation.
