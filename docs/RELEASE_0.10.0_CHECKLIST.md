# Gleec Wallet 0.10.0 release checklist

Current state: 28 October 2026. App `0.10.0+0` and SDK `0.9.0` are release
candidates. Last published app: `0.9.7-1`; unpublished 0.9.8 fixes are included.
Use the [tester/reviewer handoff](RC_0.10.0_TESTER_REVIEWER_HANDOFF.md) for the
preview, reporting instructions and controlled testing restrictions. The
[input manifest](RELEASE_0.10.0_INPUTS.json) is preparation evidence, not a
published signed-artifact manifest.

## Prepared and merged into dev

Every merge below used **squash**. The owner authorized admin bypass for dev
merges; that does not satisfy outstanding release reviews or checks.

| Repository / PR | Resulting dev commit | Purpose |
| --- | --- | --- |
| SDK #405 | `50e4ef025692870f759b47d84ab2ba6c079a93f5` | Activation/Trezor fixes |
| SDK #407 | `76140abb2312f6c306c3118a2cd619c8985e64a3` | KDF/LI.FI integration and frozen artifacts |
| SDK #409 | `cc9a585504ab2cd723043399937ac04e1dee4dd1` | SDK 0.9.0 preparation |
| SDK #411 | `6038592a9f7853cd76a1a6fcb3a0fab8f3b89847` | Reproducible Melos generation repair |
| App #3554 | `df11ff0a30b6b5bf827e04df06527821d85a5e88` | Review state across breakpoints |
| App #3557 | `653ab9000eff9828a03950e63f5969aa9e675ef6` | Combined implementation, legal and review fixes |
| App #3560 | `1b91f206e2a8d1934984abfc5fbb7eea6a5f4230` | App 0.10.0 preparation |
| App #3562 | `a2886621d155e824e0ab392bfd8166a2dc827f17` | Validated SDK gitlink and Melos evidence |

App #3555 and #3556 are closed because their exact revisions were incorporated
into #3557. Their code exists on dev; the separate PRs were not independently
merged. #3557's resulting runtime tree matched tested integration `5202777ea`.

- [x] App/SDK changelogs and versions include unpublished prior fixes and
  user-facing SDK changes. Internal package constraints are aligned.
- [x] Current SDK gitlink is `6038592a9f7853cd76a1a6fcb3a0fab8f3b89847`.
  SDK main promotion and final app main repin are still required.
- [x] Frozen KDF `35f0bde438eec2cb0471b19642b9d9c4602fa17d`, specs
  `7c388ea7b91cb7c657435d416bc03e5349b46162`, bundled coins
  `2b0aefb78b184091ab086c66e513d8b03f5d5a01`. All seven rebuilt archives
  verified; independent provenance is SDK `docs/KDF_ARTIFACTS_2026-10-28.json`.
  Build-time revision advancement is disabled; runtime coin updates stay enabled.
- [x] Security parity checked against 0.9.7-1: candidate KDF ERC-20 payment amount
  validation remains outside the watcher-reward branch, retaining the fix from
  KDF `2023112`. Diverged ancestry alone was not treated as evidence of removal.

## Fresh validation of the prepared runtime

Flutter 3.41.4 / Dart 3.11.1, workspace Melos 7.8.1. The RC handoff follow-up
changes workflow/docs only; it does not alter this application/SDK runtime.

- [x] `melos bootstrap --offline --enforce-lockfile`, both prepare hooks, 22
  resolved packages. Repeated `melos run prepare --no-select`: stable output.
- [x] App unit aggregator with four production GasFree defines: **3,898 passed /
  four skipped**.
- [x] All 16 SDK native package suites through Melos: **3,045 passed / 14 skipped**.
- [x] Six SDK Chrome/WASM suites: **176 passed**; two framework WASM suites:
  **10 passed**. Auth helper-boundary retest: **127 passed**.
