# 0.10.0 swap authorization remediation

## Release disposition

The two authorization defects reported by Opsec on 2 November are release
blockers: an offer could be executed in a later wallet session, and a pending
confirmation could execute after its form closed. They are corrected together
because offer ownership and confirmation lifetime protect different boundaries.
The reported mock probes did not establish a real-wallet debit. Their original
test file was unavailable; deterministic regression cases reconstruct the
reported sequences and cover additional races.

Review baseline: wallet `2c160b7215494f36f35d96b2fe83473c1141e09c`, SDK
`55bd00c64f5721177d26a78df297751b4b61f540`. The earlier local correction was
wallet `6e664c51d` / SDK `d48569f2`. The completion adds enforceable provenance,
dispatch serialization, and invalidation throughout asynchronous preparation.

## Authorization boundaries

- Only the issuing routed manager can execute an offer. Private issuance binds
  the original SDK session epoch; exact/Max quotes and supported copies retain
  it. There is no public operation to rebind an old offer. Logout and login to
  the same wallet invalidate the old epoch.
- Confirmation captures an instance-owned, single-use registry token and the
  original session, wallet key, review revision, quote and legal snapshot before
  preparation waits. Every continuation checks its original context before
  changing the review or dispatching. Close, cancellation, replacement, policy
  restriction and session changes revoke pending submission.
- Consent and successful-pair persistence use the original wallet key. A write
  already in progress may finish for that wallet, but cannot authorize a later
  submission or be attributed to a replacement wallet.
- `runWithSession` holds an engine lease around the raw routed `init` or
  unified atomic `sell` request. Auth transitions revoke synchronously, and
  only stopping or starting the engine waits for the lease, so identity reads
  never delay a start. The caller's intent is checked again after acquiring the
  lease. Authentication reads, status lookup and polling remain outside it to
  avoid nested-lock deadlocks.
- Before dispatch, invalidation is a definite rejection with zero RPC calls.
  After dispatch may have occurred, a lost answer or session change remains
  unconfirmed. Closing the form suppresses obsolete UI work without promising
  cancellation. Registry/history recovery remains independent of the form;
  there is no automatic resubmission.

The dispatch lease survives a UI timeout until the actual transport future
settles, for at most 10 seconds. Past that bound, logout or a wallet switch may
stop the engine, which fails the unanswered request and resets the HTTP client
before any replacement engine starts. A request the engine never answers
therefore cannot hold off logout, and an old request never reaches a
replacement engine.

## Engine follow-ups

Engine-side follow-ups are outside this remediation and are tracked privately
with the engine team.

## Validation and promotion

Validation uses Flutter 3.41.4, the app's enforced lockfile and the existing
release SDK workspace lockfile resolved offline. SDK workspace lockfiles are
generated and ignored; no dependency or KDF/coin upgrade is part of this fix.

The immutable implementation revisions are:

