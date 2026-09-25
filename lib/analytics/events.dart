import 'package:web_dex/bloc/analytics/analytics_repo.dart';
import 'package:web_dex/bloc/analytics/analytics_event.dart';

//============================================================
// Event categories should be organized in separate files:
// - HD Wallet Operations
// - UI Usability
// - Data Sync
// - Performance
//============================================================

// HD WALLET OPERATIONS
//============================================================

/// E38: Fresh receive address derived
/// Measures when a fresh HD wallet address is generated. Business category: HD Wallet Operations.
/// Provides insights on address-reuse risk and payment UX.
class HdAddressGeneratedEventData extends AnalyticsEventData {
  const HdAddressGeneratedEventData({
    required this.accountIndex,
    required this.addressIndex,
    required this.asset,
  });

  final int accountIndex;
  final int addressIndex;
  final String asset;

  @override
  String get name => 'hd_address_generated';

  @override
  Map<String, Object> get parameters => {
    'account_index': accountIndex,
    'address_index': addressIndex,
    'asset': asset,
  };
}

/// E38: Fresh receive address derived
class AnalyticsHdAddressGeneratedEvent extends AnalyticsSendDataEvent {
  AnalyticsHdAddressGeneratedEvent({
    required int accountIndex,
    required int addressIndex,
    required String asset,
  }) : super(
         HdAddressGeneratedEventData(
           accountIndex: accountIndex,
           addressIndex: addressIndex,
           asset: asset,
         ),
       );
}

// UI USABILITY
//============================================================

/// E40: Time until the top of the coins list crosses 50% of viewport
/// Measures the time it takes for the coins list to reach halfway through the viewport. Business category: UI Usability.
/// Provides insights on whether users struggle to reach balances and helps optimize list layout.
class WalletListHalfViewportReachedEventData extends AnalyticsEventData {
  const WalletListHalfViewportReachedEventData({
    required this.timeToHalfMs,
    required this.walletSize,
  });

  final int timeToHalfMs;
  final int walletSize;

  @override
  String get name => 'wallet_list_half_viewport';

  @override
  Map<String, Object> get parameters => {
    'time_to_half_ms': timeToHalfMs,
    'wallet_size': walletSize,
  };
}

/// E40: Time until the top of the coins list crosses 50% of viewport
class AnalyticsWalletListHalfViewportReachedEvent
    extends AnalyticsSendDataEvent {
  AnalyticsWalletListHalfViewportReachedEvent({
    required int timeToHalfMs,
    required int walletSize,
  }) : super(
         WalletListHalfViewportReachedEventData(
           timeToHalfMs: timeToHalfMs,
           walletSize: walletSize,
         ),
       );
}

// DATA SYNC
//============================================================

/// E41: Coins config refresh completed on launch
/// Measures when coins configuration data is refreshed upon app launch. Business category: Data Sync.
/// Provides insights on data freshness and helps monitor failed or slow syncs.
class CoinsDataUpdatedEventData extends AnalyticsEventData {
  const CoinsDataUpdatedEventData({
    required this.coinsCount,
    required this.updateSource,
    required this.updateDurationMs,
  });

  final int coinsCount;
  final String updateSource;
  final int updateDurationMs;

  @override
  String get name => 'coins_data_updated';

  @override
  Map<String, Object> get parameters => {
    'coins_count': coinsCount,
    'update_source': updateSource,
    'update_duration_ms': updateDurationMs,
  };
}

/// E41: Coins config refresh completed on launch
class AnalyticsCoinsDataUpdatedEvent extends AnalyticsSendDataEvent {
  AnalyticsCoinsDataUpdatedEvent({
    required String updateSource,
    required int updateDurationMs,
    required int coinsCount,
  }) : super(
         CoinsDataUpdatedEventData(
           updateSource: updateSource,
           updateDurationMs: updateDurationMs,
           coinsCount: coinsCount,
         ),
       );
}

