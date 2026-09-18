# PR #3525 review investigation and validation

Investigation date: 2026-09-10. Review: [shamardy's first review](https://github.com/GLEECBTC/gleec-wallet/pull/3525#pullrequestreview-5160401345).

The starting wallet revision was `eae57cd734f89270a36bcdf7c604b8cbe49869de` (`dev`), with SDK `4d386b0a710fd78aa4e5e0d782eb6d9e49d3e828`. All seven findings needed corrections. Work used isolated copies of the existing wallet and SDK `dev` branches. SDK `dev` was first fast-forwarded to its existing `main`, which already contained the wallet's pinned release fixes. Unrelated theme, diagnostic-sharing, and key-export work was excluded.

## Findings and corrections

### 1. Untraced GasFree submissions had no recovery action

[Comment 3973445249](https://github.com/GLEECBTC/gleec-wallet/pull/3525#discussion_r3973445249) was correct: the SDK exposed `discardPendingGaslessTransfer`, but no wallet action called it. A persisted `submittedUnknown` record without a trace therefore blocked subsequent sends indefinitely.

The pending receipt now offers **Clear local recovery record** only for an untraced, unresolved record. The confirmation shows the recipient, amount, asset and submission date and requires an explicit checkbox acknowledgement. Its copy explains that clearing does not cancel a transfer or establish that sending again is safe. Confirmation is bound to the displayed journal ID; it never signs, previews or submits another payment. Storage failures preserve the block. A trace attached during confirmation triggers a journal reload and reconciliation. Successful clearing resets the form and reloads remaining reservations before another GasFree preview can start.

The SDK also prevents another form or browser tab from clearing a live submission. A distinct per-submission Web Lock is acquired before the reservation becomes visible and held until submission persistence settles. Discard tries the same lock without waiting. It does not hold the journal transaction lock across network work; a destroyed browser context releases its lease so abandoned records remain recoverable. Native managers share an in-isolate lease registry.

Validation includes stale acknowledgement, duplicate/busy actions, persistent-storage failure, newly attached traces, remaining reservations, form closure, cancellation, and a 320-pixel layout at 200% text scaling using the actual English warning and acknowledgement.

### 2. Update URLs trusted arbitrary HTTP(S) destinations

[Comment 3973473791](https://github.com/GLEECBTC/gleec-wallet/pull/3525#discussion_r3973473791) was correct. The original getter accepted both HTTP and unrelated HTTPS hosts. A regression failed on the HTTP form of the official download URL.

The shared popup/action guard now accepts only HTTPS GitHub release pages and release assets under `GLEECBTC/gleec-wallet`, using the default HTTPS port and no credentials, query or fragment. It rejects unrelated repositories, lookalike hosts, ambiguous paths, encoded separators/control characters and malformed inputs. Independent review additionally reproduced exceptions from invalid percent-encoded UTF-8 and oversized ports; these lazy URI-decoding errors now return an unusable URL instead of escaping the update timer. Required updates use exactly the same guard.

The public update endpoint was checked during the investigation and still returned `https://github.com/GLEECBTC/gleec-wallet/releases/tag/0.9.6`, which remains accepted. This observation is historical, not an assertion about a future release announcement. Web updates continue to require a suitable deployed version and reload their current origin.

### 3. Activation results could cross wallet sessions

[Comment 3973489446](https://github.com/GLEECBTC/gleec-wallet/pull/3525#discussion_r3973489446) was correct in both the wallet and SDK. Five of six initial wallet race tests failed. Three initial SDK cases demonstrated late completion after a switch/reset and history written using a degraded, reread identity instead of the original verified wallet.

Wallet activation now captures one identity/session scope across retries, delays, address reads, ZHTLC configuration, metadata writes and broadcasts. Authentication events invalidate it synchronously; fresh identity checks cover delayed event delivery. Disposal and cache flushes invalidate outstanding work. A temporary missing hash preserves the strongest previously verified identity and does not authorize metadata writes for another wallet.

SDK activation captures a wallet context for the complete operation, fences stale success/error/finally effects and persists history under that captured identity. The shared coordinator seeds its identity before looking up pending work; a delayed first event for a different wallet cannot make the new wallet join the old wallet's activation. Observation revisions also prevent a delayed initial identity read from clearing a replacement wallet's already-established state. Tests cover A→sign-out→A, delayed first A/B events, same-name wallets with different hashes, identity enrichment/degradation, reset, disposal/cache flush, stale cache lookups, late failure and switching during persistence. Immutable authentication settings come from the captured wallet rather than an extra identity read. Nonterminal progress does not perform repeated identity RPCs.

### 4. Address loading could spin or permanently lose its watcher

[Comment 3973510271](https://github.com/GLEECBTC/gleec-wallet/pull/3525#discussion_r3973510271) was correct. The final 32-case regression harness against the original BLoC produced 15 failures. A single clock tick could cause repeated crossed-wallet reads; standard assets could not recover from initial reads, precache failures or watcher errors/completion. Additional cases showed that hashless identity could incorrectly leave GasFree readiness visible.

Address reads use the SDK's continuity rules while retaining the strongest identity across every await. One retry timer backs off through 1, 2, 4, 8, 16 and 30 seconds. It stops while backgrounded or closed, reconnects failed background watchers on resume, and preserves backoff through cached emissions followed by startup failure. A watcher must remain healthy for 30 seconds before resetting that backoff. Successful live updates cancel redundant scheduled reloads. GasFree Ready and verified receive actions still require a fresh verified hash; continuity alone is insufficient.

### 5. Bundled legal acceptance changed identity after the first fetch

[Comment 3973520892](https://github.com/GLEECBTC/gleec-wallet/pull/3525#discussion_r3973520892) was correct. Thirteen of the first 27 regression cases failed against the original implementation: the literal `bundled` marker was compared against an eventual Git SHA, even when the displayed document text had not changed.

New acceptance records store Git-compatible blob hashes of the actual preferred UTF-8 document text. Identical bundled, fetched and cached text therefore has one identity; changed EULA or Terms text still invalidates acceptance. Historical `bundled` records compare against bundled content. Missing/null legacy identifiers deliberately retain the existing terms-version fallback. Git hash fixtures were independently checked with `git hash-object`.

The full wallet run exposed widget test assumptions about fire-and-forget acceptance completing without asset I/O. The test harness now supplies the actual committed markdown through a test-zone asset bundle, preserving all form-submission assertions. A separate test verifies actual platform asset loading and persistence. Production acceptance remains tied to valid form submission.

Historical `bundled` records cannot reconstruct an earlier app version's asset after an upgrade. Those records still depend on the manual terms-version bump; newly recorded acceptance retains exact content identity.

### 6. Max fed status requests back into itself

[Comment 3973534121](https://github.com/GLEECBTC/gleec-wallet/pull/3525#discussion_r3973534121) was correct. Provider-unreachable, pending and unsupported responses produced 17–18 calls within 60 ms where the test expected three total calls including setup. The loop could also add events after closure.

Status completion now updates the Max display directly instead of redispatching the user's Max action. Explicit status retry still recovers readiness, and the signed preview remains authoritative. Browser/Wasm validation additionally found that a queued explicit-amount event could erase the preview guard's pending-transfer error on native while leaving it visible on Wasm. Explicit amount revalidation now completes synchronously before that guard. The strengthened test requires the exact pending error to remain after the queue settles and confirms that no preview or submission occurs.

### 7. Concurrent reconciliation could recreate a completed journal entry

[Comment 3973546216](https://github.com/GLEECBTC/gleec-wallet/pull/3525#discussion_r3973546216) was correct. Deterministic tests failed for late submitted results after confirmation/failure, two pollers sharing one manager, acceptance write/read-back retries, and downgrade from on-chain to submitted.

The journal exposes atomic `accept` and `reconcile` operations. Both require the existing request's full correlation, retain more advanced lifecycle state and refuse to create a record from a stale result. Reconciliation deletes terminal records in the same locked operation. Acceptance write/read-back is also locked, closing a second resurrection path. Delayed unknown outcomes update only existing requests. Removed/replaced records and missing in-memory correlation produce obsolete results; they cannot restore storage or publish stale progress.

Tests cover two managers, one manager with gated writes, restarts, replacement requests, conflicting terminal states, write failures, acceptance retries and correlation disappearing during an identity check. Browser tests exercise actual Web Locks; storage mocks are explicitly not evidence of real secure-storage encryption.

## Validation results

All checks used Flutter **3.41.4 / Dart 3.11.1**. The final SDK revision is [`f990692fc1fb1bad3c8df06b504e22325055d574`](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/commit/f990692fc1fb1bad3c8df06b504e22325055d574), pinned by this wallet change.

| Check | Result |
|---|---|
| Complete wallet `test_units/main.dart`, all four required GasFree defines | **911 passed, 3 skipped** |
| Complete `komodo_defi_sdk` package, `KDF_HARNESS` empty | **908 passed, 1 skipped** |
| Wallet update/address/withdrawal regressions in Chrome/Wasm | **149 passed** |
| SDK activation/history/journal/lock regressions in Chrome/Wasm | **154 passed** |
| Actual browser Web Lock contention and owning-iframe destruction, Chrome and Wasm | **3 passed on each** (Wasm cases included in the 154) |
| `komodo_defi_local_auth` | **74 passed** |
| HD replay harness, excluding benchmark | **28 passed, 3 process-tier skips** |
| Iguana replay harness, excluding benchmark | **28 passed, 3 process-tier skips** |
| Scripted HD benchmark | **1 passed**; 30% regression gate passed |
| Wallet and SDK analysis gates | **Passed with no errors**; existing warning/information diagnostics remain |
| Changed Dart formatting and Git whitespace checks | **Passed** |
| Enforced-lockfile offline dependency resolution | **Passed; wallet lockfile unchanged** |
| Release web build with `--wasm`, GasFree send/receive enabled, analytics disabled | **Passed** |

The benchmark measured sign-in at 508 ms against its 510 ms baseline (-0.4%), and first post-activation balance at 1,023 ms against 1,025 ms (-0.2%). These are scripted timings, not live-network latency measurements.

Test assets were generated before the full runs. Subsequent repetitions used `--no-pub --no-test-assets` against those prepared assets. Build-generated coin configuration drift was restored; the committed KDF and coin-configuration pins are unchanged. The final wallet and SDK native suites were rerun after the last production corrections. The six SDK browser suites are now registered in the existing Wasm CI step.

For wallet Wasm validation, a temporary entrypoint under `test/` imported the existing update, address and withdrawal suites because Flutter 3.41 hardcodes that compiler root. It was removed after validation. All new wallet regression cases remain reachable through `test_units/main.dart`.

## Pull requests and protected-branch integration

The SDK correction is [SDK PR #376](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/376), and the wallet correction is [wallet PR #3531](https://github.com/GLEECBTC/gleec-wallet/pull/3531). Both merged into `dev` on 2026-09-09 UTC (2026-09-10 local time), as SDK `5c9f7d82dab0db0aecc539f2b4fa04f76d856509` and wallet `ccb95a32e2ad74a84a61910ae831b61054e805f7`. Both were squash merges. Their complete trees match the tested SDK `f990692f` and wallet `137e33f50` correction commits. The wallet pins that tested SDK commit. [Wallet #3525](https://github.com/GLEECBTC/gleec-wallet/pull/3525) remains the existing `dev` → `main` release PR and includes these changes. All seven original review threads have updated merged references and regression evidence. The reviewer [reopened the threads and requested to resolve them personally after verification](https://github.com/GLEECBTC/gleec-wallet/pull/3525#issuecomment-5610254407); they remain open for that review.

GitHub rejected direct advancement of SDK `dev`: its rules require a pull request and CodeQL results. Both repositories require an approving review, approval of the latest push and resolved review threads; wallet `dev` additionally requires its preview and code-guidelines checks. These fix PRs supplied the required intermediate integration. SDK `dev` → `main` remains separate release work; its content includes the prior main corrections, but the squash merge did not preserve main ancestry. Protected-branch approvals and CI completion remain external release gates for subsequent changes.

### Post-merge CI verification

SDK #376 passed its all-package Flutter tests and both previews in GitHub. Wallet #3531 passed unit tests, code guidelines, HD/Iguana replay, preview, and Linux/macOS desktop builds at the follow-up check. This does not imply a green full release matrix:

- Its iOS job failed during `xcodebuild -downloadPlatform iOS` with `Unable to connect to simulator` (exit 70), before app dependency setup or compilation.
- Its Linux browser job failed in `testActivateCoins()` at `test_integration/tests/wallets_tests/test_activate_coins.dart:38`: the test searched for `overview-total-balance`, but production has used `overview-current-value` since commit `c0cd15329` in June 2025. The failure preceded any activation action; restore and coin-icon scanning had succeeded. The same obsolete selector remained in the CEX-price test and wallet navigation helper.

The follow-up corrects that selector in the activation and CEX-price tests, shared navigation helper, and disabled Bitrefill coverage. The real Chrome 152 activation-only test then restored the fixture wallet, passed the overview and empty-search assertions, activated DOGE with a successful balance stream, and completed KMD-BEP20 addition. It next failed in `wallet_tools.dart:34` because `removeAsset()` still taps `remove-assets-button`, removed from production in commit `e9abd0353` in February 2025. The targeted integration test therefore remains red; removal navigation needs separate test maintenance. No transfer path ran. Generated coin configuration changes were restored.

### Additional SDK review: disposal during a hung submission

[Comment 3973902448 on SDK #376](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/376#discussion_r3973902448) identified a new defect: `dispose()` did not terminate an active GasFree execution, so a hung relay retained its native or browser submission lease indefinitely. Both delayed-success and delayed-error regression cases reproduced the retained lease against merged SDK `dev`.

[SDK #377](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/377), commit `a63ae5ce345179bc861e739aaa8900b5940325e8`, tracks submission ownership before asynchronous lease acquisition, shares one disposal future, and cancels local network waits. It waits for already-started journal writes before releasing the lease. Late relay and trace-status responses cannot restart persistence or presentation. Late trace registrations are closed; paused consumers and hung remote stream deregistration do not retain ownership.

Disposal cannot cancel a relay already dispatched remotely. Its unresolved journal entry is retained; a replacement manager reloads it as an unknown submission, still blocks automatic reuse, and requires explicit acknowledged discard for manual recovery. A late response from the disposed manager cannot recreate the removed record or overwrite a replacement.

The ten new regression cases cover delayed relay success/error, reservation/acceptance writes and concurrent disposal, paused initial/accepted progress, late trace attachment, hung activation, hung stream deregistration, and late trace confirmation. Independent lifecycle review found no remaining blocker. Validation of the follow-up passed **918 SDK tests (1 skipped)**, **911 wallet tests (3 skipped)** and **164 SDK Chrome/Wasm cases**, including the real Web Lock tests. The ten disposal cases plus three real-lock tests also passed together in Chrome without Wasm (**13 passed**). Both analysis gates passed without errors; the three newly introduced information diagnostics were removed. Existing notices remain. Changed-file formatting and whitespace checks passed. The release Wasm build with all four GasFree defines and analytics disabled passed after the asset transformer's required first-build retry; generated configuration drift was restored.

## Scope and limits

These checks exercise real wallet BLoCs/widgets and SDK orchestration with controlled provider responses, plus browser execution and the offline replay harness. They do not demonstrate a funded mainnet GasFree transfer, a full native release smoke test, signed release artifacts, or production deployment. No funds were sent and no release was merged or deployed. The harness benchmark is a scripted regression measurement and does not measure live KDF authentication RPC latency.

The SDK adds required atomic methods to the injectable pending-transfer repository interface; custom implementations must provide their atomic semantics. Existing package versions remain release candidates consumed by the wallet's Git submodule pin.
