# App 0.10.0 + SDK 0.9.0 release review

Review the complete release diffs for app
[#3561](https://github.com/GLEECBTC/gleec-wallet/pull/3561) and SDK
[#410](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/410).
Use the [current handoff](RC_0.10.0_TESTER_REVIEWER_HANDOFF.md) and
[release checklist](RELEASE_0.10.0_CHECKLIST.md) for evidence and known gates.
This is a review assignment; do not change product code or approve a release
merely because a checklist or suite passes.

## Resolve exact review scope

Use an isolated checkout of GLEECBTC/gleec-wallet and its SDK gitlink. Fetch app
and SDK `main`/`dev`, then record the full base/head SHAs before reading patches.
The SDK must be the intended standalone/submodule repository, not the app-owned
`packages/` directory.

```bash
# App repository
git fetch origin main dev
git rev-parse origin/main origin/dev
git diff --name-status origin/main...origin/dev
git diff --stat origin/main...origin/dev
git log --oneline --no-merges origin/main..origin/dev
git rev-parse origin/dev:sdk

# SDK repository (run these within sdk/)
git fetch origin main dev
git rev-parse origin/main origin/dev
git diff --name-status origin/main...origin/dev
git diff --stat origin/main...origin/dev
git log --oneline --no-merges origin/main..origin/dev
```

Freeze those SHAs in subsequent diff commands. If heads move, report the delta
and review it explicitly. Do not silently use old polish/feature branches or
substitute an app development SDK pin for the SDK release head. After SDK main
promotion, separately inspect the final app repin and actual SDK main merge SHA.

## Review method and priorities

Keep an explicit checklist of every changed file, including generated code,
configuration, workflows, dependencies, submodule pointers and documentation.
Read patches with sufficient callers/models/platform implementations to judge
behavior. Report findings first; include severity, exact file/line, trigger,
consequence, evidence and a concrete correction. Deduplicate existing findings
and link them rather than treating a known blocker as resolved.

Prioritize:

- Exact asset/network/account identity, decimal precision, provider fees, gas,
  native Max reserve, minimum and approval/spender scope. Missing evidence must
  not become a claim that no permission is needed (atomic X04/Q12, #3563).
- Quote revalidation, worse-minimum acceptance, uncertain starts, asynchronous
  wallet/pair changes, duplicate submission, stale state and funding changes.
- Persistence, identity isolation, approvals/payments/refunds, terminal vs delayed
  statuses, recovery after restart and reliable links/diagnostics.
- SDK public API/constraint compatibility, typed RPC envelopes, native/web
  boundaries, part libraries and stable index/build-runner output.
- Pinned KDF/spec/coin/artifact integrity and security parity with the last
  published release, including ERC-20 payment validation.
- Legal availability/consent hashing, preview-only exception isolation, default
  production gate and absence of fabricated acceptance.
- Onboarding/auth/Trezor restrictions, balances/history/transfers and failure
  handling across supported platforms. Explain each real regression, not a
  hypothetical checklist concern.
- Accuracy of release claims and evidence: measured vs provider-reported,
  historical vs current head, blocked/deferred vs passed, unsigned vs signed.

## Validation and deliverable

Follow repository AGENTS.md and docs/TESTING.md. New app unit files must be
imported by test_units/main.dart. Use Flutter 3.41.4 and the four production
GasFree defines for that aggregator. SDK validation uses the prepared Melos
workspace (7.8.1), native package suites and relevant WASM suites. Preserve
lockfiles and unrelated changes. Name exact failures and skipped cases; a setup
failure is not a failed product test and does not pass that surface either.

Write findings to `docs/SDK_APP_DIFF_REVIEW_FINDINGS.md` in the review checkout,
with resolved SHAs, file-coverage appendix, tests actually run and limitations.
State no findings only when the full stated scope was reviewed. Keep funded
wallet evidence private. A person presses any control committing real funds.
Independent reviewers may split work by explicit file/domain ownership, then
reconcile coverage and cross-boundary findings before sign-off.
