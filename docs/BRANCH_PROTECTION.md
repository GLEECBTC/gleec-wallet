# GitHub branch protection

This runbook applies to `GLEECBTC/gleec-wallet` and
`GLEECBTC/komodo-defi-sdk-flutter`. It complements [Gitflow](GITFLOW_BRANCHING.md).
The release owner controls main promotion. Preparing rules, PRs or RCs does not
permit an agent to merge main. The current app/SDK RC PRs remain open.

## Enforced merge methods

| Target | Allowed method | Additional merge-layer rule |
| --- | --- | --- |
| `dev` | Squash | Linear history |
| `main` | Merge commit | Preserve release/hotfix ancestry |
| `release-*` | Merge commit | Carry focused approved changes |
| `hotfix-*` | Merge commit | Protected hotfix staging |

Legacy `release/*` and `hotfix/*` targets receive the same protection, but new
branches follow the documented kebab-case naming. Repository settings keep
merge commits and squash enabled and disable rebase merging. A repository-wide
squash-only setting would break main/release promotion, so it is not used.

The two versioned profiles are:

- [`gitflow-dev-squash.json`](../.github/rulesets/gitflow-dev-squash.json)
- [`gitflow-preserve-merges.json`](../.github/rulesets/gitflow-preserve-merges.json)

Activated and read back on **29 October 2026**:

| Repository | Dev squash rule | Preserve-merges rule |
| --- | --- | --- |
| App | [26119737](https://github.com/GLEECBTC/gleec-wallet/rules/26119737) | [26119738](https://github.com/GLEECBTC/gleec-wallet/rules/26119738) |
| SDK | [26119744](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/rules/26119744) | [26119746](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/rules/26119746) |

Both are active branch rulesets with **empty bypass lists**. Their pull-request
rule makes direct protected-branch pushes and an incorrect merge method fail
for administrators too, unless an administrator separately changes the rule.
The method layer has zero *additional* approval requirements; it does not remove
or replace the matching baseline rule's existing one-review requirement,
last-push approval, resolved discussions, required CI, deletion protection or
force-push protection. GitHub applies every matching ruleset together.

## Baseline protections retained

The 29 October 2026 audit found native repository rulesets, not classic branch
protection entries. A classic protection endpoint returning 404 therefore does
not mean a branch is unprotected. Inspect effective rules and rule insights.

| Repository | Baseline rulesets retained |
| --- | --- |
| App | `protected-main` (3213702), `protected-dev` (16653655), `protected-release` (16653657), `protected-hotfix` (16653660) |
| SDK | `protected-main-dev` (2615280), `protected-release-hotfix` (16653680) |

Every baseline requires one approving review, approval of the latest push by
someone else and resolved review discussions. Existing CodeQL/code-scanning
and reviewer settings are preserved. Do not add linear history to main or
release/hotfix targets, or remove another ruleset to make a merge button work.

Current active CI status requirements are preserved:

| Target | App required statuses | SDK required statuses |
| --- | --- | --- |
| main | `build_and_preview`, `validate_code_guidelines`, `Test web-app-linux-profile`, `Test web-app-macos` | No active named status-check rule; existing CodeQL code-scanning requirement remains |
| dev | `build_and_preview`, `validate_code_guidelines` | No active named status-check rule; existing CodeQL code-scanning requirement remains |
| release | `build_and_preview`, `validate_code_guidelines` | No active named status-check rule |
| hotfix | `validate_code_guidelines` | No active named status-check rule |

Both repositories also have an `evaluate-ci` ruleset. **Evaluate is observational,
not enforced.** This rollout does not turn every platform/build job in that
ruleset into a release gate. In particular, SDK package tests and the app unit
suite remain mandatory contributor/release validation even where their status
is not enforced by an active GitHub check rule. Do not represent those checks as
GitHub-enforced. Any CI-gate expansion needs its own reviewed configuration
change and confirmation that every named job actually runs for every target.

The accompanying policy PRs align the existing protected-target filters with
both kebab-case and legacy slash names. App hosting, desktop, mobile and both
Docker workflows include `release-*` / `hotfix-*`; app code guidelines use `**`
so legacy slash targets also run. SDK package tests include both release/hotfix
forms. Docker path filters and all job/test behavior remain unchanged.

Before a new release-target repair, ensure its source includes the applicable
trigger fix; otherwise a required app preview can remain pending without a run.
Existing RC heads are not advanced by this settings rollout. Backport the
workflow-only fix through a focused reviewed PR when needed; do not silently
import unrelated dev work.

## Source flow and review

Native merge-method restrictions do not prove that a feature began on dev,
that a hotfix began on main, or that a release carry contains only an approved
fix. Squashing deliberately changes ancestry. Reviewers must check source and
target, identify the accepted dev squash, compare the selected patch/content,
and record validation and resulting immutable SHAs. A `sync-*` name alone is
not evidence. The merge matrix and hotfix staging procedure are in Gitflow.

## Bypass and emergencies

Baseline rules preserve the existing organization-admin and repository-admin
**pull-request-only** bypass. That is a technical capability, not standing
permission for an agent to skip review, CI or release gates. A previous RC/dev
exception does not authorize a later main merge. Record owner authorization,
reason, failing/pending checks, method, target and exact reviewed SHA for each
exception. Keep the approved merge method even during a baseline bypass.

The new method rulesets themselves have no bypass actors. An emergency change
to them needs an explicit, recorded administrator decision, a configuration
backup and subsequent restoration. Do not disable protections, add an agent/app
bypass, rewrite dev or force-push a release branch as a routine workaround.

## Audit and update

Repository rule pages:

- [Wallet rules](https://github.com/GLEECBTC/gleec-wallet/rules)
- [SDK rules](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/rules)

Run the read-only drift audit with an authenticated GitHub CLI account:

```sh
python3 tool/check_gitflow_rules.py --repo GLEECBTC/gleec-wallet
python3 tool/check_gitflow_rules.py --repo GLEECBTC/komodo-defi-sdk-flutter
```

It compares the two native profiles and repository merge toggles. It does not
change settings, execute a merge, validate the human source-flow review or claim
CI/review success. Exit 0 means a match, 1 means policy drift, 2 means the audit
could not run. The copies of the profiles and audit tool in both repos must
remain identical; update them together through focused dev PRs.

For an approved configuration update, save the existing repository settings,
all affected rulesets and their IDs outside the checkout. Review the JSON diff;
apply only the two method rulesets and the three merge toggles. Use the existing
ID from `GET /repos/{owner}/{repo}/rulesets`, rather than creating a duplicate:

```sh
gh api --method PUT repos/OWNER/REPO/rulesets/ID \
  --input .github/rulesets/gitflow-dev-squash.json
```

Use the corresponding preserve-merges file for its ID. Re-read each ruleset,
run the drift audit and inspect `GET /repos/{owner}/{repo}/rules/branches/dev`
and `.../main`. Verify the effective allowed-method intersection, remaining
review/check requirements, and that main/release HEADs and RC PR states did not
move. Never test a rejection by attempting a real main merge.

Rollback only the managed method-layer changes from that backup: restore an
updated managed ruleset, or delete only a newly created managed ID, and restore
the previous repository merge toggles. Leave the baseline protections and CI
rules intact. Repeat the audit and record the administrator action. Reverting a
JSON file in Git alone does not change live GitHub settings.

[GitHub rule layering](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets#about-rule-layering)
and [merge-type restrictions](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets#require-a-pull-request-before-merging)
explain how native enforcement composes with these existing rules.
