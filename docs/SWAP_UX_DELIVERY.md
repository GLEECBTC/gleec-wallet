# Swap experience delivery

This is the original delivery record. The [combined integration record](https://github.com/GLEECBTC/gleec-wallet/pull/3617)
documents which older submission/session paths were superseded by newer auth
contracts and carries the current testing/release boundaries. Historical counts
and engine-pin observations below are not final integration results.

Date: 2026-11-08
Authority: user-approved “Gleec swap: effortless, reassuring, and subtly polished” plan
Owner: wallet UI/state implementation team

## Boundary

This is an app-only change using the existing SDK and execution contracts. It
does not change KDF, rebuild engine artifacts, repin an engine, alter commission
policy, or add liquidity providers/chains. The reported fee-collector incident
is an engine error, not evidence that the pair lacks liquidity.

## Reference and design gate

The [interactive storyboard](design/swap_experience/index.html) is a local,
self-contained interaction reference. Open it directly in a browser. Choose a
scenario outside the app frame, or follow the controls inside it. It makes no
network requests, opens no wallet, and cannot send funds. Amounts, addresses,
timing, and outcomes are illustrative fixtures.

The approved user plan and the current `SwapPalette`, `SwapText`, and motion
components are the implementation references. The generic design-system search
does not override Gleec's actual app tokens.

**UI-Pro Basis:**

```sh
python3 .agents/skills/ui-ux-pro-max/scripts/search.py "Gleec Wallet crypto wallet fintech mobile" --design-system -p "Gleec Wallet"
python3 .agents/skills/ui-ux-pro-max/scripts/search.py "flutter financial app navigation accessibility" --stack flutter -n 5
python3 .agents/skills/ui-ux-pro-max/scripts/search.py "financial data display forms error recovery" --domain ux -n 8
python3 .agents/skills/ui-ux-pro-max/scripts/search.py "animation accessibility loading motion error recovery" --domain ux -n 6
```

**Gate Status: exception.** `docs/design/DESIGN.md` and
`docs/design/GLEEC_PURPLE_VAULT_DESIGN_LANGUAGE.md` are absent from this checkout.
Owner: UI implementation lead. The user approved using current Gleec components
as the source. The consequence is that the storyboard is an interaction/layout
reference rather than a claim of fidelity to an unavailable export.

**Screenshot follow-up completed:** the implementation owner reviewed the
[Flutter fixture captures](design/swap_experience/qa/flutter/README.md) at phone
and desktop widths, including keyboard and large text. Automated semantics and
reduced-motion checks passed. This closes the implementation screenshot review
against current tokens; physical screen-reader/device usability remains a
release check. The HTML reference is not a substitute for device validation.

## Screen-state contract

Every state is one user moment and has at most one overlay. The scenario
selector is outside the simulated product; no test controls belong in the app.

| ID | Surface/state | Layout and behavior | Implementation boundary |
|---|---|---|---|
| SW-01 | Form, quote ready | Full-width asset/network headers, USD amount, balance/Max, stable receive area, concise cost/time, Review. | Entry widgets and unified swap state. |
| SW-02 | Asset picker | Pay starts with holdings; receive starts with recent/popular supported assets. Search/network selection is immediate. Choosing an asset returns at once. | Picker emits intent; BLoC owns preparation. |
| SW-03 | Form, preparation/initial quote | Selection/input remains visible and editable. Preparation is local to the form. Missing receipt/prices are placeholders, never zero. | Explicit preparation/funding readiness. |
| SW-04 | Form, slow quote | Stable geometry. At three seconds, explain that options are still being checked. A healthy source can become usable independently. | Incremental quote stream and bounded source timers. |
| SW-05 | Form, failed quote | Preserve pair, amount, and mode. Explain temporary quote failure with Retry. No speculative liquidity, gas, or location diagnosis. | Typed failure presentation. |
| SW-06 | Compact review | Paid amount, expected/minimum receipt, networks, own recipient, estimated costs, provider, permission summary, Confirm. Details expand on demand. | Frozen review plus fresh pre-send validation. |
| SW-07 | Review, changed terms | Display previous/new terms and request explicit acceptance. Never start merely because the new result arrived. | Existing material-change safeguards. |
| SW-08 | Progress, preparation | Specific checking/starting headline. Do not claim receiving or funds sent. A registered execution remains discoverable. | Existing execution registry. |
| SW-09 | Progress, receiving | Show evidence-backed source-send/receiving state, realistic estimate or unknown timing, keep-open requirement where applicable. Back to wallet remains reachable. | Shared execution presentation. |
| SW-10 | Wallet, ongoing | One compact row for the ongoing swap, or a count for multiple swaps. Open the existing tracking surface. | Existing registry, no new poller. |
| SW-11 | Confirmed receipt | What arrived and network, View asset, receipt detail, one brief completion moment. Pending balance refresh is labelled. | Outcome evidence and actual balance refresh. |
| SW-12 | Recovery | Distinguish nothing sent, approval-only cost, unknown start, sent/unknown outcome, partial receipt, and refund. Never automatically resubmit an uncertain start. | Existing spend evidence/recovery contracts. |

### Information and state rules

- Preserve in-session drafts; persist only the preferred amount mode per wallet.
- USD is the initial preference when conversion is available. Switching modes
  never reinterprets the digits as a different asset amount.
- A chosen quote stays chosen. Another provider's arrival does not silently
  switch execution type. “Best” requires complete comparable economics.
- Review readiness requires known funding/address preparation. Fiat ranking
  completeness is separate from token-denominated affordability.
- Max first resolves the controlling amount, then compares other sources at
  that exact amount. Review and execution keep the accepted concrete snapshot.
- Policy checking, lookup failure, and confirmed restriction have distinct
  copy/actions. Only a confirmed restriction gets location wording.
- Keep minimum, fees, approval, slippage, reacceptance, and duplicate-start
  protections. Detailed disclosure may scroll when required by large text or
  exceptional warnings.
- In-app navigation is distinct from closing/suspending the app. Atomic swaps
  keep the existing device-running requirement; routed receiving requires
  appropriate source-send evidence.

## Motion contract

| Trigger | Specification |
|---|---|
| Press/release | 0.97 scale, 100 ms press / 220 ms release; invoke action immediately. |
| Picker | 220 ms slide/fade; return immediately after selection. |
| Asset/quote update | 160 ms local surface/color settle; exact money text appears immediately. |
| Reverse pair | 180 ms direction-icon rotation; invalidate the old quote immediately. |
| Form/review/progress transition | One 240 ms directional reveal; no duplicate live controls. |
| Details expansion | 200 ms height/chevron transition following user action. |
| Confirmed receipt | Icon 0.92 → 1 in 320 ms; one thin ring ends within 600 ms. |
| Error/delay | Calm 160–200 ms replacement, no bounce or shake. |

One main animated focus per transition. No animated financial counters, fake
progress percentages, mandatory delay, confetti, sounds, or repeating token
orbits. Initial shimmer is bounded; extended waiting is a stable status with
one meaningful busy indicator. Effects pause offscreen/backgrounded and do not
replay for polling, remounts, or historical outcomes. Reduced motion shows final
states immediately. Haptics are native-only and limited to explicit selection,
eligible confirmation, newly observed success, and immediate attention.

## Validation record

The status below is intentionally explicit. A storyboard does not prove app
implementation, device performance, funded settlement, or user-study results.

| Gate | Evidence/result | Status |
|---|---|---|
| Interactive reference | [Browser QA](design/swap_experience/qa/README.md): 20/20 interaction checks, both themes, phone/wide inspection, clean console, and OS/explicit reduced motion. | Passed for the HTML reference only. |
| Incremental quote and readiness tests | `swap_quote_stream_test`, `swap_bloc_stream_test`, `swap_bloc_preparation_test`, `swap_preferences_mode_test`. | Focused regressions passed. |
| Review and recovery regressions | Fresh funding after changed-term acceptance; stale input/Max/session responses; minimum and uncertain-start protections. | Focused regressions passed. |
| Motion/lifecycle tests | Reduced motion, background, remount/replay, repeated polling, button bounds and input-element retention. | Focused motion/review/handoff regressions passed. |
| Phone screenshots | [Actual Flutter fixture captures](design/swap_experience/qa/flutter/README.md): ready, slow, failure, review, receiving, receipt, keyboard, 200% text. | Captured and reviewed. |
| Desktop screenshots | [Desktop changed terms](design/swap_experience/qa/flutter/desktop-light-changed.png), with labeled prior estimate and readable legal links. | Captured and reviewed. |
| Real-device profiling | Tap ≤100 ms; no animation delays; smooth 60 fps target. | Pending device run. |
| Quote timing | Healthy supported warm USDC→ETH target: median ≤2 s / p95 ≤5 s. Separate cold preparation and settlement. | Pending measured run. |
| Funded preview round | Human presses every money-moving control per `SWAP_LIVE_TEST_BRIEF.md`. | Human-operated release check. |
| Moderated study | At least 4/5 users unassisted per core task, zero money-fact misunderstandings, ≥4/5 clarity/responsiveness from 4/5 participants. | Human usability check. |

Required automated commands and GasFree defines remain in `docs/TESTING.md`.
New test files must be imported from `test_units/main.dart`. Keep failures named
and separate from suites that pass.


## Implementation and validation boundaries

The app retains unsigned drafts in memory for the current wallet session; it
persists only preferences and the existing last-used pair. Explicit entry/deep
links take precedence, and signing out or changing wallets clears draft amounts.
A started or uncertain execution is tracked rather than restored as a submit-ready
amount. Consumed deep-link signatures remain deduplicated across wallet sessions.

The wallet row, Activity, full progress screen, notices, and receipt read the
existing execution registry. Presentation remembers acknowledgements/effect IDs
and actual balance-refresh status only. It adds no execution store or polling
loop. Receipt refresh reads SDK balances with `forceRefresh: true`; receipt
amounts never manufacture a wallet balance.

New suites are imported and invoked in `test_units/main.dart`. Tests use the
pinned Flutter 3.41.4 with the four documented GasFree production defines. Local
runs reuse `build/unit_test_assets` with `--no-pub --no-test-assets`, avoiding
asset transformers. SDK code, KDF build configuration and both dependency locks
are unchanged by this work; the pre-existing SDK/config edits were preserved.

The existing GUI wrapper always builds through `flutter drive`, and exposes no
existing-build option. It can invoke the KDF asset transformer, so it was not run
under the no-KDF-change boundary. The native Flutter widget integration tests
exercise the new navigation, keyboard, lifecycle and execution surfaces using
fixtures. SDK package suites are not affected because this delivery changes no
SDK code. Physical-device, live-engine and human usability gates above remain
open; fixture timings are not production latency measurements.


## Local check commands

```sh
flutter test --no-pub --no-test-assets test_units/main.dart \
  --dart-define=TRON_GASLESS_ENABLED=true \
  --dart-define=TRON_GASLESS_RECEIVE_ENABLED=true \
  --dart-define=TRON_GASLESS_BASE_URL=https://quicknode.gleec.com/gasfree/tron \
  --dart-define=TRON_GASLESS_SERVICE_PROVIDER=TLntW9Z59LYY5KEi9cmwk3PKjQga828ird

# Optional fixture captures, in addition to assertions:
SWAP_CAPTURE_DIR=/tmp/gleec-swap-flutter-captures \
  flutter test --no-pub --no-test-assets \
  test_units/tests/swap/swap_ux_capture_test.dart
```

These commands require the existing cached test assets. A clean CI environment
uses the normal commands in `docs/TESTING.md` and its configured asset setup.


Focused validation runs passed before the final aggregator run: 405
state/accessibility checks; 156 motion/review/handoff checks; 162 unique entry
checks across two runs; 146 remaining progress/service checks; 48 final
wallet/session/scope checks; and 59 final visual-polish checks. These overlap
and must not be added as a unique total. The HTML reference passed 20/20
browser interaction checks. Changed-file Dart analysis reported no issues.

Global `flutter analyze --no-pub` also ran. The checkout has existing errors in
archived `docs/local-rc-2026-10-28` Dart excerpts and existing SDK diagnostics;
those unrelated files were left intact. The changed-file analysis is the clean
result for this delivery.


## Final local result

- App aggregator with GasFree enabled: **3,946 passed, 4 skipped, 1 failed**
  (5m04s). Late wallet/session/scope additions separately passed **48/48**.
- The sole aggregate failure is the existing test
  `swap_src_atomic_refund_test.dart`, “its default gas limits are those of the
  KDF this build pins” (line 168). It expects a pin beginning `35f0bde4`, while
  the already-edited checkout pins `f9632e0ec771668a6f21b37aede01a30110141cb`.
  This test and that configuration were not changed by this delivery. The
  compatibility guard was preserved; no new engine-fee assumption was made to
  make the test green. That existing compatibility check remains a release gate.
- All **116 changed Dart files** pass formatting verification and scoped Dart
  analysis with **no issues**; `git diff --check` passes.
- Pre-existing root edits and the complete SDK diff were compared to their
  starting snapshots and are unchanged. KDF build-config JSON and both lockfile
  hashes are unchanged.
- No funded controls were operated. Device profiling, live-engine quote
  percentiles, the funded preview round, GUI build/drive validation, and the
  moderated five-user study remain open as documented above.
