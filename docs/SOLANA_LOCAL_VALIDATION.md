# Solana local validation

Validation on 2026-11-08 uses isolated checkouts based on wallet
`8d515c7606e9f37002128b889c7451a92f4d7ec5`, SDK
`ab29d57aa05aa48240ab7430c6d51a4f5e60a579` and coins
`ca20611537fe84f9398d1a63f3d27a4386fb161d`.
The original mixed workspace is not the source of the PR test results.
Flutter is pinned to 3.41.4. SDK authentication is a separate prerequisite;
Solana's final review diff excludes its shared dispatch guard and transport hooks.
The initial SDK Solana commit was `f8c497c7c71e58a232897d37f0457e140b750c86`
([SDK PR #444](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/444)),
stacked on the separately reviewed authentication commit
`c8438ebfffcd72998c46aa454a9e4ae845422316`.

## Initial registry and native engine evidence

[Coins PR #2103](https://github.com/GLEECBTC/coins/pull/2103) contains the validated
catalog commit `83ed4b75564a1e097d774d64ac5343b161fcb44c`.
All 35 scanner/generator tests pass. Regeneration reproduces all five candidate
fixture files byte-for-byte, and the old/new generators produce identical output
for all 774 existing assets with identical inputs and network calls disabled.
Read-only public node probes pass health, finalized slot and expected genesis
checks for mainnet and devnet. Production generated catalog outputs are unchanged.

The extracted wallet runner passes 19 offline manifest/smoke tests. A fresh
unfunded native smoke also passes for both HD and Iguana using `KDF_BINARY` and
isolated temporary wallets. It verifies zero-balance SOL/classic-SPL activation,
shared platform/token owner, distinct wallet derivation, targetless v2 history,
address validation, deactivation and later token activation. It performs no
signing, key export, withdrawal, broadcast, order placement or swap recovery.

That smoke uses development engine `b1ff8f05c880d6f118124cac9ef615aa9d91bb39`
(version `3.1.0-beta_b1ff8f0`), binary SHA-256
`4afd0cc03f54ea06a0b298db77e97ee561d8d9ea336f673d3fd30e2b49a0eb0c`,
and wallet-only catalog SHA-256
`5f91b1ade662ac4bcc89aad5d95df68bd11be5c13792f25f0d8cb632e29857bf`.
It is development evidence, not proof of the eventual combined release engine.

## Initial branch validation record

The final wallet gate on the published SDK commit passes **4,057 tests with four skips** using the
prescribed four GasFree defines and freshly generated test assets. The full
`flutter analyze --no-pub` invocation reports **zero errors**, 56 warnings and
2,145 informational notices; its nonzero exit is not described as a clean
analyzer pass. Scoped trading analysis has no issues. The final-stack WebAssembly
release build passes in 80.9 seconds with production
capability defaults. All 68 manifest/dependency hashes remain unchanged, and the
result contains no debug-wallet fixture files or references. This establishes
compilation, not browser engine execution.

Review and regression testing fixed: stale displayed amounts after a rebuilt
Solana review; canonical durable duplicate protection across equivalent default
parameters; signed-preview cleanup on session changes; and missing retry currency
after a failed funding-balance read. Confirmation tests require fresh funding and
exactly one submission. New tests are registered in `test_units/main.dart`.
Earlier mixed-workspace test totals are not used as PR evidence.

The final stacked SDK checks pass:

| Suite | Passed | Skipped |
| --- | ---: | ---: |
| Core SDK | 1,294 | 1 |
| Focused Solana contracts | 51 | 0 |
| Types | 203 | 3 |
| RPC methods | 388 | 0 |
| Coin registry client | 146 | 0 |
| Coin updates | 108 | 0 |
| SDK UI | 4 | 0 |
| Framework | 113 | 1 environmental skip, resolved below |
| Harness HD / Iguana replay | 224 each | 3 opt-in process cases each |
| Chrome/Wasm Solana streams/catalog | 3 | 0 |
| Chrome/Wasm isolated storage | 2 | 0 |
| Chrome/Wasm transport/diagnostics | 5 | 0 |

The framework Windows wrapper passes separately with
`GLEEC_CMAKE=/Users/charl/Library/Android/sdk/cmake/3.22.1/bin/cmake`, including its
10 Python cases. The auth base's macOS validator matrix also passes 11 Ruby
cases/32 assertions. The harness benchmark passes the committed 30% threshold
(sign-in -0.4%, first fetched balance -0.1%). SDK changed-file analysis reports
zero errors/warnings and 202 informational notices; generator-owned Freezed output
retains five whitespace-only lines. These are recorded rather than described as
a fully clean analyzer/whitespace run.

The wallet dependency update requires only two test-double signature adaptations
for the authentication SDK's optional registration parameter. Wallet auth UI and
behavior changes remain in their separate workstream.

## PR review validation

The initial review updates keep authentication on the separate prerequisite and
retain both production build configuration files byte-for-byte. The approved
native archive follow-up below records the later two-platform exception. Coins revision
`58534ebf14503c4c7b29928fb6b6730cc69eb4b7` passes all 40 registry tests.
Maintainer feedback prompted the devnet rename to `TESTSOL` / `TESTUSDC-TESTSOL`,
avoiding mainnet pricing prefixes and preserving KDF's ticker/platform statistics
identity. Generator output retains the exact `-TESTSOL` suffix. All 774 existing
raw/generated configurations and both mainnet Solana entries remain unchanged.
The wallet-only catalog digest is now
`5d10d969557cd0a681e4d60b605641606e76f55b8050e757597dc735d033451c`;
[the candidate guide](SOLANA_INTEGRATION.md) records both swap-snapshot digests.
The earlier snapshot and smoke evidence above are retained as history, not reused
as the renamed candidate's manifest.

Final SDK review revision `cd3a5bc8b3b5a4ae5fa1de79c36d6c24c5cd5b83` is stacked
on the separate authentication prerequisite
`cf69f4611b83bba7e05831e1b20c2447337ce867`. The authentication package has no
diff relative to that base. The ticker follow-up changes only fixture/test names
and symbol assertions. All five affected SDK suites and both replay/benchmark
gates pass on the final frozen source. The two changed Chrome/Wasm fixtures pass;
the full 268-test browser run recorded below also passed before this data-only
follow-up and remains a CI requirement on the final commit.

Final validation: 1,304 core tests (one skip), 147 coin tests, 112 update tests,
and 227 harness tests per wallet mode (three opt-in process skips each).
Four Chrome/Wasm storage tests verify actual IndexedDB isolation, reopen and
custom-token restoration. The exact 15-file Chrome/Wasm SDK workflow passes all
268 tests, including 38 withdrawal tests with real cross-context lock exclusion
and cancellation cleanup. Both harness benchmarks pass the 30% threshold:
HD sign-in +1.6% / first balance +1.1%; Iguana +0.6% / +0.1%.
Review-file analysis has no errors or warnings; existing informational notices
remain. Formatting and review diff checks pass.

The final wallet gate passes **4,102 tests with four skips** using the prescribed
GasFree defines. Full wallet analysis reports zero errors, 55 existing warnings
and 2,144 informational notices; the final changed trading files analyze clean.
The WebAssembly release build passes in 68.9 seconds and contains no debug-wallet
fixture files or references. The 22 offline candidate/smoke-tool tests pass.

The authentication package now passes all 196 tests. Its earlier Trezor streamed
sign-in timing failure was corrected on the separate authentication branch.
Framework (114), RPC (388), types (203 plus three skips), UI (four), transformer
(125), migration (14), CLI (30), market data (362 plus six skips), charts (17),
logs (27) and symbols (one) pass.

Two unused test mocks were replaced with real collaborators backed by their
existing mocked clients to avoid the pinned Wasm compiler's private-forwarder
defect; all test cases and assertions remain. The replay fixture now separates
known wallets from active sessions after no-auth restart. Its two new lifecycle
regressions and original deletion tests pass; the production authorization guard
is unchanged.

Native CI preparation now fetches and verifies the selected pinned platform
before CMake/CocoaPods configuration. All 21 offline fixture cases pass, and
preparation against the actual pinned Windows archive passes digest/provenance
verification. The selected-platform helper and CI action contain no wallet
authentication behavior changes. The macOS and Linux artifact-publication
blockers and SDK-merged pin gate remain enforced. The Windows CI build is
[green](https://github.com/GLEECBTC/gleec-wallet/actions/runs/42526474678/job/128871102830)
on wallet `611e24a411737d2d91efa2d31b77f55d97396ce1` and again on `77b3d3c8364de10c8f2c25a764a2d9ee9ad6db0a`.
Later checks add safe diagnostics and Linux/iOS fixture coverage while preserving
the native-library prerequisites.

The fresh unfunded native smoke passes again in both derivation modes at
2026-11-08 22:37 UTC using the same exact development binary above and the renamed
catalog digest `5d10d969557cd0a681e4d60b605641606e76f55b8050e757597dc735d033451c`
from coins commit `58534ebf14503c4c7b29928fb6b6730cc69eb4b7`. Retired identifiers
cannot authorize a new trade, including with restored catalog metadata. A new immutable manifest
and isolated preview profile were generated; old preview data was not migrated
or cleared. The smoke performs no signing, export, withdrawal, broadcast or
funded trading.

Review regressions cover late multi-token completion, disabled-engine cache
shortcuts, custom SPL restore/identity, stale candidate caches, overlapping send
confirmations, stale-wallet completion details, failed startup reuse, queued
preview events, refreshed sender display, invalid candidate profiles, smoke RPC
envelope overrides, changed funding/receive deductions, final transport
freshness and policy, and routed/bot restrictions. Solana bot automation remains
gated pending engine per-order funding/policy enforcement; manual devnet orders
retain the existing opt-in and acceptance requirements. All new wallet tests
are registered in `test_units/main.dart`.

The SDK workflow now runs on every PR base, including the authentication stack.
The wallet SDK workflow matches the actual `sdk` gitlink. These coverage fixes
do not bypass native packaging checks or the SDK-merged pin gate.

The browser integration runner now rejects nonzero process exits even if output
contains a success marker, and also recognizes Flutter's plural failure summary.
Seven focused regressions cover those outcomes and remain in the required unit
entry point. The existing browser suite still skips Banxa/Ramp, and its bounded
DEX check does not certify complete settlement. A green browser regression run
therefore does not close the funded Solana acceptance gates below.

## Production configuration and remaining acceptance

The SDK production engine remains
`f9632e0ec771668a6f21b37aede01a30110141cb`, and its catalog remains
`cc8249e85e54467bc2684c2712857711eab55fd2`. On 2026-11-09 the user approved
updating only the Linux/macOS archive selectors and checksums in both build
configuration files, plus Linux shared-library packaging. All other manifest
fields stay unchanged from the SDK base. No candidate browser/mobile artifact
replaces a production asset. Candidate catalogs require an immutable digest,
isolated storage, dedicated browser origin and explicit `enableAutoUpdate:false`.

The [engine dependency record](SOLANA_KDF_DEPENDENCIES.md) remains open. Fixture
and replay tests do not establish funded SOL/SPL transfers, Token-2022 support,
SPL Max decimal scaling, real token-history streaming/backfill, or native/browser
atomic execution and recovery. Those rounds require a combined engine and the
manual submission procedure in [SWAP_LIVE_TEST_BRIEF.md](SWAP_LIVE_TEST_BRIEF.md).
Mainnet atomic trading and Solana routed execution remain unavailable.

The separate authentication prerequisite requires native libraries on desktop.
The original macOS/Linux archives were rejected because they lacked usable dynamic
libraries. The approved replacements are built from the same exact production
KDF commit and are published as [native library assets](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/releases/tag/native-library-assets-f9632e0-20261108):

| Platform | Archive SHA-256 |
| --- | --- |
| macOS universal | `a77a26c9814008c958b4f57d928ef59ca01b04b3d0c2710ea49ed8a707cfabd8` |
| Linux x64 | `beb961fe98dbb3d0b1542fb530c749317ecd573b57f94d63b720f4908841d899` |

SDK commit `34faf005b2e092419d0cb12b84f21b02a6c7f0d6` contains the approved
native artifact and packaging follow-up. Normal credential-free SDK downloads
pass checksum/provenance checks for both.
The actual Linux validator and macOS arm64/x86_64 validator pass. All 31 Linux
ELF packaging cases and seven focused Flutter checks pass without skips. The
complete updated framework suite passes all 117 tests. Changed-file analysis
reports zero errors/warnings and one existing informational notice. Linux
now bundles only validated shared libraries beside the app and loads them from
that installation, with no executable copied into the user's home. SDK CI
explicitly installs the fixture tools and selects GNU readelf; local validation
uses LLVM readelf. Wallet Linux CI explicitly installs binutils for validation.

The full wallet gate passes again on this approved SDK update: **4,102 tests,
four skips**, with all four prescribed GasFree defines. Full wallet analysis
again reports zero errors, 55 existing warnings and 2,144 informational notices.

The production source/catalog pins, authentication separation, library checks
and SDK-merged pin gate remain enforced. Application builds must validate the
new artifacts on the updated PR head. The unfunded process smoke above uses the
explicit `KDF_BINARY` development override and does not prove native application
packaging or close the Solana combined-engine acceptance gates.