- [x] Full analysis: **zero errors**, 55 warnings / 2,146 infos. The additional
  infos vs the earliest snapshot are ignored generated browser wrappers; no
  new changed-line diagnostic remains.
- [x] Consumer enforced offline lockfile, input hashes, changed Dart formatting
  and diff checks pass. No hosted dependency roll was introduced.
- [ ] Final-head hosted checks/reviews and actual signed platform evidence.
  Record each failing or pending job separately; see current release PR checks.

## Testing evidence and required dispositions

- [x] Seven human-submitted settlements recorded, including buffered native-Max
  retest on `ed609b9`. Preserve earlier failure evidence; private chain details
  remain local. No further funded operation is required solely for version,
  code-generation or workflow/docs preparation.
- [x] Final native Chrome 200% legal-warning review on `5202777`, 100% desktop,
  phone 360×800 and tablet 768×1024, with expiry/Refresh. Safari and signed
  platforms need separate results.
- [ ] Atomic token-approval disclosure X04/Q12: [#3563](https://github.com/GLEECBTC/gleec-wallet/issues/3563).
  Keep those cases unfunded until resolved/reviewed; missing permission evidence
  cannot support a claim that no permission is needed.
- [ ] Existing transfer/history completeness, direction and review-labelling
  findings need disposition against the private live ledger.
- [ ] Approved LI.FI text must replace the hosted placeholder before production.
  The owner-authorized manual RC legal-testing bypass keeps the notice and
  cannot record missing terms as accepted. Ordinary builds remain gated.
- [ ] Explicit disposition of optional X06/X07 liquidity and stalled DOC/MARTY
  testnet refund cases. They are blocked, not successful execution evidence.
- [ ] KDF review: status-polling rate-limit backoff and native bridge-fee
  restriction remain open. Specs review still needs the history-method question
  and stale-thread disposition. Already implemented envelope fixes are not
  reported as current schema defects.
- [ ] Proxy/backend deployment provenance, capacity/recovery and upstream failed
  tests `validate_dex_fee_invalid_sender_erc`, `firo_lelantus_tx_details`,
  `test_block_header_utxo_loop` (run `39776341104`) need concrete disposition.
  Pinned source consumption does not require a mechanical KDF/spec branch merge;
  a changed KDF source requires seven new archives and renewed validation.
- [ ] Supported signed platforms: Safari/device behavior, fresh install, upgrade,
  signing/notarization/store evidence. Compilation alone does not satisfy these.

Five-person usability and live fiat testing were explicitly deferred by the
owner. Banxa #3559 is after 0.10.0. Preserve that disposition instead of imposing
those tests again or describing them as passed.

## Promotion and distribution order

1. Complete SDK release gates, then merge SDK #410 (`dev` → `main`) using a
   **merge commit**. Record its actual immutable main SHA. Tags/publication
   follow the approved release process.
2. Open and **squash merge** an app dev PR pinning that SDK main SHA. Reconcile
   the manifest/checklists and repeat consumer lockfile/tests as appropriate.
   Consider the SDK-tag preflight documentation in app #3510 in that final repin.
3. Complete app release gates and review the final diff/checks. Merge app #3561
   (`dev` → `main`) using a **merge commit**. Auto-merge is not enabled.
4. Tag/build/publish from the recorded main commits. Record output and generated
   coin hashes, configuration/defines and signing identity. Preserve at least
   the prior 0.9.7-1 standard: detached signatures and signed SHA256SUMS. Verify
   installation/upgrade for every advertised artifact.
5. Final production build must have `BYPASS_LEGAL_DOCUMENT_GATE=false`, approved
   hosted legal text and clean-profile consent verification. Retire the manual
   RC exception/channel after testing. Web deployment and GitHub publication
   are separate operations; inspect legacy `release: created` native triggers.

This checklist does not authorize a production merge or waive an unresolved
release gate. It is ready to accompany reviewer and controlled-tester invitations.
