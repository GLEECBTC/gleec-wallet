# Unified Swap production readiness

This plan tracks the SDK and Gleec Wallet work paired with the KDF plan at
`komodo-defi-framework/docs/plans/unified-swap-production-readiness.md`.
KDF is the authoritative durable execution and Activity store; wallet caches
are rendering aids only.

## SDK contracts and artifacts

- [x] Remove localhost and local-branch artifact sources and retain only clean,
      trusted HTTPS sources and immutable checksums in the SDK build config.
- [ ] Advance the SDK artifact pin to the immutable KDF commit that contains
      all fifteen route and external-execution RPCs after every platform
      artifact below is published and verified.
- [ ] Publish verified KDF artifacts for web, iOS, macOS, Windows, Linux, and
      Android armv7/aarch64, with committed checksums and platform markers.
- [x] Add strict immutable Dart models for every request, response, enum,
      error, exact asset/source selector, digest, control, evidence, holding,
      and Activity cursor.
- [x] Preserve unknown discriminators in a non-executable unknown variant and
      expose a localized fallback instead of guessing or throwing.
- [x] Add cross-language golden JSON/digest fixtures and parser boundary tests.
- [x] Add a `TradeRouteManager` whose observation lifecycle never cancels a
      backend execution; only an explicit capability-authorized action can.
- [x] Add `prepare_execution` bindings and fail-closed RFC 8785 verification
      for the candidate, prepared Review, every external-stage consent, and
      complete route consent, with a canonical cross-language fixture.

## App feature

- [x] Implement `features/unified_swap` with domain, infrastructure,
      application, and presentation boundaries.
- [x] Implement `UnifiedSwapBloc` with exact intent, source/recipient,
      latest-intent-wins quoting, expiration, ranking, option selection, and
      revalidation.
- [x] Implement `RouteExecutionBloc` with review, init, typed progress,
      reattachment, explicit controls, recovery, and live announcements.
- [x] Implement `RouteActivityBloc` with KDF list/get pagination,
      active/attention/completed grouping, wallet reset, and resume
      reconciliation.
- [x] Add canonical `/swap`, `/activity`,
      `/activity/:routeExecutionId`, and `/advanced` navigation plus safe
      legacy DEX/Bridge redirects without addresses in URLs.
- [x] Implement a fail-closed V1 policy for software-key EVM native/ERC-20
      sources and exact KDF identities; unsupported source, provider, action,
      unknown capability, and unknown compliance variants remain inert.
- [x] Connect that policy to the production KDF capability/coin-activation
      inventory, including exact KDF-advertised destinations and activated
      software-key EVM sources.
- [x] Apply the specified slippage, quiet-refresh, price-impact, liquidity,
      token, valuation, ranking, and privacy defaults in tested product policy.
- [x] Connect wallet trading compliance and localized Gleec-owned customer
      copy to the production exact asset/source resolver.
- [x] Wire a wallet-scoped exact quote store and KDF-prepared Review/consent
      bundle. Keep init disabled until displayed source, steps, economics,
      fee caps, and ERC-20 approval scope are inseparable from full consent.
- [x] Supply the production chain-native recipient validator, selected-address
      funding checks, and explicit per-stage gas/non-network fee-limit policy
      to the wallet-scoped quote factory. No aggregate-fee fallback is used.

## Verification and rollout

- [x] Add focused BLoC, repository, widget, semantics, and lifecycle coverage
      without increasing the recorded analysis debt.
- [x] Add tamper tests for candidate, Review, stage, source, expiry, approval,
      and fee-cap bindings; the focused Unified Swap suite is green.
- [ ] Complete the remaining golden, force-kill/resume platform, and full
      accessibility-matrix coverage without increasing analysis debt.
- [ ] Add deterministic full-stack value and ambiguous/recovery paths through
      the production proxy/CORS and real KDF persistence/signing boundaries.
- [ ] Complete responsive, theme, text-scale, reduced-motion, keyboard,
      screen-reader, localization, and five-user moderated validation gates.
- [x] Add privacy-safe durable-outcome analytics and independent quote/init
      build switches, all defaulting off.
- [x] Make desktop/mobile/UI build gates non-permissive and require exact SDK
      and KDF SHAs plus a verified immutable artifact manifest for integration
      previews.
- [ ] Complete internal, 10%, and general-availability rollout stages.

## Latest closure verification

- Wallet Unified Swap domain, config, execution, Activity, routing,
  composition, and presentation tests: 102 passed.
- Advanced destructive-confirmation, 200% text button, and UI-kit focus tests:
  5 passed.
- RPC SDK contract, shared task-error envelope, and digest tests: 27 passed.
- SDK route-manager tests: 23 passed; forced authenticated pubkey-refresh tests:
  2 passed; external-execution startup tests: 8 passed.
- Wallet Unified Swap analysis: no issues. Calm Core/UI-kit/Advanced analysis:
  no errors or warnings, with 106 pre-existing informational lints. New SDK
  contract surfaces have no errors or warnings; larger legacy SDK files retain
  their recorded informational debt.
- Proxy security suite: 36 passed. Public documentation JSON, structure, H1,
  and CompactTable checks passed; its online release lookup was unavailable in
  the offline environment.
- A complete Flutter 3.41.4 profile web build passed with all new trading flags
  left at their default fail-closed values; the compiler's WebAssembly dry run
  also passed.
- Dart formatting, localization JSON/static-key resolution, and repository diff
  checks: clean.
- Executable prototype verifier: 134 passed, 0 warnings, 0 failed.

The implementation remains a release no-go. The unchecked immutable artifact
pin, canonical Flutter goldens, full-stack restart/recovery and platform
proofs, accessibility/usability validation, authorized proxy deployment, and
staged rollout require release infrastructure or coordinated validation that
is not present in this worktree.

Delete this file only when every checkbox is complete.
