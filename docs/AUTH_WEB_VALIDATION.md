# Browser wallet credentials and release checks

The browser vault is `web/services/wallet_credentials.js`, called through
`WebCredentialBackend`. It stores wallet-bound, versioned AES-GCM envelopes in
IndexedDB. Initial `browserLocal` records contain an unattended, non-exportable
CryptoKey and are **not a wallet authentication boundary**. Same-origin code can
use that key. Neither browser persistence nor a saved password is a seed backup.

Passkey enrollment uses the exact current hostname as the relying-party ID.
Production is `dex.gleec.com`; preview hosts are separate relying parties. A fresh
user-verified assertion must return the expected 32-byte PRF output, pass client
challenge/origin, RP hash, UP/UV, credential and signature validation, and decrypt
a persisted staging envelope before promotion. The atomic promotion removes the
previous unattended key and all abandoned staging records. AES-GCM additional
authenticated data binds the record to the wallet key, origin and enrollment.
Deleting browser data removes the encrypted wallet and its metadata: a synced
passkey alone cannot restore either.

Web Locks coordinate ceremonies without queuing surprise prompts. BroadcastChannel
carries revision/protection events only, never passwords or unlocked sessions.
New passkey enrollment is disabled without Web Locks. The low-level credential
reader does not remove existing formats, but the complete app also requires the
SDK's pre-existing Web Locks catalog coordination (see the browser minimum below).
Cancellation, backgrounding and external revision changes invalidate pending
operations. Protected deletion uses a one-use, wallet/revision/generation-bound
authorization token with a 60-second monotonic expiry. A deletion-purpose read can
supply the same fresh authorization so engine verification and credential cleanup
do not prompt twice. Tokens are held only in memory and cleared on locking or
credential changes.

An explicit **Replace passkey using password** action is separate from ordinary
unlock and enrollment. The application must freshly verify the supplied password
against the exact SDK wallet/session before invoking the backend, and capture
the protected record's revision. The bridge requires that same revision and a
Web Lock, then creates and verifies a new PRF envelope before atomic promotion.
It cannot verify the old wallet password itself and never decrypts or releases
the old credential during replacement. Cancellation leaves the previous record
intact. The corresponding explicit password-verified deletion operation grants
only a bounded, one-use deletion token. Neither path is triggered automatically
by a failed or canceled provider challenge. This trusts the application's fresh
SDK proof for destructive changes; it does not turn a JavaScript Boolean into an
authorization boundary for secret reads.

Password Credential API fulfillment is reported as `unknown`, not proof of a
provider save or synchronization. Persistent browser storage is requested best
effort after initial durable creation, with dialogs serialized; denial does not
claim backup or remove access.

A normal browser download cannot confirm that the user retained the encrypted
wallet file. It records `encrypted_file_export_requested`, without setting
`encrypted_file_exported`, `has_backup` or independent recovery evidence. Phrase
confirmation remains a separate action. Fresh authorization and a wallet-bound
operation permit must still be current when sensitive export work is dispatched.

## Automated checks

Use the repository's pinned Flutter version (currently 3.41.4). Do not run a
separate Flutter version's dependency resolution against this checkout.

```sh
node --test test_units/services/wallet_access/web_credential_backend.test.js
fvm flutter test --no-pub test_units/services/wallet_access/web_credential_bridge_test.dart
```

The Flutter bridge test runs the Node security suite, and is registered in the
main app CI aggregator. Node 22 or newer is recommended; no npm packages are
required. Coverage includes real ES256/RS256 verification with a fake provider,
PRF absence/mismatch, malformed assertion fields, corrupted storage, persistence
failures, cancellation, downgrade prevention, rotation, deletion replay/expiry,
and script-policy consistency. This does not simulate an actual provider's
hardware or synchronization guarantees.

An optional isolated Chrome integration test exercises real IndexedDB and a
Chrome virtual authenticator's PRF. It must run against localhost only and creates
and disposes its own fresh browser context. Start an isolated Chrome with a local
DevTools endpoint and serve `web/services/` on localhost:18766, then run:

```sh
node test_units/services/wallet_access/web_credential_backend.browser.test.js
```

`GLEEC_TEST_CDP` selects the local DevTools endpoint (default
`http://127.0.0.1:9222`). `GLEEC_TEST_FIXTURE_URL` selects the local fixture server
(default `http://localhost:18766/`). Use the hostname `localhost` for WebAuthn, not
an IP literal. The fixture must never use a real wallet or user browser profile.

The compiled fixture checks the actual Dart/JavaScript bridge and blocks arbitrary
inline and external-origin scripts under the shipping CSP:

