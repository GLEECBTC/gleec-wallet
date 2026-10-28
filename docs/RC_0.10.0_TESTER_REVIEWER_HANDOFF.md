# Gleec Wallet 0.10.0 RC: tester and reviewer handoff

Prepared 28 October 2026. This candidate is available for code review and a
controlled testing round. Production promotion remains gated below. The release
owner sends invitations; this handoff does not request reviews or contact testers.

## Review entry points and identity

| Component | Review / pinned input |
| --- | --- |
| App 0.10.0+0 | [Frozen candidate](https://github.com/GLEECBTC/gleec-wallet/compare/main...release-0.10.0), `main...release-0.10.0` |
| SDK 0.9.0 | [Release PR #416](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/416), `main...release-0.9.0` |
| Tested application runtime | `f94e507214ad0330d508bfe8d68624ad067ff526`; final SDK bookkeeping changes docs only |
| SDK gitlink | `22e14ac94fb555776eda370de08f1dafd5ca4019` |
| KDF | `35f0bde438eec2cb0471b19642b9d9c4602fa17d` |
| RPC specs | `7c388ea7b91cb7c657435d416bc03e5349b46162` |
| Bundled coins | `2b0aefb78b184091ab086c66e513d8b03f5d5a01`; runtime updates enabled |

The [input manifest](RELEASE_0.10.0_INPUTS.json) records archive/config/lockfile
hashes. The final deployed preview's `rc-test-build.json` records its full app
and SDK commits, JavaScript hash, KDF configuration hash, build time, legal
override and Actions run. Record that identity with every report; compare it
with Settings and the release PR head. A version number alone is insufficient.
The preview URL and verified deployment run are maintained in the current app
release-branch PR. The old dev-headed app #3561 and SDK #410 are replaced,
not merged; their historical discussions remain linked from the current PRs.

The ordinary current release-PR preview retains the legal gate. It is separate
from the manual RC legal-testing preview. Old #3557/#3561 previews are not the
frozen candidate; use the identity recorded on the current release PR.

## Temporary legal exception

The owner authorized testing while the LI.FI document is unpublished. The local
LI.FI draft is now marker-free and all five legal text files are ignored, local-only
handoff copies. Removing that local marker does not upload or approve the text.
Only the explicit, manually dispatched RC test build
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

Before production: upload counsel-approved LI.FI text, deploy with the bypass
disabled, and test clean-profile
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

- **New atomic EVM-token sells are unavailable in this RC.** [#3569](https://github.com/GLEECBTC/gleec-wallet/pull/3569)
  rejects unverifiable spender/approval scope at quote, review and RPC boundaries,
  including Advanced orders and restored bots. The UI explains that restriction
  and cannot claim no approval is needed. Do not fund disabled cases. Native
  atomic and routed token permission contracts remain separate; existing
  recovery and cancellation stay available.
- Native routed Max now selects a smaller, completely repriced amount with
  twice the reported gas requirement retained. It makes at most three exact
  quote requests after KDF Max and never falls back to unbuffered Max. Token
  Max and atomic swaps follow their separate paths. Review the
  [actual policy and limits](NATIVE_MAX_GAS_RESERVE.md).
- Seven human-submitted settlements are already recorded, including the buffered
  native-Max retest on `ed609b9`. The later `5202777` layout fix passed native
  Chrome review checks at 200%, 100%, phone and tablet, including expiry/Refresh.
  Later freeze repairs have synthetic/native/browser regression coverage.
  They are not new funded-settlement evidence; further live checks remain
  human-operated and should target the current frozen preview.
- Optional X06/X07 have no observed order-book offers. DOC/MARTY real refund
  testing is blocked by stalled configured testnet tips. Report these as blocked,
  not failed executions or passing cases. Fixture refund coverage is separate.
- Transfer review/input [#3570](https://github.com/GLEECBTC/gleec-wallet/pull/3570)
  and native precision [#3571](https://github.com/GLEECBTC/gleec-wallet/pull/3571)
  separate recipient principal, network fee and same-asset total; preserve exact
  selectable/accessible amounts; and reject unsupported precision or mismatched
  signed EVM principal before submission.
- History [#3572](https://github.com/GLEECBTC/gleec-wallet/pull/3572) with SDK #413
  preserves signed outgoing movements across cache/refetch, restores ETC through
  its verified explorer, and distinguishes unknown gross direction, self-transfer
  principal/fee and missing fiat. The explorer has a bounded 1,000-row per-address
  history window; this does not establish unlimited internal-call completeness.
- SDK #412 binds routed handles/polling/results to the authenticated session.
  A start without its durable UUID stays unconfirmed; matching history amounts
  cannot claim an existing swap. Native/browser regressions cover wallet changes
  and late results. Private live evidence remains in its local ledger.
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
| App unit aggregator, all four production GasFree defines | 3,919 passed / four skipped |
| All 16 SDK native package suites through Melos | 3,056 passed / 14 skipped |
| SDK Chrome/WASM / framework WASM | 213 / 10 passed |
| Auth helper-boundary retest | 127 passed |
| Full analysis | Zero errors; 55 warnings / 2,144 infos, no new changed-line diagnostic |
| Consumer enforced offline lockfile, changed Dart formatting, diff checks | Passed |
| RC preview guard: ordinary/default paths and invalid override rejection | 11 passed |
| Existing legal repository, swap and onboarding suites, compiled bypass enabled | 53 passed; warning retained and missing-term acceptance absent |

The full app aggregator passed in 4m46s on the combined runtime. Analysis has
zero errors and the same 55 existing warnings; its nonzero exit reflects that
backlog. Final enforced offline Melos bootstrap produced no tracked drift.
The final SDK freeze commit changes only Markdown relative to `52f1181f`;
its package CI and SDK/playground previews passed. The current frozen-head
checks remain authoritative: pending/running jobs are not passes. Record a
specific failure and distinguish setup/network failures from code defects.
Compilation does not establish signing, installation or upgrade behavior.

For systematic review, use the [full-diff review prompt](SDK_APP_FULL_DIFF_REVIEW_PROMPT.md).
Prioritize amounts/precision/fees, spender and approval scope, quote revalidation,
uncertain starts, wallet isolation, persisted recovery, public SDK compatibility,
native/WASM boundaries and frozen artifact integrity. Record files actually
reviewed and open findings; do not turn this checklist into an approval claim.

## Freeze and main promotion

The RC source is frozen on `release-0.10.0` and `release-0.9.0`, both created
from dev after the focused squash merges. Later dev work cannot enter these
candidates automatically. Keep the release PRs open for tester/reviewer feedback.
Only verified blockers should change a frozen branch; squash the focused fix
into dev, carry only that reviewed fix to release, and repeat affected checks.

1. Complete current-head reviews/checks and distribution gates in the
   [release checklist](RELEASE_0.10.0_CHECKLIST.md): approved production legal
   text, blocked-case dispositions, upstream operational signoff and signed
   platform install/upgrade evidence remain separate from source freeze.
2. Promote SDK #416 from `release-0.9.0` to `main` with a **merge commit** after
   its gates pass. Record the actual main SHA; squash an app dev PR pinning it,
   carry that bookkeeping fix into the app release branch, and refresh the
   manifest/consumer checks. Confirm the SDK runtime matches the frozen one.
3. Promote the app `release-0.10.0` PR to `main` with a **merge commit** after
   app gates pass. Every PR into dev uses squash, including focused release
   reconciliation. No automatic merge or main admin bypass is assumed.
4. Run the SDK tag preflight in [BUILD_RELEASE.md](BUILD_RELEASE.md#github-release-preflight)
   before app tagging/publication. Retain hashes, detached signatures and signed
   SHA256SUMS at least to the 0.9.7-1 standard. Test final production builds with
   the legal bypass disabled, then retire the isolated RC exception/channel.

## Report a finding

Include the preview/run, full app/SDK commits, platform/browser, profile type,
network and token contract, reproducible steps, expected/actual behavior, impact,
and whether any approval/payment was submitted. Name an exact failing test or
blocked dependency. Put public-safe screenshots and minimal diagnostics in the
issue; keep seeds, keys, wallet databases, private balances and transaction
receipts out of public reports. Preserve the private evidence in its existing
local ledger rather than copying it into release documentation.
