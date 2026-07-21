# Gleec Unified Swap — Competitor-Grade Remediation QA

Date: 2026-07-19
Artifact: `gleec-unified-swap.html`
Artifact SHA-256: `cefd8117e0b36ab22216b013319e9812c01561b1e83792a841382ad60d0d1537`
Artifact size: `299,524` bytes

## Audit verdict

Remediation required.

The original generic “Passed” conclusion was withdrawn because it predated the competitor-grade financial, execution-control, interaction, accessibility, and responsive requirements. This record preserves that audit verdict and records the completed remediation separately.

## Remediation outcome

The interactive design artifact now passes the scoped artifact-level remediation gate. It preserves an Exodus-simple entry, Uniswap-style review discipline, automatic same/cross-chain inference, transparent comparison, and evidence-led recovery. Activity is explicitly a non-durable in-memory fixture that simulates KDF-authoritative `list_executions` and `get_execution`; the artifact no longer presents its own rows as a durable store. This is not a production-readiness claim for unfinished release gates or the outstanding moderated user study.

## 1. Entry and consumer simplicity — healthy

- Entry is exactly two amount cards with embedded source and recipient addresses, one compact quote strip, and one contextual CTA. There is no Bridge mode, account selector, route marketplace, provider logo, or routing slogan.
- Same-chain continuity is ETH on Ethereum → USDC on Ethereum. Cross-chain continuity is ETH on Ethereum → USDC on Arbitrum One. Mixed continuity is USDC on Ethereum → BTC on Bitcoin.
- The selected address balance is explicit; destination network and recipient remain visible; gas-aware Max is the only permanent amount shortcut.
- The quote strip exposes minimum received, total cost, estimated time, qualified ranking, and comparison. At 375px the strip and CTA no longer overlap; at the bottom scroll position the CTA clears the persistent navigation by 32px.
- One intent-versioned quote controller now owns amount, asset, recipient, source-address, retry, recovery, and inspector transitions. `Checking…` resolves to a terminal ready or recoverable state. Picker overlays and navigation preserve still-valid work so it can complete in domain state while hidden and be ready when the surface returns; only intent changes and superseded requests invalidate stale callbacks.
- Busy semantics remain present only while work is active and clear on ready, timeout, offline, expiry, validation, and failure outcomes. Timeout, offline, and expired quotes expose deterministic retry paths rather than indefinite loading.
- Max and spendable-balance validation use the currently selected source address. Browser acceptance covered a lower-balance address, source changes, recipient and asset changes, and recovery that requests a fresh quote.
- High-price-impact, low-liquidity, suspicious-token, unknown-token, and price-estimate-unavailable states are included.
- No customer-facing Li.Fi/provider attribution, `Main account`, `Connected account`, `Atomic`, or `external route` terminology remains.

## 2. Financial correctness and review — healthy

- One canonical fixture object drives entry, options, review, progress, Activity, evidence, and outcomes for each prototype journey.
- `63/63 fixture assertions` pass for asset/network/address continuity, expected ≥ minimum, fee arithmetic, option/outcome identity, ordered stages, and persisted holdings.
- Fee totals reconcile without double counting. Approval gas is nested as `Approval network cost`; maximum network cost is a protection bound, not a second fee.
- The mixed fixture uses the economically derived `0.01816 WBTC` intermediate holding; the impossible `0.062 WBTC` value is absent.
- Review uses a compact transfer summary and keeps expected outcome, minimum receive, total cost, estimated completion, source, recipient, warnings, permission, and CTA decision-visible. `Costs & protection` and `Route & identities` progressively disclose fee mechanics, full identities, and route detail without duplicating the permanent summary.
- The Review action footer remains sticky and safe-area-aware on narrow canvases. Preflight revalidation has explicit checking, material-change, structural-change, expired, and failed outcomes; failed preflight clears busy state and offers recovery without submitting stale consent.
- Desktop details/comparison/review are non-modal side panels with one primary action. Focus moves to the heading, Back/Escape returns focus, and editing the underlying intent closes and invalidates the panel.
- Material refresh uses the actually selected option and canonical fixture for old-versus-new consent; structural changes require fresh evaluation.
- Ranking copy is qualified: “Best net return among currently available, comparable options.” Warnings remain visible independently of rank.

## 3. Execution safety and Activity — healthy

