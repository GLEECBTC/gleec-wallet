import 'package:flutter_test/flutter_test.dart';

import 'tests/encryption/encrypt_data_tests.dart';
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
import 'tests/wallet/coin_details/coin_details_balance_confirmation_controller_test.dart';
import 'tests/wallet/coin_details/coin_details_balance_content_test.dart';
import 'tests/wallet/coin_details/kmd_rewards_logic_test.dart';
import 'tests/wallet/coin_details/receive_address_faucet_widget_test.dart';
import 'tests/wallet/coin_details/rewards_widget_test.dart';
import 'tests/wallet/coin_details/transaction_details_logic_test.dart';
import 'tests/wallet/coin_details/transaction_views_widget_test.dart';
import 'tests/wallet/coin_details/withdraw_form_bloc_test.dart';
import 'tests/wallet/coin_details/withdraw_form_fill_section_test.dart';
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
void main() {
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

  group('Crypto:', () {
    testEncryptDataTool();
  });

  group('MyRecentSwaps:', () {
    testMyRecentSwapsResponse();
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
    testWithdrawFormFillSection();
    testTransactionDetailsLogic();
    testKmdRewardsLogic();
    testRewardsWidgets();
    testTransactionViewsWidgets();
    testReceiveAddressFaucetWidgets();
  });
}