// PERFORMANCE
//============================================================

/// E44: Delay from page open until interactive (Loading logo hidden)
/// Measures the delay between opening a page and when it becomes interactive. Business category: Performance.
/// Provides insights on performance bottlenecks that impact user experience.
class PageInteractiveDelayEventData extends AnalyticsEventData {
  const PageInteractiveDelayEventData({
    required this.pageName,
    required this.interactiveDelayMs,
    required this.spinnerTimeMs,
  });

  final String pageName;
  final int interactiveDelayMs;
  final int spinnerTimeMs;

  @override
  String get name => 'page_interactive_delay';

  @override
  Map<String, Object> get parameters => {
    'page_name': pageName,
    'interactive_delay_ms': interactiveDelayMs,
    'spinner_time_ms': spinnerTimeMs,
  };
}

/// E45: Delay from sign-in until the wallet total in USD can first be shown.
///
/// The metric users were actually complaining about, and the one nothing here
/// measured. [PageInteractiveDelayEventData] stops when the loading logo is
/// hidden and [WalletListHalfViewportReachedEventData] only fires on scroll -
/// both can be green while every balance row still shows a placeholder.
///
/// Stops at the first non-null `computeWalletTotalUsd`, i.e. the first frame in
/// which at least one asset has both a balance and a price. Fired once per
/// session; see `WalletLoadTimeline`.
///
/// [assetCount] and [pricedAssetCount] are carried because the timing is only
/// interpretable next to them: one priced asset out of forty is a very
/// different result from forty out of forty at the same millisecond count.
class TimeToFirstBalanceEventData extends AnalyticsEventData {
  const TimeToFirstBalanceEventData({
    required this.timeToFirstBalanceMs,
    required this.assetCount,
    required this.pricedAssetCount,
    required this.walletType,
  });

  final int timeToFirstBalanceMs;
  final int assetCount;
  final int pricedAssetCount;

  /// `hd` or `iguana`. HD pays an address-scan cost that iguana does not, and
  /// without this the two populations average into a number describing neither.
  final String walletType;

  @override
  String get name => 'time_to_first_balance';

  @override
  Map<String, Object> get parameters => {
    'time_to_first_balance_ms': timeToFirstBalanceMs,
    'asset_count': assetCount,
    'priced_asset_count': pricedAssetCount,
    'wallet_type': walletType,
  };
}

/// E45: Delay from sign-in until the wallet total in USD can first be shown.
class AnalyticsTimeToFirstBalanceEvent extends AnalyticsSendDataEvent {
  AnalyticsTimeToFirstBalanceEvent({
    required int timeToFirstBalanceMs,
    required int assetCount,
    required int pricedAssetCount,
    required String walletType,
  }) : super(
         TimeToFirstBalanceEventData(
           timeToFirstBalanceMs: timeToFirstBalanceMs,
           assetCount: assetCount,
           pricedAssetCount: pricedAssetCount,
           walletType: walletType,
         ),
       );
}

/// E44: Delay from page open until interactive (Loading logo hidden)
class AnalyticsPageInteractiveDelayEvent extends AnalyticsSendDataEvent {
  AnalyticsPageInteractiveDelayEvent({
    required String pageName,
    required int interactiveDelayMs,
    required int spinnerTimeMs,
  }) : super(
         PageInteractiveDelayEventData(
           pageName: pageName,
           interactiveDelayMs: interactiveDelayMs,
           spinnerTimeMs: spinnerTimeMs,
         ),
       );
}

({int accountIndex, int addressIndex}) parseDerivationPath(String path) {
  final segments = path.split('/');
  int account = 0;
  int address = 0;
  if (segments.length >= 5) {
    account = int.tryParse(segments[3].replaceAll("'", '')) ?? 0;
    address = int.tryParse(segments[4].replaceAll("'", '')) ?? 0;
  }
  return (accountIndex: account, addressIndex: address);
}
