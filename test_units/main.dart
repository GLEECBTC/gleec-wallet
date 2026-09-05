import 'package:flutter_test/flutter_test.dart';

import 'services/initializer/app_error_handling_test.dart'
    as app_error_handling_test;
import 'views/wallets_manager/widgets/wallet_simple_import_test.dart'
    as wallet_simple_import_test;

// Suites that only expose `main()`, imported with a prefix so they can be
// aggregated here. CI runs *only* this file
// (.github/workflows/unit-tests-on-pr.yml), so a test file that is not
// reachable from here never runs - these 18 were silently skipped.
import 'bloc/cex_market_data/common/update_frequency_backoff_strategy_test.dart'
    as update_frequency_backoff_strategy_test;
import 'services/initializer/legacy_app_settings_migration_service_test.dart'
    as legacy_app_settings_migration_service_test;
import 'shared/utils/formatters_test.dart' as formatters_test;
import 'shared/widgets/quick_login_switch_test.dart' as quick_login_switch_test;
import 'tests/analytics/firebase_config_test.dart' as firebase_config_test;
import 'tests/analytics/firebase_analytics_api_test.dart'
    as firebase_analytics_api_test;
import 'tests/analytics_test.dart' as analytics_test;
import 'tests/custom_token_import/custom_token_import_bloc_test.dart'
    as custom_token_import_bloc_test;
import 'tests/custom_token_import/custom_token_import_repository_test.dart'
    as custom_token_import_repository_test;
import 'tests/fiat/fiat_default_preference_test.dart'
    as fiat_default_preference_test;
import 'tests/fiat/tron_fiat_mapping_test.dart' as tron_fiat_mapping_test;
import 'tests/mm2/tron_gasless_provider_config_test.dart'
    as tron_gasless_provider_config_test;
import 'tests/nfts/nft_main_bloc_test.dart' as nft_main_bloc_test;
import 'tests/nfts/nft_main_repo_test.dart' as nft_main_repo_test;
import 'tests/nfts/nft_tabs_widget_test.dart' as nft_tabs_widget_test;
import 'tests/views/dex/simple/form/tables/table_utils_test.dart'
    as table_utils_test;
import 'tests/wallet/coin_details/gasless_pending_transfer_panel_test.dart'
    as gasless_pending_transfer_panel_test;
import 'tests/wallet/coin_details/gasless_recovery_banner_scope_test.dart'
    as gasless_recovery_banner_scope_test;
import 'tests/wallet/coin_details/gasless_support_diagnostics_test.dart'
    as gasless_support_diagnostics_test;
import 'views/common/hw_wallet_dialog/trezor_dialog_select_wallet_test.dart'
    as trezor_dialog_select_wallet_test;
import 'views/wallets_manager/widgets/hardware_wallets_manager_test.dart'
    as hardware_wallets_manager_test;
import 'views/wallets_manager/widgets/wallet_login_test.dart'
    as wallet_login_test;
import 'views/wallets_manager/widgets/wallets_manager_entry_test.dart'
    as wallets_manager_entry_test;
import 'views/wallets_manager/widgets/wallets_manager_test.dart'
    as wallets_manager_test;

import 'tests/dex/order_model_validation_test.dart';
import 'tests/dex/trading_entities_guards_test.dart';
import 'tests/encryption/encrypt_data_tests.dart';
import 'tests/fiat/fiat_checkout_url_allowlist_test.dart'
    as fiat_checkout_url_allowlist_test;
