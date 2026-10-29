# RC idle-session policy fix — 28 October 2026

## Cause and evidence

The Chrome session returned from a swap review to a configured form showing
"We couldn't check swap options." The retained browser diagnostics did not
establish an HTTP 429; the HTTP cause must not be reported as confirmed.

Two deterministic policy-transition bugs explain the lost review and excess
quote traffic:

1. The one-minute policy poll emits loading, then either success or failure.
   The previous RC preserved a review during loading but discarded it when
   the lookup failed. An unavailable lookup was indistinguishable from a
   resolved restriction in the swap capabilities.
2. Every return to an enabled policy scheduled an ordinary evaluation and
   offer read. Those events counted as user interaction, refreshing the idle
   clock. They also bypassed the timer's foreground/idle checks and marked
   routed quotes as user requests, permitting rate-limit probes after pauses.

Regressions use the real swap BLoC, repository and routed source with a
counting provider on a fake clock. Before the fix, three hours of policy
polls produced 270 provider quotes on an idle form (expected 3), 180 while
backgrounded (expected 1), and 22 rate-limit probes (expected 1). The real
shell-listener regression also demonstrated that lookup failure discarded
the review. No funded operations are involved in these tests.

## Resulting behavior

- A pending or unavailable policy lookup preserves the accepted review and
  disables Start. A resolved trading restriction, hardware-wallet change or
  sign-out retains its existing stop behavior.
- An interrupted revalidation is invalidated; policy recovery cannot replay
  an earlier Start request.
- Policy readiness resumes the existing quote clock while the form is visible
  and in use. It does not renew user activity or retry a failed quote.
- A first quote blocked by initial policy loading can resume automatically.
  Such a request is marked automatic, preserving routed backoff.
- Idle, background and rate-limited scenarios keep their original budgets.
  The three-hour unavailable-policy review remains present and expires in
  place, without repricing or starting anything.

The trading-policy service, SDK activation-policy enforcement, legal consent
and execution checks remain in force. This fix changes presentation and
request scheduling, not permission to trade.

## Wallet and SDK PR audit

The owner selected the current RC and relevant fixes; older feature/draft
PRs are outside this integration.

| PR | Current source head / inclusion |
|---|---|
| Wallet [#3554](https://github.com/GLEECBTC/gleec-wallet/pull/3554) | `e93c11427c3be9454c5627302b7ecc730149f5b5`; already included. A virtual merge returns the RC's exact committed tree. |
| Wallet [#3555](https://github.com/GLEECBTC/gleec-wallet/pull/3555) | `622f3f36ad46016c935ba699895c2de1584c2426`; recovery/link/attention changes are already included. The only virtual-merge conflict is the newer terms-repository import; keeping it adds no source changes. |
| Wallet [#3556](https://github.com/GLEECBTC/gleec-wallet/pull/3556) | `ce9e889dd0c6724eaa5e1d05933bc5a6f399d06a`; start guards, quote-owned funding, fee consent and stale-response checks are already included and adapted to the newer legal and routed-Max code. Reapplying the old patch duplicates the post-terms trading guard and review part declaration. Its original disabled-policy review reset is the path corrected here. |
| SDK [#407](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/407) | The tested pin `b5c1d9db854358b84cfb4b22f0fd86d1ba8780d1` exactly matched its then-current head. |
| SDK [#405](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/405) | `d7093fd0816178528953ebb7ed368808e1027f65` was missing. Reviewed and merged into SDK #407 as `59dc947f281fefd8f0863e4c6e95cd30f28b741f`; the wallet now pins that revision. |
| SDK [#276](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/276) | The preview-then-execute behavior is already present in both withdrawal managers with newer checks. Reapplying the old patch duplicates the legacy `executeWithdrawal` implementation. |

SDK #405 corrects activation strategy selection and adding a token to an
active Trezor GLEEC platform. It does not fix the wallet's idle quote loop.
Its merge preserves KDF `35f0bde`, the frozen artifact inputs, complete routed
Max funding and the exact provider minimum. The conflicting old changelog
entry for the removed guard-margin API was not restored.

This is source integration into the RC branches. It does not merge these PRs
into the release branches or close their review/release gates.

## Validation

- SDK integration: 91 activation tests and 10 asset-filter tests passed.
- SDK activation analysis: zero errors/warnings, 113 infos.
- Wallet analysis: zero errors, 55 warnings and 2,146 infos.
- Wallet full unit suite: **3,863 passed, four skipped** with all four
  production GasFree defines. New tests are in files already imported by the
  aggregator.
- Formatting and diff checks passed.

The original reproduced regressions fail before the fix and pass after it.
Hosted CI and the new preview deployment must be verified independently.
