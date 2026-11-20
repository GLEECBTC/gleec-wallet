import 'package:easy_localization/easy_localization.dart';
import 'package:web_dex/shared/trading/trading_asset_policy.dart';

/// Maps local capability refusals consistently for restored and edited bots.
String marketMakerErrorMessage(Object error) {
  if (error is TradePreflightRejected) {
    return marketMakerErrorMessage(error.cause);
  }
  if (error is SolanaMarketMakerUnavailable) {
    return 'solanaMarketMakerUnavailable'.tr();
  }
  return error.toString();
}