- Fixture transitions preserve exact reviewed consent and bind it to the same full execution ID before progress; completed rows keep that consent/execution-ID identity.
- Activity copy and a machine-readable contract identify `experimental::trade_route::list_executions` and `experimental::trade_route::get_execution` as authoritative. The prototype’s `activityRows` are explicitly in-memory and non-durable.
- Signed bytes are reconciliation-only unless authoritative capabilities say otherwise. Signed/reconciliation states expose no cancel or stop language; source-confirmed work shows `Stop after current step` only when typed capability permits it.
- Passive progress contains no no-op `Continue tracking` action. Users can leave via `View in Activity`; navigation never implies execution stops.
- Activity filters are Active, Needs attention, and Completed. Rows show both assets and networks, one human status, last update, and an action badge only when action is genuinely required.
- The refund fixture is now a supported-network EVM historical record (Ethereum → Arbitrum One), marked read-only with no historical execution action. Different-token decisions, missing orders, claimable recovery, and approval remediation are under Needs attention.
- The 17-stage route collapses 12 completed stages while preserving their evidence and keeps the five remaining semantic stages visible.

## 4. Recovery and evidence — healthy

- Every recovery state answers what happened, where funds were last confirmed or verified, and what the user can do now.
- Ambiguous broadcast uses: “Last confirmed location: 1 ETH at 0x5520…7B91 on Ethereum. Current location is not yet verified. The transaction may still be pending.”
- Recovery distinguishes verified current holding, last confirmed location, unknown current location, and pending evidence. No state fabricates fund location.
- Evidence is execution-specific. Every stored execution ID is full and unique; visual clipping uses CSS only, while detail and copy actions retain the full value. Completed rows bind consent and evidence to their own execution ID.
- Recovery holdings now reconcile to their canonical records: 1,318.42 USDT for different-token recovery, 892.00 USDC for the missing-order case, 0.01816 WBTC for intermediate/recoverable cases, 320 USDC for approval-only, and 409.20 USDT for the EVM refund.
- Full holding copy uses the full address. Token contracts, asset IDs, source/recipient addresses, holdings, transaction evidence, and receipts have reveal/copy patterns.
- `INVALID`, unknown future status, and invalid evidence explicitly prevent later stages from starting while verification continues.
- Claim-refund and revoke-allowance designs remain disabled and contract-dependent until typed actions exist.
- Clipboard success is announced only after the platform write resolves; a denied or unavailable write produces a failure announcement with manual-copy guidance.

## 5. Interaction and accessibility — healthy

- All ten prototype journeys completed through customer-facing controls: `10/10`, covering 35 user actions and 5 explicit system transitions.
- Confirmation dialogs alone use modal semantics: scrim, inert background, focus trap, Escape policy, and opener focus restoration.
- Composite option and picker controls use radio/listbox semantics with roving focus and Arrow/Home/End navigation. The expanded 128-option state has exactly one checked and one tabbable radio.
- Validation is associated with the actual amount, recipient, asset, or source-address control using field-specific invalid/described-by relationships.
- Selection, current page/step, busy state, filter state, and status changes use `aria-current`, `aria-pressed`, `aria-busy`, live regions, and completed/error/cancelled timeline labels.
- Viewport, theme, text-scale, and motion test controls are controlled selection groups with visible and semantic active states. They can be reversed individually or restored together with Reset; focus and toolbar synchronization survive rerenders.
- Inspected reusable controls have zero targets under 48 CSS pixels. At 200% text, all navigation labels remain visible and unbroken without being hidden or truncated.
- True underlying canvases measure 375, 390, 768, 1024, and 1440 CSS pixels. Representative entry, options, review, progress, Activity, recovery, 200% text, and long-route states have zero horizontal overflow.
- Reduced-motion transitions resolve to `0.000001s` while preserving state, focus, and status semantics.
- Measured contrast: dark body 17.21:1, tertiary 8.45:1, quote 9.13:1, primary action 4.87:1, link 4.68:1, control boundary 3.68:1; light body 19.51:1, tertiary/quote 6.30:1, primary action 4.87:1, link 7.15:1, control boundary 3.79:1.
- UTF-8 metadata, Manrope, Remix icons, the combined official Gleec icon and theme-aware wordmark, authentic token art, and distinct chain badges are bundled locally. Unknown tokens use a neutral initials fallback.

## Automated and runtime evidence

