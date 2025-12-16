# Gitflow and branching strategy

1. `dev` branch is created from `master`
2. A release branch is created from `dev` just before release (e.g. `release-0.4.2`)
3. Feature branches are created from `dev`
4. When a feature is complete it is merged into the `dev` branch
5. When the release branch is done it is merged into `master` and `dev`
6. If an issue in `master` is detected a hotfix branch is created from `master`
7. Once the hotfix is complete it is merged to both `dev` and `master`

[More...](https://www.atlassian.com/git/tutorials/comparing-workflows/gitflow-workflow)

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
- Hotfix branch (hotfixes based on `master` branch):
  - `hotfix-`
- Release branch:
  - `release-RELEASE.VERSION.NUMBER` (e.g. `release-0.4.2`)
- Sync branch (for resolving merging conflicts between release and dev branch after merging it to master):
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
