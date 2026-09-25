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

Unit tests pass and gate every PR. Run them:

```bash
flutter test test_units/main.dart \
  --dart-define=TRON_GASLESS_ENABLED=true \
  --dart-define=TRON_GASLESS_RECEIVE_ENABLED=true \
  --dart-define=TRON_GASLESS_BASE_URL=https://quicknode.gleec.com/gasfree/tron \
  --dart-define=TRON_GASLESS_SERVICE_PROVIDER=TLntW9Z59LYY5KEi9cmwk3PKjQga828ird
```

All four dart-defines are mandatory: without them ~36 GasFree tests hang rather than fail and wedge the whole run. CI runs *only* `test_units/main.dart`, so a new test file must be imported there or it never runs.

Integration/GUI tests (`dart run_integration_tests.dart`), the KDF harness, the SDK package suites, and the full CI map are documented in `docs/TESTING.md`. If a suite is red, name the failing test — do not generalise it to the others.

## Additional Documentation

### Code Styles/Standards

Follow the existing architecture and style of the codebase: BLoC where applicable, general OOP/SOLID guidelines. Commit messages and PR titles follow Conventional Commits (`type(scope): summary`).

### Gleec Wallet

Detailed instructions for building and running the app can be found in `docs/BUILD_RUN_APP.md` and other files in the `docs/` directory. See `README.md` for an overview of available documentation, and `docs/TESTING.md` for every test surface.

The majority of the crypto/API-related operations are abstracted out to the `komodo_defi_sdk` and its associated packages e.g. `komodo_defi_types`.

### Komodo DeFi Flutter SDK

The SDK is vendored into this repo as the `sdk/` submodule (upstream: `komodo-defi-sdk-flutter`). Its packages live in `sdk/packages/` — `komodo_defi_sdk`, `komodo_defi_types`, `komodo_defi_framework`, `komodo_defi_rpc_methods` and others. The top-level `packages/` directory is *not* the SDK; it holds app-owned packages (`komodo_ui_kit`, `komodo_persistence_layer`).

For features involving RPC requests, the typed request/response classes in `sdk/packages/komodo_defi_rpc_methods/lib/src/rpc_methods/` are the reference — they are grouped by domain (`activation/`, `hd_wallet/`, `transaction_history/`, `trading/`, …). Read the applicable request, its response shape, and its existing callers before adding one.

## PR Guidance

Commit messages should be clear and descriptive. When opening a pull request, summarize the purpose of the change and reference related issues when appropriate. Ensure commit messages and PR title follow the Conventional Commits standard.

<!-- The following sections are automatically generated during environment setup -->