```sh
fvm flutter build web --no-pub --release --csp --no-web-resources-cdn \
  --target=test_units/services/wallet_access/web_credential_smoke.dart \
  --output=/tmp/gleec-auth-web-smoke
# Serve that directory on localhost:18767 in a separate terminal.
GLEEC_TEST_COMPILED=true GLEEC_TEST_FIXTURE_URL=http://localhost:18767/ \
  node test_units/services/wallet_access/web_credential_backend.browser.test.js
```

The fixture source is outside `web/` so it is not copied into production output.
A successful fixture is not a full-app KDF or wallet-recovery test.

The release harness starts its own Chrome process and persistent disposable
profile, takes an immutable copy of the existing `build/web`, and serves it only
on localhost. It refuses to run if the generated bundle contains the private
`debug_data.json` fixture. It stops Chrome and its local server and deletes the
test profile on completion. Do not run it while the source build is being replaced.

```sh
node test_units/services/wallet_access/web_credential_release.browser.test.js
GLEEC_TEST_LIFECYCLE=true node test_units/services/wallet_access/web_credential_release.browser.test.js
```

`GLEEC_TEST_CHROME` may select an installed Chrome executable. The harness uses
ports 18768 and 9223 and requires those ports to be free. It creates no funded
wallet and submits no financial action. The optional lifecycle round adds real
29/31-second background intervals with frozen page timers. The separate recovery
round retains the generated fixture password and recovery phrase only in its
test-process memory, uses neither screenshots nor the clipboard for secrets,
and compares hashes of verified public wallet identity and derivation settings:

```sh
node test_units/services/wallet_access/web_wallet_recovery.browser.test.js
node test_units/services/wallet_access/web_missing_data.browser.test.js
node test_units/services/wallet_access/web_passkey_replacement.browser.test.js
node test_units/services/wallet_access/web_browser_support.browser.test.js
GLEEC_TEST_NARROW_AUTH=true node test_units/services/wallet_access/web_wallet_recovery.browser.test.js
```

The missing-data round uses ports 18769/9224. The replacement round requires a
production build containing the explicit recovery UI and backend APIs. These
optional full-app harnesses are separate from the fast Node security suite,
which currently passes 80 cases through the CI-aggregated Dart bridge test.
The narrow authorization round downloads before phrase confirmation, verifies
only requested-export evidence, and completes passkey-authorized phrase backup
without rerunning imports. Set `GLEEC_TEST_EXPECTED_BUILD_SHA256` to the approved
`main.dart.js` hash to prevent a round from using an older compiled artifact.

## Browser minimum and unsupported startup

