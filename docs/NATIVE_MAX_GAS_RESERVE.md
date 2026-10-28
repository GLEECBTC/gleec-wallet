# Native Max gas reserve

The release enables `RoutedSwapMaxPolicy` in the wallet's routed quote source.
KDF `35f0bde` calculates Max using current gas requirements, then obtains a new
route and fee estimate at execution. A fee increase can make that reviewed Max
unfundable. The wallet now selects a smaller, separately priced amount while
KDF continues to validate, sign and execute the exact reviewed quote.

## Amount selection

For native coins only, obtain KDF's complete Max quote. Let `M` be its principal
and `G` its reported native `required_balance`, summed across native gas rows.
The budget `B = M + G` is a conservative lower bound on the spendable balance
KDF just checked. It does not use an aggregate wallet balance, add recognized
swap locks back, or assume that KDF found the absolute largest fundable amount.

Choose `A = floor(B - 2G - P)` in source-coin units, where `P` is any provider
fee charged on top in that coin. Ask KDF for a complete exact quote at `A`.
Return it only when `A + 2G_fresh + P_fresh <= B`. If fresh fees increased,
reduce the candidate and quote again. Never increase principal to chase falling
fees. There are at most three exact requests after KDF Max, sharing one overall
timeout with that Max request. A timed-out response cannot launch another call.

KDF's current native Max checks principal plus gas; adding provider fees to
the inferred budget would claim funds that this check did not establish.
Consequently additional provider fees can make this policy more conservative.
Fees already included in the exchanged amount are not reserved again.

Missing or inconsistent required gas data, no positive sellable amount,
changing account/recipient, or failure to establish headroom within the request
budget leaves Max unavailable. Provider failures retain their existing typed
errors and shared rate-limit backoff. The policy never falls back to an
unbuffered Max. Exact amounts, token Max and atomic swaps keep their existing
paths. KDF may still reject a later balance decrease or fee increase beyond the
reserve; no finite reserve guarantees future execution.

## Review and presentation

The final exact quote supplies the source amount, destination minimum, fees,
route and execution payload together. No amount or receive minimum is modified
after review. Existing review revalidation and new-acceptance rules still apply;
there is no automatic resubmission of a failed or uncertain swap.

`maxRetainedBalance` describes balance retained by this selection policy. The
existing Max message shows it as funds kept for fees. It is not an estimated
charge and does not replace KDF's `requiredGasBalance`, affect fee totals or
net-return ranking. Pricing/cache/form refresh preserve this metadata. KDF
execution and persisted route records keep their original schema.

## Release configuration and removal

The default is enabled in normal release builds. An operator can roll back with
`--dart-define=SWAP_NATIVE_MAX_GAS_RESERVE=false`; this restores direct KDF Max,
including its known fee-change limitation. It is not a user-facing preference.
The SDK behavior and KDF source revision are unchanged. The SDK pin also
refreshes artifact checksums after the owner rebuilt that same KDF source; see
[verified artifact provenance](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/blob/4fcaf002925093cdd7709cb41f8615547dd9ab30/docs/KDF_ARTIFACTS_2026-10-28.json).

Keep this policy until a pinned KDF version provides equivalent protection or
a reviewed replacement flow when execution funding changes. Validate changing
gas limits/prices, route changes, spendable balances/locks, small amounts,
token gas funding, provider minimums, and review/expiry behavior before removal.
Then remove the policy, its switch and source wiring; preserve the regression
scenarios against the new KDF contract. Do not infer support from a newer
version string or an unchanged-source rebuild alone.

## Validation

The wallet aggregator imports `swap_native_max_reserve_test.dart` and
`swap_routed_max_fees_test.dart`. They cover the release default, complete
repricing, rising/falling fees, request bounds, missing funding data, provider
errors/backoff, exact/token exclusions, cached and refreshed reserves, timeout
continuations, and review/start/expiry behavior. The explicit rollback tests
continue to exercise the unmodified KDF Max contract.

A human-submitted buffered native-Max retest on `ed609b9` settled successfully
on 28 October 2026 and reconciled independently against source and destination
chain evidence. It supplements the six earlier settlements. Private transaction
details remain in the local RC ledger. This result does not guarantee tolerance
for every later fee increase; synthetic funding checks remain separate evidence.

Validation on 28 October 2026 with Flutter 3.41.4:

- Wallet aggregator: **3,887 passed, four skipped** with production GasFree defines.
- Focused policy, funding and review suites: **42 passed natively and 42 in
  Chrome/WASM**. Flutter's Wasm test loader requires paths under `test/`; the
  browser run used a temporary `test/local_rc_validation -> ../test_units` link,
  removed after the run. The first attempt using `test_units/` directly failed
  during loader compilation before running tests.
- Flutter analysis: **zero errors**, 55 existing warnings and 2,146 existing
  infos; changed-file formatting and diff checks pass.
- Shipped native KDF: eight controlled cases on the prior archive and the same
  eight on the verified 28 October rebuild. The release reserve passes initial
  funding for unchanged fees, a 54.8% increase, and exactly double the initial
  requirement; one gas unit beyond double is rejected. All cases stop before
  signing/broadcast. These replay the policy amounts under fixed quote inputs;
  the production Dart policy and review flow are covered separately above.
- Rebuild provenance: all seven platform archives verified against GitHub
  Actions digests, ZIP integrity and published mirror checksums. All **30 SDK
  manifest/platform-selection tests passed**. KDF source remains `35f0bde`;
  the rebuilt native binary reports build time `2026-10-28T10:04:03.635418Z`.
