# v0.9.7 release candidate review

Reviewed on 2026-09-05 against [PR #3525](https://github.com/GLEECBTC/gleec-wallet/pull/3525).

## Review basis

- Release base: `origin/main`, `07fc5bc5961e258399ad829c8c0784fcb27d4d53`.
- Review branch starts at `origin/dev`, `e1f7885d18a895ce443464d247349bcc31715522`.
- [PR #3514](https://github.com/GLEECBTC/gleec-wallet/pull/3514), head `8adb081f305e5e8a78fe5ce6eb36aba74931976e`, is squash-merged locally before the review fixes. This includes the web update changes from #3526.
- Original SDK release pin: `7dce2687276684c132a1d9e4702c7d5c541eba2a`; initial fixes are committed at `a9e3bde6`, followed by the verified-identity API correction at `51e4b56a7c0712711b0441d4c67d6d3a99332e97` and the Wasm activation race correction at `0c69c1b5d2e68225b8377e6a4099862f133727c3`, on SDK branch `fix/release-candidate-review-20260905`.
- Scope: the complete app release diff (409 files including #3514), the SDK roll's wallet identity/history/persistence and GasFree paths, native/Firebase configuration, build workflows, checkout scripts, and tests. Independent reviews covered transfers, receive/activation, onboarding, NFT/history, web/fiat, and the SDK, followed by a second review of the fixes.

## Findings addressed

| Finding | Trigger and correction |
| --- | --- |
| Saved-wallet Delete opened Login | The onboarding wrapper discarded the selected action. Carry the action through the manager constructors and test deletion/cancellation. |
| Mobile backup could trap the user | Reused settings pages omitted their mobile Back control inside the modal. Give the modal a Back action and allow seed controls to wrap at compact widths. Cancelling never grants the pending receive action. |
| Backup warnings crossed same-name wallets | An in-memory acknowledgement used the display name. Key it by full wallet identity and decline results from a replaced wallet. |
| Stale backup confirmation could update another wallet | Bind the confirmation event and metadata write to the original identity, including the check inside the authentication write lock. Close stale dialogs and discard late mnemonic results. |
| Failed address refresh remained loading | The error branch retained `submitting`. Emit failure and allow a later successful refresh to recover. |
| Re-enabling a hidden coin could remain activating | The activation bridge deduplicated a deliberate replay against an old retained active state. Force explicit snapshot replays while retaining ordinary event deduplication. |
| Resume could leave Receive without a subscription | A status-only refresh could not finish an interrupted initial subscription. Restart the subscription when status or watcher setup is incomplete. |
| Background revocation could be overwritten | A final awaited wallet check could outlive the request generation. Check generation again after the await before publishing ready state. |
| Custody copy could outlive validation | A backup prompt could stay open through expiry, revocation, or wallet replacement. Recheck wallet identity and current receive status immediately before clipboard access. |
| NFT activation requests crossed sessions | Old authentication or activation completions could start stale work or release a newer session's chain claim. Use session-owned claims and guards after awaits. |
| Temporary identity failure disconnected history | Name-only identity events for the same authenticated wallet cleared history streams and changed storage namespace. Preserve the verified identity for these degraded events. |
| Old activation polluted another wallet's history state | An activation completion could populate the next wallet's per-session marker before identity validation. Validate before adding the marker. |
| Merged history could attach to the next wallet | The historical-to-live transition could retain the previous wallet's rows while opening another wallet's stream. Keep one wallet context across the entire merged stream. |
| Consolidation fee shortages looked like connection failures | Map typed insufficient-gas/fee-balance errors to the existing TRX funding guidance; keep unknown and transport errors blocked. |
| Bitrefill bridge accepted unauthenticated incoming messages | Require the exact provider origin and active iframe window; ignore malformed payloads. This hardens a pre-existing boundary touched by #3514. Execute tests against the actual JavaScript asset in CI. |
| Web update popup could describe an unavailable release | A newer deployed version was accepted even when still older than the announcement. Require deployment to satisfy the announced release as well as improve on the running version. |

The release notes now include #3514/#3526, the already-merged Firebase startup fix #3520, and the review corrections.

## Initial review validation

Flutter is pinned to `3.41.4`; the app test suite uses all four mandatory `TRON_GASLESS_*` defines from `docs/TESTING.md`. SDK tests keep `KDF_HARNESS` empty and the replay harness uses fake RPC transport.

| Check | Result |
| --- | --- |
| App unit/widget aggregator, `test_units/main.dart` | 771 passed, 3 skipped |
| `komodo_defi_sdk` full package suite | 872 passed, 1 skipped |
| `komodo_defi_local_auth` full package suite | 60 passed |
| Wallet-load replay harness, HD and iguana | 30 passed, 4 process-tier tests skipped |
| Wallet-load benchmark and committed 30% regression gate | Passed; measured deltas from -0.4% to +0.7% |
| Actual Bitrefill JavaScript asset tests | 13 passed; registered in code-guidelines CI |
| Hosting URL, GasFree configuration, preview provenance shell tests | All passed |
| CI analysis: `flutter analyze --no-pub --no-fatal-warnings --no-fatal-infos` | Passed, no errors; existing warning/information diagnostics remain |
| Release web build with all four GasFree defines | Passed, including Flutter's Wasm dry run |
| Formatting of changed Dart files and whitespace checks | Passed |

The build-generated coin configuration change was restored; the KDF binary pin remains unchanged. The app and SDK fixes are committed separately. The SDK branch is published in [PR #374](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/374), targeting `main` as a release-line hotfix.

## Follow-up: verified identity is required for metadata writes

[Review comment #3941129166](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/374#discussion_r3941129166) is valid: an unavailable identity RPC produces a name-only `WalletId`. Equality alone accepts a different seed recreated under the same name while that outage persists. Both regression cases (key update and whole-map replacement) fail with the old equality-only guard and pass with the corrected guard.

All SDK metadata setters and atomic updates now require `expectedWalletId`. Both the expected and freshly resolved identities must contain a nonblank public-key hash and compare equal under the authentication write lock. Rejection occurs before the transform or metadata write and does not sign out the replacement session. This is an explicitly accepted breaking API change; migration guidance and unreleased changelog entries accompany it. Package version assignment, tags, and publishing remain release-preparation work.

The app carries the original identity through backup confirmation, wallet export, registration/restore finalizers, metadata repair, hardware-wallet setup, asset activation, legacy migration, and rollback. Export captures identity before the password prompt and checks it around mnemonic retrieval and file saving. Stale migration and ZHTLC completion stop without altering the replacement session. Identity-unavailable activation becomes suspended, with session-generation checks preventing a late cancellation from changing a newer login.

Validation of the follow-up with Flutter `3.41.4`:

| Check | Result |
| --- | --- |
| App unit/widget aggregator with all four GasFree defines | 784 passed, 3 skipped |
| `komodo_defi_sdk` full package suite | 872 passed, 1 skipped |
| `komodo_defi_local_auth` full package suite | 74 passed |
| Replay harness, excluding benchmark tests | 28 passed, 3 process-tier skips |
| CI-equivalent app and local-auth analysis | No errors; existing diagnostics remain |
| Changed-file formatting and whitespace checks | Passed |

The initial benchmark, script, and release web-build results above predate this follow-up; those checks were not rerun for the metadata API migration.

## Follow-up: activation completion must recheck the session synchronously

[Review comment #3941224671](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/374#discussion_r3941224671) is valid on WebAssembly. Its async-return completion can yield after wallet A passes identity validation. A queued authentication event then switches to wallet B and clears the activation markers, before A's continuation adds its marker to B's session. B's next history request incorrectly skips activation.

The SDK now checks wallet identity, session generation, and disposal synchronously immediately before adding the marker. The authoritative asynchronous identity check remains. Two regressions using ordinary queued microtasks both fail against the previous implementation in Chrome/Wasm (one activation instead of two) and pass with the guard. Native execution alone does not expose this timing gap. CI now runs the complete wallet-race test file in Wasm, with software WebGL enabled only in its isolated test browser.

Validation at SDK commit `0c69c1b5d2e68225b8377e6a4099862f133727c3`, using Flutter `3.41.4`:

| Check | Result |
| --- | --- |
| Wallet-history race suite in Chrome/Wasm | 8 passed; both new regressions failed before the fix |
| Full SDK package suite on the native VM | 874 passed, 1 skipped |
| App unit/widget aggregator with all four GasFree defines | 784 passed, 3 skipped |
| Replay harness, excluding benchmark tests | 28 passed, 3 process-tier skips |
| Analysis of changed SDK Dart files | No errors; 18 existing information diagnostics |
| Changed-file formatting, whitespace, shell syntax, workflow YAML | Passed |

The local-auth code is unchanged by this correction; its 74-test result above remains the previous validation. The build-generated coin configuration change was restored again. The companion app now pins this SDK commit.

## Release boundaries

- The app review changes remain on the local review branch; the SDK fixes are pushed to PR #374. No GitHub merge, release tag, production deployment, or funded transfer is part of this review.
- Native signing/distribution and a deployed RC smoke test remain release checks. The observed GitHub checks on the release PR passed except `Test web-app-linux-profile`; that existing integration failure is not a passing validation result for this patch.
- Production-hosted wrapper protection reaches shipped native clients only when the updated wrapper and headers are actually deployed. The included deployment verifier checks that separate release action.
