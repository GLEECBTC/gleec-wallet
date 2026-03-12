# Main Project Diff Review Findings

## 1. Scope

- Exact repo reviewed: `/Users/charl/Code/UTXO/gleec-wallet-dev`
- Exact diff reviewed: `dev...codex/upgrade-flutter-3-41-native-host`
- Exact refs resolved: `dev` = `bd09e34050e1a5ef2e167a354a80ddcfcaf009f5`, `codex/upgrade-flutter-3-41-native-host` = `9fad5f504cb2a8588fcb2143bb4b0a732011d69f`
- Review date: 2026-03-12
- Changed files reviewed: 213

## 2. Review Summary

- Overall verdict: Not ready to merge.
- Count of findings by severity: `Blocker: 0`, `High: 2`, `Medium: 5`, `Low: 0`
- Key risk themes:
  - ZHTLC activation cleanup now leaves in-flight work running after sign-out/dispose.
  - Tendermint transaction history regressed in two ways: it can both duplicate one lifecycle update and collapse distinct same-hash transfers.
  - The desktop/web header account control regressed from an interactive dropdown to a static label.
  - QA automation can now false-pass critical tests and lose intended failure/report handling.
  - Balance fallback polling is disabled globally whenever any watcher exists, leaving other assets vulnerable to stale balances.

## 2.1 Resolution Tracking (Post-review)

- Status snapshot date: `2026-03-12`
- Historical note: Sections below remain the original review record. Resolution states here reflect the current workspace.
- Findings already resolved in current workspace:
  - `F001` Resolved in local changes to `lib/services/arrr_activation/arrr_activation_service.dart`
  - `F002` Resolved in local changes to `lib/bloc/transaction_history/transaction_history_bloc.dart`
  - `F003` Resolved in local changes to `lib/views/common/header/actions/account_switcher.dart`
  - `F005` Resolved in local changes to `lib/bloc/transaction_history/transaction_history_bloc.dart`
- Findings resolved by this patch:
  - `F004` Resolved via strict majority-based early-exit logic in `automated_testing/runner/retry.py`
  - `F006` Resolved via per-asset watcher coverage checks and watcher termination handling in `lib/bloc/coins_bloc/coins_repo.dart` + `lib/bloc/coins_bloc/coins_bloc.dart`
  - `F007` Resolved via `set -e`-safe exit capture and artifact handling flow in `automated_testing/ci-pipeline.sh`
- Architecture alignment in current workspace:
  - Balance coverage checks are now exposed from SDK balance management and consumed from app-layer coin polling logic.
  - Transaction lifecycle reconciliation/ordering is exposed as a high-level merged SDK stream and consumed by the transaction history bloc.

## 3. Findings

### F001
- Severity: `High`
- Repo: `Main`
- Diff: `dev...codex/upgrade-flutter-3-41-native-host`
- File path and line numbers: `lib/services/arrr_activation/arrr_activation_service.dart:327-331,454-457,543-546`
- Title: Sign-out cleanup no longer cancels in-flight ZHTLC activations
- Why this is a bug, regression, or missing edge-case handling: The new cancellation path only stops work when `_cancelledActivations` contains the asset ID, but `_cleanupOnSignOut()` and `dispose()` now call `clear()` on that set instead of marking active assets as cancelled. That means an activation/retry loop already running in `_performActivation()` keeps executing after auth teardown, even though the service has already cleared the UI cache and pending configuration state.
- Concrete scenario or failure mode: Start an ARRR/ZHTLC activation, then sign out before it completes. The status bar disappears because cached state is cleared, but the activation future keeps retrying in the background and can still finish or fail against the torn-down session, producing stale status/error writes after logout.
- Recommended fix direction: During sign-out/dispose, mark every active asset in `_ongoingActivations` (and any cached activation entries) as cancelled before clearing UI state, and only clear the cancellation markers after the outstanding activation futures have finished or been abandoned safely.