import 'tests/formatter/compare_dex_to_cex_tests.dart';
import 'tests/formatter/cut_trailing_zeros_tests.dart';
import 'tests/formatter/duration_format_tests.dart';
import 'tests/formatter/format_amount_tests.dart';
import 'tests/formatter/format_amount_test_alt_tests.dart';
import 'tests/formatter/format_dex_amt_tests.dart';
import 'tests/formatter/formatted_date_tests.dart';
import 'tests/formatter/leading_zeros_tests.dart';
import 'tests/formatter/number_without_exponent_tests.dart';
import 'tests/formatter/text_input_formatter_tests.dart';
import 'tests/formatter/truncate_hash_tests.dart';
import 'tests/helpers/calculate_buy_amount_tests.dart';
import 'tests/helpers/get_sell_amount_tests.dart';
import 'tests/helpers/max_min_rational_tests.dart';
import 'tests/helpers/total_24_change_tests.dart';
import 'tests/helpers/total_fee_test.dart';
import 'tests/helpers/update_sell_amount_tests.dart';
import 'tests/helpers/update_version_compare_tests.dart';
import 'tests/gasless/tron_gasless_policy_test.dart';
import 'tests/password/validate_password_tests.dart';
import 'tests/password/validate_rpc_password_tests.dart';
import 'tests/sorting/sorting_tests.dart';
import 'tests/swaps/my_recent_swaps_response_tests.dart';
import 'tests/system_health/http_head_time_provider_tests.dart';
import 'tests/system_health/http_time_provider_tests.dart';
import 'tests/system_health/ntp_time_provider_tests.dart';
import 'tests/system_health/system_clock_repository_tests.dart';
import 'tests/system_health/time_provider_registry_tests.dart';
import 'tests/balance_utils/compute_wallet_total_usd_tests.dart';
import 'tests/balance_utils/coins_state_usd_conversion_test.dart';
import 'tests/analytics/frame_gap_metrics_test.dart';
import 'tests/sorting/coin_sort_order_test.dart';
import 'tests/wallet/coins_bloc_balance_emit_test.dart';
import 'tests/services/legal_acceptance_test.dart';
import 'tests/services/storage_persistence_gate_test.dart';
import 'tests/wallet/seed_backup_policy_test.dart';
import 'views/common/seed_backup_gate_test.dart';
import 'tests/analytics/onboarding_funnel_test.dart';
import 'tests/analytics/transaction_event_privacy_test.dart';
import 'tests/bitrefill/bitrefill_refund_url_test.dart';
import 'tests/bitrefill/bitrefill_wallet_binding_test.dart';
import 'tests/wallet/coin_details/coin_details_balance_confirmation_controller_test.dart';
import 'tests/wallet/coin_details/coin_details_balance_content_test.dart';
import 'tests/wallet/coin_details/gasless_consolidation_wizard_lifecycle_test.dart';
import 'tests/wallet/coin_details/kmd_rewards_logic_test.dart';
import 'tests/wallet/coin_details/receive_address_faucet_widget_test.dart';
import 'tests/wallet/coin_details/rewards_widget_test.dart';
import 'tests/wallet/coin_details/transaction_details_logic_test.dart';
import 'tests/wallet/coin_details/transaction_sanitize_custody_test.dart';
import 'tests/wallet/coin_details/transaction_history_bloc_test.dart';
import 'tests/wallet/coin_details/transaction_views_widget_test.dart';
import 'tests/wallet/coin_details/withdraw_form_bloc_test.dart';
import 'tests/wallet/coin_details/withdraw_form_confirm_receipt_test.dart';
import 'tests/wallet/coin_details/withdraw_form_fill_section_test.dart';
import 'tests/wallet/coin_details/coin_addresses_bloc_gasless_revalidation_test.dart';
import 'tests/wallet/coin_activation_state_bridge_test.dart';
import 'tests/auth/auth_bloc_test.dart';
import 'tests/wallet/wallet_operation_identity_test.dart';
import 'tests/wallet/coins_bloc_activation_recovery_test.dart';
import 'tests/wallet/coins_bloc_pubkeys_retry_test.dart';
import 'tests/utils/convert_double_to_string_tests.dart';
import 'tests/utils/convert_fract_rat_tests.dart';
import 'tests/utils/double_to_string_tests.dart';
import 'tests/utils/explorer_url_tests.dart';
import 'tests/utils/get_fiat_amount_tests.dart';
import 'tests/utils/get_usd_balance_tests.dart';
import 'tests/utils/ipfs_gateway_manager_test.dart';
import 'tests/utils/transaction_history/sanitize_transaction_tests.dart';