The existing SDK catalog requires Web Locks to serialize asynchronous work
across tabs and workers. A process-local mutex or an expiring storage lease does
not provide the same exclusion across engine, catalog and vault writes. This
release makes that existing minimum explicit rather than weakening catalog
safety. [Web Locks specification](https://www.w3.org/TR/web-locks/).

Before Flutter or the optional KDF preload starts, a self-hosted gate checks a
secure context, IndexedDB availability, WebCrypto and a usable Web Locks request.
It probes only a harmless, non-queuing capability lock; it never opens, clears,
migrates or writes wallet storage. Missing or rejected capabilities produce an
accessible message with **Try again**, update/storage/HTTPS guidance, and accurate
recovery instructions. Retry only rechecks; startup proceeds once the required
capability is available. If using another browser/profile/device, the recovery
phrase or encrypted file plus password is still required. Existing data and
credential readers are retained.

Missing PRF or passkey support alone does **not** trigger this gate. A browser
that meets the storage/coordination minimum still receives instant, explicitly
unprotected local creation. The pre-SDK gate cases are part of the Node suite
already imported by the main Flutter CI aggregator; the separate real-browser
round checks blocked startup, preserved protected data, retry and missing-PRF
creation against the built app.

The startup message is one blocked state, with a pending Retry state and no
wallet information displayed. UI-Pro Basis: the repository's design-system,
Flutter accessibility and error-recovery searches, plus contrast, keyboard,
48-pixel target and narrow/large-text checks. Gate Status: **exception**, using
the user's approved current-style exception because the canonical design files
are absent. Owner: browser bootstrap implementation; visual design ownership
remains with the authentication design owner. It uses the existing light/dark
backgrounds and purple action styling, native text/button semantics, a polite
alert and no motion. Follow-up: physical screen-reader review and comparison
with the canonical design reference when supplied. Nonsecret startup screenshots
are recorded under `build/qa/screenshots/auth_browser_support/` by the real-browser
check; they contain no wallet names or secret screens.

## Recorded local validation (2026-11-08)

The Flutter 3.41.4 production build was exercised in an isolated, unfunded Chrome
profile. Creation without typing, automatic return to the existing unprotected
wallet, explicit sign-out across a page restart, and subsequent explicit reopening
succeeded. Security settings enrolled a virtual authenticator's PRF passkey;
IndexedDB then contained one protected active record, no unattended key and no
staging record. A cold page restart reopened that wallet with exactly one
assertion. Aborting a pending ceremony left the same unlock dialog with enabled
fallback actions; its challenge counter stayed unchanged until explicit retry,
which succeeded.

An earlier production candidate's Settings rename flow also succeeded with one fresh passkey
assertion. The header changed immediately; after a page restart, exactly one
automatic assertion reopened the wallet with that same new display label. A
fingerprint of the vault key, credential ID, enrollment ID, revision and protection
matched the pre-rename value, confirming that the existing enrollment survived
the display-name change. No additional credential was created.

The full app loaded the renderer, KDF and worker scripts from the local wallet
origin without observed CSP violations. The compiled bridge fixture also proved
that unapproved inline and external-origin scripts are blocked. These checks use
a virtual authenticator; they do not establish physical-device authentication
or provider synchronization guarantees.

Additional release rounds subsequently verified a full Chrome process shutdown
and restart with the same disposable profile: the unprotected wallet reopened
with the same identity and credential fingerprint. A protected record also
survived process restart when its virtual provider was absent; ending that
unavailable ceremony exposed password/recovery options without replacement or
downgrade. This models provider loss, not a physical passkey provider's ability to
retain its PRF material across restart.

Two real tabs demonstrated removal of the old unattended path, revision-only
broadcast events and immediate Web Locks rejection of concurrent ceremonies.
An injected external revision notification aborted an outstanding challenge.
Flipping a stored ciphertext byte caused authenticated decryption to fail closed
while preserving the record. Actual downloaded diagnostic logs (67–99 current
schema records in the observed rounds) contained no generated-password canary;
the browser console check likewise found none.

Four unthrottled local Chrome 156 measurements, after the local KDF WebAssembly
download completed, observed creation feedback in the semantics tree at
43–59 ms and an opened wallet at 1,758–2,076 ms. A double-requestAnimationFrame
paint estimate ranged from 61–142 ms. There were no OS confirmation prompts in
these initial browser-local creations. These are local-host observations under
concurrent development load, not approved reference-device results. In
particular, the 142 ms paint estimate prevents claiming the visible-feedback
target was met in every observed round.

After the private debug-fixture packaging issue was fixed, an immutable copy of
the clean production build (`main.dart.js` SHA-256
`48e2e4e18046914dbde7728defc56cbf1aa24af1756736620a412efdcc46901c`)
passed file and compiled-manifest exclusion preflights. Two clean-build creation
rounds observed semantics feedback at 48/41 ms, paint estimates at 136/63 ms,
local creation at 1,914/1,770 ms, and navigation-to-open-wallet at
3,538/3,169 ms. Both had zero system challenges and zero observed CSP violations.
The latter KDF asset download took 83 ms and completed 402 ms after navigation.
The timing separates local work from OS confirmation time (zero in these rounds)
and does not establish a reference-device performance guarantee.

With real browser visibility changes and page timers frozen, the 29-second return
reused the existing session with no assertion; the 31-second return performed
exactly one fresh assertion before reopening. A full Chrome restart without the
virtual provider preserved the protected record. Its **Use password** action
successfully reopened the same wallet with the known fixture credential, without
downgrading the stored protection. This exposed the need for the explicit
replacement flow described above; its new backend passes the security suite.

The clean full app completed generated-password phrase backup and all phrase
confirmation selections through fresh passkey authorization, with no unknown
password entry or forced custom-password choice. Encrypted-file export likewise
required no unknown-password entry and contained neither plaintext phrase nor
password. Separate phrase and encrypted-file imports both preserved a hash of
the verified SDK public identity and derivation options while creating distinct
immutable entries. After those real actions, browser console messages and an
actual 33,517-byte downloaded support log contained neither the fixture phrase
nor generated-password canary. Secrets stayed in test-process memory; no seed
screenshots or clipboard operations were used.

The missing-credential cold-process check preserved the encrypted wallet and
allowed its known password to reopen the same verified identity. Missing encrypted
wallet data separately preserved the vault, offered phrase/file import, and did
not generate or claim a replacement wallet. Clearing the disposable origin's
local data while retaining its virtual provider credential returned to the
create/import entry with no automatic assertion and no wallet data: the retained
passkey and known password alone did not recover a wallet. Final
replacement/deletion UI checks are recorded separately below.

The subsequent build containing explicit passkey recovery (`main.dart.js` SHA-256
`043cff271b2c65ac87381ea43bdcdcde22a04beb69bb040e5a01895f1064b002`)
passed the complete release harness. Creation feedback was observed at 45 ms
(71 ms paint estimate), local creation at 1,793 ms, and navigation-to-wallet at
3,073 ms. KDF asset download took 69 ms and ended 401 ms after navigation. OS
challenge time was zero and no CSP violation was observed. The frozen-page
29-second round returned after 29,052 ms with zero new assertions; the 31-second
round returned after 31,343 ms with exactly one. Full browser restart, two-tab
coordination, corrupted-envelope preservation and known-password provider-loss
fallback all passed again.

On that build the actual explicit replacement UI rejected a wrong password
without starting a provider ceremony, preserved the previous protected record
when setup was canceled, enrolled a new provider only after verified registration
and assertion, and reopened through exactly one assertion after page restart.
The deletion step exposed a separate reachability issue: switching wallets signs
the engine out before the selector, so active-wallet password deletion needs a
Settings entry and correct engine-shutdown sequencing. The correction is
validated on the merged-SDK artifact below.

### Merged-SDK artifact

The merged-SDK production artifact has `main.dart.js` SHA-256
`3a5b41f4a6728aecf7f8ed4ea6f12dbc622b3902f5758e7dc3511a8aa2a818af`.
It contains the complete merged SDK authorization prerequisites, active-wallet
deletion sequence, optional-updater dismissal correction and browser startup
minimum. Each final browser round copied this same artifact to an immutable,
disposable fixture after checking the private fixture and compiled manifest were
absent. The built credential and browser-support scripts matched their sources.

The real startup-gate round passed. Removing Web Locks before navigation blocked
Flutter and KDF before loading their executable resources, preserved the existing
protected vault fingerprint, and initiated no assertion. Retry while capability
was missing remained usable. Restoring capability and retrying reopened the same
wallet through exactly one assertion. Light/dark screenshots at 1,280 pixels and
320 pixels with 200% text were reviewed; text reflowed without horizontal
overflow, the page remained vertically scrollable, and the native action retained
a 48-pixel target and keyboard focus. Reduced-motion mode disabled the loader
animation. A separate profile with passkey capability absent still completed
durable instant creation in the accurately classified `browserLocal` state.

The final explicit-replacement round rejected a wrong password without invoking
the provider, preserved the prior record on cancellation, and accepted a new
provider only after usable PRF registration and assertion. The subsequent cold
page return used exactly one assertion and retained the same protected record.
After removing that provider, **Settings → Security → Review wallet removal →
Use password** completed active-wallet deletion with the known fixture password.
Both credential records and encrypted engine-wallet rows were absent afterward;
cold return stayed signed out with no challenge and no replacement wallet.

The fresh final-artifact recovery round completed generated-password phrase
backup and confirmation through passkey authorization without unknown-password
entry or a mandatory custom password. Encrypted-file export also required no
unknown-password entry and contained neither plaintext phrase nor password.
Independent phrase and encrypted-file restores both matched the verified public
wallet identity and derivation-options hash, with distinct immutable entries.
Browser console messages and the actual 43,412-byte support export contained
neither the fixture phrase nor the generated-password canary. Secrets remained
in test-process memory; no secret screenshots or clipboard operations were used.

The test driver now waits for the new document's loader before semantic actions
after navigation, and resolves, validates and activates the current control
atomically. Previously the departing DOM or a semantics rebuild between lookup
and click could make the fixture throw a TypeError or miss a control. File-chooser
failure also now reaches cleanup instead of an unhandled rejection. No production
behavior changed for these test-only corrections. The pure Node suite passed all
80 cases again, and the web Dart adapter passed targeted analysis with no issues.

The process-restart, missing-data and frozen 29/31-second samples above retain
their explicitly recorded earlier artifact hashes. They were not silently
relabeled as final-artifact results. This final narrow round did not remeasure
reference-device performance or physical provider behavior.
The final browser-support and replacement/deletion rounds passed again with the
corrected navigation helper. All owned disposable profiles, downloaded fixture
exports and immutable build copies were removed; no fixture servers or Chrome
debug endpoints remained on ports 18766–18769 or 9223–9224. The user's browser
and the original private development fixture were not modified.

### Final sensitive-authorization regression artifact

The subsequent final artifact has `main.dart.js` SHA-256
`43f7b16897e483f75def9c154bb91b837333e2fab20d5173095659224568eb79`.
It includes the sensitive foreground handoff, post-authorization operation
permits, export-destination authorization, requested-only browser download
evidence and explicit sensitive-dialog cancellation handling. Both narrow browser
rounds required this exact hash, took immutable local copies, and passed the
private-asset preflight. No production source changed during these checks.

On a fresh generated-password wallet with a virtual PRF passkey, encrypted-file
download completed before any phrase backup. Fresh passkey authorization required
no unknown-password entry. The saved catalog recorded
`encrypted_file_export_requested: true`, with neither `encrypted_file_exported`
nor `has_backup` true and recovery evidence `none`; the visible **Backup seed
phrase** reminder remained. The probe returned only those whitelisted flags,
keeping the catalog and its local key inside the disposable browser. The actual
download contained neither plaintext fixture phrase nor password.

The same wallet then completed passkey-authorized phrase reveal and confirmation,
recorded `phraseConfirmed`, and required no custom-password selection. The export
remained unconfirmed independently of that phrase evidence. Browser console
canaries contained neither the generated password nor phrase.

The other narrow round again rejected wrong-password replacement without a
provider ceremony, preserved the protected record on replacement cancellation,
and reopened a usable replacement through one automatic assertion. A second
cold launch initiated exactly one challenge; cancellation left the unlock
fallback usable and the vault unchanged, with no repeated prompt. Only explicit
retry started the next challenge and reopened the same wallet. After removing
the virtual provider, password-authorized active-wallet removal cleared both
credential records and encrypted engine-wallet rows. Cold return stayed signed
out and initiated no challenge.

Earlier full seed/file restoration identity, missing-data, process-restart,
support-export, frozen-page timing and performance rounds keep their original
artifact hashes above. They were not repeated or claimed as measurements of this
narrow final artifact. Physical providers, reference devices and deployment
checks remain separate release gates. Both final profiles, downloads, immutable
copies and local browser/server processes were cleaned up afterward.

## Hosting contract

All production builds must use `--csp --no-web-resources-cdn`. The custom Flutter
bootstrap resolves CanvasKit under the wallet's own origin. The HTML meta policy
and Firebase response policy permit only same-origin executable scripts,
WebAssembly compilation, and an exact hash for the existing structured-data
block. Arbitrary inline scripts, JavaScript eval and third-party executable
sources are excluded. Styles and data/network connections have separate policy
allowances. Data-only Matomo analytics remains available; Firebase initialization
is disabled on web because FlutterFire imports executable scripts from gstatic.
Native Firebase is unaffected.

The meta policy is a fallback for hosts other than Firebase. Every host serving
`dex.gleec.com` must also emit the response headers from `firebase.json`, including
`Content-Security-Policy` with `frame-ancestors 'self'`, `X-Content-Type-Options:
nosniff` and the existing other security headers. Do not add `unsafe-inline`,
`unsafe-eval`, CDN script allowlists or parent-domain RP IDs to work around a
failed release. Verify the built application starts the bundled KDF under this
policy. Audit same-origin executable dependencies: CSP cannot protect against
compromised code that is legitimately hosted on the wallet origin.

`web/.well-known/apple-app-site-association` declares
`B52ZCS7TMQ.com.GleecDEX.wallet` under `webcredentials.apps`. Firebase's ignore
rules deliberately preserve `.well-known`, and its matching header serves
`application/json`. `hosting.appAssociation` is explicitly `NONE` so Firebase
serves this file instead of generating a different association from project apps.
Firebase documents automatic association as the default, and its maintainer
recommends `NONE` for a custom file. [Firebase configuration documentation](https://firebase.google.com/docs/hosting/full-config),
[Firebase maintainer guidance](https://github.com/firebase/firebase-tools/issues/2134#issuecomment-614918362).
The root `/` entry also explicitly revalidates so stale entry HTML cannot omit
the newly introduced credential bridge. The three wallet service scripts also
revalidate alongside the compiled application to avoid stale bridge APIs. Check
deep SPA entry routes after deployment as well as `/`; response policies are
matched against the requested route before rewrites.
[Firebase header matching](https://firebase.google.com/docs/hosting/full-config#headers).
On the actual `dex.gleec.com` host, serve
the association file at the exact
HTTPS path `/.well-known/apple-app-site-association`, without authentication,
redirects or substitution by the SPA rewrite. Confirm the signed app entitlement
and bundle/team identity agree. Preparing this artifact does not establish that
Apple has fetched the production association; verify hosting after deployment.

A restrictive Permissions-Policy or parent iframe can prevent WebAuthn; wallet
credential operations reject embedded contexts. Supported PRF capability is
confirmed by enrollment and a subsequent assertion, not inferred solely from
`PublicKeyCredential` existence.

## Production observation (2026-11-08, 19:41:21 UTC)

Read-only requests to `https://dex.gleec.com/` returned HTTP 200 with CSP only
`frame-ancestors 'self'`, no meta CSP, and two inline executable scripts. The
root response declared a 3,600-second cache lifetime. The live bootstrap lacked the local
CanvasKit override; code inspection selected its gstatic fallback, but this was
not a live network-execution trace. The association URL returned HTTP 200
`application/json` containing only empty `applinks` configuration, with no
`webcredentials` or wallet application ID. [Wallet entry](https://dex.gleec.com/),
[live bootstrap](https://dex.gleec.com/flutter_bootstrap.js),
[live association](https://dex.gleec.com/.well-known/apple-app-site-association).

These observations describe the previous deployment. The prepared strict policy,
local scripts and custom association are not established on production until an
authorized deployment and fresh header/body checks succeed. No deployment was
performed during that read-only production audit.

## Acceptance still requiring devices and deployment

Physical-device biometric/PIN fallback, provider loss, deleted passkeys, storage
eviction, OS suspension/lock behavior on physical devices, passkey-provider
persistence across browser restart, signing identity/domain
association and the supported browser/provider matrix remain release checks.
Automatic prompting is best effort; cancellation must leave an explicit Unlock
button. Browser system-lock detection is limited. Full-app creation timing must
be measured separately from OS-confirmation time on reference devices; virtual
authenticator fixtures do not establish that target.

## Hosting-only candidate against the current production baseline (2026-11-09)

This separate security candidate does **not** roll out the authentication overhaul.
A read-only Firebase release capture identified the deployed app as source
`7154c3c578ea1456543dd6c1b00ebd45053485e0`, SDK
`dac63d7e8ce6fc2583862dcb69e56c01a8dc6494`, and live version
`sites/gleec-wallet-official/versions/05f0079ed5c6ab96`. The original public main
bundle SHA-256 is
`185236d23e35594cb201a92065b690c2fd623905aef25ed54b8301caef9040c3`.
That finalized hosting version is the rollback anchor for this limited deployment.
The original file list and response hashes were captured before preparing the
candidate; no production configuration was changed by these local checks.

A header-only change fails: the original HTML has executable inline startup code
and its Flutter loader requests a CDN renderer. Extracting those startup snippets
and serving the renderer locally still produces six policy violations from web
Firebase core/analytics module injection. The candidate therefore rebuilds only
that deployed source with Flutter 3.41.4, `--csp`, and
`--no-web-resources-cdn`, disables that web-only Firebase analytics path, retains
the existing data-only Matomo settings, and retains native Firebase behavior.
The lockfile is unchanged. The deployed KDF binary, bundled coin assets/config,
and disabled GasFree feature settings are preserved. The compiler engine differs
from the previously deployed compiler; this is a baseline-source rebuild, not a
claim of byte-identical compiled application behavior.

The remaining changes are self-hosted startup/checkout helper scripts, explicit
public-asset inclusion, strict application CSP and security/cache headers, and
custom AASA delivery with `appAssociation: NONE`. The packaged dependency's t-rex
helper scripts are also extracted into local files. The generated service worker
uses the existing cleanup/unregister pattern; no offline wallet backup capability
is introduced. No new credential-vault bridge or new onboarding source is bundled.
The source patch was applied to a second pristine archive of the exact baseline:
`git apply --check` and byte-for-byte comparison of all 12 changed files passed.

Candidate manifest:

- ZIP SHA-256: `a26c400356a4327a86c423ee6e202af13314dc5cc54c0134c6b4794b04a17c0d`.
- Main bundle SHA-256: `57ff05372df7031c5e9213198bd4ad9bfcb6b8749f297c0dcd999c15e531d7e9`.
- Hosting configuration SHA-256: `e14db95bfd1da7df2b9de0f32cec0a14a94cee7bca2e1313666de1fc4eb9786d`.
- Source patch SHA-256: `5404f66556730904007a2f660367a180de2dbda15298dddbe399f765045f8278`.
- Exactly 845 ZIP entries, only `firebase.json` and allowlisted `public/**` files;
  31,670,384 compressed bytes. Actual build and ZIP privacy scans passed.

Disposable Chrome checks on that exact main hash passed ordinary password-form
creation, settings sign-out, cold reload, and password sign-in to the same unfunded
wallet. All 16 loaded JavaScript/Wasm resources came from the local wallet origin;
there were zero CSP violations. Separate helper-page checks passed approved and
rejected fiat targets, the existing Bitrefill target, checkout completion, and
the packaged game helper, again with zero CSP violations. Provider navigation was
blocked by the fixture, so this does not claim a real checkout or transaction test.
The existing app's validation update required waiting for a render frame before
the fixture pressed Create; this was a test-driver timing correction, not a
production behavior change. Owned profiles and local servers were removed.

An additional compatibility test created an unfunded password wallet with the
captured original production main bundle, signed out, closed the browser process,
and reopened the same disposable profile and local origin with the candidate.
The original catalog entry remained, the original password unlocked the wallet,
and an in-browser SHA-256 comparison confirmed the encrypted KDF wallet record
was byte-identical. No decrypted phrase, password or wallet record was printed.
There were zero CSP violations after the upgrade. This check used the original
and candidate main hashes recorded above and did not alter the frozen candidate.

### Firebase reserved-route coverage limitation

Live read-only responses for `/__/auth/handler` and `/__/auth/iframe` are
Firebase-managed HTML with inline scripts and no CSP. The versioned reserved
Firebase SDK route also bypasses the site's headers. Firebase gives reserved
`/__` routes priority over custom redirects, files and rewrites; the normal site
configuration cannot replace them. See [Firebase reserved URLs](https://firebase.google.com/docs/hosting/reserved-urls)
and [hosting response priority](https://firebase.google.com/docs/hosting/full-config).
No content-injection exploit was established by these observations. These are
trusted hosting-provider helper pages, but they prevent an assertion that the
application policy is enforced across every executable page on the origin.

The read-only DNS check showed `dex.gleec.com` points directly to
`gleec-wallet-official.web.app` (Firebase address `199.36.158.100`); Cloudflare is
currently authoritative DNS, not an HTTP proxy for this path. Closing the reserved
route coverage gap needs a separately reviewed edge/hosting control. No DNS,
proxy, Worker, account or service changes were made by the candidate checks.
Production or preview verification must report this residual explicitly, and must
verify actual header/body bytes after deployment rather than inferring delivery
from the repository configuration. The security candidate does not satisfy
physical biometric/provider acceptance for the new authentication release.

### Preview-only scope clarified

The requested deployment scope for this round is pull-request/isolated previews.
Production hosting promotion and Cloudflare routing/activation are deferred.
A passing preview establishes the candidate's served application-owned CSP and
AASA configuration; it does not establish production activation or coverage of
Firebase's reserved namespace. The prepared production rollback anchor above is
retained as evidence, not an instruction to promote this candidate.

Read-only GitHub lookup found no existing pull request containing the complete
instant-creation/passkey overhaul. Legal PR #3558 is already merged and the
separate Solana PR #3611 does not provide this preview. The corrected onboarding
build with main SHA-256
`b8f42b368c10e4fa95682461d4e73ea09267d3c37d77cfd80afeb818ff48baad`
comes from a mixed working-tree snapshot (manifest SHA-256
`7de39fbcd7507abed6ff7a46f7cef3c441633cf8b2e9c47554aaa2621ba30fc0`),
not a published auth commit. An auth-scoped PR and its ordinary preview build must
be identified before labeling an existing hosted preview as that final source.


### Served isolated preview verified (2026-11-09)

[Security baseline preview](https://gleec-wallet-official--auth-security-20261108-ke7ob56c.web.app)
serves Firebase version `sites/gleec-wallet-official/versions/67d7ebc3d2b94638`.
[CI run 42537721568](https://github.com/GLEECBTC/gleec-wallet/actions/runs/42537721568)
bound the uploaded artifact to the complete remote file/hash map, exact hosting
configuration and preview channel identity. This is the same baseline ZIP/main
hash recorded above, not the new onboarding build. No production promotion or
Cloudflare routing change occurred. An independent read-back of `dex.gleec.com`
confirmed the original production main hash is unchanged and its root still
returns the previous `frame-ancestors`-only CSP.

Independent HTTP checks then verified exact candidate response bytes and the
strict CSP, `nosniff` and `SAMEORIGIN` headers on ten application-owned paths:
root, index, a deep SPA route, main, bootstrap, extracted startup script, AASA,
fiat HTML/JS, and the packaged game helper. AASA returns the exact configured
`webcredentials.apps` identifier with `Content-Type: application/json`; Firebase
is no longer substituting its generated association on this preview.

Root/index/main/bootstrap/startup script responses use
`no-cache, max-age=0, must-revalidate`. Fiat helper HTML/JS revalidate, and AASA
uses its configured one-hour cache. The `/wallet` SPA rewrite and packaged t-rex
HTML retain Firebase's default `max-age=3600`. Consequently, this configuration
does not promise immediate deep-link shell refresh during subsequent preview
updates; a default revalidation policy would be a separate configuration change.

A fresh disposable Chrome profile on the actual HTTPS preview passed ordinary
password-form wallet creation, settings sign-out, cold reload, and unlocking the
same unfunded wallet with its password. All 16 executed JavaScript/Wasm resources
came from the preview origin and there were zero CSP violations. The profile was
removed afterward; no user profile, funds or production wallet was involved.

The actual preview independently confirms the reserved-route limitation:
`/__/auth/handler` and `/__/auth/iframe` return HTTP 200 with one inline script
and no CSP, and the reserved versioned Firebase SDK script also has no CSP.
This is reported as provider-managed policy coverage, not a demonstrated
content-injection exploit. Reserved-namespace edge activation remains deferred
under the preview-only instruction. Passing this baseline preview does not
satisfy the new onboarding preview or physical-device acceptance checks.

### Default cache revalidation follow-up

The initial preview exposed a stale-shell gap: Firebase applied its one-hour
cache default to deep SPA rewrites and packaged helper HTML. The reviewed
configuration now supplies `no-cache, max-age=0, must-revalidate` as the default
for all application-owned responses. The explicit coin-icon exception remains
`public, max-age=2592000`; AASA now inherits revalidation instead of overriding
it with a one-hour cache. Script/provider allowances, content, wallet code and
production routing are unchanged.

A focused regression checks the catch-all default, icon exception/order and
absence of any other positive cache-age override. It lives in the existing
Node browser suite invoked by `test_units/main.dart`; both scoped hosting tests
and the complete 81-test browser suite passed. The baseline ZIP remains unchanged. The exact static hosting overlay is
SHA-256 `4ba5e021a0ce94f8e0b02f30635367d6586e0b31d31d052505faf020678c27fd`.
Actual served verification of this overlay passed as recorded below. The earlier
one-hour observations describe the superseded preview configuration.


### Final cache-overlay preview verified (2026-11-09)

The same [security baseline preview](https://gleec-wallet-official--auth-security-20261108-ke7ob56c.web.app)
now serves version `sites/gleec-wallet-official/versions/4a7943088d4ee536`.
[CI run 42538745323](https://github.com/GLEECBTC/gleec-wallet/actions/runs/42538745323)
at workflow commit `c6839e245554337379b62ea10651d36fcb7833b6` verified the
unchanged baseline ZIP and the exact cache overlay. This verification concerns
the original production-feature security build (`57ff0537…d7e9` main bundle),
**not** the corrected onboarding/rollback snapshot (`b8f42b36…baad`).

Sanitized, durable response and browser evidence is in
[AUTH_WEB_PREVIEW_EVIDENCE.json](AUTH_WEB_PREVIEW_EVIDENCE.json). Thirteen actual
served paths matched their candidate byte hashes and strict CSP, `nosniff` and
`SAMEORIGIN` headers:

| Served path | Actual cache behavior |
| --- | --- |
| `/` | Revalidate |
| `/index.html` | Revalidate |
| `/wallet` | Revalidate |
| `/wallet/security/fixture` | Revalidate |
| `/main.dart.js` | Revalidate |
| `/flutter_bootstrap.js` | Revalidate |
| `/flutter_service_worker.js` | Revalidate |
| `/services/security-startup-1.js` | Revalidate |
| `/.well-known/apple-app-site-association` | Revalidate; exact JSON and `application/json` |
| `/assets/assets/web_pages/fiat_widget.html` | Revalidate |
| `/assets/assets/web_pages/fiat_widget.js` | Revalidate |
| `/assets/packages/flutter_inappwebview/assets/t_rex_runner/t-rex.html` | Revalidate |
| `/assets/packages/komodo_defi_framework/assets/coin_icons/png/btc.png` | `public, max-age=2592000` |

All twelve non-icon responses now have `max-age=0, must-revalidate`; the ten
paths without the existing fiat override also have `no-cache`. The previous deep
SPA/helper/AASA stale-cache gap is closed for the final served configuration.
The explicit coin-icon exception remains intact.

A fresh disposable profile on this final HTTPS preview again passed password-form
creation, settings sign-out, cold reload, and password sign-in to the same
unfunded wallet. All sixteen JavaScript/Wasm resources came from the preview
origin, with zero CSP violations. The owned browser/profile was cleaned up.
The unchanged bundle did not require another old-wallet migration run; that
proof remains recorded above.

Independent production read-back still reports main SHA-256
`185236d23e35594cb201a92065b690c2fd623905aef25ed54b8301caef9040c3`
and the prior `frame-ancestors`-only root CSP. Production was not deployed, and
Cloudflare routing was not changed. Firebase reserved helper routes still return
HTTP 200 without application CSP; activation of that separate control remains
deferred. This completes the baseline preview/configuration checks, without
claiming onboarding-preview or physical-device acceptance.