### F004
- Severity: `High`
- Repo: `Main`
- Diff: `dev...codex/upgrade-flutter-3-41-native-host`
- File path and line numbers: `automated_testing/runner/retry.py:66-81`
- Title: Critical retry logic can declare success before a majority is possible
- Why this is a bug, regression, or missing edge-case handling: `should_stop_early()` now exits as soon as there are two `PASS` attempts or two all-`ERROR` attempts, regardless of `max_attempts`. `run_test_with_retries()` applies this to critical-tagged tests that are configured for 5 attempts, so the code can return a final vote after only 2 runs even though a 5-attempt majority has not been established.
- Concrete scenario or failure mode: A critical test gets `PASS`, `PASS`, `FAIL`, `FAIL`, `FAIL` in a real 5-attempt run. With the current early-stop logic, the runner exits after the second attempt and records a final `PASS`, defeating the majority-vote safeguard that the matrix is relying on.
- Recommended fix direction: Only early-exit when the leading status has already crossed the true majority threshold for `max_attempts` or when the remaining attempts can no longer change the outcome.

### F002
- Severity: `Medium`
- Repo: `Main`
- Diff: `dev...codex/upgrade-flutter-3-41-native-host`
- File path and line numbers: `lib/bloc/transaction_history/transaction_history_bloc.dart:113-156,217-252,312-369`
- Title: Tendermint history now collapses distinct same-hash transfers into one entry
- Why this is a bug, regression, or missing edge-case handling: `_usesTxHashLookup()` now treats `txHash` as the canonical identity for every Tendermint/Tendermint-token history item. `_findExistingTransactionInternalId()` reuses the first internal ID seen for that hash, and later events with the same hash are merged into the existing row. Cosmos-family transactions can legitimately contain multiple transfer messages/events for the same wallet under one transaction hash, so this loses real history entries instead of only deduplicating pending-to-confirmed updates.
- Concrete scenario or failure mode: A multisend or multi-message Cosmos transaction yields two wallet-visible transfers with the same `txHash` but different `internalId` values. After this change, only one row remains in history; the surviving row may carry the wrong amount, memo, or confirmation data for one of the messages.
- Recommended fix direction: Limit the `txHash` fallback to the specific pending/confirmed churn the SDK emits, or key Tendermint entries with a more specific composite identifier (for example `txHash + message/event index` or another stable per-event discriminator) instead of `txHash` alone.

### F005
- Severity: `Medium`
- Repo: `Main`
- Diff: `dev...codex/upgrade-flutter-3-41-native-host`
- File path and line numbers: `lib/bloc/transaction_history/transaction_history_bloc.dart:110-142,206-226,268-276`
- Title: Tendermint pending transactions can duplicate when `txHash` appears later
- Why this is a bug, regression, or missing edge-case handling: `_transactionKey()` uses `internalId` until a Tendermint transaction gains a non-empty `txHash`, then switches identity to `txHash`. The merge maps in both subscription paths are rebuilt from current state using that derived key, so a pending item first seen without a hash is no longer matched when the confirmed update for the same lifecycle arrives with a hash.
- Concrete scenario or failure mode: A Tendermint transfer is first streamed as pending with `internalId=abc` and empty `txHash`, then re-emitted after broadcast with `txHash=0x123`. The second event gets a different merge key and the history list ends up with two rows for the same transaction lifecycle instead of one updated row.
- Recommended fix direction: Keep a stable lifecycle key from first sighting to confirmation, or explicitly bridge `internalId` to `txHash` when the hash first appears instead of switching keys mid-stream.

