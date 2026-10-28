# Gleec Wallet 0.10.0 release checklist

Prepared 28 October 2026. Version `0.10.0+0` is preparation metadata; the last
published app release is 0.9.7-1. The closed 0.9.8 candidate (#3543) was not
published. Its fixes are included and documented in 0.10.0.

The [preparation input manifest](RELEASE_0.10.0_INPUTS.json) records the current
lockfile/config hashes, seven archive digests and default build settings.
It must be reconciled with final build settings and output evidence at freeze.

## Candidate inputs and PR sequence

- App integration source: `5202777ea23ec38acf26c5e344e5eb36cdf75130`, #3557.
  It integrates the #3554–#3556 review/recovery changes and #3558 legal changes.
- SDK integration source: `03a3cb1adf666952a16f0cd80e67b8173076f4c1`, SDK #407,
  including SDK #405. SDK 0.9.0 preparation is stacked on that source.
- This preparation was stacked on app `feat/kdf-667045c`. #3554 and #3557
  have now squash merged into `dev`; retarget this preparation to `dev` after
  source-branch reconciliation. Preserve reviewed content and record real SHAs.
- Branch strategy: **squash every PR into `dev`**, including integration and
  preparation PRs. Use merge commits only for `dev` → `main` release promotion.
  Source-branch updates may merge dev for conflict resolution; the final PR
  merge into dev must still be a squash.
- The actual release PR is `dev` → `main`, initially draft. It must contain
  both integrations, preparation and the final SDK `main` pin before promotion.
- KDF `35f0bde438eec2cb0471b19642b9d9c4602fa17d`; specs
  `7c388ea7b91cb7c657435d416bc03e5349b46162`; bundled coins
  `2b0aefb78b184091ab086c66e513d8b03f5d5a01`. Seven archive checksums and
  independent rebuild provenance live in SDK `docs/KDF_ARTIFACTS_2026-10-28.json`.
- Bundled coin revision advancement stays disabled; runtime updates stay
  enabled. Do not copy earlier candidate manifests as final-head evidence.
- Toolchain: Flutter 3.41.4 / Dart 3.11.1. Retain the app lockfile and path
  overrides as one complete SDK checkout. Record final lockfile and output
  SHA-256 hashes, generated coin hashes, build defines and signing identity
  with the final distribution manifest.

## Preparation validation

- [x] Bump app version and replace Unreleased notes with 0.10.0 notes.
- [x] Include unpublished 0.9.8 fixes and user-facing SDK changes.
- [x] Separate expected, guaranteed, provider-reported and measured swap facts.
- [x] Check security parity with 0.9.7-1: candidate KDF `eth.rs` line 5859
  validates ERC-20 payment amount outside the watcher-reward branch. This
  directly retains the fix from KDF `2023112`; divergent ancestry alone would
  not establish it. See SDK 0.9.0 checklist for immutable source links.
- [x] Pin SDK dev preparation squash `cc9a585504ab2cd723043399937ac04e1dee4dd1`
  (SDK #409, now merged); consumer lockfile changes only 11 SDK version lines.
  SDK #410 is the separate draft `dev` → `main` promotion. Final main pin is
  still required before app promotion.
- [x] Fresh app aggregator: **3,898 passed, four skipped**, all four production
  GasFree defines, Flutter 3.41.4 / Dart 3.11.1.
- [x] Full analysis after resolving both workspaces: **zero errors**,
  55 existing warnings and 2,130 infos.
- [ ] Complete final-head platform, SDK, harness, preview and dependency checks.

Fresh preparation results are recorded in the PR. Historical integration
evidence on `5202777` reports 3,898 app units passed / four skipped. SDK
`03a3cb1a` passed all 16 package suites, both WASM steps and both previews.
These are not fresh results for the prepared version graph.

### Fresh preparation validation — 28 October 2026

- Full app aggregator: **3,898 passed / four skipped**, 5m15s. The fresh
  checkout's first asset-transform pass requested its documented rebuild;
  the complete rerun passed without disabling a guard or changing a checksum.
- All 16 SDK package suites: **3,045 passed / 14 skipped**, with the prepared
  SDK versions. Individual results are in SDK 0.9.0's checklist.
- `flutter pub get --enforce-lockfile --offline` succeeds. Lockfile drift is
  limited to the 11 local SDK package versions, with no hosted dependency roll.
- Full analysis: **zero errors**, 55 existing warnings and 2,130 infos. The
  initial pass before SDK dev-dependency resolution had setup errors; resolution
  and a full rerun removed them. No Dart source changed or needs formatting.
- All internal dependency minimums, local Markdown targets and diff checks pass.
- Final-head hosted CI, WASM, signed platform and installation evidence remain
  separate requirements; these local results do not complete them.

## Required release dispositions

- [ ] Close/review atomic token-approval disclosure (X04/Q12), legal-document
  availability and existing transfer/history findings from the live round.
  Optional ETC/BNB cases without offers are blocked, not passed execution.
- [ ] Verify final live 200%/short-window review behavior after sign-in, Safari,
  fresh install and upgrade on supported signed builds. PR build success alone
  does not establish notarization, signing or installability.
- [ ] Preserve the recorded seven settled live operations, including the
  human-submitted buffered native-Max retest on `ed609b9`. Retain the earlier
  failed preparation evidence. Private transaction details stay local. Any
  newly needed funded operation requires a person to commit funds.
- [ ] Record owner disposition of five-person usability and live fiat on-ramp
  testing deferred for the integration RC. Banxa quote test remains enabled;
  provider/proxy failure is tracked in #3559. Do not call a deferred test passed.
- [ ] Resolve KDF native bridge-fee/status polling review, specs review,
  proxy/backend deployment provenance/load recovery and upstream failures
  `validate_dex_fee_invalid_sender_erc`, `firo_lelantus_tx_details`,
  `test_block_header_utxo_loop` (run `39776341104`).
- [ ] Current-head release reviews and required checks pass or have a concrete,
  authorized disposition. The one-off #3557 legal preview override does not
  transfer to this PR or production. Do not weaken rulesets/tests for release.

## Promotion and distribution order

1. Squash merge reviewed SDK integration/preparation to `dev`; promote SDK
   `dev` to `main` with a merge commit and record the immutable release SHA. Create the
   approved SDK/package tags only under the release process.
2. Repin this app preparation to that SDK `main` SHA, resolve/review lockfile,
   and repeat consumer checks. The SDK preparation branch pin is provisional.
3. Squash merge reviewed app integration/preparation to `dev`. Recheck `main` ancestry,
   final diff, SDK reachability, checks and all remaining gates on app promotion.
4. Promote app `dev` to `main` with a merge commit; record final SHA. Create the
   `0.10.0` release/tag on that commit under the approved release process.
   Build signed artifacts from that same commit, attach hashes and signatures,
   verify install/upgrade and reconcile release notes with the actual artifacts.
   Prior 0.9.7-1 desktop assets included detached signatures and signed SHA256SUMS;
   preserve at least that verification standard. Record actual platform coverage.
5. Inspect release workflow triggers before publishing. Legacy native workflows
   listen to `release: created`; creating a draft is not proof those builds ran.
   Web RC and production deployment remain separate from a merge or GitHub tag.

This preparation opens reviewable PRs. It does not merge, publish, deploy,
commit funds or waive an unresolved gate.

## Dev merge record — 28 October 2026

- App #3554: squash `df11ff0a30b6b5bf827e04df06527821d85a5e88`.
- App #3557: squash `653ab9000eff9828a03950e63f5969aa9e675ef6`.
- SDK #405 and #407 are also squash merged into SDK dev; #407's actual squash
  is `76140abb2312f6c306c3118a2cd619c8985e64a3`.
- App dev after both implementation merges exactly matches tested integration
  `5202777ea`. #3555/#3556 content is included through #3557; their separate
  merges have conflicts and were not performed.
- The owner explicitly authorized admin bypass for dev merges. #3554's updated
  head CI was still running; #3557's known provider/UI and preview results stay
  recorded separately. The passing combined runtime tree was preserved exactly.
- Preparation #3560 is retargeted/reconciled to dev and must also be squashed.
  Its SDK dev preparation pin remains provisional until SDK main promotion;
  final SDK-main repinning and the draft #3561 release gates remain required.

The app preparation now pins SDK dev squash `cc9a5855`, whose complete tree
matches the updated SDK preparation head `63b04232`. Compared with the tested
SDK preparation `2f6ba724`, only the release checklist changed. App runtime and
dependency files remain those tested at `6bca15444`; app documentation, the
input manifest and the equivalent SDK gitlink record the real squash history.
SDK main promotion and final main repinning remain separate release gates.

## Melos validation and final dev candidate — 28 October 2026

The configured SDK Melos bootstrap was run with Flutter 3.41.4 / Dart 3.11.1,
workspace Melos 7.8.1, `--offline --enforce-lockfile`, and both prepare hooks
(index generation followed by build runners). Melos resolves 22 workspace
packages. Repeating `melos run prepare --no-select` produced identical output.

The initial regeneration exposed five analysis errors: platform-specific lock
implementations were exported together and routed-swap Dart parts were exported
as standalone libraries. SDK #411 corrects the generator configuration,
refreshes tracked output and preserves the internal Trezor helper boundary.
It is squash merged into SDK dev at
`6038592a9f7853cd76a1a6fcb3a0fab8f3b89847`, the current app gitlink.
Original SDK preparation #409 remains recorded separately at `cc9a5855`.

Fresh validation on the corrected generated output:

- All 16 SDK package suites through `melos exec`: **3,045 passed / 14 skipped**.
- App aggregator with all production GasFree defines: **3,898 passed / four
  skipped**, 4m59s.
- Six SDK Chrome/WASM suites: **176 passed**; two framework WASM suites:
  **10 passed**. Auth retest after preserving its helper boundary: **127 passed**.
- Full analysis: **zero errors**, 55 warnings and 2,146 infos. The extra infos
  relative to the earliest snapshot come from ignored generated web wrappers.
  No new changed-line diagnostic remains.
- Changed-file formatting, generation stability, input hashes and diff checks
  pass. Package versions and consumer dependency versions are unchanged.

SDK #410 and app #3561 still require the recorded final main-promotion and
release gates. Once SDK main is promoted, repin the app to that immutable main
SHA in a squash-merged dev PR before promoting the app to main.
