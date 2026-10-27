# KDF LI.FI combined candidate — Decker handover

Prepared 27 October 2026. This is a local engineering handover record; no handover
message, PR comment, review request or other communication was sent.

**Release preparation can proceed. The combined code and build inputs are pinned;
formal code-freeze approval and production release remain conditional on the gates
below.** Integration of #3554–#3556 and the build-input freeze are complete. The
human-funded round, independent review and distribution checks are still outstanding.

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
build settings and local output digests. Documentation commits after the wallet
implementation revision do not change its validated runtime tree. PRs remain open;
no merge, production deployment or funded mainnet execution was performed.

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
| Live proxy quotes | Arbitrum and Base exact quotes, included 2% fee, funding totals and rejected unfunded Max passed. [Final report](KDF_LIFI_QUOTE_REPORT_2026-10-27_FINAL.json). |

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

CI for the exact implementation is separate from local evidence. Current snapshot
and links are in the validation report. Do not treat queued/running jobs as passing,
or transfer an older head's platform/UI status to this candidate. The earlier
Chrome/Safari failure was `Run Fiat On-Ramp tests:` — missing
`fiat-payment-method-ramp-0`; provider credentials were only a hypothesis.

## Human-owned gates and acceptance evidence

| Owner | Gate and evidence required before release |
|---|---|
| Decker / release owner | Confirm version, platforms, release branch and immutable release SHA. Review the combined resolution and exact candidate CI. A failed gate needs a named failure and explicit disposition, not a blanket green status. |
| SDK / wallet reviewers | Approve current #407 and #3557, including build-cache behavior and the retained legacy receive policy. Reconcile #3554–#3556 administratively after accepting their integrated changes; this task did not close or merge them. |
| Human tester with QA | Run [the funded round](SWAP_LIVE_TEST_BRIEF.md) on the exact candidate: native and token sells, approval, cross-chain completion, successful Max, cancellation/restart after approval, actual commission and gas evidence, Activity/exports, and an order-book regression. A person presses every fund-committing control. Include funds arriving/leaving between review and Start. Replay partial/refund/missing-measurement outcomes where inducing them live is unsafe. |
| Product / usability owner | Complete [the five-person session](SWAP_USABILITY_SESSION.md): at least four complete each core task unassisted, with zero misunderstandings of the five money facts; or explicitly revise this release gate. No completed study is claimed. |
| KDF maintainer | Disposition the token `call.value == 0` restriction ([review thread](https://github.com/GLEECBTC/kdf-internal/pull/29#discussion_r4144211079)). It matches the pinned spec but can exclude routes with native bridge fees; record accepted scope or change/review KDF and the contract together. No actual route failure from this restriction was observed here. |
| KDF / proxy owner | Resolve or explicitly accept five-second status-error polling ([review thread](https://github.com/GLEECBTC/kdf-internal/pull/29#discussion_r4144146204)); verify shared proxy capacity, limits, monitoring and recovery. Wallet quote backoff does not control that engine loop. |
| KDF maintainer / release owner | Investigate or approve a documented exception for upstream failures `validate_dex_fee_invalid_sender_erc`, `firo_lelantus_tx_details`, `test_block_header_utxo_loop` in [run 39776341104](https://github.com/GLEECBTC/kdf-internal/actions/runs/39776341104). Its Docker/integration tiers were skipped. Upstream CI is not green. |
| Specs reviewer | Close the review loop on specs `7c388ea`; the older changes-requested review predates implemented envelope fixes and does not prove those defects remain. |
| Decker / signing owner | Produce signed installers with the Gleec identities/profiles, macOS notarization and store/distribution checks. Validate fresh install, launch, restart and upgrade on supported devices. PR builds are not distribution/signing evidence. |

**The Linux archive gap is closed.** All seven archives retain the verified
checksums from the earlier recovery. No commission value confirmation is needed;
the values above were already approved. External recipients, Tron/BTC routing,
upstream merges and production deployment remain outside Phase 1 EVM scope.

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