### F003
- Severity: `Medium`
- Repo: `Main`
- Diff: `dev...codex/upgrade-flutter-3-41-native-host`
- File path and line numbers: `lib/views/common/header/actions/account_switcher.dart:17-23,31-61`
- Title: Header account switcher became a non-interactive label
- Why this is a bug, regression, or missing edge-case handling: The previous `UiDropdown` + `LogOutPopup` flow was removed and replaced with a plain `_AccountSwitcher` widget inside `ConnectWalletWrapper`. In the logged-in state there is now no tap target, dropdown, logout action, or wallet-switch affordance attached to the control at all.
- Concrete scenario or failure mode: On the main desktop/web layout, clicking the current account name/icon in the top bar no longer does anything. Users lose the header-level logout/switch flow that existed before this diff and must find a different route through settings.
- Recommended fix direction: Restore an interactive top-bar control for logged-in users, either by reinstating the dropdown/menu or by wiring the header control to the wallet manager/logout dialog explicitly.

### F006
- Severity: `Medium`
- Repo: `Main`
- Diff: `dev...codex/upgrade-flutter-3-41-native-host`
- File path and line numbers: `lib/bloc/coins_bloc/coins_bloc.dart:237-249`, `lib/bloc/coins_bloc/coins_repo.dart:82-84,124-146`
- Title: One active balance watcher disables fallback polling for every asset
- Why this is a bug, regression, or missing edge-case handling: The 3-minute fallback refresh now returns early whenever `CoinsRepo.hasActiveBalanceWatchers` is true, but that flag is global and only means at least one asset has a watcher entry. It does not guarantee every enabled asset currently has a healthy live balance subscription.
- Concrete scenario or failure mode: A wallet has one coin with a live balance watcher and another coin whose watcher was never started, silently ended, or is unsupported. Because `_balanceWatchers.isNotEmpty` stays true, `CoinsBalancesRefreshed()` never fires for the second coin and its displayed balance can remain stale indefinitely.
- Recommended fix direction: Gate fallback polling per asset or per unsupported/dead watcher rather than with a single global boolean, and treat watcher termination/error as a signal to resume polling coverage.

### F007
- Severity: `Medium`
- Repo: `Main`
- Diff: `dev...codex/upgrade-flutter-3-41-native-host`
- File path and line numbers: `automated_testing/ci-pipeline.sh:1-2,39-62`
- Title: CI pipeline exits before it can record smoke/full runner failures
- Why this is a bug, regression, or missing edge-case handling: The script enables `set -euo pipefail` and then executes the smoke and full runner commands directly before reading `$?`. Under `set -e`, any non-zero exit from those commands terminates the script immediately, so the later branching that distinguishes infra failure from test failure and copies reports is skipped.
- Concrete scenario or failure mode: The smoke gate returns exit code `1`. Instead of copying the available report and exiting through the documented smoke-failure path, the shell aborts on line 40 and the artifact-handling block never runs.
- Recommended fix direction: Capture those runner exit codes in an `if` block or temporarily disable `errexit` around the commands whose status is intentionally inspected.

## 4. Static Analysis

- Main repo `flutter analyze` result: failed with `3072 issues found`.
- Pre-existing analyzer noise dominates the result set. The failing tail is concentrated in `sdk/products/komodo_compliance_console/test/**` unresolved imports/undefined symbols, plus existing test-only lint noise in `test_integration/**` and `test_units/**`.
- Targeted analyzer spot-check on key changed app files (`lib/services/arrr_activation/arrr_activation_service.dart`, `lib/bloc/transaction_history/transaction_history_bloc.dart`, `lib/bloc/withdraw_form/withdraw_form_bloc.dart`, `lib/views/wallet/coin_details/withdraw_form/withdraw_form.dart`) reported only 4 info-level issues (`implementation_imports`, one `unnecessary_import`, and two `curly_braces_in_flow_control_structures`).
- Diff-related analyzer issues identified at error/warning level: none from the targeted app-file spot-check; the repo-wide failure remains dominated by existing SDK/test noise outside this branch diff.
- `flutter analyze` does not cover the new `automated_testing/**` Python/bash files, so the QA-runner findings above come from manual code review rather than Dart analyzer output.

## 5. Residual Risks and Verification Gaps

