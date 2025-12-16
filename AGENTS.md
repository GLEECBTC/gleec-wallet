# Repository Guidelines for Agents

This repository is a Flutter project. The environment has all Dart and Flutter dependencies pre-fetched during setup, but network access is disabled afterwards. Use the commands below to work with the project.

## Setup

```bash
flutter pub get --enforce-lockfile
```

If the above fails due to the offline environment, add the `--offline` flag.

## Static Analysis and Formatting

Run analysis and formatting (only on changed files) before committing code:

```bash
flutter analyze

dart format [files]

```

## Running Tests

Unit tests and integration tests are currently failing. Instead of running tests to validate fixes, do a thorough code review of the changes and static analysis

## Additional Documentation

### Code Styles/Standards

Ensure you follow the existing architecture and style of the codebase. The codebase uses BLoC where applicable and follows general OOP/SOLID coding guidelines. Familiarise yourself with the BLoC conventions and Conventional Commits standards included at the end of this document.

### Gleec Wallet

This section is only relevant if you are working in the `gleec-wallet` repository:

Detailed instructions for building and running the app can be found in `docs/BUILD_RUN_APP.md` and other files in the `docs/` directory. See `README.md` for an overview of available documentation.

The majority of the crypto/API-related operations are abstracted out to the `komodo_defi_sdk` and its associated packages e.g. `komodo_defi_types`.

# Komodo DeFi Flutter SDK

This section is only relevant if you are working in the `komodo-defi-sdk-flutter` repository:

The repository consists of a suite of packages (in the `packages` directory) which make up a Flutter SDK package `komodo_defi_sdk` used for implementing Komodo DeFi into Flutter apps.

The KDF API documentation can be found in the root folder at `/KDF_API_DOCUMENTATION.md`. For any features involving RPC requests, ensure you reference and understand all applicable RPCs, data structure and general notes needed to implement the feature in the SDK.

## PR Guidance

Commit messages should be clear and descriptive. When opening a pull request, summarize the purpose of the change and reference related issues when appropriate. Ensure commit messages and PR title follow the Conventional Commits standard as described in the standards section below.

<!-- The following sections are automatically generated during environment setup -->
