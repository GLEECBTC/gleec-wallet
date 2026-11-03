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
- `runWithSession` holds the existing auth read lease around the raw routed
  `init` or unified atomic `sell` request. Auth transitions revoke synchronously
  and take the write lease before changing the engine. The caller's intent is
  checked again after acquiring the read lease. Authentication reads, status
  lookup and polling remain outside it to avoid nested-lock deadlocks.
- Before dispatch, invalidation is a definite rejection with zero RPC calls.
  After dispatch may have occurred, a lost answer or session change remains
  unconfirmed. Closing the form suppresses obsolete UI work without promising
  cancellation. Registry/history recovery remains independent of the form;
  there is no automatic resubmission.

The dispatch lease deliberately survives a UI timeout until the actual transport
future settles. A stalled request can delay logout or wallet switching. Releasing
the lease using `Future.timeout` would let an old request reach a replacement
engine. A genuinely abortable transport deadline is deferred rather than
weakening this ownership guarantee.

## Deferred proxy trust hardening

The RC still trusts Komodo Defi Proxy for provider responses. At the unchanged
KDF pin `e40ac2fb4319d352bf9c93683eb2518ce9f939e0`, the execution-contract policy
is derived from `/chains`' `diamondAddress`; transaction targets and approval
spenders are checked against that same policy. Quotes and `/chains` share the
configured proxy. Internally consistent malicious responses therefore need not
fail those checks. Client request signatures and successful transaction
simulation do not independently authenticate provider response contents.

This is a material trust dependency, not evidence that the proxy is compromised.
The signing boundary belongs in KDF; a late Flutter-only address check would not
provide a complete remedy. The next security architecture work must define and
test an independently authenticated, versioned contract policy with update and
revocation behavior, and verify transaction intent against coordinated malicious
catalog, approval, recipient and calldata responses. Address pinning alone is
not sufficient. Its engine changes require all-platform artifact validation.

Source evidence at the exact RC engine:
[catalog policy](https://github.com/GLEECBTC/kdf-internal/blob/e40ac2fb4319d352bf9c93683eb2518ce9f939e0/mm2src/mm2_main/src/routed_swap/context.rs#L104),
[target and spender checks](https://github.com/GLEECBTC/kdf-internal/blob/e40ac2fb4319d352bf9c93683eb2518ce9f939e0/mm2src/mm2_main/src/routed_swap/swap_task.rs#L1514),
[shared proxy base](https://github.com/GLEECBTC/kdf-internal/blob/e40ac2fb4319d352bf9c93683eb2518ce9f939e0/mm2src/trading_api/src/lifi_api/client.rs#L147).

## Validation and promotion

Validation uses Flutter 3.41.4, the app's enforced lockfile and the existing
release SDK workspace lockfile resolved offline. SDK workspace lockfiles are
generated and ignored; no dependency or KDF/coin upgrade is part of this fix.

The immutable implementation revisions are:

| Target | App source | SDK pin |
| --- | --- | --- |
| RC | `e148efcb5f5ea611e7edd0aa3cdfc3860bc8984b` | `c0edb25e3e3a7a7bf04f4eddc2bbf4acf7b46727` ([SDK #427](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/427)) |
| Development | `f65ed6430cffcd6cfccaa55192619407f5d6267a` | `d7f03b63c0a895e6ccca0ce0bece9d4afb0385cf` ([SDK #426](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/426)) |

App runtime and test trees are identical between these two revisions. The SDK
package trees are also identical. Later evidence-only commits do not change
these tested sources. KDF build configuration SHA-256 remains
`e79216c9b05ea6eb439857e41e6f362b135005f8035ff9fc875ddfa6c7707576`;
app lockfile SHA-256 remains
`545db76fc5f2c5d7fc704a383f487f0364ac2733896db84c00881cb661ccfdc6`.

### Local checks on the final RC implementation

| Check | Result |
| --- | --- |
| App aggregator, all four production GasFree defines | 3,991 passed, 4 skipped |
| Core SDK suite | 1,233 passed, 1 skipped |
| Local-auth suite | 156 passed |
| Framework suite | 101 passed |
| RPC suite | 379 passed |
| Types suite | 191 passed, 3 skipped |
| Replay harness, HD | 221 passed, 3 skipped |
| Replay harness, iguana | 221 passed, 3 skipped |
| App Chrome/WASM authorization and lifecycle tests | 84 passed |
| SDK Chrome/WASM routed-session tests | 42 passed |
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
