# Design QA — Gleec Unified Swap

Build: production-readiness prototype defect closure
Date: 2026-07-19
Artifact SHA-256: `cefd8117e0b36ab22216b013319e9812c01561b1e83792a841382ad60d0d1537`

## Final result

Passed

## Gate summary

| Area | Result | Evidence |
|---|---|---|
| Entry simplicity | Pass | Two outcome cards, embedded addresses, compact quote, one CTA; intent-versioned quote evaluation always reaches a ready or recoverable terminal state. |
| Financial correctness | Pass | Canonical fixtures, `63/63` assertions, reconciled fees, expected/minimum and persisted-holding continuity. |
| Quote reliability | Pass | Latest intent wins; intent changes invalidate stale callbacks, while picker overlays and navigation preserve still-valid work to complete while hidden; busy semantics clear on every terminal state. |
| Review and consent | Pass | Compact transfer summary, decision-visible protection and costs, `Costs & protection` and `Route & identities` accordions, sticky footer, exact approval, and explicit preflight/revalidation recovery. |
| Execution safety | Pass | Authoritative cancel/stop/reconciliation capabilities; no action inferred from labels. |
| Activity and recovery | Pass | KDF-authoritative list/get fixture contract, full execution IDs, reconciled holdings, read-only EVM refund history, known/unknown location distinctions, typed-action gating. |
| Interaction | Pass | `10/10` customer-operated flows; deterministic timeout/offline/expiry retry; non-modal side panels; focus-managed confirmation dialogs. |
| Accessibility | Pass | 48px targets, terminal busy semantics, roving composite focus, field-specific errors, controlled active/reset test groups, focus/toolbar synchronization, visible 200% labels, contrast, and reduced motion. |
| Responsive layout | Pass | True-width 375/390/768/1024/1440 canvases with zero inspected overflow and safe mobile navigation. |
| Brand and copy | Pass | Combined official Gleec icon and theme-aware wordmark, local fonts/icons/token art, neutral customer presentation, and consumer language. |

## Evidence summary

- Static and executable verifier: `134/134`, zero warnings/failures.
- Runtime fixtures: `63/63` assertions.
- Prototype flows: `10/10`, 35 user actions and 5 explicit system transitions.
- Browser acceptance: quote resolution/races/retries, valid work preserved across picker/navigation surfaces, selected-source Max and balance validation, intent changes, fresh recovery quotes, loaders, Review preflight/failure, 200% text, responsive themes/reduced motion, and controlled active/reset states passed.
- Final screenshots: 18 workbench captures plus 3 exact 390×844 raw browser-viewport captures, classified in `qa-evidence/manifest.json`.
- Browser runtime logs: no warnings or errors.

## Scope boundary

This pass applies to the interactive design artifact and its contract handoff. Activity rows remain explicit non-durable fixtures; KDF list/get remains authoritative. It does not waive the server-prepared Review/consent, platform artifact, full-stack, operational, accessibility, or moderated five-user production gates.