- Static and executable verifier: `134/134` checks pass, zero warnings, zero failures. New executable checks cover Activity authority, full execution IDs, recovery amounts, consent binding, analytics whitelisting, clipboard success/failure, and evidence file dimensions/formats.
- Runtime fixture assertions: `63/63`.
- Customer-operated prototype journeys: `10/10`.
- The previously recorded full browser acceptance run covered Checking-to-ready, timeout/offline/expiry retry, latest-amount-wins, preservation of valid quote work across picker/navigation surfaces, Max and lower-balance source validation, recipient and asset changes, recovery fresh quote, picker and Activity loaders, Review preflight and failure, 200% text, responsive light/dark/reduced-motion modes, and active/reset accessibility controls. The 2026-07-19 closure adds targeted raw-browser captures and executable contract checks; it does not claim a new full browser matrix run.
- Full machine-readable acceptance summary: [runtime-acceptance.json](qa-evidence/runtime-acceptance.json).

## Visual evidence

Items 1–18 are QA-workbench captures: the named width is the wallet canvas configured inside the 1280px outer capture.

1. [Workbench · 390px dark cross-chain entry canvas](qa-evidence/01-entry-crosschain-390-dark.png)
2. [Workbench · 1440px dark desktop review canvas](qa-evidence/02-review-crosschain-1440-dark.png)
3. [Workbench · 390px light external-recipient canvas at 200% text](qa-evidence/03-recipient-confirm-390-light-200.png)
4. [Workbench · 390px signed reconciliation canvas with no cancellation action](qa-evidence/04-signed-reconciliation-390-dark.png)
5. [Workbench · 390px Activity needs-attention canvas](qa-evidence/05-activity-needs-attention-390-dark.png)
6. [Workbench · 390px ambiguous-location recovery canvas](qa-evidence/06-ambiguous-location-390-dark.png)
7. [Workbench · 1440px 128-option stress canvas](qa-evidence/07-options-stress-128-1440-dark.png)
8. [Workbench · 390px 17-stage timeline stress canvas](qa-evidence/08-timeline-stress-17-390-dark.png)
9. [Workbench · 375px light entry canvas](qa-evidence/09-entry-375-light.png)
10. [Workbench · 768px dark entry canvas](qa-evidence/10-entry-768-dark.png)
11. [Workbench · 1024px light review canvas](qa-evidence/11-review-1024-light.png)
12. [Workbench · 390px dark progress canvas with reduced motion](qa-evidence/12-progress-390-dark-reduced-motion.png)
13. [Workbench · 390px dark entry canvas while checking](qa-evidence/13-entry-checking-390-dark.png)
14. [Workbench · 390px dark route-options canvas after checking resolves](qa-evidence/14-entry-route-options-after-check-390-dark.png)
15. [Workbench · 390px light quote-timeout canvas with retry](qa-evidence/15-entry-timeout-retry-390-light.png)
16. [Workbench · 390px dark compact Review canvas](qa-evidence/16-review-390-dark.png)
17. [Workbench · 390px light compact Review canvas at 200% text](qa-evidence/17-review-390-light-200.png)
18. [Workbench · 1440px light accessibility-controls canvas at 200% with reduced motion](qa-evidence/18-accessibility-controls-active-1440-light-200-reduced.png)

Items 19–21 are raw browser screenshots whose PNG dimensions equal the named viewport exactly.

19. [Raw 390×844 dark Swap entry viewport](qa-evidence/19-raw-viewport-entry-390x844-dark.png)
20. [Raw 390×844 dark Activity needs-attention viewport](qa-evidence/20-raw-viewport-activity-attention-390x844-dark.png)
21. [Raw 390×844 dark ambiguous-recovery viewport](qa-evidence/21-raw-viewport-recovery-ambiguous-390x844-dark.png)

Capture types, dimensions, and corrected legacy JPEG extensions are recorded in [the evidence manifest](qa-evidence/manifest.json).

## Contract and release limitations

- KDF—not this prototype—is the authoritative Activity store. Production must use authenticated list/get, reconciliation, and reattachment; the artifact’s in-memory fixtures are never an accepted route registry.
- Release remains gated by the server-prepared Review/consent contract, immutable platform artifacts, full-stack restart/recovery validation, platform/accessibility coverage, and the staged operational controls in the production-readiness plan.
- Production UI must hide claim-refund and revoke-allowance until typed actions exist.
- The handoff documentation now separates internal provider/tool evidence from Gleec-owned customer presentation.
- A moderated study with at least five representative wallet users was not executed locally. It remains a mandatory production gate: at least four users must complete each core task unassisted, and none may misunderstand minimum received, destination network, active recipient, cancellation availability, or known fund location.

## Final result

Passed

The interactive artifact passes the prototype defect-closure gate. Production remains gated by the listed server, artifact, full-stack, platform, operational, accessibility, and moderated-user requirements.