- Native-host and WASM changes still need manual launch verification on Android, iOS, Linux, Windows, and hosted web with COEP/COOP headers. Static review cannot prove startup/runtime behavior across every host.
- The `sdk` submodule pointer was reviewed for integration fit and the high-level commit delta was inspected, but this was not a full SDK-internal audit of every downstream package.
- Per repository guidance, unreliable unit/integration tests were not used as acceptance criteria. This review therefore relies on code inspection plus analyzer output rather than runtime regression tests.

## 6. Reviewed Files Appendix

| Repo | Diff | Status | File | Findings | Notes |
| --- | --- | --- | --- | --- | --- |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `.docker/build.sh` | None | Build/deployment config |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `.github/actions/generate-assets/action.yml` | None | Build/deployment config |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `.gitignore` | None | Application update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `.metadata` | None | Application update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `android/app/build.gradle` | None | Native host/build upgrade |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `android/app/src/main/java/com/komodoplatform/atomicdex/MainActivity.java` | None | Native host/build upgrade |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `android/settings.gradle` | None | Native host/build upgrade |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `app_theme/pubspec.yaml` | None | Dependency/version update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `assets/translations/en.json` | None | Localization update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `automated_testing/.env.example` | None | QA automation bundle |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `automated_testing/GLEEC_WALLET_MANUAL_TEST_CASES.md` | None | QA automation bundle |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `automated_testing/ci-pipeline.sh` | F007 | QA automation bundle |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `automated_testing/docker-compose.yml` | None | QA automation bundle |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `automated_testing/gleec-qa-architecture.md` | None | QA automation bundle |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `automated_testing/gleec-qa-evaluation.md` | None | QA automation bundle |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `automated_testing/manual_companion.yaml` | None | QA automation bundle |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `automated_testing/requirements.txt` | None | QA automation bundle |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `automated_testing/runner/__init__.py` | None | QA automation bundle |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `automated_testing/runner/__main__.py` | None | QA automation bundle |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `automated_testing/runner/guards.py` | None | QA automation bundle |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `automated_testing/runner/interactive.py` | None | QA automation bundle |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `automated_testing/runner/models.py` | None | QA automation bundle |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `automated_testing/runner/ollama_monitor.py` | None | QA automation bundle |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `automated_testing/runner/os_automation.py` | None | QA automation bundle |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `automated_testing/runner/playwright_helpers.py` | None | QA automation bundle |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `automated_testing/runner/preflight.py` | None | QA automation bundle |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `automated_testing/runner/prompt_builder.py` | None | QA automation bundle |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `automated_testing/runner/reporter.py` | None | QA automation bundle |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `automated_testing/runner/retry.py` | F004 | QA automation bundle |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `automated_testing/runner/runner.py` | None | QA automation bundle |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `automated_testing/setup.sh` | None | QA automation bundle |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `automated_testing/test_matrix.yaml` | None | QA automation bundle |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `docs/BUILD_RELEASE.md` | None | Documentation/process update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `docs/BUILD_RUN_APP.md` | None | Documentation/process update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `docs/BUILD_SECURITY_ADVISORY.md` | None | Documentation/process update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `docs/FLUTTER_VERSION.md` | None | Documentation/process update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `docs/GLEEC_SERVICE_AUDIT_MATRIX.md` | None | Documentation/process update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `docs/GLEEC_UNIFIED_APP_EXECUTIVE_BRIEF.md` | None | Documentation/process update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `docs/GLEEC_UNIFIED_APP_PLAN.md` | None | Documentation/process update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `docs/GLEEC_UNIFIED_APP_PRD.md` | None | Documentation/process update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `docs/GLEEC_UNIFIED_APP_UX_SPEC.md` | None | Documentation/process update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `docs/GLEEC_UNIFIED_APP_WIREFRAME_BRIEFS.md` | None | Documentation/process update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `docs/MULTIPLE_FLUTTER_VERSIONS.md` | None | Documentation/process update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `docs/POLISH_ISSUES_GAME_PLAN.md` | None | Documentation/process update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `docs/QA_TEST_CASE_GENERATION_PROMPT.md` | None | Documentation/process update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `docs/SDK_APP_FULL_DIFF_REVIEW_PROMPT.md` | None | Documentation/process update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `docs/UNIFIED_GLEEC_APP_PRODUCT_PLAN.md` | None | Documentation/process update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `docs/UNLOCALIZED_TEXT.md` | None | Documentation/process update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `firebase.json` | None | Build/deployment config |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `ios/Flutter/AppFrameworkInfo.plist` | None | Native host/build upgrade |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `ios/Podfile` | None | Native host/build upgrade |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `ios/Podfile.lock` | None | Native host/build upgrade |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `ios/Runner.xcodeproj/project.pbxproj` | None | Native host/build upgrade |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `ios/Runner/AppDelegate.swift` | None | Native host/build upgrade |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `ios/Runner/Info.plist` | None | Native host/build upgrade |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `ios/Runner/SceneDelegate.swift` | None | Native host/build upgrade |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/app_config/package_information.dart` | None | Web/WASM/platform integration |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/bloc/app_bloc_root.dart` | None | Web/WASM/platform integration |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/bloc/auth_bloc/auth_bloc.dart` | None | Wallet auth/import/manager flow |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/bloc/auth_bloc/trezor_auth_mixin.dart` | None | Wallet auth/import/manager flow |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/bloc/bridge_form/bridge_repository.dart` | None | DEX/bridge/trading flow |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/bloc/bridge_form/bridge_validator.dart` | None | DEX/bridge/trading flow |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/bloc/cex_market_data/models/adapters/graph_cache_adapter.dart` | None | Market-data/chart update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/bloc/cex_market_data/models/adapters/point_adapter.dart` | None | Market-data/chart update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/bloc/cex_market_data/portfolio_growth/portfolio_growth_repository.dart` | None | Market-data/chart update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/bloc/cex_market_data/profit_loss/models/adapters/fiat_value_adapter.dart` | None | Market-data/chart update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/bloc/cex_market_data/profit_loss/models/adapters/profit_loss_adapter.dart` | None | Market-data/chart update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/bloc/cex_market_data/profit_loss/models/adapters/profit_loss_cache_adapter.dart` | None | Market-data/chart update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/bloc/cex_market_data/profit_loss/profit_loss_repository.dart` | None | Market-data/chart update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/bloc/coin_addresses/bloc/coin_addresses_bloc.dart` | None | Wallet asset/address UI |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/bloc/coins_bloc/coins_bloc.dart` | F006 | Wallet asset/address UI |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/bloc/coins_bloc/coins_repo.dart` | None | Wallet asset/address UI |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/bloc/dex_repository.dart` | None | DEX/bridge/trading flow |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/bloc/settings/settings_bloc.dart` | None | Settings/general UI update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/bloc/settings/settings_event.dart` | None | Settings/general UI update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/bloc/settings/settings_state.dart` | None | Settings/general UI update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/bloc/taker_form/taker_validator.dart` | None | DEX/bridge/trading flow |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/bloc/transaction_history/transaction_history_bloc.dart` | F002, F005 | History presentation/update logic |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/bloc/version_info/version_info_bloc.dart` | None | Application update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/bloc/version_info/version_info_state.dart` | None | Application update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/bloc/withdraw_form/withdraw_form_bloc.dart` | None | Withdrawal flow |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/bloc/withdraw_form/withdraw_form_event.dart` | None | Withdrawal flow |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/bloc/withdraw_form/withdraw_form_state.dart` | None | Withdrawal flow |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/blocs/orderbook_bloc.dart` | None | DEX/bridge/trading flow |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/blocs/trading_entities_bloc.dart` | None | DEX/bridge/trading flow |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/dispatchers/popup_dispatcher.dart` | None | Web/WASM/platform integration |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/generated/codegen_loader.g.dart` | None | Localization update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/main.dart` | None | Web/WASM/platform integration |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/mm2/mm2_api/rpc/rpc_error.dart` | None | Application update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/mm2/mm2_api/rpc/rpc_error_type.dart` | None | Application update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/mm2/rpc_web.dart` | None | Web/WASM/platform integration |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/model/coin_utils.dart` | None | Application update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/model/kdf_auth_metadata_extension.dart` | None | Wallet auth/import/manager flow |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/model/settings/market_maker_bot_settings.dart` | None | Application update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/model/stored_settings.dart` | None | Settings/general UI update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/model/wallet.dart` | None | Wallet auth/import/manager flow |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/platform/platform.dart` | None | Web/WASM/platform integration |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/platform/platform_native.dart` | None | Web/WASM/platform integration |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/platform/platform_web.dart` | None | Web/WASM/platform integration |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/router/navigators/main_layout/main_layout_router_delegate.dart` | None | Application update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/sdk/widgets/window_close_handler.dart` | None | Web/WASM/platform integration |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/services/arrr_activation/arrr_activation_service.dart` | F001 | ZHTLC activation flow |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/services/file_loader/file_loader.dart` | None | Web/WASM/platform integration |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/services/initializer/app_bootstrapper.dart` | None | Application update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/services/platform_info/platform_info.dart` | None | Web/WASM/platform integration |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/services/platform_info/web_platform_info.dart` | None | Web/WASM/platform integration |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/services/platform_web_api/platform_web_api.dart` | None | Web/WASM/platform integration |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/services/platform_web_api/platform_web_api_implementation.dart` | None | Web/WASM/platform integration |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/services/platform_web_api/platform_web_api_stub.dart` | None | Web/WASM/platform integration |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/services/platform_web_api/platform_web_api_web.dart` | None | Web/WASM/platform integration |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/shared/constants.dart` | None | Application update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/shared/ui/ui_tab_bar/ui_tab_bar.dart` | None | Shared UI/utility update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/shared/utils/hd_wallet_mode_preference.dart` | None | Wallet auth/import/manager flow |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/shared/utils/kdf_error_display.dart` | None | Shared UI/utility update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/shared/utils/swap_export.dart` | None | Shared UI/utility update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/shared/utils/validators.dart` | None | Shared UI/utility update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/shared/utils/window/window.dart` | None | Web/WASM/platform integration |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/shared/widgets/coin_balance.dart` | None | Settings/general UI update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/shared/widgets/coin_fiat_balance.dart` | None | Settings/general UI update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/shared/widgets/coin_select_item_widget.dart` | None | Settings/general UI update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/shared/widgets/connect_wallet/connect_wallet_button.dart` | None | Wallet auth/import/manager flow |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/shared/widgets/remember_wallet_service.dart` | None | Wallet auth/import/manager flow |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/common/header/actions/account_switcher.dart` | F003 | Shared UI/utility update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/common/hw_wallet_dialog/hw_dialog_wallet_select.dart` | None | Shared UI/utility update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/common/hw_wallet_dialog/trezor_steps/trezor_dialog_select_wallet.dart` | None | Shared UI/utility update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/common/main_menu/main_menu_bar_mobile.dart` | None | Shared UI/utility update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/common/main_menu/main_menu_desktop.dart` | None | Shared UI/utility update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/dex/dex_helpers.dart` | None | DEX/bridge/trading flow |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/dex/dex_list_filter/mobile/dex_list_header_mobile.dart` | None | DEX/bridge/trading flow |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/dex/entities_list/common/swap_actions_menu.dart` | None | DEX/bridge/trading flow |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/dex/entities_list/history/history_item.dart` | None | History presentation/update logic |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/dex/entities_list/history/history_list.dart` | None | History presentation/update logic |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/dex/entities_list/history/swap_history_sort_mixin.dart` | None | History presentation/update logic |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/dex/entities_list/in_progress/in_progress_item.dart` | None | DEX/bridge/trading flow |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/dex/entities_list/orders/order_item.dart` | None | DEX/bridge/trading flow |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/dex/entity_details/swap/swap_details_page.dart` | None | DEX/bridge/trading flow |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/dex/entity_details/swap/swap_details_step.dart` | None | DEX/bridge/trading flow |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/dex/entity_details/trading_details.dart` | None | DEX/bridge/trading flow |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/dex/simple/form/maker/maker_form_trade_button.dart` | None | DEX/bridge/trading flow |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/dex/simple/form/tables/coins_table/coins_table_item.dart` | None | DEX/bridge/trading flow |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/dex/simple/form/taker/available_balance.dart` | None | DEX/bridge/trading flow |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/dex/simple/form/taker/coin_item/coin_group_name.dart` | None | DEX/bridge/trading flow |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/dex/simple/form/taker/taker_form_content.dart` | None | DEX/bridge/trading flow |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/main_layout/main_layout.dart` | None | Application update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/main_layout/widgets/main_layout_top_bar.dart` | None | Settings/general UI update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/market_maker_bot/coin_search_dropdown.dart` | None | DEX/bridge/trading flow |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/market_maker_bot/market_maker_bot_form.dart` | None | DEX/bridge/trading flow |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/market_maker_bot/market_maker_bot_form_content.dart` | None | DEX/bridge/trading flow |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/market_maker_bot/market_maker_bot_page.dart` | None | DEX/bridge/trading flow |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/market_maker_bot/trade_bot_update_interval.dart` | None | DEX/bridge/trading flow |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/nfts/nft_main/nft_main_controls.dart` | None | NFT UI update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/nfts/nft_tabs/nft_tab.dart` | None | NFT UI update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/nfts/nft_transactions/mobile/widgets/nft_txn_mobile_filter_card.dart` | None | NFT UI update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/nfts/nft_transactions/mobile/widgets/nft_txn_mobile_filters.dart` | None | NFT UI update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/settings/widgets/general_settings/app_version_number.dart` | None | Settings/general UI update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/settings/widgets/general_settings/general_settings.dart` | None | Settings/general UI update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/settings/widgets/general_settings/settings_hide_balances.dart` | None | Settings/general UI update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/settings/widgets/general_settings/settings_manage_trading_bot.dart` | None | Settings/general UI update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/settings/widgets/settings_menu/settings_logout_button.dart` | None | Settings/general UI update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/wallet/coin_details/coin_details_info/charts/portfolio_growth_chart.dart` | None | Wallet asset/address UI |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/wallet/coin_details/coin_details_info/charts/portfolio_profit_loss_chart.dart` | None | Wallet asset/address UI |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/wallet/coin_details/coin_details_info/coin_addresses.dart` | None | Wallet asset/address UI |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/wallet/coin_details/coin_details_info/coin_details_info.dart` | None | Wallet asset/address UI |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/wallet/coin_details/faucet/faucet_view.dart` | None | Wallet asset/address UI |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/wallet/coin_details/transactions/transaction_details.dart` | None | History presentation/update logic |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/wallet/coin_details/transactions/transaction_list_item.dart` | None | History presentation/update logic |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/wallet/coin_details/withdraw_form/widgets/fill_form/fields/fields.dart` | None | Withdrawal flow |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/wallet/coin_details/withdraw_form/widgets/fill_form/fields/fill_form_memo.dart` | None | Withdrawal flow |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/wallet/coin_details/withdraw_form/widgets/send_complete_form/send_complete_form.dart` | None | Withdrawal flow |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/wallet/coin_details/withdraw_form/widgets/send_confirm_form/send_confirm_form.dart` | None | Withdrawal flow |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/wallet/coin_details/withdraw_form/withdraw_form.dart` | None | Withdrawal flow |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/wallet/coins_manager/coins_manager_controls.dart` | None | Wallet asset/address UI |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/wallet/coins_manager/coins_manager_helpers.dart` | None | Wallet asset/address UI |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/wallet/coins_manager/coins_manager_list_item.dart` | None | Wallet asset/address UI |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/wallet/coins_manager/coins_manager_list_wrapper.dart` | None | Wallet asset/address UI |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/wallet/coins_manager/coins_manager_select_all_button.dart` | None | Wallet asset/address UI |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/wallet/wallet_page/charts/coin_prices_chart.dart` | None | Wallet asset/address UI |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/wallet/wallet_page/charts/price_chart_tooltip.dart` | None | Wallet asset/address UI |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/wallet/wallet_page/common/expandable_coin_list_item.dart` | None | Wallet asset/address UI |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/wallet/wallet_page/common/expandable_private_key_list.dart` | None | Wallet asset/address UI |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/wallet/wallet_page/common/grouped_assets_list.dart` | None | Wallet asset/address UI |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/wallet/wallet_page/common/zhtlc/zhtlc_activation_status_bar.dart` | None | ZHTLC activation flow |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/wallet/wallet_page/wallet_main/active_coins_list.dart` | None | Wallet asset/address UI |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/wallet/wallet_page/wallet_main/balance_summary_widget.dart` | None | Wallet asset/address UI |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/wallet/wallet_page/wallet_main/wallet_main.dart` | None | Wallet asset/address UI |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/wallet/wallet_page/wallet_main/wallet_overview.dart` | None | Wallet asset/address UI |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/wallets_manager/wallets_manager_wrapper.dart` | None | Wallet auth/import/manager flow |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/wallets_manager/widgets/custom_seed_dialog.dart` | None | Wallet auth/import/manager flow |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/wallets_manager/widgets/wallet_creation.dart` | None | Wallet auth/import/manager flow |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/wallets_manager/widgets/wallet_import_by_file.dart` | None | Wallet auth/import/manager flow |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/wallets_manager/widgets/wallet_import_type_dropdown.dart` | None | Wallet auth/import/manager flow |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/wallets_manager/widgets/wallet_list_item.dart` | None | Wallet auth/import/manager flow |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/wallets_manager/widgets/wallet_login.dart` | None | Wallet auth/import/manager flow |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/wallets_manager/widgets/wallet_rename_dialog.dart` | None | Wallet auth/import/manager flow |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `lib/views/wallets_manager/widgets/wallet_simple_import.dart` | None | Wallet auth/import/manager flow |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `linux/CMakeLists.txt` | None | Native host/build upgrade |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `macos/Podfile.lock` | None | Application update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `packages/komodo_persistence_layer/lib/src/hive/box.dart` | None | Persistence/Hive CE migration |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `packages/komodo_persistence_layer/lib/src/hive/lazy_box.dart` | None | Persistence/Hive CE migration |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `packages/komodo_persistence_layer/lib/src/persisted_types.dart` | None | Persistence/Hive CE migration |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `packages/komodo_persistence_layer/pubspec.yaml` | None | Dependency/version update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `packages/komodo_ui_kit/lib/src/buttons/ui_dropdown.dart` | None | Shared UI kit update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `packages/komodo_ui_kit/lib/src/buttons/ui_primary_button.dart` | None | Shared UI kit update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `packages/komodo_ui_kit/lib/src/controls/selected_coin_graph_control.dart` | None | Shared UI kit update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `packages/komodo_ui_kit/lib/src/display/statistic_card.dart` | None | Shared UI kit update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `packages/komodo_ui_kit/lib/src/dividers/ui_scrollbar.dart` | None | Shared UI kit update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `packages/komodo_ui_kit/pubspec.yaml` | None | Dependency/version update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `pubspec.lock` | None | Dependency/version update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `pubspec.yaml` | None | Dependency/version update |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `roles/nginx/templates/airdex.conf.j2` | None | Build/deployment config |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `sdk` | None | SDK submodule pointer review |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `web/index.html` | None | Build/deployment config |
| Main | `dev...codex/upgrade-flutter-3-41-native-host` | Reviewed | `windows/CMakeLists.txt` | None | Native host/build upgrade |
