# v0.9.7 release candidate review

Reviewed on 2026-09-05 against [PR #3525](https://github.com/GLEECBTC/gleec-wallet/pull/3525).

## Review basis

- Release base: `origin/main`, `07fc5bc5961e258399ad829c8c0784fcb27d4d53`.
- Review branch starts at `origin/dev`, `e1f7885d18a895ce443464d247349bcc31715522`.
- [PR #3514](https://github.com/GLEECBTC/gleec-wallet/pull/3514), head `8adb081f305e5e8a78fe5ce6eb36aba74931976e`, is squash-merged locally before the review fixes. This includes the web update changes from #3526.
- Original SDK release pin: `7dce2687276684c132a1d9e4702c7d5c541eba2a`; reviewed fixes are committed at `a9e3bde6` on SDK branch `fix/release-candidate-review-20260905`.
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

## Validation

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

The build-generated coin configuration change was restored; the KDF binary pin remains unchanged. The app and SDK fixes are committed separately, with the app pointing to the local SDK fix commit. The SDK branch must be published before another checkout can fetch that new submodule revision.

## Release boundaries

- These are local review changes. No GitHub merge, release tag, production deployment, or funded transfer is part of this review.
- Native signing/distribution and a deployed RC smoke test remain release checks. The observed GitHub checks on the release PR passed except `Test web-app-linux-profile`; that existing integration failure is not a passing validation result for this patch.
- Production-hosted wrapper protection reaches shipped native clients only when the updated wrapper and headers are actually deployed. The included deployment verifier checks that separate release action.
