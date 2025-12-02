# SDK Dependency Management

This document describes how to manage SDK dependencies in the Gleec Wallet project.

## SDK Dependencies

The Gleec Wallet relies on several SDK packages maintained in the [komodo-defi-sdk-flutter](https://github.com/GLEECBTC/komodo-defi-sdk-flutter) repository. These packages include:

- `komodo_cex_market_data`
- `komodo_defi_sdk`
- `komodo_defi_types`
- `komodo_ui`
- and others

## Automated Updates with GitHub Actions

We have an automated process to update these SDK dependencies using a GitHub Actions workflow. This workflow runs:

- Daily at midnight
- When code is pushed to the `dev` branch
- Manually through the GitHub Actions UI

### Manual Trigger in GitHub Actions

To manually trigger the SDK roll workflow:

1. Go to the [GitHub Actions tab](https://github.com/GLEECBTC/gleec-wallet/actions)
2. Select the "Roll SDK Packages" workflow
3. Click "Run workflow"
4. Configure options:
   - **Upgrade all packages**: Set to `true` to upgrade all dependencies, not just SDK packages
   - **Target branch**: Specify which branch the pull request should target (defaults to `dev`)
5. Click "Run workflow"

## Running the SDK Roll Script Manually

For development or testing purposes, you can run the SDK roll script manually on your local machine.

### Prerequisites

- Flutter development environment set up
- Git configured
- Access to the repository

### Steps to Run Manually

1. Clone the repository if you haven't already:

   ```bash
   git clone https://github.com/GLEECBTC/gleec-wallet.git
   cd komodo-wallet
   ```

2. Make the script executable:

   ```bash
   chmod +x .github/scripts/roll_sdk_packages.sh
   ```

3. Run the script with the desired parameters:

   **To update only SDK packages (default):**

   ```bash
   UPGRADE_ALL_PACKAGES=false TARGET_BRANCH=dev .github/scripts/roll_sdk_packages.sh
   ```

   **To update all packages:**

   ```bash
   UPGRADE_ALL_PACKAGES=true TARGET_BRANCH=dev .github/scripts/roll_sdk_packages.sh
   ```

4. Review the changes:

   - The script will create a file called `SDK_CHANGELOG.md` with details of all packages that were updated
   - Check the changes in the `pubspec.yaml` and `pubspec.lock` files

5. If you want to commit these changes:

   ```bash
   git add **/pubspec.yaml **/pubspec.lock
   git commit -m "chore: roll SDK packages"
   git push
   ```

### Script Parameters

The script accepts the following environment variables:

- `UPGRADE_ALL_PACKAGES`: Set to `true` to upgrade all packages, not just SDK packages. Defaults to `false`.
- `TARGET_BRANCH`: The target branch for the changelog information. Defaults to `dev`.

## Troubleshooting

### No Updates Found

If the script exits with a message "No rolls needed", it means that either:

1. All SDK packages are already at their latest versions
2. The script couldn't find any SDK packages in your project

You can check by examining your `pubspec.yaml` files to ensure they contain references to the SDK packages.

### Understanding Exit Codes

The script uses the following exit codes:

- `0`: Success - SDK packages were rolled successfully
- `100`: No updates needed - the script ran correctly but no packages needed updating
- Any other code: An error occurred during the execution

### Script Execution Issues

If you encounter permission issues:

```bash
chmod +x .github/scripts/roll_sdk_packages.sh
```

If Flutter commands fail, ensure your Flutter environment is properly set up:

```bash
flutter doctor
```

## SDK Package Identification

The script identifies SDK packages by looking for packages with names matching those in the `SDK_PACKAGES` array in the script. These refer to external packages from the GLEECBTC SDK repository and can be declared in your `pubspec.yaml` files in two ways:

- Git dependency (Option 2): declared with a `git:` section pointing to the `GLEECBTC/komodo-defi-sdk-flutter` repository
- Hosted dependency (Option 3): declared as a standard hosted package on pub.dev with a version constraint (for example, `^0.3.0`)

Local packages that are part of this repository (like `komodo_ui_kit` and `komodo_persistence_layer`) are not considered external SDK packages and will not be updated by this script unless they themselves depend on SDK packages.

When running in SDK-only mode (`UPGRADE_ALL_PACKAGES=false`):

- Hosted SDK dependencies are bumped to the latest available version on pub.dev by executing `flutter pub add <package>`, which updates the version constraint in `pubspec.yaml` and refreshes the lockfile.
- Git-based SDK dependencies are refreshed with `flutter pub upgrade --unlock-transitive <packages>` to update the lockfile according to the configured `ref`.

## Error Handling

The SDK roll script and GitHub Actions workflow are designed with robust error handling to ensure reliable operation. Here's what you should know:

### Shell Script Error Handling

- The script uses `set -e` to exit immediately if any command fails
- It includes a cleanup function that runs on exit to handle any temporary files
- Specific handling for package upgrade failures allows the script to continue even if individual package upgrades fail
- Clear logging with different levels (info, warning, error) to help diagnose issues

### Exit Codes

- **0**: Success - changes were made and applied
- **100**: No changes needed - everything ran correctly, but no packages needed updating (this is not an error)
- **Any other code**: An actual error occurred during execution

### GitHub Actions Workflow Error Handling

The GitHub Actions workflow has additional safeguards:

- Proper detection of the roll script's exit codes to differentiate between "no updates needed" and actual errors
- Error handling for git operations, including branch deletion and pushing
- Fallback mechanisms for GitHub CLI operations
- Warning and error annotations in the workflow logs to make issues more visible

### Common Issues

1. **Access Permission Issues**:

   - The GitHub token might not have sufficient permissions
   - Solution: Check repository permissions for the GitHub token

2. **Branch Protection Rules**:

   - If the target branch has protection rules, the workflow might fail to push changes
   - Solution: Adjust branch protection rules or use a different target branch

3. **Flutter Environment Issues**:

   - Mismatched Flutter versions can cause package incompatibilities
   - Solution: Ensure the Flutter version specified in the workflow matches what's used in development

4. **Network or GitHub API Issues**:
   - Temporary GitHub API issues can cause the workflow to fail
   - Solution: Re-run the workflow after a delay