/// Run in terminal flutter test test_units/main.dart
/// More info at documentation "Unit and Widget testing" section
///
/// The GasFree suites need the feature compiled in. A plain
/// `flutter test test_units/main.dart` leaves `tronGaslessServiceProvider`
/// empty, so every provider-identity check fails closed and ~36 gas-free tests
/// cannot reach the states they assert. That is the compiled configuration
/// behaving correctly, not a broken test. CI passes these
/// (.github/workflows/unit-tests-on-pr.yml); to reproduce it locally:
///
/// ```sh
/// flutter test test_units/main.dart \
///   --dart-define=TRON_GASLESS_ENABLED=true \
///   --dart-define=TRON_GASLESS_RECEIVE_ENABLED=true \
///   --dart-define=TRON_GASLESS_BASE_URL=https://quicknode.gleec.com/gasfree/tron \
///   --dart-define=TRON_GASLESS_SERVICE_PROVIDER=TLntW9Z59LYY5KEi9cmwk3PKjQga828ird
/// ```
void main() {
  app_error_handling_test.main();
  wallet_simple_import_test.main();
  group('App update:', () {
    testUpdateVersionCompare();
    testUpdateDownloadUri();
  });

  group('Formatters:', () {
    testCutTrailingZeros();
    testFormatAmount();
    testToStringAmount();
    testLeadingZeros();
    testFormatDexAmount();
    testDecimalTextInputFormatter();
    testDurationFormat();
    testNumberWithoutExponent();
    testCompareToCex();
    testTruncateHash();
    testFormattedDate();
    //testTruncateDecimal();
  });

  group('Password:', () {
    testValidateRPCPassword();
    testcheckPasswordRequirements();
  });

  group('Sorting:', () {
    testSorting();
  });

  group('Utils:', () {
    testComputeWalletTotalUsd();
    testCoinsStateUsdConversion();
    // TODO: re-enable or migrate to the SDK
    testUsdBalanceFormatter();
    testGetFiatAmount();
    testCustomDoubleToString();
    testExplorerUrlHelpers();
    testRatToFracAndViseVersa();

    testDoubleToString();
    testSanitizeTransaction();
    testIpfsGatewayManager();
  });

  group('Helpers: ', () {
    testMaxMinRational();
    testCalculateBuyAmount();
    // TODO: re-enable or migrate to the SDK
    testGetTotal24Change();
    testGetTotalFee();
    testGetSellAmount();
    testUpdateSellAmount();
  });

  testTronGaslessPolicy();

  group('Crypto:', () {
    testEncryptDataTool();
  });

  group('MyRecentSwaps:', () {
    testMyRecentSwapsResponse();
  });

  group('Dex trading safety:', () {
    testTradingEntitiesGuards();
    testOrderModelValidation();
  });

  group('SystemHealth: ', () {
    testHttpHeadTimeProvider();
    testSystemClockRepository();
    testHttpTimeProvider();
    testNtpTimeProvider();
    testTimeProviderRegistry();
  });

  group('CoinDetails:', () {
    testWithdrawFormBloc();
    testCoinDetailsBalanceConfirmationController();
    testCoinDetailsBalanceContent();
    testGaslessConsolidationWizardLifecycle();
    testWithdrawFormFillSection();
    testWithdrawFormConfirmReceipt();
    testTransactionDetailsLogic();
    testTransactionSanitizeCustody();
    testKmdRewardsLogic();
    testRewardsWidgets();
    testTransactionViewsWidgets();
    testTransactionHistoryBloc();
    testReceiveAddressFaucetWidgets();
  });

  testCoinActivationStateBridge();
  testAuthBloc();
  testWalletOperationIdentity();
  nft_main_bloc_test.testNftMainBloc();
  nft_main_repo_test.testNftMainRepo();
  nft_tabs_widget_test.testNftTabsWidget();
  testCoinsBlocActivationRecovery();
  testCoinsBlocPubkeysRetry();
  testCoinAddressesBlocGaslessRevalidation();
  testFrameGapMetrics();
  testCoinSortOrder();
  testCoinsBlocBalanceEmit();
  testLegalAcceptance();
  testStoragePersistenceGate();
  testSeedBackupPolicy();
  testSeedBackupGate();
  testOnboardingFunnel();
  testTransactionEventPrivacy();
  testBitrefillRefundUrl();
  testBitrefillWalletBinding();

  // Previously unreachable suites. Each declares its own groups inside its
  // `main()`, so calling it here is equivalent to running the file directly.
  update_frequency_backoff_strategy_test.main();
  legacy_app_settings_migration_service_test.main();
  formatters_test.main();
  quick_login_switch_test.main();
  analytics_test.main();
  firebase_config_test.main();
  firebase_analytics_api_test.main();
  custom_token_import_bloc_test.main();
  custom_token_import_repository_test.main();
  fiat_checkout_url_allowlist_test.main();
  fiat_default_preference_test.main();
  tron_fiat_mapping_test.main();
  tron_gasless_provider_config_test.main();
  table_utils_test.main();
  gasless_pending_transfer_panel_test.main();
  gasless_support_diagnostics_test.main();
  gasless_recovery_banner_scope_test.main();
  trezor_dialog_select_wallet_test.main();
  hardware_wallets_manager_test.main();
  wallet_login_test.main();
  wallets_manager_entry_test.main();
  wallets_manager_test.main();
}