| Target | App source | SDK pin |
| --- | --- | --- |
| RC | `33bf94a7cc4ed9b4ba5bc04f2694a344445908a1` | `3730b456d1bb9046ab899a0d367e5c1a2eb9055a` ([SDK #429](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/429)) |
| Development | `d4df53688b5602462247bc92dfbd7d9f3b5e77c8` | `0cd7578e8887290371e4d06d527d95c97cba9d38` ([SDK #428](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/428)) |

App runtime and test trees are identical between these two revisions. The SDK
package trees are also identical. Later evidence-only commits do not change
these tested sources. KDF build configuration SHA-256 remains
`e79216c9b05ea6eb439857e41e6f362b135005f8035ff9fc875ddfa6c7707576`;
app lockfile SHA-256 remains
`545db76fc5f2c5d7fc704a383f487f0364ac2733896db84c00881cb661ccfdc6`.

### Local checks on the final RC implementation

| Check | Result |
| --- | --- |
| App aggregator, all four production GasFree defines | 3,991 passed, 4 skipped; repeated on final app/SDK pin pair |
| Core SDK suite | 1,238 passed, 1 skipped |
| Local-auth suite | 156 passed |
| Framework suite | 101 passed |
| RPC suite | 379 passed |
| Types suite | 191 passed, 3 skipped |
| Replay harness, HD | 221 passed, 3 skipped |
| Replay harness, iguana | 221 passed, 3 skipped |
| App Chrome/WASM authorization and lifecycle tests | 84 passed |
| SDK Chrome/WASM routed-session tests | 47 passed |
| Local-auth Chrome/WASM dispatch-lease tests | 10 passed |
| Release web/WASM build | Passed |
| macOS debug compile with CI unsigned settings | Passed |
| Full app analysis | Zero errors; 55 warnings and 2,140 infos; exit 1 |
| SDK analysis (library, routed tests and shared auth fixture) | Zero errors/warnings; 521 infos; exit 0 |
| Changed Dart files and whitespace | Formatted; diff checks passed |

No app warning points to a changed file. Repository-wide lint debt remains;
this record does not describe full analysis as clean. The ordinary signed
macOS build could not find a development provisioning profile for
`com.GleecDEX.wallet`; the subsequent unsigned compile used the existing CI
settings and passed without changing project signing configuration.

The first complete app run had seven fixture-contract failures: two review/
start tests used a wallet key inconsistent with their auth fixture, one
preferences test expected a fallback to an unvalidated user, one late-start
test expected success after sign-out, and three app-root widget tests lacked
session contexts in their auth fake. The fixtures now model the actual session
contract and preserve teardown and uncertainty assertions. No production
authorization check was relaxed to make them pass.

The initial candidate's 11 app regressions were insufficient for the completed
design. SDK dependencies now resolve with the enforced lockfile; the earlier
missing-`mocktail` loading failures are superseded by the complete suite runs.
The first app WASM invocation also failed to load because Flutter 3.41.4 roots
browser tests at `test/`, while this app uses `test_units/`. Running the same
three files through a temporary symlink under `test/` passed all 84 cases;
the link was removed afterwards.

SDK #426/#427 delivered the implementation; #428/#429 completed five explicit
wallet-transition test combinations. The final SDK pins differ from the original
validated pins only in `routed_swap_offer_session_test.dart`. The complete core
suite and browser session suite were rerun on those final pins, and independent
review approved the added assertions. The app aggregator passed again on the
final app/SDK pair (3,991 / 4 skipped). All other validated library, test, dependency and engine
inputs are unchanged.

### Regression boundaries

- SDK offer tests cover exact/Max offers, supported copies and preserved
  minimums, fresh recovery offers, foreign managers, manually constructed
  offers, session changes while quoting, and logout/login to the same wallet.
- App BLoC and submission tests cover close, cancel, reset, review replacement,
  trading restrictions and session revocation across legal reads, price and
  balance reads, blocked persistence, and executor preparation. They assert
  zero dispatch for abandoned preparation and require a new confirmation for
  material quote changes.
- Registry tests cover foreign and reused tokens, synchronous session
  revocation before delayed notifications, known identifiers on late answers,
  recovery independent of form lifetime, and exactly one atomic/routed start.
- Real auth tests cover lease queueing, synchronous revocation, transport
  settlement and error release, deferred wallet transitions, typed errors,
  Trezor delegation, and reads outside the lease to avoid nested-lock deadlocks.

An independent read-only review of the final app source and SDK `c0edb25e`
found no remaining blocker in pre-dispatch rejection, post-dispatch uncertainty,
review ownership, or recovery. Hosted PR checks and deployed preview identity
are separate evidence and must be read from the exact PR head; local results
do not imply that hosted workflows have passed.

### Hosted delivery evidence

The implementation SDK PRs are merged: development `2e162cbb96c7aef2df2bd72e4aa6af80846ac406`
and RC `d58bb7bb9a8eba0cd970f34e02bf3bd004c91b1e`. The test follow-up is also merged:
development `e217dbb6399859a2cd130ef43756a5c62e5039bb` and RC
`3832b0f45d349e46faf25d79bc643c5218bf73f2`. Exact app acceptance and refreshed
preview identity are maintained on [app #3583](https://github.com/GLEECBTC/gleec-wallet/pull/3583)
and [app #3584](https://github.com/GLEECBTC/gleec-wallet/pull/3584).

The original implementation passed hosted SDK all-package tests (16 suites),
both SDK WASM gates, app unit-test steps, app code guidelines, and Android,
Windows and Linux builds. These results belong to the earlier PR heads; later
head statuses are not inferred from them. One iOS job stopped before compilation
in `xcodebuild -downloadPlatform iOS` with “Unable to connect to simulator”
(exit 70; [failed job](https://github.com/GLEECBTC/gleec-wallet/actions/runs/41654060085/job/125979565320)).
The identical Xcode version and unchanged iOS/workflow inputs passed on 2 November
([baseline job](https://github.com/GLEECBTC/gleec-wallet/actions/runs/41531143872/job/125571356077)).
This runner setup failure is not an app test pass. Local release-WASM
and deployed-preview wallet/signed-out Swap smoke checks captured no console
errors; no wallet was connected or funds submitted.

### Reproduction

Use `fvm flutter pub get --enforce-lockfile --offline` in the app and SDK
workspace with their existing lockfiles, then the app aggregator command in
[TESTING.md](TESTING.md) / `AGENTS.md`, with all four GasFree defines.
Run `fvm flutter test --no-pub --reporter expanded` in each affected SDK
package listed above. Run the harness suite with
`KDF_HARNESS_WALLET_TYPE=hd`, then `KDF_HARNESS_WALLET_TYPE=iguana`.
These are replay runs; they make no claim about funded settlement or the
separately recorded upstream engine failures.

For the app browser check, temporarily link `test/opsec_units` to
`../test_units` and run `fvm flutter test --no-pub --platform chrome --wasm`
with the same four GasFree defines and these files:

```text
test/opsec_units/tests/swap/swap_bloc_start_session_test.dart
test/opsec_units/tests/swap/swap_submission_authorization_test.dart
test/opsec_units/tests/swap/swap_exec_routed_executor_test.dart
```

Use the software-WebGL Chrome wrapper described in `TESTING.md`, then remove
the temporary link. The SDK and local-auth browser suites use their normal
`test/` paths. Build the app with `fvm flutter build web --release --wasm
--no-pub` and `fvm flutter build macos --debug --no-pub` using the same defines;
the latter needs the repository's unsigned CI environment for a compile-only
check on this machine.

Main promotion, production publication, signed installation/upgrade and any
funded acceptance test remain separate release actions. No funded action is
performed by this remediation.
