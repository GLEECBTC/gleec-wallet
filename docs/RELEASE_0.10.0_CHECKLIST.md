# Gleec Wallet 0.10.0 release checklist

Current proposal: 29 October 2026. App `0.10.0+0` and SDK `0.9.0` are release
candidates. Last published app: `0.9.7-1`; unpublished 0.9.8 fixes are included.
Use the [tester/reviewer handoff](RC_0.10.0_TESTER_REVIEWER_HANDOFF.md) for the
preview, reporting instructions and controlled testing restrictions. The
[input manifest](RELEASE_0.10.0_INPUTS.json) is preparation evidence, not a
published signed-artifact manifest.

## Pending merged-dev KDF roll

The proposed gitlink is SDK `21f64b5002e7ea14296db985a8cade07e003e1d4`
([SDK #419](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/419)),
pinning merged KDF dev `e40ac2fb4319d352bf9c93683eb2518ce9f939e0`.
[SDK #420](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/420)
prepares its focused carry into frozen `release-0.9.0`. The app pointer PR
must be repinned to the actual accepted frozen SDK SHA before its dev squash,
then carried through its own focused `release-0.10.0` PR after tests and review
pass. Both main RCs stay open. The accepted 28 October snapshot below and its
previews remain historical; they do not certify this new roll.

- [x] Full ten-platform build passed; all seven SDK archives independently
  match Actions artifacts and ordinary mirror downloads. Strict CLI passed.
- [x] Enforced offline Melos bootstrap and repeated prepare passed without
  tracked generation drift. All 16 suites: **3,057 passed / 14 skipped**;
  core Chrome/WASM **215 passed**, framework WASM **10 passed**.
- [x] Verified new native KDF version and read-only Arbitrum/Base quotes,
  funding, minimums, included fee and unfunded Max using a fresh unfunded wallet.
- [x] Rechecked unchanged `eth.rs` payment/refund defaults (155,000 / 125,000);
  update their source comment and deliberate exact-pin regression together.
- [x] Full app aggregator after that source-check update: **3,919 passed / four
  skipped** with all four production GasFree defines. Full analysis: **zero
  errors**, existing 55 warnings / 2,144 infos; changed-file formatting and
  input/lockfile/hash checks passed.
- [ ] Current-head hosted checks, reviewer signoff, SDK dev squash/focused RC
  carry, final app pin/dev squash/focused RC carry, and refreshed RC preview.
- [ ] Upstream KDF run `40755486033`: failed tests are named in SDK provenance;
  its one retry repeated the macOS integration failures; remaining jobs are
  pending. Build/downstream success does not waive session-storage, Sia Max
  or other upstream failures.

The [input manifest](RELEASE_0.10.0_INPUTS.json) describes this proposal.
The records below describe the previous accepted frozen snapshot.

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
| SDK #412 | `97b48556ab607506909734841e1f0a003cece694` | Wallet-scoped routed handles and unconfirmed starts |
| SDK #413 | `56828b91cb3eb147538803a524271278a2107b75` | Signed EVM movements and verified ETC history |
| SDK #414 | `52f1181f2e0362b6963084089407a06af2e717ad` | Final SDK validation record |
| SDK #415 | `22e14ac94fb555776eda370de08f1dafd5ca4019` | Frozen release-branch strategy |
| App #3568 | `dfe722dcf166da4d5bd78b9120c84505812c83f9` | Consume wallet-scoped routed sessions |
| App #3569 | `22c0892e4ce0341e4c935159842bbf98a1f3f9fb` | Refuse unverifiable atomic EVM-token permission |
| App #3570 | `c85742a272a4cb92499db821e288a982a56b9ab3` | Transfer principal, review and precision |
| App #3571 | `c0373eed24d0dbe95a5030b4cb513b9fa464aedb` | Native EVM precision when metadata omits decimals |
| App #3572 | `f94e507214ad0330d508bfe8d68624ad067ff526` | History direction, self transfers and valuation |
| App #3510 | `698af846229cc3458dc539d5f3e39fa7f76967d6` | SDK tag/version/ancestry preflight before publication |
| SDK #417 | `e849cd0de5b59aa6ebe49f5e137c9af6184604e8` | Complete in-flight pagination with session revocation |

SDK #418 normally merged only the #417 dev squash into `release-0.9.0` as
`80e656101ce1b85fe05ddcbc05b0520f3265d1a0`; their complete trees match.
The SDK #416 pagination review thread is resolved.

App #3555 and #3556 are closed because their exact revisions were incorporated
into #3557. Their code exists on dev; the separate PRs were not independently
merged. #3557's resulting runtime tree matched tested integration `5202777ea`.

- [x] App/SDK changelogs and versions include unpublished prior fixes and
  user-facing SDK changes. Internal package constraints are aligned.
- [x] Current SDK gitlink is `80e656101ce1b85fe05ddcbc05b0520f3265d1a0` on frozen
  `release-0.9.0` ([SDK #416](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/416)).
  SDK main promotion and final app main repin are distribution steps after
  review, not prerequisites for freezing this exact RC source.
- [x] Frozen KDF `35f0bde438eec2cb0471b19642b9d9c4602fa17d`, specs
  `7c388ea7b91cb7c657435d416bc03e5349b46162`, bundled coins
  `2b0aefb78b184091ab086c66e513d8b03f5d5a01`. All seven rebuilt archives
  verified; independent provenance is SDK `docs/KDF_ARTIFACTS_2026-10-28.json`.
  Build-time revision advancement is disabled; runtime coin updates stay enabled.
- [x] Security parity checked against 0.9.7-1: candidate KDF ERC-20 payment amount
  validation remains outside the watcher-reward branch, retaining the fix from
  KDF `2023112`. Diverged ancestry alone was not treated as evidence of removal.

## Fresh validation of the prepared runtime

Flutter 3.41.4 / Dart 3.11.1, workspace Melos 7.8.1. Combined runtime is
app source `f94e5072` with SDK `80e65610`, tree-identical to the validated
SDK dev squash `e849cd0d`. The later SDK review repair follows every in-flight
history page and retains session revocation across later pages. The final app
consumer gate was repeated with that repair. App implementation is unchanged;
its final preparation adds documentation and the immutable SDK candidate pin.

- [x] `melos bootstrap --offline --enforce-lockfile`, both prepare hooks, 22
  resolved packages. Repeated `melos run prepare --no-select`: stable output.
- [x] App unit aggregator with four production GasFree defines: **3,919 passed /
  four skipped**.
- [x] All 16 SDK native package suites through Melos: **3,057 passed / 14 skipped**.
- [x] Nine core SDK Chrome/WASM files: **215 passed**; two framework WASM files:
  **10 passed**. Auth helper-boundary retest: **127 passed**.
- [x] Full analysis: **zero errors**, 55 warnings / 2,144 infos. The warnings
  match the existing baseline; no new changed-line diagnostic
  remains. Analysis exits nonzero because the repository includes that warning
  backlog, not because this candidate has analysis errors.
- [x] Consumer enforced offline lockfile, input hashes, changed Dart formatting
  and diff checks pass. No hosted dependency roll was introduced.
- [ ] Frozen-head hosted checks and reviewer signoff; record each failing or
  pending job separately on the current release PRs. Signed platform evidence
  remains a distribution gate below, distinct from source code freeze.

## Testing evidence and required dispositions

- [x] Seven human-submitted settlements recorded, including buffered native-Max
  retest on `ed609b9`. Preserve earlier failure evidence; private chain details
  remain local. No further funded operation is required solely for version,
  code-generation or workflow/docs preparation.
- [x] Final native Chrome 200% legal-warning review on `5202777`, 100% desktop,
  phone 360×800 and tablet 768×1024, with expiry/Refresh. Safari and signed
  platforms need separate results.
- [x] Atomic token-approval disclosure X04/Q12: [#3563](https://github.com/GLEECBTC/gleec-wallet/issues/3563).
  Unverifiable atomic EVM-token sells are explicitly unavailable in this RC,
  including Advanced orders and restored bot starts. Quote, review and RPC
  boundaries reject them before any new order or approval. Do not fund these
  disabled cases; native atomic and routed token contracts remain separate.
  Existing swap recovery/cancellation stays available.
- [x] Transfer review and input #3565: signed EVM principal/Max, fee and
  same-asset total are distinct; exact amounts remain accessible/selectable.
  Unsupported precision and mismatched signed EVM amounts cannot be submitted.
  Unit/widget cases cover the rejection and normal/Max review. No new funded
  transfer is claimed by these automated checks.
- [x] Wallet-history #3566: SDK #413 preserves signed net-only history on
  cache/refetch and uses the verified ETC Blockscout endpoint. App rows/details
  distinguish gross unknown direction, self-transfer principal/fees and
  unavailable fiat; normalized token symbols select current spot prices.
  Synthetic/native/browser regressions and the public-address CORS probe pass.
  Private chain evidence remains local; this is not an unbounded internal-call
  history or new funded-settlement certification.
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

## Freeze boundary and promotion order

The app freezes on `release-0.10.0`; SDK freezes on `release-0.9.0`.
Both branches come from dev after the focused squash merges above. The old
dev-headed app #3561 / SDK #410 are replaced by release-branch PRs, so future
dev commits cannot silently enter this RC. Keep both promotions open for
reviewer/tester feedback. The exact app commit and preview provenance belong
in the release PR and `rc-test-build.json`; this file cannot contain its own
commit hash.

Freeze means no planned runtime changes remain for #3563, #3565, #3566 or the
two SDK correlation/session findings or the later pagination review. The
99-page recovery and page-21 wallet-change regressions pass in native/WASM.
Restrict changes to verified blockers;
make each repair on a focused branch, squash it into dev, carry only that
reviewed fix into the release branch and repeat affected validation. Do not
advance release branches to unrelated dev work.

1. Complete SDK release gates, then merge [SDK #416](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/416)
   (`release-0.9.0` → `main`) using a **merge commit**. Record its actual
   immutable main SHA. Tags/publication follow the approved release process.
2. Open and **squash merge** an app dev PR pinning that SDK main SHA. Carry
   that reviewed bookkeeping commit into `release-0.10.0`, reconcile the
   manifest/checklists and repeat consumer checks as appropriate. Prove that
   the promoted SDK runtime matches the frozen candidate; investigate any diff.
3. Complete app release gates and review the final diff/checks. Merge the app
   release PR (`release-0.10.0` → `main`) using a **merge commit**. Reconcile
   release changes back into dev through a focused **squash** PR as needed.
   No automatic merge is enabled and no main admin bypass is assumed.
4. Before app tagging/publication, run the SDK tag/version/ancestry preflight in
   [BUILD_RELEASE.md](BUILD_RELEASE.md#github-release-preflight). Build/publish
   from the recorded main commits. Record output and generated coin hashes,
   configuration/defines and signing identity. Preserve at least the prior
   0.9.7-1 standard: detached signatures and signed SHA256SUMS. Verify
   installation/upgrade for every advertised artifact.
5. Final production build must have `BYPASS_LEGAL_DOCUMENT_GATE=false`, approved
   hosted legal text and clean-profile consent verification. The marker-free
   local LI.FI draft is not evidence that hosting or legal approval changed.
   Retire the manual RC exception/channel after testing. Web deployment and
   GitHub publication are separate operations; inspect legacy `release: created`
   native triggers.

Code freeze does not certify a public release. The outstanding operational,
legal, reviewer and signed-platform items above remain distribution gates.
The owner may invite reviewers and controlled testers using the frozen source
and freshly verified preview identity.
