# Validation and independent review record

Original review date: 2026-09-09. Toolchain: Flutter 3.41.4 on macOS. All added test credentials,
mnemonics and keys are synthetic. No feedback was submitted to a live provider,
and no blockchain transaction was broadcast.

## TRON/TRC20 export removal — 2026-09-14

The [SDK RC review](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/382#issuecomment-5662538367)
supersedes the active-address TRON export design described in the historical
record below. TRON/TRC20 private-key display and export are now disabled until
KDF implements `get_private_keys` for TRON. The SDK reports `unsupportedProtocol`
for structured exports and rejects these protocols in the strict API without
issuing RPCs. The wallet's legacy seed-backup key collection also excludes them.

The SDK removes the temporary typed RPC wrappers, private-key address derivation,
HD metadata searches, direct PointyCastle dependency, active-address coverage
API, separate signing-asset attribution and workaround-specific tests and
execution wrapper. Ordinary offline
exports and authentication/session protections remain. Historical test counts
and independent-review attestations below apply only to their named commits;
they do not validate the removal or describe the revised suite totals.

The removal uses SDK branch `fix/disable-tron-private-key-export`, based on
`dev` at `12cda755e7d1b0b77a865623841437aa3648597c`, and the existing wallet
integration branch `fix/release-diagnostics-and-key-export` (PR #3530).
The wallet pins SDK cleanup commit `f7b3d606`.
Fresh validation with Flutter 3.41.4 / Dart 3.11.1:

| Check | Result |
| --- | --- |
| Full wallet unit/widget aggregator, all four GasFree defines | 1,087 passed, 3 existing skips |
| Full SDK package suite | 944 passed, 1 existing skip |
| RPC methods package suite | 237 passed |
| Types package suite | 183 passed, 3 existing skips |
| SDK export regressions | 26 passed, included in the SDK total |
| Wallet analysis, including vendored packages | No errors; 55 existing warnings and 2,084 infos |
| SDK package analysis | No errors; 11 existing warnings and 822 infos |
| Changed Dart formatting and diff whitespace | Passed |

No changed code has an analysis error or warning. The final seed-backup page
and its regression test additionally pass targeted analysis without findings.
New tests verify unsupported TRX/TRC20 outcomes without RPC calls in both
wallet modes, including HD index 777; mixed exports retain supported coins.
Wallet regressions cover reveal, QR, clipboard, save/share, and the legacy
seed-backup path. All four legacy/HD and mixed/TRON-only seed tests run through
the CI aggregator. Their initial scrolling-text timer teardown issue was fixed
in the test, and the complete aggregator was rerun successfully.

An independent read-only review found no actionable correctness or security
issues. The test-generated build configuration was restored, preserving the
KDF and coin pins. No live-node or device test was required to exercise the
TRON export restriction: the regressions assert that no RPC is issued.

## Original implementation commits

Both repositories used `fix/release-diagnostics-and-key-export`.

| Repository | Reviewed implementation commit | Review base |
| --- | --- | --- |
| SDK | `00821337492faf939e2fe88f7c1119849aa9dcdd` | `4d386b0a710fd78aa4e5e0d782eb6d9e49d3e828` |
| App | `aa343d20f011506af63e0a7dbb37fffa3bd684f0` | `eae57cd734f89270a36bcdf7c604b8cbe49869de` |

The SDK branch includes `origin/dev`
`c696117ade94511c1a6a2c17e47583a57f645f53` and preserves the app's existing
descendant security fixes before adding the remediation. KDF remains
`3.1.0-beta_f3efd2c`, source `f3efd2ca10420f2982fa127dde84dcc17891f577`. The
existing Delete fix is retained. Test-generated build configuration changes were
restored; KDF pins are unchanged.

## Initial follow-up after this review

Pull request review raised two findings, addressed in SDK commits
`0606d009437d290c293e8f36297db2dc63e67ed1`, which keeps a running log export out
of the export clear, and `6d753cae2161eeafabb19821bf3eb862abec4928`, which
versions the packages this candidate changes. Neither commit is covered by the
independent review recorded here.

At that stage the app pinned `6d753cae2161eeafabb19821bf3eb862abec4928`, which carries
`00821337492faf939e2fe88f7c1119849aa9dcdd` in its history, and `pubspec.lock`
records the five raised SDK package versions. Dependency resolution is otherwise
unchanged.

See [the implementation notes](PRIVATE_KEY_EXPORT_SECURITY.md) for boundaries,
coverage semantics, migration behavior and limitations.

## Adoption of merged SDK 0.8.0 — 2026-09-11

At this stage the app pinned `12cda755e7d1b0b77a865623841437aa3648597c`, the merged
[SDK preparation PR #381](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/381).
[SDK RC PR #382](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/382)
tracks its promotion from `dev` to `main`. This commit includes the token-only
TRC20 export and native cross-instance retention fixes from the subsequent
reviews on SDK #375. At this stage TRON export was limited to its verified
active address; that behavior is superseded by the September 14 removal.
Native export ownership remains scoped to one Dart isolate.

`pubspec.lock` records the seven stable package versions: SDK 0.8.0, local-auth
0.6.0, framework 0.6.0, types 0.6.0, RPC methods 0.7.0, coin updates 2.1.1 and
Dragon Logs 3.0.0. No other dependency resolution changed. KDF and coin pins
remain unchanged.

Wallet `dev` at `10bcc8dbb35d06f3463181e1086b93a81f2dbb3e` was merged into
this branch so its existing wallet-isolation and GasFree corrections remain
present. The only conflict was the SDK gitlink. The older SDK pin `f990692f`
has the same tree as merged SDK #376 (`5c9f7d82`), which is an ancestor of the
new SDK pin. Keeping `12cda755` therefore retains those corrections. This merge
also brings in the existing `docs/PR_3525_REVIEW_VALIDATION.md` from wallet `dev`.

Wallet `dev` at `d39db831606c3cbd96dc26512c18472ae605da7d` (after wallet #3532)
was merged into this branch afterwards. The only conflict was again the SDK
gitlink: `dev` pinned `a63ae5ce`, the pre-squash head of SDK #377, while this
branch keeps `12cda755`, which descends from `223fd1d9`, the byte-identical
squash of that PR. Keeping `12cda755` therefore retains the gas-free disposal
correction as well. The merge otherwise brings in `dev`'s updated
`docs/PR_3525_REVIEW_VALIDATION.md` and browser integration-test selectors; no
`pubspec.lock` line moved.

Fresh checks against the reconciled wallet implementation at
`b7d7833d08ef5d6fc21bb4e123aa8d494a7b6170`, using Flutter 3.41.4 / Dart 3.11.1:

| Check | Result |
| --- | --- |
| Full wallet `test_units/main.dart`, all four required GasFree defines | 1,076 passed, 3 existing skips |
| Offline dependency resolution with `--enforce-lockfile` | Passed |
| SDK workspace dependency resolution | Passed |
| Full wallet/workspace analysis | No errors; 55 warnings and 2,070 informational findings |
| Theme colour-role fixtures and guard | Passed |
| Hosting deploy URL reader fixtures | Passed |
| Bitrefill message bridge tests | Passed |
| Git whitespace and unintended generated-file checks | Passed |

Re-run at the second merge commit `aa9827ed0` (Flutter 3.41.4 / Dart 3.11.1):
full `test_units/main.dart` with the four GasFree defines 1,076 passed with the
same 3 skips; `flutter pub get --enforce-lockfile` passed without changing the
lockfile; analysis reported no errors, 55 warnings and 2,087 informational
findings; the theme colour-role fixtures and guard and the 13 Bitrefill message
bridge tests passed.

No Dart source was manually changed for this repin or conflict resolution.
The initial isolated analysis lacked the SDK's own test dependency resolution;
resolving that workspace removed the setup errors before the final analysis
above. Plain `flutter analyze --no-pub` remains nonzero for the existing warning
and information diagnostics; no analyzer suppression was added.

The merged SDK has exactly the same Git tree as release-preparation head
`043031f4`. Its [release checklist](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/blob/12cda755e7d1b0b77a865623841437aa3648597c/docs/RELEASE_0.8.0_CHECKLIST.md)
records all 16 passing SDK package suites, Chrome/Wasm races, native/browser
logging, the pinned-KDF export contract, HD/Iguana replay and both web example
builds. Those checks were run during release preparation and were not repeated
for this tree-identical merge. The checklist separately identifies the existing
sample-test failures and unperformed platform checks.

This is fresh consumer validation, not an extension of the original independent
security-review attestation to later commits. The historical results and limits
below remain tied to their original implementation commits.

## Original validation results — 2026-09-09

Counts below identify separate suites; focused tests can also be included in a
package or app aggregate, so the rows must not be added together.

| Check | Result |
| --- | --- |
| Full app `test_units/main.dart`, all four required GasFree defines | 908 passed, 3 pre-existing skips |
| Full `komodo_defi_sdk` suite, with the bundled-KDF export regression enabled | 907 passed, 1 pre-existing skip |
| Auth/Trezor regressions, including Delete, transition timing and wrong-password classification | 59 passed |
| SDK structured export regressions | 32 passed, also included in the SDK aggregate |
| Typed legacy `show_priv_key` RPC tests | 4 passed |
| Framework/RPC/sanitizer/streaming logging regressions, including actual WASM transport | Passed; synthetic secret sentinels and operational-value preservation checked |
| Seed-node startup fallback tests | 15 passed, including 8 new diagnostic regressions |
| DragonLogs native storage tests | 15 passed |
| DragonLogs Chrome OPFS/Web Locks tests | 9 passed, including worker concurrency and stable snapshots during writes |
| App export BLoC, delivery, real adapter, password and lifecycle regressions | 38 passed, included in the app aggregate |
| App logger, safe exporter, feedback and screenshot regressions | 34 passed, included in the app aggregate |
| App diagnostic artifact cleanup and guarded file delivery | 10 passed, included in the app aggregate |
| KDF replay, default/HD mode | 30 passed, 4 skips |
| KDF replay, legacy/iguana mode | 28 passed, 3 skips |
| Android bridge and MainActivity compilation against Flutter embedding and Android API 35 | Passed; javac reported missing Kotlin annotation metadata in the minimal validation classpath |
| Analysis of changed app files | No errors or warnings; 12 existing informational findings |
| Analysis of changed SDK files | No errors or warnings; 238 informational findings |
| Required repository-wide `flutter analyze --no-pub` | No errors; nonzero exit from 55 existing warnings and 2,088 informational findings |
| Changed-file formatting, generated localization keys and whitespace checks | Completed |

The three app skips are the existing `Get formatted USD balance using SDK
balance`, `getTotal24Change calculates total change`, and `Total fee positive
test` fixtures. The SDK skip is the existing balance-cache test whose empty-cache
expectation contradicts automatic reattachment after a wallet change. No new test
was skipped to make the original changes pass. The former real KDF export
regression ran successfully in that aggregate; it was removed with the
workaround on September 14.

### Reproduction commands for retained suites

The deleted TRON export contract and its environment variable are omitted.
These commands can validate the current tree, but the historical counts above
apply only to the original implementation.

Use the pinned toolchain, rather than a different globally selected Flutter:

```sh
export PATH="/Users/charl/fvm/versions/3.41.4/bin:$PATH"
flutter pub get --enforce-lockfile --offline
flutter test --no-pub test_units/main.dart \
  --dart-define=TRON_GASLESS_ENABLED=true \
  --dart-define=TRON_GASLESS_RECEIVE_ENABLED=true \
  --dart-define=TRON_GASLESS_BASE_URL=https://quicknode.gleec.com/gasfree/tron \
  --dart-define=TRON_GASLESS_SERVICE_PROVIDER=TLntW9Z59LYY5KEi9cmwk3PKjQga828ird

cd sdk/packages/komodo_defi_sdk
KDF_HARNESS='' flutter test --no-pub

cd ../dragon_logs
flutter test --no-pub test/dragon_logs_test.dart test/log_storage_privacy_test.dart
flutter test --no-pub --platform chrome test/web_log_storage_privacy_test.dart

cd ../komodo_defi_framework
flutter test --no-pub --platform chrome \
  test/operations/kdf_operations_wasm_diagnostics_test.dart

cd ../komodo_defi_harness
KDF_HARNESS_WALLET_TYPE=hd flutter test --no-pub --exclude-tags bench
KDF_HARNESS_WALLET_TYPE=iguana flutter test --no-pub --exclude-tags bench
```

The removed KDF export wrapper previously ran against a loopback mock node and
temporary wallet data. Its active-key derivation and HD metadata checks were
specific to the superseded workaround. Those checks and the associated scalar,
address/path and activation tests are no longer part of the retained suites.
Current regressions require TRON/TRC20 rejection without RPCs while preserving
supported offline exports, concurrency, strict ranges and session invalidation.

## Independent security review

A separate read-only `gleec_reviewer` agent examined the implementation and test
sources. It did not implement the fixes. Test-execution evidence came from the
implementation agents and the final aggregate runs above.

Review covered the committed SDK logging, storage, authentication and export
boundaries and the committed app BLoC, service adapters, delivery, migration,
feedback and screenshot boundaries. Findings were resolved and re-reviewed:

- Actual WASM fallback logging could still expose untrusted method/response
  values; the real JS transport now has captured-output regressions.
- Public authentication transitions initially revoked exports too late; the
  source now revokes synchronously before awaits and rejects pending transitions.
- Mutable selections and cross-manager capabilities could weaken session
  binding; selections are copied before awaiting and tokens are owner-bound.
- Parent activation state and HD metadata/path mismatches needed explicit
  rejection; the SDK now returns unavailable outcomes without guessing coverage.
- Async delivery checks left a final scheduling gap; each irreversible handoff
  has a synchronous generation check, including after destination selection.
- Browser downloads cannot report confirmed completion; they now remain
  unconfirmed and never mark the export as completed.
- Permanent asset exclusions and pending QR intent needed preservation; the UI
  now uses consistent selection and revision checks.
- Feedback sensitivity checked after screenshot capture could become false on
  logout; capture-lifetime sensitivity and preview painting now fail closed.
- Tests found an invalid transparent PNG and an already-disposed controller
  subscription; both were corrected and covered by pixel/decoder regressions.

The reviewer attested that the exact SDK and app implementation commits listed
above match the reviewed changes, with **no unresolved blocking findings**.

## Remaining verification limits

This is a code and automated-test review, not a guarantee that no vulnerability
exists. Full live-network GUI integration and benchmark tiers were not run for
this remediation. Real Android/iOS share-sheet lifecycle and provider failures,
process termination while staging a share, Windows filesystem behavior, and
multiple complete app tabs remain outside the exercised tests. Browser storage
tests did run real OPFS, Web Locks and a concurrent worker.

Already downloaded/shared diagnostics cannot be revoked. Old open app tabs can
still execute old code; updated clients never import their legacy namespace.
These limits remain relevant when evaluating release readiness. The original
current-address-only TRON coverage is superseded: TRON/TRC20 private-key export
is disabled pending KDF `get_private_keys` support.
