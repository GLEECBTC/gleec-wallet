# Upcoming wallet integration preview

This draft combines the active post-0.10.0 app and SDK work into one early
preview. Its target is `dev`; the original feature PRs remain available for
focused review.

| Source | Included head |
| --- | --- |
| Flutter 3.50 / Dart 3.14, app #3615 | `e83862e4da10499e1659e7ec763910a5c0c254fa` |
| Audited onboarding/device access, app #3612 | `6b80c458650572c042c9c7867f777c7265f5519f` |
| Audited Solana, app #3611 | `b58b21c21d84186b9b0525db513064a460451e0a` |
| Audited pricing, app #3607 | `309dd97d926383feeb4f0c34a907de986be7b716` |
| Combined SDK #448 | `776559bcfcdc32fc047710c8960c4eba38879012` |

The app branch preserves the four published app heads as ancestors. SDK #448
combines SDK #443, #444, #445 and #447. The app pins that combined SDK rather
than selecting one feature branch's dependency tree. SDK #448 is merged into
SDK `dev` as `776559bc`, whose tree equals the tested head `ca316f29`.

## Swap UX reconciliation

The previously local Swap UX was reviewed against the newer authentication,
funding and Flutter changes rather than copied wholesale. Its source was
captured separately from the mixed workspace; unrelated workspace changes,
wallet data, local logs and deployment state are excluded.

Retained improvements include incremental quote arrival, explicit asset and
funding preparation, precise token/USD entry, session-scoped drafts, compact
review/details, recovery presentation, reduced-motion behavior and the wallet
swap-progress row. Existing Gleec components remain the visual authority.

The following older implementation paths were superseded:

- Direct executor/registry starts without captured authorization. Submission
  continues through the newer wallet-session lease, review revision and final
  dispatch guard. Disposal before dispatch cannot send; dispatched work stays
  discoverable and uncertain starts cannot be retried automatically.
- The older consent callback and preparation status. Consent uses the newer
  captured wallet identity/current-confirmation contract, and `starting`
  begins only at dispatch. Failed, throwing or late consent never authorizes
  an engine request; retry requires a new explicit review.
- User-name-only session resets and pre-auth draft retention. Runtime session
  epochs invalidate drafts, precision lookups, presentation and stale requests.
- Duplicate form-reset handlers. The preparation-aware handlers retain the
  current amount-mode behavior and existing start-in-doubt protection.

The combined quote stream retains the audit's fastest-alternative safeguards:
late snapshots cannot remove an explicit valid selection or revive expired,
wrong-pair, wrong-amount or Max-incompatible alternatives. Amount/Max controls
remain locked while a start may be running. Existing terminal swap-state and
exact-UUID history assertions from the Flutter upgrade remain intact.

## Validation

Flutter 3.50.0 / Dart 3.14.0; the app gate uses the four production GasFree
defines from `docs/TESTING.md`. New Swap tests are imported and invoked in
`test_units/main.dart`.

- Complete SDK core: 1,324 passed, one existing skip.
- Complete SDK authentication: 196 passed.
- SDK pricing/providers: 374 passed, six opt-in live-provider skips.
- Deployment privacy/URL fixtures: 27 + eight passed in each repository.
- Android signing fixture and all nine LI.FI build-profile fixtures passed.
- Full app analysis: zero errors, 60 warnings and 3,253 informational findings.
  All 122 changed app Dart files have zero scoped errors/warnings.
  SDK analysis also found no errors; documented warning/deprecation debt
  remains. Changed Dart files were formatted.
- Complete app aggregator: **4,784 passed, 26 platform/opt-in skips**, 6m54s.
  Published integration CI results are recorded in the PR.
- SDK analysis: zero errors; 2,064 existing warnings/informational findings
  across the combined workspace, including supported deprecated Flutter APIs.

Local widget tests reuse cached assets with shaders recompiled for Flutter
3.50. Native asset generation is serialized because concurrent transformers
share framework output paths. CI builds and validates fresh artifacts.

The first integration CI run exposed two tooling incompatibilities. Docker
reached native CMake configuration before generating the verified library;
the wrapper now runs the same manifest-checked preparation as shared CI.
Nine Docker regressions cover preparation order, failure propagation, SDK
preservation and target selection. The browser driver selected a zero-sized
stale Flutter 3.50 input instead of the visible confirmation field. It now
selects rendered, enabled controls before focusing or typing. The complete
compiled phrase/encrypted-file recovery flow passed after that correction,
including identity, derivation and diagnostic-canary assertions. No wallet
authorization or recovery assertion was bypassed.

Full application WebAssembly acceptance then found two runtime defects that
compilation and the existing package lanes did not cover. Adapting the SDK's
optional-named extension tear-off to a zero-argument engine-stop callback
trapped; an explicit call preserves the same nested transition/revocation
behavior. KDF's numeric Argon2 version became `19.0` through JS interop and
failed string-to-integer parsing; the parser now accepts exact integral values,
retains hex/decimal string compatibility and rejects fractional/non-finite
values without exposing malformed inputs in errors. Focused tests reproduced
both failures before correction. The SDK runs the auth and JS-boundary
regressions in WebAssembly CI.

After those fixes, the **complete release Wasm recovery flow passed** with
JavaScript fallback rejected: creation, passkey registration/verification,
requested-only encrypted export, phrase confirmation, reload/sign-out, separate
seed and encrypted-file restoration, verified identity/derivation and diagnostic
canaries. The harness fingerprints the Wasm binary and serves `.mjs` correctly;
`docs/TESTING.md` records the command. SDK auth recheck: 196 passed; complete
types: 214 passed/three existing skips; real Wasm auth: two passed; KDF Wasm
transport/privacy: 11 passed; browser log-storage privacy: 12 passed. The
changed SDK source/tests have clean scoped analysis and formatting.

All five full-app browser suites also passed against the real release Wasm
binary: credentials/lifecycle, recovery, missing data, passkey replacement and
browser support. The last includes the audited offline helper after the same
asset preparation used by CI. The SDK playground JSON-editor test passed after
its asset hook received the existing build-time GitHub token; the SDK workflow
now supplies it consistently. This final SDK CI correction changes no Dart
runtime source.

**UI-Pro Basis:** the repository's wallet design-system, Flutter accessibility
and financial error-recovery searches; existing Swap state/motion contract;
`docs/design/swap_experience` reference; automated layout/semantics/motion tests.

**Gate Status: exception.** The canonical design files referenced by the skill
are absent. The original approved Gleec components/reference remain the basis;
current screenshots and automated checks are required, while real-device
screen-reader/usability and profiling remain manual follow-up. The original
Swap delivery record contains earlier evidence and is not the final integration
test result.

## Remaining release gates

The SDK must merge to an accepted branch and the app must be repinned before
release. The SDK ancestry safeguard remains enabled and deliberately rejects
the preview-only commit. A successful preview is not production approval.

Physical biometric/PIN/passkey/provider behavior, OS lock/invalidation/reinstall,
trusted signing/provisioning and rollback, production helper-origin closure,
funded native/browser Solana and swap acceptance, uncertain-signature recovery,
SPL Max/Token-2022, funded history/backfill, combined seven-platform KDF artifacts
preserving LI.FI, bot per-order guarantees, Banxa/live-provider availability,
historical-log/credential review, device performance and moderated usability
remain separate gates. A person operates every control that commits funds in
manual preview rounds. Capability defaults and production KDF/catalog pins are
preserved; no production promotion is performed.
