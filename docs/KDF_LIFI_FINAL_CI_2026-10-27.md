# Final CI verification — 27 October 2026

This follow-up checks wallet #3557 at
`1c7f74722f49c45193339ab229b92db8d3ae0c93` and SDK #407 at
`b5c1d9db854358b84cfb4b22f0fd86d1ba8780d1`. Wallet runtime code remains
`1643c3323f5ebeb9168b244d969a5e6d6df971a1`; the newer wallet commit only adds
release records. The SDK pin, seven KDF archive hashes, bundled coin pin,
lockfiles and runtime-update policy remain frozen as recorded in the
[candidate manifest](KDF_LIFI_CANDIDATE_MANIFEST_2026-10-27.json).

No communication, review request, upstream merge, production configuration
change, deployment or mainnet funded execution was performed for this follow-up.
Normal PR checks and their preview deployment were already running from the prior
publication. This follow-up initially remained local while the communication
restriction was interpreted to include automated preview comments. The user later
clarified that branch publication and PR updates are authorized; the restriction
applies to contacting colleagues. The outcomes below remain tied to the checked
heads; subsequent test revisions need their own hosted CI results.

**Final result:** SDK #407 is green. Wallet #3557 has seven successful workflows
and one failed workflow: Chrome and Safari on-ramp UI tests. The wallet/SDK
integration, unit/coverage, harness, preview and all five platform builds passed.
No LI.FI integration source regression was identified in these results. The
remaining failure is a current Ramp/proxy quote authorization error, requiring
its service owner; it was not bypassed with a client or test change.

