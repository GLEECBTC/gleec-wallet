# KDF LI.FI combined candidate — Decker handover

Prepared 27 October 2026. This is an engineering handover record. Branch publication
and PR metadata updates are authorized; no direct colleague message or review
request has been sent.

**Release preparation can proceed. The combined code and build inputs are pinned;
formal code-freeze approval and production release remain conditional on the gates
below.** Integration of #3554–#3556 and the build-input freeze are complete. The
human-funded round, independent review and distribution checks are still outstanding.
**Final CI:** SDK #407 is green. Wallet #3557 passed units/coverage, harness,
all five platform builds, preview, dependency scan and guidelines. Chrome and
Safari each passed wallets, wallet management, DEX and miscellaneous tests, then
failed `Run Fiat On-Ramp tests:` at missing `fiat-payment-method-ramp-0`.
See the [completed CI verification](KDF_LIFI_FINAL_CI_2026-10-27.md) and confirmed
Ramp/proxy quote credential rejection. There is no pending CI left at the checked
published heads. Publication of the subsequent Banxa test and documentation
changes is now authorized, including normal automated CI/preview comments. Their
hosted CI must be checked separately; the earlier results do not establish a pass
for the new revision.

**User disposition, 27 October:** Ramp is a known unavailable service and is
deferred to the next update. Its failed browser assertions remain recorded, but
Ramp repair is no longer an unresolved code-freeze gate for this candidate.
Banxa's production catalogs, payment methods and all six API quotes passed the
recorded check; [the details and limits are below](#banxa-verification-and-ramp-disposition).
The local test follow-up now tests Banxa independently: Chrome passed USD/BTC,
EUR/BTC and EUR/LTC quote selection; all 3,800 wallet tests passed (four skipped).
Ramp is explicitly deferred/skipped. Safari compilation succeeded but execution
requires Remote Automation on the test host. Checkout and completed purchases
remain unverified. See [the new test validation](KDF_LIFI_ONRAMP_TEST_VALIDATION_2026-10-27.md).

**KDP / RC investigation:** no observed blocker requires a newer backend KDF.
Fresh native and Chrome WASM LiFi quotes passed; the current main `v3.1.1-beta` and pinned LiFi
build have identical signature/peer-healthcheck contracts. Deployment versions
and image digests remain unknown and require owner evidence. See
[the proxy compatibility audit](KDF_LIFI_PROXY_RC_AUDIT_2026-10-27.md).

## Candidate identity

| Input | Frozen value |
|---|---|
| Wallet implementation | `1643c3323f5ebeb9168b244d969a5e6d6df971a1` on `feat/kdf-667045c`, [#3557](https://github.com/GLEECBTC/gleec-wallet/pull/3557) |
| SDK | `b5c1d9db854358b84cfb4b22f0fd86d1ba8780d1`, [#407](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/407); published before the wallet pin |
| KDF | `35f0bde438eec2cb0471b19642b9d9c4602fa17d`, all seven platform SHA-256 values retained |
| Specs | `7c388ea7b91cb7c657435d416bc03e5349b46162` |
| Bundled coins | `2b0aefb78b184091ab086c66e513d8b03f5d5a01`; build-time advancement disabled |
| Toolchain | Flutter 3.41.4 / Dart 3.11.1; exact compiler revisions in the manifest |
| Version in source | `0.9.8+0`; this task does not choose the release version |
| Commission | KDF startup policy: `gleec-dex-staging`, `fee_bps: 178`, `lifi_fee_bps: 22`; combined included fee once |
| Proxy | `https://quicknode.gleec.com/lifi`; API key remains at the proxy |
| Runtime coin updates | Still enabled; this freeze fixes bundled build inputs, not the live feed or live network state |

The [machine-readable manifest](KDF_LIFI_CANDIDATE_MANIFEST_2026-10-27.json) records
lockfiles, generated asset digests, platform archive checksums, compiler versions,
build settings and local output digests. Documentation and test-only commits
after the wallet implementation revision do not change its validated runtime tree.
Generated JSON reports and log indexes are retained locally under the ignored
`.lifi/evidence/` directory and are not included in a fresh checkout. The versioned summaries retain
commands, results and limitations; the manifest retains frozen inputs and checksums.
PRs remain open; no merge, production deployment or funded mainnet execution was
performed.

## Integrated scope and conflict decisions

The following complete source diffs were applied to #3557 from their common base
`dea583b8ea57d46c9b42a3c3c4cadc216e1b131d`, then committed together. Their original
commits are not merge parents; the exact source revisions are recorded here so
reviewers can compare the resolution. Do not merge the same changes a second time.

| Source PR | Source head | Included behavior |
|---|---|---|
| [#3554](https://github.com/GLEECBTC/gleec-wallet/pull/3554) | `e93c11427c3be9454c5627302b7ecc730149f5b5` | Preserve the Swap scope through phone/tablet/desktop breakpoints and keep an unanswered Start guarded. |
| [#3555](https://github.com/GLEECBTC/gleec-wallet/pull/3555) | `622f3f36ad46016c935ba699895c2de1584c2426` | Recovery and attention behavior, approval timelines, safe external links, and opening the intended swap in Advanced. |
| [#3556](https://github.com/GLEECBTC/gleec-wallet/pull/3556) | `ce9e889dd0c6724eaa5e1d05933bc5a6f399d06a` | Trading-policy/terms checks, replacement-quote revalidation, quote-owned affordability, fee-change consent and stale-start guards. |

The notices conflict retains provider-reported payout labeling. The four BLoC
conflicts retain KDF required funding rather than substituting estimated gas,
Max intent across slippage/source changes, manual edits exiting Max, and review
invalidation of outstanding form requests. Five additional integration regressions
exercise these intersections; all new app tests are registered in
`test_units/main.dart`. The provider minimum, concrete execution amount and
approval/payout evidence remain as implemented in #3557. The legacy receive-asset
restriction from #3556 is included: old assets can be sold, but not selected to
receive through links or side switches either.

The SDK freeze also fixes a hidden mutable input: setting only
`update_commit_on_build=false` still selected a branch CDN. Frozen builds now use
commit-addressed raw content and metadata, verify sizes and Git blob hashes on
download and cache reuse, reject extra cached icons, and signal that Flutter must
rebuild after correcting assets. An empty tracked `.gitkeep` is allowed. Existing
automatic-update mode keeps its CDN behavior. When a cache contains obsolete
icons, follow the error and remove the generated icon directory before rebuilding;
do not disable verification. Use a clean output directory for release packaging.

## Fresh validation

See [commands and results](KDF_LIFI_VALIDATION_2026-10-27.md). These are fresh local
checks on the combined implementation, not passes copied from the input branches.

| Surface | Result |
|---|---|
| Wallet unit/widget aggregator, four GasFree defines | 3,800 passed; 4 skipped |
| SDK RPC / types / framework / local auth / coin updates / core | 379 / 191 (3 skipped) / 101 / 127 / 106 / 1,192 (1 skipped) passed |
| Asset transformer | 119 passed, including six frozen-build regressions |
| HD and iguana harness replay | 221 passed / 3 skipped each |
| HD and iguana performance comparison | Both passed the 30% regression gate |
| Chrome / WASM routed RPC | 107 passed |
| Python quote-runner regressions | 2 passed, including blocked fund-committing RPC methods |
| Analysis and formatting | No analyzer errors; existing 55 warnings and 2,141 infos. Changed Dart files formatted; no conflict markers or whitespace errors. |
| Web release / unsigned macOS release | Both passed from clean output directories; packaged coin files and all pinned icons match the source. Neither is a signed distribution approval. |
| Live proxy quotes | Arbitrum and Base exact quotes, included 2% fee, funding totals and rejected unfunded Max passed. See [validation details](KDF_LIFI_VALIDATION_2026-10-27.md#read-only-live-checks); generated JSON is local evidence. |

The first full wallet run failed only the new test
`changing slippage beside a Max review keeps Max as intent`: the test fixture
omitted its liquidity source. The corrected full run passed. The first web build
failed closed on obsolete cached icons; 72 extras were quarantined, all 444 pinned
icons verified, and the output directory rebuilt cleanly. The first two quote runs
failed during startup. Retained redacted diagnostics identified the second failure
as a randomly generated password containing three repeated characters; the runner
now rejects those passwords, with a deterministic regression. The first run's
engine detail was deleted by cleanup, so its precise cause remains unproven.
Earlier 26 October startup failure likewise cannot be retrospectively diagnosed.

Final CI is checked at wallet head `1c7f74722f49c45193339ab229b92db8d3ae0c93`
and SDK `b5c1d9db854358b84cfb4b22f0fd86d1ba8780d1`, separately from the earlier
local evidence. See [the final workflow results](KDF_LIFI_FINAL_CI_2026-10-27.md).
The absent Ramp widget is no longer supported only by a credential hypothesis:
a current read-only quote probe returns `AUTH.ACCESS.INVALID_HOST_API_KEY`, with
inner status 403 despite outer HTTP 200. Lists still load. This is a proxy/provider
authorization failure; its underlying configuration cause and historic failures
are not retroactively proven. No provider credential was changed. That CI follow-up retained the original test
expectation; the later local change separates Banxa from deferred Ramp as described above.

## Banxa verification and Ramp disposition

On 27 October, 08:07:13–08:07:18 UTC, ten read-only requests through
`https://fiat-ramps.gleec.com/api/v1/banxa` succeeded using `is_test_mode=false`
and the same endpoint/parameter shapes as the wallet's `BanxaFiatProvider`.

| API request | Recorded result |
|---|---|
| Supported fiat currencies | HTTP 200; 29 currencies, including USD and EUR. |
| Supported coins | HTTP 200; 120 entries, including BTC and LTC. |
| USD → BTC payment methods | HTTP 200; active Visa/Mastercard and Google Pay. |
| EUR → LTC payment methods | HTTP 200; active Visa/Mastercard, Google Pay, SEPA and PayPal. |
| USD 50 → BTC quotes | Both methods returned HTTP 200 and positive quoted coin amounts. |
| EUR 50 → LTC quotes | All four methods returned HTTP 200 and positive quoted coin amounts. |

All six quotes matched the requested fiat amount, source/target currencies and
payment-method ID, with a positive spot price. These are timestamped observations;
they do not promise later rates or availability in every region. The sanitized
requests, catalog counts, methods, quote fields and timestamps remain local at
`.lifi/evidence/KDF_LIFI_BANXA_DIAGNOSTIC_2026-10-27.json`. No API key, account,
wallet address, order or payment was supplied or created by this probe.

This API check alone did not establish browser behavior. The earlier hosted UI
jobs failed at Ramp before reaching Banxa, so they established neither a Banxa
pass nor a Banxa failure. The subsequent independent Chrome test passed USD/BTC,
EUR/BTC and EUR/LTC quote selection; Safari compilation succeeded but its session
could not start without Remote Automation. Updated hosted validation remains open.
The [on-ramp test report](KDF_LIFI_ONRAMP_TEST_VALIDATION_2026-10-27.md) retains
commands, toolchain, results and that limitation. Order creation, hosted checkout,
KYC, payment and delivery remain unverified; a human-operated purchase is required
before claiming end-to-end readiness.

The user explicitly deferred known Ramp unavailability to the next update.
Its repair is therefore an accepted limitation for this candidate, while the
historical failed CI results remain failed. The API-only Banxa verification
changed no test assertion, credential, runtime code or build input. The later
local test change explicitly skips Ramp and runs Banxa independently. Restore
Ramp quote authorization and run its independent Chrome/Safari checks for the
next update. Review, funded/usability, KDF/proxy/spec, release-identity and
signing gates remain as listed below; this consolidation does not close any gate.

## Human-owned gates and acceptance evidence

| Owner | Gate and evidence required before release |
|---|---|
| Decker / release owner | Confirm version, platforms, release branch and immutable release SHA. Review the combined resolution and exact candidate CI. A failed gate needs a named failure and explicit disposition, not a blanket green status. |
| SDK / wallet reviewers | Approve current #407 and #3557, including build-cache behavior and the retained legacy receive policy. Reconcile #3554–#3556 administratively after accepting their integrated changes; this task did not close or merge them. |
| Fiat proxy / Ramp owner — next update | User explicitly deferred known Ramp unavailability on 27 October. Restore server-held quote authorization and run the independent Ramp target for that update. Historical CI failures remain visible; the updated default gate explicitly skips Ramp and actively tests Banxa. This is an accepted limitation for the current candidate. |
| Fiat QA / browser CI owner | Banxa now passes its independent Chrome quote/selection test. Rerun updated Safari checks on a Remote Automation-enabled host and obtain hosted results for the published test changes. Hosted checkout, payment and delivery remain human-owned before claiming end-to-end on-ramp readiness. |
| Human tester with QA | Run [the funded round](SWAP_LIVE_TEST_BRIEF.md) on the exact candidate: native and token sells, approval, cross-chain completion, successful Max, cancellation/restart after approval, actual commission and gas evidence, Activity/exports, and an order-book regression. A person presses every fund-committing control. Include funds arriving/leaving between review and Start. Replay partial/refund/missing-measurement outcomes where inducing them live is unsafe. |
| Product / usability owner | Complete [the five-person session](SWAP_USABILITY_SESSION.md): at least four complete each core task unassisted, with zero misunderstandings of the five money facts; or explicitly revise this release gate. No completed study is claimed. |
| KDF maintainer | Disposition the token `call.value == 0` restriction ([review thread](https://github.com/GLEECBTC/kdf-internal/pull/29#discussion_r4144211079)). It matches the pinned spec but can exclude routes with native bridge fees; record accepted scope or change/review KDF and the contract together. No actual route failure from this restriction was observed here. |
| KDF / proxy owner | Resolve or explicitly accept five-second status-error polling ([review thread](https://github.com/GLEECBTC/kdf-internal/pull/29#discussion_r4144146204)); verify shared proxy capacity, limits, monitoring and recovery. Wallet quote backoff does not control that engine loop. |
| KDP deployment owner | Record deployed proxy revision/image digest and backend KDF version/image digest; the source Dockerfile's `dev-latest` tag is not immutable provenance. Native and browser signed quotes passed; confirm shared-load recovery and reconnection on the actual deployment. No evidence currently establishes that updating only backend KDF is required; merged proxy fixes and quote evidence are detailed in the RC audit. |
| KDF maintainer / release owner | Investigate or approve a documented exception for upstream failures `validate_dex_fee_invalid_sender_erc`, `firo_lelantus_tx_details`, `test_block_header_utxo_loop` in [run 39776341104](https://github.com/GLEECBTC/kdf-internal/actions/runs/39776341104). Its Docker/integration tiers were skipped. Upstream CI is not green. |
| Specs reviewer | Close the review loop on specs `7c388ea`; the older changes-requested review predates implemented envelope fixes and does not prove those defects remain. |
| Decker / signing owner | Produce signed installers with the Gleec identities/profiles, macOS notarization and store/distribution checks. Validate fresh install, launch, restart and upgrade on supported devices. PR builds are not distribution/signing evidence. |

**The Linux archive gap is closed.** All seven archives retain the verified
checksums from the earlier recovery. No commission value confirmation is needed;
the values above were already approved. External recipients, Tron/BTC routing,
upstream merges and production deployment remain outside Phase 1 EVM scope.

## What still blocks formal code freeze

Ramp is explicitly deferred by the user to the next update, so its named CI
failure has an accepted disposition. Historical hosted CI remains red. The updated
Banxa test passed locally in Chrome; Safari and hosted validation of the local
test revision remain open. No completed Banxa purchase is claimed.

1. **Independent review:** current SDK/wallet approvals, closure of the specs
   review, and explicit KDF decisions on native bridge fees, status polling and
   the three failing upstream tests. Include the local on-ramp test diff and
   obtain the remaining Safari/hosted evidence or an explicit release disposition.
2. **Human evidence:** the funded round and the agreed usability gate, with any
   resulting defects fixed or explicitly accepted on the frozen candidate.
3. **Release identity:** Decker/release owner confirms version, branch, platform
   scope and the exact approved commit. No new version is inferred here.

Signed packaging, notarization/store checks and installation/upgrade evidence
remain required **before distribution**. They are separate from the code-freeze
approval itself; a defect found there can still require a reviewed unfreeze.

## Handover sequence

1. Review this immutable implementation, the SDK pin and manifest; confirm the
   independent CI results and disposition any named failure.
2. Complete funded/usability and KDF/proxy/spec decisions; fix any resulting defects
   before declaring formal code freeze. An engine change requires a new consistent
   seven-platform pin and validation; never mix revisions.
3. Freeze the approved release SHA, version and non-secret build settings. If the
   SDK is squash-merged, prove tree equivalence before changing the wallet pin.
4. Build clean signed artifacts, record their digests separately from these local
   unsigned outputs, complete installation/upgrade checks and obtain release approval.

## Historical validation before the combined candidate

The 26 October results below belong to wallet `202ef1f0b` and SDK
`9e3cc0af627cfb11567c3180a64aeb2efa564c5c`, before integration of #3554–#3556.
They preserve the earlier evidence; the current candidate uses the identities and
fresh validation recorded above. KDF `35f0bde`, specs `7c388ea` and the coins pin
were already in place. The SDK was published before the wallet was repinned.
The [SDK validation and artifact provenance](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/blob/9e3cc0af627cfb11567c3180a64aeb2efa564c5c/docs/LIFI_INTEGRATION_VALIDATION.md)
records the seven archive digests, Linux recovery, SDK suite commands/counts and
read-only proxy quotes for that SDK revision.

| Historical local check, Flutter 3.41.4 | Recorded result |
|---|---|
| Wallet aggregator | 3,679 passed, four skipped, with `--no-pub --no-test-assets` and the four prescribed GasFree defines. New policy tests were registered in `test_units/main.dart`. |
| Wallet analysis | Zero errors, 55 existing warnings, 2,141 infos; nonzero exit from the existing diagnostics, none in changed wallet files. Localization keys were regenerated, changed Dart files formatted and `git diff --check` passed. |
| Web and unsigned macOS release | Both passed with exit 0. A signed macOS attempt failed because no provisioning profile for `com.GleecDEX.wallet` was installed. |
| Browser/WASM routed RPC | 107 passed in a fresh browser test profile using mocked RPCs: exact/Max requests, concrete init, locked balances, funding totals, optional measured/provider payouts and gas-estimation envelopes. |
| Native proxy quotes | Arbitrum/Base pairs passed twice with a fresh unfunded wallet, including the final run without a debug wrapper. An earlier startup attempt failed without retained engine detail and remains unresolved historically. |

The wallet suite covered Max refresh races, manual edits, source/order changes,
rate-limit pauses, rejected Max, immutable review snapshots, required funding,
included fees, partial/refund and optional payout evidence, exports, and known
approval/gas evidence. The provider minimum was passed unchanged to `init`.
The native smoke also checked concrete amount, positive minimum, funding versus
estimated gas, one included 2% fee and named `InsufficientBalance` for unfunded
Max. Four negative checks rejected fund-committing RPC method names. Neither the
mocked browser suite nor these quotes establishes funded LI.FI execution.

Historical builds temporarily set `coins.update_commit_on_build=false` and
restored the original manifest afterwards. That procedure preceded the stronger
commit-addressed build freeze described above. Both generated engine targets
were `35f0bde`. The unsigned macOS check used:

```sh
xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner \
  -configuration Release -derivedDataPath build/macos \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

The current [validation commands](KDF_LIFI_VALIDATION_2026-10-27.md) and
[native smoke instructions](TESTING.md#lifi-read-only-native-smoke) retain the
repeatable procedures. The historical browser command used
`flutter test --no-pub --platform chrome --wasm --reporter expanded test/src/rpc_methods/routed_swap`
from `sdk/packages/komodo_defi_rpc_methods`, with the same fresh-profile Chrome
wrapper documented in the current validation.

| Historical CI on the delivered 26 October commits | Result |
|---|---|
| [SDK all-package tests](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/actions/runs/40354801183) | Passed, including WebAssembly transport. |
| [Wallet units](https://github.com/GLEECBTC/gleec-wallet/actions/runs/40355113122) | Passed. |
| [HD/iguana replay and performance](https://github.com/GLEECBTC/gleec-wallet/actions/runs/40355113090) | Passed. |
| [Web preview](https://github.com/GLEECBTC/gleec-wallet/actions/runs/40355113206) | Passed. |
| [Desktop builds](https://github.com/GLEECBTC/gleec-wallet/actions/runs/40355113089) | Windows/Linux passed. macOS was cancelled with no runner name or executed steps; logs unavailable. |
| [Mobile builds](https://github.com/GLEECBTC/gleec-wallet/actions/runs/40355113066) | Android passed. iOS was cancelled with no runner name or executed steps; logs unavailable. |
| [Chrome/Safari UI](https://github.com/GLEECBTC/gleec-wallet/actions/runs/40355113130) | Both passed wallets, wallet management, DEX and miscellaneous suites, then failed only `fiat_onramp_tests`. Chrome recorded `Run Fiat On-Ramp tests:` finding zero `fiat-payment-method-ramp-0` widgets. |

The cancelled macOS/iOS jobs are not passing builds. Those browser logs alone
only suggested rejected credentials; the later independent Ramp probe established
its current authorization error without retroactively proving every earlier
failure's cause. No provider keys were read or changed in those checks. These
statuses belong to the delivered commits, not later runner/documentation commits,
and are distinct from the current candidate CI and the three upstream KDF failures.

The historical native quote report remains local evidence at
`.lifi/evidence/KDF_LIFI_AUTOMATED_QUOTE_REPORT_2026-10-26.json`.
The original two validation summaries and the Banxa summary are preserved
byte-for-byte under `.lifi/evidence/summaries/`, with source commit and SHA-256
values in `.lifi/evidence/summary-consolidation-index.json`. These ignored local
files are not required to read the results, limitations or gates in this handover.
