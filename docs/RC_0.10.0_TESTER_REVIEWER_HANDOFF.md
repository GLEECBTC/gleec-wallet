# Gleec Wallet 0.10.0 RC: tester and reviewer handoff

Prepared 28 October 2026. This candidate is available for code review and a
controlled testing round. Production promotion remains gated below. The release
owner sends invitations; this handoff does not request reviews or contact testers.

## Review entry points and identity

| Component | Review / pinned input |
| --- | --- |
| App 0.10.0+0 | [Release PR #3561](https://github.com/GLEECBTC/gleec-wallet/pull/3561), `main...dev` |
| SDK 0.9.0 | [Release PR #410](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/410), `main...dev` |
| Tested application runtime | `a2886621d155e824e0ab392bfd8166a2dc827f17` before this workflow/documentation handoff |
| SDK gitlink | `6038592a9f7853cd76a1a6fcb3a0fab8f3b89847` |
| KDF | `35f0bde438eec2cb0471b19642b9d9c4602fa17d` |
| RPC specs | `7c388ea7b91cb7c657435d416bc03e5349b46162` |
| Bundled coins | `2b0aefb78b184091ab086c66e513d8b03f5d5a01`; runtime updates enabled |

The [input manifest](RELEASE_0.10.0_INPUTS.json) records archive/config/lockfile
hashes. The final deployed preview's `rc-test-build.json` records its full app
and SDK commits, JavaScript hash, KDF configuration hash, build time, legal
override and Actions run. Record that identity with every report; compare it
with Settings and the release PR head. A version number alone is insufficient.
The preview URL and verified deployment run are maintained in app #3561.

The ordinary [#3561 preview](https://walletrc--pull-3561-merge-zdanlngw.web.app)
retains the legal gate. It is separate from the manual RC legal-testing preview.
Do not substitute an older #3557 preview for the current candidate.

## Temporary legal exception

The owner authorized testing while the LI.FI document is unpublished. Keep the
hosted placeholder marker. Only the explicit, manually dispatched RC test build
sets `BYPASS_LEGAL_DOCUMENT_GATE=true`. The notice remains visible and missing
or placeholder terms never become acceptance records. Trading policy, funding,
quote review and uncertain-start checks still apply. This exception does not
establish legal approval or production readiness.

The workflow accepts the exception only from `GLEECBTC/gleec-wallet` on `dev`,
with `rc_expected_app_commit` equal to its full 40-character run SHA. It deploys
to the isolated `rc-0-10-0-legal-testing` channel, expiring after seven days.
Ordinary PR/dev builds keep the gate; the workflow does not deploy to production.

To refresh it, resolve the reviewed `dev` SHA, then dispatch:

```bash
gh workflow run firebase-hosting-pull-request.yml \
  --repo GLEECBTC/gleec-wallet --ref dev \
  -f rc_legal_availability_bypass=true \
  -f rc_expected_app_commit=<full-reviewed-dev-sha>
```

Read the deployed URL from that run's summary. Check `rc-test-build.json`, hash
the served `main.dart.js` against its recorded SHA-256, and verify the legal
warning before sharing. A moved dev head must fail the requested-commit guard.
If the build expires, refresh explicitly and update the recorded identity.

Before production: upload counsel-approved LI.FI text, remove the marker only
from that final text, deploy with the bypass disabled, and test clean-profile
consent plus existing-wallet/recovery behavior. See [hosting handoff](legal-hosting/README.md).

## Tester round

Start with a clean disposable profile. Let the owner choose any funded wallet,
assets, amounts and spend limit. A person enters credentials and presses every
approval, Start, transfer or other control that commits funds. An agent may
prepare a review and independently verify the result. Follow
[How a round runs](SWAP_LIVE_TEST_BRIEF.md#how-a-round-runs).

1. Verify the build identity, warning, wallet/network/account and token contract.
   Check onboarding, unlock, receive/copy, activation and restart without funding.
2. Exercise quotes, comparison, expiry/Refresh, slippage, rate limits and missing
   gas. Check source-address spendable funds separately from HD totals. Do not
   generate load against the shared LI.FI proxy without agreeing capacity.
3. On review, compare principal, network, recipient, provider, minimum, fees and
   permission evidence. Resize/reload, background/restore and change wallet or
   pair while requests are pending. Stale facts must not start another swap.
4. Check desktop at 100% and 200%, phone 360×800 and tablet 768×1024. Legal
   warning, minimum, expiry and actions must remain reachable. Safari and signed
   device builds need their own results.
5. For an approved funded case, stop at review for the person to inspect and
   submit. Verify source principal plus gas, destination recipient/contract and
   received amount against independent chain evidence. Distinguish expected,
   guaranteed, provider-reported and independently measured values.
6. Reopen Activity and restart. Preserve approval and payment hashes separately.
   An unanswered Start must remain uncertain until reconciled; do not resubmit
   automatically. Exercise destructive/recovery faults only with fixtures.

### Known restrictions and preserved evidence

- **Atomic token approval X04/Q12 is blocked for funded testing.** The atomic
  adapter lacks permission evidence while review can claim no permission is
  required. [#3563](https://github.com/GLEECBTC/gleec-wallet/issues/3563) tracks
  the engine contract, truthful disclosure and regression coverage needed.
- Native routed Max now selects a smaller, completely repriced amount with
  twice the reported gas requirement retained. It makes at most three exact
  quote requests after KDF Max and never falls back to unbuffered Max. Token
  Max and atomic swaps follow their separate paths. Review the
  [actual policy and limits](NATIVE_MAX_GAS_RESERVE.md).
- Seven human-submitted settlements are already recorded, including the buffered
  native-Max retest on `ed609b9`. The later `5202777` layout fix passed native
  Chrome review checks at 200%, 100%, phone and tablet, including expiry/Refresh.
  This handoff changes workflow/docs only; it does not require another funded
  operation merely to repeat the version/code-generation preparation.
- Optional X06/X07 have no observed order-book offers. DOC/MARTY real refund
  testing is blocked by stalled configured testnet tips. Report these as blocked,
  not failed executions or passing cases. Fixture refund coverage is separate.
- Existing transfer/history completeness, direction and review-labelling
  findings still need disposition against the private live ledger. Do not infer
  that a settled swap proves all transfer/history surfaces correct.
- Five-person usability and live fiat testing were explicitly deferred by the
  owner. Banxa follow-up [#3559](https://github.com/GLEECBTC/gleec-wallet/issues/3559)
  is after 0.10.0; it is not a newly imposed RC prerequisite.

## Evidence available to reviewers

Flutter 3.41.4 / Dart 3.11.1; workspace Melos 7.8.1. Fresh preparation ran
`melos bootstrap --offline --enforce-lockfile`, including both prepare hooks,
and repeated `melos run prepare --no-select` with stable output. All 22 workspace
packages resolved; regenerated platform barrels/parts were corrected in SDK #411.

| Validation | Result |
| --- | --- |
| App unit aggregator, all four production GasFree defines | 3,898 passed / four skipped |
| All 16 SDK native package suites through Melos | 3,045 passed / 14 skipped |
| SDK Chrome/WASM / framework WASM | 176 / 10 passed |
| Auth helper-boundary retest | 127 passed |
| Full analysis | Zero errors; 55 warnings / 2,146 infos, no new changed-line diagnostic |
| Consumer enforced offline lockfile, changed Dart formatting, diff checks | Passed |
| RC preview guard: ordinary/default paths and invalid override rejection | 11 passed |
| Existing legal repository, swap and onboarding suites, compiled bypass enabled | 53 passed; warning retained and missing-term acceptance absent |

Hosted CI is recorded on the PR heads. At handoff preparation, web, Linux,
Windows, Android, Docker and dependency scan checks passed; iOS stopped before
compilation at `xcodebuild -downloadPlatform iOS` with "Unable to connect to
simulator" (exit 70), and that job was retried. Other queued/running jobs are
not passes. Successful compilation does not establish signing, installation or
upgrade behavior. Read the current checks before approving a release.

For systematic review, use the [full-diff review prompt](SDK_APP_FULL_DIFF_REVIEW_PROMPT.md).
Prioritize amounts/precision/fees, spender and approval scope, quote revalidation,
uncertain starts, wallet isolation, persisted recovery, public SDK compatibility,
native/WASM boundaries and frozen artifact integrity. Record files actually
reviewed and open findings; do not turn this checklist into an approval claim.

## Before main promotion

1. Resolve #3563 and transfer/history findings, legal production availability,
   final-head review/checks and platform install/upgrade evidence. Record explicit
   dispositions for blocked cases and outstanding KDF/spec/proxy concerns in the
   [release checklist](RELEASE_0.10.0_CHECKLIST.md).
2. Promote SDK #410 from `dev` to `main` with a merge commit after its gates pass.
   Record the actual main SHA; then squash an app dev PR pinning that SHA and
   refresh the manifest/consumer checks. SDK dev is still a provisional RC pin.
3. Promote app #3561 from `dev` to `main` with a merge commit after app gates pass.
   All preparatory PRs into either dev use squash. No automatic merge is enabled.
4. Build/tag/publish under the release process. Retain hashes, detached signatures
   and signed SHA256SUMS at least to the 0.9.7-1 standard. Test final production
   builds with the legal bypass disabled. This testing exception is not a release
   waiver and must be retired after the RC testing period.

## Report a finding

Include the preview/run, full app/SDK commits, platform/browser, profile type,
network and token contract, reproducible steps, expected/actual behavior, impact,
and whether any approval/payment was submitted. Name an exact failing test or
blocked dependency. Put public-safe screenshots and minimal diagnostics in the
issue; keep seeds, keys, wallet databases, private balances and transaction
receipts out of public reports. Preserve the private evidence in its existing
local ledger rather than copying it into release documentation.