**Subsequent user disposition, 27 October:** Ramp is known unavailable and is
deferred to the next update. This accepts the named limitation for the current
candidate without changing any recorded CI outcome. A subsequent
[Banxa check](KDF_LIFI_DECKER_HANDOVER_2026-10-27.md#banxa-verification-and-ramp-disposition) verified production payment
methods and six valid quotes; it does not verify checkout or completed purchases.

The later [independent on-ramp test follow-up](KDF_LIFI_ONRAMP_TEST_VALIDATION_2026-10-27.md)
changes the test gate: Banxa runs independently, Ramp is explicitly deferred.
Chrome passed locally; Safari requires Remote Automation. No updated hosted CI
was triggered, so the workflow statuses below remain the results of the earlier
published head.

All workflows below are completed. The generated CI record is local evidence at
`.lifi/evidence/KDF_LIFI_FINAL_CI_2026-10-27.json` (excluded from Git). It contains
final statuses, artifact IDs/digests, exact assertion evidence and verified commit
identities. The workflow links and outcomes below remain the versioned summary.
No runtime code was changed or test rerun solely to turn a failed external service
check green.

## Completed SDK and non-UI wallet checks

| Check at the verified head | Final result |
|---|---|
| [SDK consolidated tests](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/actions/runs/40464029709) | Passed: all 16 discovered package suites; dedicated browser wallet-isolation/GasFree tests (176) and KDF web transport tests (10) also passed. Flutter 3.41.4. |
| [SDK playground preview](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/actions/runs/40464029776) | Passed. |
| [Wallet unit and coverage](https://github.com/GLEECBTC/gleec-wallet/actions/runs/40465519684) | Passed: 3,800 tests, 4 skipped; logs confirm coverage test and HTML report generation succeeded. |
| [HD/iguana replay and performance](https://github.com/GLEECBTC/gleec-wallet/actions/runs/40465519737) | Passed. |
| [Windows, Linux and macOS builds](https://github.com/GLEECBTC/gleec-wallet/actions/runs/40465519726) | All passed. |
| [Android and iOS builds](https://github.com/GLEECBTC/gleec-wallet/actions/runs/40465519766) | Both passed. |
| [Wallet preview](https://github.com/GLEECBTC/gleec-wallet/actions/runs/40465519756) | Passed; deployed coin digests independently verified below. |
| [Dependency scan](https://github.com/GLEECBTC/gleec-wallet/actions/runs/40465520322) | Passed; not a claim of a full security audit. |
| [Code guidelines](https://github.com/GLEECBTC/gleec-wallet/actions/runs/40465519757) | Passed. |

The browser DEX scenario uses the repository's public testnet atomic-swap fixtures;
a pass does not establish funded LI.FI execution.

Build successes are compilation/package evidence. They do not prove signed
production distribution, notarization, installation/upgrade or funded execution.
The older handover's pending statuses are superseded by this table.

## Final-head browser UI failure

[UI run 40465519648](https://github.com/GLEECBTC/gleec-wallet/actions/runs/40465519648)
finished failed on both browsers at the verified wallet head.

| Suite | Chrome | Safari |
|---|---|---|
| `wallets_tests` | Passed | Passed |
| `wallets_manager_tests` | Passed | Passed |
| `dex_tests` | Passed | Passed |
| `misc_tests` | Passed | Passed |
| `fiat_onramp_tests` | Failed | Failed |

Both driver artifacts identify `Run Fiat On-Ramp tests:`: expected one widget
keyed `fiat-payment-method-ramp-0`, found zero. Chrome artifact `12717219496` and
Safari artifact `12716919823` have their SHA-256 digests and expiry dates in the
machine-readable CI record. The assertion is unchanged from the earlier runtime
head; its independent current service diagnosis follows below.

A passing retry requires the production quote authorization to work. Repair the
Ramp/proxy credential or authorization first, then rerun **both** jobs from this
same workflow run. A blind retry against the same rejected credential is not a
fix. No retry or credential change was applied. The user subsequently accepted
Ramp unavailability for this candidate and deferred repair to the next update.

## Frozen preview verification

All three coin configuration files served by the current PR preview match the
manifest's SHA-256 values. The local report
`.lifi/evidence/KDF_LIFI_PREVIEW_INPUT_CHECK_2026-10-27.json` records the URLs,
digests and check time; it is excluded from Git. This verifies the deployed
bundle's inputs, not a funded route or the mutable runtime coin feed.

## Independent provider diagnosis

The existing `Run Fiat On-Ramp tests:` assertion expects
`fiat-payment-method-ramp-0`. A read-only probe against the same non-test proxy
endpoints used by the profile/release UI suite established:

- Ramp currency and asset lists return HTTP 200, allowing the form to populate.
- The Ramp USD 50 / BTC quote also has outer HTTP 200, but its JSON body reports
  `AUTH.ACCESS.INVALID_HOST_API_KEY` with `statusCode: 403`. No usable quote or
  payment methods can be constructed from that response.
- Banxa payment-method lookup returned HTTP 200; this initial probe does not establish
  its checkout or quote health and does not claim both providers have the same
  failure.

The later [Banxa verification](KDF_LIFI_DECKER_HANDOVER_2026-10-27.md#banxa-verification-and-ramp-disposition)
supersedes the initial quote-health uncertainty with six successful quotes.
The browser test asserts Ramp first, so its failure never establishes whether
Banxa renders or completes checkout in that run.

The local probe report,
`.lifi/evidence/KDF_LIFI_ONRAMP_DIAGNOSTIC_2026-10-27.json`, records the exact
public requests and sanitized response summaries; it is excluded from Git. No
order or payment was created; no wallet address or private credential was supplied.
The wallet's
on-ramp client, integration test and UI workflow are unchanged by #3554–#3557.

This establishes a current Ramp/proxy credential rejection, independently of
whether any CI attempt reaches that assertion. It does not establish why the
credential was rejected or prove every historic absent-widget failure had the
same cause. The proxy/provider owner must repair the server-held credential or
its authorization and then rerun the affected UI jobs. Changing client fixtures,
skipping the provider check, or substituting a demo key would not repair this
production integration. No such workaround was applied.

## Earlier implementation-head UI run

[Run 40464113981](https://github.com/GLEECBTC/gleec-wallet/actions/runs/40464113981)
on `1643c3323` completed with the on-ramp suite failing in both Chrome and Safari.
Both browsers passed `wallets_tests`, `wallets_manager_tests`, `dex_tests` and
`misc_tests`. The Safari driver artifact (`12716084678`) explicitly shows zero
widgets keyed `fiat-payment-method-ramp-0` in `Run Fiat On-Ramp tests:`.
These results support the integrated runtime behavior but do not substitute for
the separate final-head CI results above.

## Review and freeze gates

At this check, #3557 and #407 still have no submitted reviews. KDF #29 has two
unresolved review threads: token routes requiring nonzero native bridge fees,
and status-error polling without backoff. Specs #2 still has the older
changes-requested review; current envelope fixes do not remove the need for
review closure. The three named upstream KDF unit failures remain separate from
wallet/SDK CI and artifact recovery.

The [Decker handover](KDF_LIFI_DECKER_HANDOVER_2026-10-27.md) is the consolidated
owner/gate checklist. Formal freeze still needs current-head review decisions,
any failed integration gate repaired or explicitly dispositioned, human-funded
and usability evidence, KDF/proxy/spec decisions, and an agreed release identity.
Signing, distribution and device installation/upgrade evidence are additional
release gates. The Linux engine archive gap remains closed.
