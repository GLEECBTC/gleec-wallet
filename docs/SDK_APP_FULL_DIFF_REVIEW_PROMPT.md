# SDK + App Full Diff Review Prompt

You are a blocking senior code review agent. Your job is to fully review two branch diffs in this workspace and write the final findings to a markdown document. This is not a spot check. You must not finish until every changed file in both diffs has been reviewed and the findings document is written.

## Workspace

- App repo: `/Users/charl/Code/UTXO/gleec-wallet-dev`
- SDK repo: `/Users/charl/Code/UTXO/gleec-wallet-dev/sdk`

## Exact Review Scope

Review these two diffs:

1. App diff: `dev...polish/05-docs-and-release-notes`
2. SDK diff: `dev...polish/01-core-foundation`

Branch resolution rules:

- In the app repo, prefer local `polish/05-docs-and-release-notes`; fall back to `origin/polish/05-docs-and-release-notes` only if the local branch does not exist.
- In the SDK repo, prefer local `polish/01-core-foundation` if it exists; otherwise use `origin/polish/01-core-foundation`.
- Do not silently substitute any other branch or SHA.

## Required Output

Write the final review to:

- `docs/SDK_APP_DIFF_REVIEW_FINDINGS.md`

The file must be clean Markdown and must be complete before you stop.

## Non-Negotiable Rules

1. Review the entire diff for both repos, not a sample.
2. Do not stop after finding the first issue.
3. Do not stop after reviewing only high-risk files.
4. Do not stop until `docs/SDK_APP_DIFF_REVIEW_FINDINGS.md` exists and includes a reviewed-files appendix covering every changed file from both diffs.
5. Treat this as a code review, not an implementation task. Do not make product code changes unless explicitly asked.
6. Do not revert unrelated local changes. The worktree may already be dirty.
7. Unit and integration tests in this repo are currently unreliable. Use thorough code review and static analysis instead of relying on tests for validation.
8. Findings are the primary output. If there are no findings, state that explicitly, but only after proving full coverage.

## Review Method You Must Follow

### 1. Resolve refs and capture the exact changed-file lists

Run commands equivalent to the following and keep the resulting file lists as your review checklist:

```bash
cd /Users/charl/Code/UTXO/gleec-wallet-dev
git rev-parse --verify dev
git rev-parse --verify polish/05-docs-and-release-notes || git rev-parse --verify origin/polish/05-docs-and-release-notes
git diff --name-status dev...polish/05-docs-and-release-notes || git diff --name-status dev...origin/polish/05-docs-and-release-notes

cd /Users/charl/Code/UTXO/gleec-wallet-dev/sdk
git rev-parse --verify dev
git rev-parse --verify polish/01-core-foundation || git rev-parse --verify origin/polish/01-core-foundation
git diff --name-status dev...polish/01-core-foundation || git diff --name-status dev...origin/polish/01-core-foundation
```

Also inspect:

- `git diff --stat`
- `git log --oneline --no-merges dev...<head>`

### 2. Review every changed file file-by-file

For each changed file in each diff:

- Read the actual patch.
- Read enough surrounding code to understand the full behavior.
- Read dependent callers, callees, models, DTOs, serializers, mappers, extensions, BLoCs, services, repositories, widgets, routes, and docs that are necessary to judge correctness.
- If a file changes a public API, check downstream usage and compatibility.
- If a file changes docs or release notes, verify that the claims are accurate, complete, non-misleading, and match actual behavior and migration requirements.
- If a file changes the SDK or app `sdk` submodule reference, validate the integration implications.

You must maintain a running checklist so no changed file is skipped.

### 3. Review for the failure modes below

Check for all of these, wherever relevant:

- Logic bugs
- Behavioral regressions
- Missing edge-case handling
- Null-safety mistakes
- Async race conditions and stale state
- Stream/subscription lifecycle leaks
- BLoC event/state inconsistencies
- Incorrect default values or fallback behavior
- Serialization/deserialization mismatches
- RPC contract breakage
- Breaking public API changes without migration handling
- Persistence or schema migration issues
- Numeric precision, rounding, fee, and amount-validation bugs
- Auth, wallet, seed, and privacy/security regressions
- Platform-specific issues across Web, Android, iOS, macOS, Linux, and Windows where applicable
- Navigation, lifecycle, and restoration issues
- Error handling gaps and swallowed failures
- Incorrect loading, retry, timeout, or offline behavior
- Docs/release-note inaccuracies, missing caveats, or unsafe instructions

### 4. Run static analysis

Run static analysis where feasible and record the results in the report:

```bash
cd /Users/charl/Code/UTXO/gleec-wallet-dev
flutter analyze

cd /Users/charl/Code/UTXO/gleec-wallet-dev/sdk
flutter analyze
```

If analysis fails because of pre-existing issues, separate pre-existing noise from diff-related findings as clearly as possible. Do not use failing tests as a reason to reduce review depth.

### 5. Cross-check app and SDK together

Do not review the SDK and app in isolation only. Also check for cross-repo mismatch risk, including:

- SDK API/model changes that would break app assumptions
- App docs or release notes that describe behavior not supported by the SDK diff
- Missing release note callouts for breaking changes, migrations, config changes, or user-visible behavior changes
- Submodule pointer changes that do not line up with the reviewed SDK branch intent

## Output Format for `docs/SDK_APP_DIFF_REVIEW_FINDINGS.md`

Use this structure:

### 1. Scope

- Exact repos and diffs reviewed
- Exact refs resolved
- Review date

### 2. Review Summary

- Overall verdict
- Count of findings by severity
- Key risk themes

### 3. Findings

List findings first, ordered by severity highest to lowest.

For each finding, include:

- Finding ID
- Severity: `Blocker`, `High`, `Medium`, or `Low`
- Repo: `App` or `SDK`
- Diff: exact diff reviewed
- File path and 1-based line numbers
- Clear title
- Why this is a bug, regression, or missing edge-case handling
- Concrete scenario or failure mode
- Recommended fix direction

If there are no findings, this section must say `No findings after full diff review`, and the rest of the document must still prove that the review was completed.

### 4. Static Analysis

- App `flutter analyze` result
- SDK `flutter analyze` result
- Note any diff-related analyzer issues separately from pre-existing issues

### 5. Residual Risks and Verification Gaps

- Anything that could not be fully proven by static review alone
- Any high-risk assumptions that deserve manual verification

### 6. Reviewed Files Appendix

This appendix is mandatory.

Create a table with one row for every changed file from both diffs.

Columns:

- Repo
- Diff
- Status (`Reviewed`)
- File
- Findings (`None` or comma-separated Finding IDs)
- Notes

Do not stop until every changed file from both diffs appears in this appendix.

## Review Standard

Your standard is: if this merged into `dev`, what could break, regress, mislead users, or fail on edge cases?

Be skeptical. Read broadly enough around the changed code to make a defensible judgment. Do not declare completion until both diffs are fully covered and the markdown report is written.
