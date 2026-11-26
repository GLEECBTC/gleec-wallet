# Gitflow and branching strategy

This policy applies to Gleec Wallet and the Komodo DeFi Flutter SDK.
[Branch protection](BRANCH_PROTECTION.md) records the live enforcement,
versioned rule payloads, bypass limits and administration procedure.

## Branch flow and merge methods

The **destination branch** determines the merge method, even when the same
change is delivered to more than one branch.

| Destination | Permitted source / purpose | Merge method |
| --- | --- | --- |
| `dev` | Feature/fix branches; focused hotfix or release reconciliation | **Squash only** |
| `release-<version>` | Focused, reviewed fixes carried from dev through `sync-*` | **Merge commit only** |
| `main` | Reviewed `release-*` candidate or production `hotfix-*` | **Merge commit only** |
| `hotfix-*` | Focused fix PR into protected hotfix staging branch | **Merge commit only** |

Rebase merging is disabled. Do not enable linear history on main, release or
hotfix targets: it would prevent their required merge commits. Dev requires
linear history as an additional safeguard.

1. Create ordinary `add-*`, `improve-*`, `remove-*`, `fix-*` or `test-*` work
   from `dev`. Open the PR into dev and squash it after its reviews and checks.
   Use Conventional Commit PR titles and final commit messages.
2. Freeze a versioned release branch from the reviewed dev snapshot shortly
   before release. Open release → main as the RC PR and leave it open for
   testers/reviewers. Later dev work must not enter this candidate automatically.
3. For a freeze repair, first squash its focused PR into dev. Create `sync-*`
   from the frozen release and carry only that accepted fix through a separate
   release PR, merged normally. If merging a dev ref would import unrelated
   work, cherry-pick only the accepted patch and record both the original dev
   squash and carry commit. Compare the focused diff/content and rerun affected
   validation; branch names or ancestry alone do not establish equivalence.
4. The release owner promotes release → main with a merge commit after release
   gates pass. Tag/build from the recorded immutable main SHA. Release changes
   not already present on dev are reconciled through a focused **squash** PR;
   do not merge the entire release history into dev.
5. A production hotfix starts from main. Create the protected `hotfix-*` staging
   branch at that baseline and develop on a separate `fix-*` work branch when
   PR-only protections prevent direct changes. Merge its reviewed fix PR into
   hotfix staging, then hotfix → main normally. Deliver the same repair to dev
   through a focused **squash** PR and record its resulting dev SHA.
6. In the paired wallet/SDK release, promote SDK first, record its actual main
   SHA, then squash the app's immutable SDK repin into dev and carry it into the
   app release branch. Compare runtime content before app main promotion.

Always select the merge method explicitly in automation. For example:

```sh
gh pr merge <dev-pr> --squash --match-head-commit <reviewed-head-sha>
gh pr merge <release-pr> --merge --match-head-commit <reviewed-head-sha>
```

These examples document the release owner's procedure; they are not permission
for an agent to merge main. A request to prepare/freeze an RC does not authorize
main promotion. Main merges remain with the owner unless explicitly delegated.
Previous approval for an exceptional dev bypass is not standing permission to
skip future reviews, tests or production gates.

GitHub enforces the destination's merge method, PR requirement and existing
review/check rules. Review must still establish the allowed source, initial
branch point, approved patch scope and SDK pin. GitHub's branch rules cannot
prove selective carry or original ancestry after a squash.

## Branch naming conventions

### 1. Use short, clear, descriptive name

  | ❌ Bad                               |  ✅ Good             |
  | ------------------------------------ | --------------------- |
  | `patch-002`                          | `fix-logout-crash`    |
  | `build-for-ios-macos-universal_html` | `test-universal-html` |

### 2. Use prefixes to indicate branch type

- Feature branch (adding, improving, refactoring, or removing a feature):
  - `add-`
  - `improve-`
  - `remove-`
- Bug fix branch (regular bug fixes):
  - `fix-`
- Hotfix branch (hotfixes based on `main` branch):
  - `hotfix-`
- Release branch:
  - `release-RELEASE.VERSION.NUMBER` (e.g. `release-0.4.2`)
- Sync branch (focused release carries and reconciliation between release/main and dev):
  - `sync-`
- Test branch (testing, temp branches, etc):
  - `test-`

### 3. Avoid special characters (`/`, `>`, <https://github.com/GLEECBTC/komodowallet/issues/907>)

  | ❌ Bad            | ✅ Good         |
  | ----------------- | ---------------- |
  | `sync/0.4.2->dev` | `sync-0.4.2-dev` |

### 4. Prefer hyphen separator (kebab-case) over underscore (snake_case)

  | ❌ Bad             | ✅ Good           |
  | ------------------ | ------------------ |
  | `add_green_button` | `add-green-button` |

### 5. Avoid using issue IDs, SHA, etc. Release version is only allowed in release branches

  | ❌ Bad                | ✅ Good              |
  | --------------------- | --------------------- |
  | `dropdown-item-0.4.2` | `release-0.4.3`       |
  | `wasm-3f70b911b-demo` | `test-wasm-api`       |
  | `issue-514`           | `improve-seed-import` |
