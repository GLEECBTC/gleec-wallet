import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:matomo_tracker/matomo_tracker.dart';
import 'package:web_dex/model/settings/analytics_settings.dart';
import 'package:web_dex/shared/constants.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'analytics_api.dart';
import 'analytics_repo.dart';

class MatomoAnalyticsApi implements AnalyticsApi {
  late MatomoTracker _instance;
  final Completer<void> _initCompleter = Completer<void>();

  bool _isInitialized = false;
  bool _isEnabled = false;
  int _initRetryCount = 0;
  static const int _maxInitRetries = 3;

  /// SYNC NOTE:
  /// The event-to-category mapping and numeric value extraction keys below must
  /// stay in sync with `lib/analytics/required_analytics_events.csv`.
  /// Ideally these would not be hard-coded and should be generated from a
  /// shared analytics metadata source.

  /// Explicit mapping of GA4 event names to Business Categories as defined in
  /// `lib/analytics/required_analytics_events.csv`.
  static const Map<String, String> _eventCategoryMap = {
    // User Engagement
    'app_open': 'User Engagement',

    // User Acquisition
    'onboarding_start': 'User Acquisition',
    'onboarding_step_viewed': 'User Acquisition',
    'onboarding_step_completed': 'User Acquisition',
    'onboarding_step_abandoned': 'User Acquisition',
    'wallet_created': 'User Acquisition',
    'wallet_imported': 'User Acquisition',

    // Security
    'backup_complete': 'Security Adoption',
    'backup_skipped': 'Security Risk',

    // Portfolio
    'portfolio_viewed': 'Portfolio',
    'portfolio_growth_viewed': 'Portfolio',
    'portfolio_pnl_viewed': 'Portfolio',

    // Asset Mgmt
    'add_asset': 'Asset Mgmt',
    'view_asset': 'Asset Mgmt',
    'asset_enabled': 'Asset Mgmt',
    'asset_disabled': 'Asset Mgmt',

    // Transactions
    'send_initiated': 'Transactions',
    'send_success': 'Transactions',
    'send_failure': 'Transactions',

    // Trading (DEX)
    'swap_initiated': 'Trading (DEX)',
    'swap_success': 'Trading (DEX)',
    'swap_failure': 'Trading (DEX)',

    // Cross-Chain
    'bridge_initiated': 'Cross-Chain',
    'bridge_success': 'Cross-Chain',
    'bridge_failure': 'Cross-Chain',

    // NFT Wallet
    'nft_gallery_opened': 'NFT Wallet',
    'nft_transfer_initiated': 'NFT Wallet',
    'nft_transfer_success': 'NFT Wallet',
    'nft_transfer_failure': 'NFT Wallet',

    // Market Bot
    'marketbot_setup_start': 'Market Bot',
    'marketbot_setup_complete': 'Market Bot',
    'marketbot_trade_executed': 'Market Bot',
    'marketbot_error': 'Market Bot',

    // Rewards
    'reward_claim_initiated': 'Rewards',
    'reward_claim_success': 'Rewards',
    'reward_claim_failure': 'Rewards',

    // Ecosystem
    'dapp_connect': 'Ecosystem',

    // Preferences
    'settings_change': 'Preferences',
    'theme_selected': 'Preferences',

    // Stability
    'error_displayed': 'Stability',

    // Growth
    'app_share': 'Growth',

    // HD Wallet Ops
    'hd_address_generated': 'HD Wallet Ops',

    // UX & UI
    'wallet_list_half_viewport': 'UI Usability',

    // Data Sync
    'coins_data_updated': 'Data Sync',

    // Search
    'searchbar_input': 'Search',

    // Performance
    'page_interactive_delay': 'Performance',
  };

  /// Visit-scoped dimension identifiers (set once per session).
  static const Map<String, int> _visitDimensionIds = {
    'platform': 1,
    'app_version': 2,
    'referral_source': 3,
    'theme_name': 4,
    'update_source': 5,
  };

  /// Action-scoped dimension identifiers (sent with each event).
  static const Map<String, int> _actionDimensionIds = {
    'asset': 6,
    'secondary_asset': 7,
    'network': 8,
    'secondary_network': 9,
    'amount': 10,
    'fee': 11,
    'collection_name': 12,
    'token_id': 13,
    'pair': 14,
    'strategy_type': 15,
    'hd_type': 16,
    'failure_reason': 17,
    'screen_context': 18,
    'stage_skipped': 19,
    'method': 20,
    'import_type': 21,
    'setting_name': 22,
    'total_coins': 23,
    'total_value_usd': 24,
    'period': 25,
    'timeframe': 26,
    'growth_pct': 27,
    'realized_pnl': 28,
    'unrealized_pnl': 29,
    'profit_usd': 30,
    'backup_time': 31,
    'duration_ms': 32,
    'load_time_ms': 33,
    'time_to_half_ms': 34,
    'update_duration_ms': 35,
    'interactive_delay_ms': 36,
    'spinner_time_ms': 37,
    'nft_count': 38,
    'pairs_count': 39,
    'base_capital': 40,
    'account_index': 41,
    'address_index': 42,
    'wallet_size': 43,
    'coins_count': 44,
    'query_length': 45,
    'dapp_name': 46,
    'new_value': 47,
    'channel': 48,
    'scroll_delta': 49,
    'page_name': 50,
    'expected_reward_amount': 51,
    'step': 52,
    'step_index': 53,
    'flow': 54,
    'entry_point': 55,
    'existing_wallet_count': 56,
  };

  static const Set<String> _assetDimensionRequiredEvents = {
    'add_asset',
    'view_asset',
    'asset_enabled',
    'asset_disabled',
    'send_initiated',
    'send_success',
    'send_failure',
    'swap_initiated',
    'swap_success',
    'swap_failure',
    'bridge_initiated',
    'bridge_success',
    'bridge_failure',
    'reward_claim_initiated',
    'reward_claim_success',
    'reward_claim_failure',
    'hd_address_generated',
    'marketbot_trade_executed',
  };

  /// Queue to store events when analytics is disabled
  final List<AnalyticsEventData> _eventQueue = [];

  /// Tracks the currently active visit-scoped dimension values so we only send updates
  /// when something changes (e.g., theme switch mid-session).
  final Map<String, String> _currentVisitDimensions = {};

  @override
  String get providerName => 'Matomo';

  @override
  bool get isInitialized => _isInitialized;

  @override
  bool get isEnabled => _isEnabled;

  @override
  Future<void> initialize(AnalyticsSettings settings) async {
    return _initializeWithRetry(settings);
  }

  /// Initialize with retry mechanism
  Future<void> _initializeWithRetry(AnalyticsSettings settings) async {
    try {
      if (kDebugMode) {
        log(
          'Initializing Matomo Analytics with settings: isSendAllowed=${settings.isSendAllowed}',
          path: 'analytics -> MatomoAnalyticsApi -> _initialize',
        );
      }

      // Initialize Matomo only if configuration is provided

      final bool hasConfig = matomoUrl.isNotEmpty && matomoSiteId.isNotEmpty;
      if (!hasConfig) {
        if (kDebugMode) {
          log(
            'Matomo configuration missing (MATOMO_URL and/or MATOMO_SITE_ID). Disabling Matomo.',
            path: 'analytics -> MatomoAnalyticsApi -> _initialize',
          );
        }
        _isInitialized = false;
        _isEnabled = false;
        if (!_initCompleter.isCompleted) {
          _initCompleter.complete();
        }
        return;
      }

      await MatomoTracker.instance.initialize(
        siteId: matomoSiteId,
        url: matomoUrl,
        dispatchSettings: const DispatchSettings.persistent(),
        // Include backend API key header similarly to feedback feature
        customHeaders: {
          if (const String.fromEnvironment('FEEDBACK_API_KEY').isNotEmpty)
            'X-KW-KEY': const String.fromEnvironment('FEEDBACK_API_KEY'),
        },
      );
      _instance = MatomoTracker.instance;

      _isInitialized = true;
      // Disable analytics in CI or when analyticsDisabled flag is set
      final bool shouldDisable = analyticsDisabled || isCiEnvironment;
      _isEnabled = settings.isSendAllowed && !shouldDisable;

      if (kDebugMode) {
        log(
          'Matomo Analytics initialized: _isInitialized=$_isInitialized, _isEnabled=$_isEnabled',
          path: 'analytics -> MatomoAnalyticsApi -> _initialize',
        );
      }

      if (_isInitialized && _isEnabled) {
        await activate();
      } else {
        await deactivate();
      }

      // Successfully initialized
      if (!_initCompleter.isCompleted) {
        _initCompleter.complete();
      }
    } catch (e) {
      _isInitialized = false;

      if (kDebugMode) {
        log(
          'Error initializing Matomo Analytics: $e',
          path: 'analytics -> MatomoAnalyticsApi -> _initialize',
          isError: true,
        );
      }

      // Try to initialize again if we haven't exceeded max retries
      if (_initRetryCount < _maxInitRetries) {
        _initRetryCount++;

        if (kDebugMode) {
          log(
            'Retrying Matomo analytics initialization (attempt $_initRetryCount of $_maxInitRetries)',
            path: 'analytics -> MatomoAnalyticsApi -> _initialize',
          );
        }

        // Retry with exponential backoff
        await Future.delayed(Duration(seconds: 2 * _initRetryCount));
        await _initializeWithRetry(settings);
      } else {
        // Maximum retries exceeded
        if (!_initCompleter.isCompleted) {
          _initCompleter.completeError(e);
        }
      }
    }
  }

  @override
  Future<void> retryInitialization(AnalyticsSettings settings) async {
    if (!_isInitialized) {
      _initRetryCount = 0;
      return _initializeWithRetry(settings);
    }
  }

  @override
  Future<void> sendEvent(AnalyticsEventData event) async {
    // If not initialized or disabled, enqueue for later
    if (!_isInitialized || !_isEnabled) {
      _eventQueue.add(event);
      return;
    }

    final normalizedParameters = _normalizeParameters(
      event.parameters,
      event.name,
    );
    final sanitizedParameters = normalizedParameters.map((key, value) {
      if (value == null) {
        return MapEntry(key, 'null');
      }
      if (value is Map || value is List) {
        return MapEntry(key, jsonEncode(value));
      }
      return MapEntry(key, value.toString());
    });

    final visitDimensionUpdates = _extractVisitDimensionUpdates(
      sanitizedParameters,
    );
    if (visitDimensionUpdates.isNotEmpty) {
      await _setVisitDimensions(visitDimensionUpdates);
    }

    final actionDimensions = _extractActionDimensions(sanitizedParameters);
    _ensureAssetDimension(event.name, actionDimensions, sanitizedParameters);

    final primaryEventLabel =
        _derivePrimaryEventLabel(event, sanitizedParameters) ?? event.name;

    // Log the event in debug mode with formatted parameters for better readability
    if (kDebugMode) {
      final formattedParams = const JsonEncoder.withIndent(
        '  ',
      ).convert(sanitizedParameters);
      log(
        'Matomo Analytics Event: ${event.name}; Parameters: $formattedParams',
        path: 'analytics -> MatomoAnalyticsApi -> sendEvent',
      );
    }

    try {
      // Convert to Matomo event format
      _instance.trackEvent(
        eventInfo: EventInfo(
          category: _extractCategory(event.name),
          action: event.name,
          name: primaryEventLabel,
          value: _extractEventValue(normalizedParameters),
        ),
        dimensions: actionDimensions,
      );

      // Note: Custom dimensions should be set separately in Matomo
      // You can extend this implementation to handle custom dimensions if needed
    } catch (e, s) {
      log(
        e.toString(),
        path: 'analytics -> MatomoAnalyticsApi -> sendEvent',
        trace: s,
        isError: true,
      );
    }
  }

  @override
  Future<void> activate() async {
    if (!_isInitialized) {
      return;
    }

    _isEnabled = true;
    _currentVisitDimensions.clear();
    // Matomo doesn't have a direct enable/disable method like Firebase
    // so we handle this by simply processing queued events

    // Process any queued events
    if (_eventQueue.isNotEmpty) {
      if (kDebugMode) {
        log(
          'Processing ${_eventQueue.length} queued Matomo analytics events',
          path: 'analytics -> MatomoAnalyticsApi -> activate',
        );
      }

      final queuedEvents = List<AnalyticsEventData>.from(_eventQueue);
      _eventQueue.clear();

      int processedCount = 0;
      for (final event in queuedEvents) {
        await sendEvent(event);
        processedCount++;
      }

      if (kDebugMode && processedCount > 0) {
        log(
          'Successfully processed $processedCount queued Matomo analytics events',
          path: 'analytics -> MatomoAnalyticsApi -> activate',
        );
      }
    }
  }

  @override
  Future<void> deactivate() async {
    if (!_isInitialized) {
      return;
    }

    if (kDebugMode) {
      log(
        'Matomo analytics collection disabled',
        path: 'analytics -> MatomoAnalyticsApi -> deactivate',
      );
    }

    _isEnabled = false;
    // Matomo doesn't have a direct disable method
    // Events will be queued instead of sent when disabled
  }

  Map<String, dynamic> _normalizeParameters(
    Map<String, dynamic> parameters,
    String eventName,
  ) {
    final original = <String, dynamic>{};
    for (final entry in parameters.entries) {
      final value = entry.value;
      if (value != null) {
        original[entry.key] = value;
      }
    }

    dynamic sanitizeValue(dynamic value) {
      if (value == null) return null;
      if (value is String) {
        final trimmed = value.trim();
        return trimmed.isEmpty ? null : trimmed;
      }
      return value;
    }

    final normalized = <String, dynamic>{};

    final dynamic asset = sanitizeValue(
      original.remove('asset') ??
          original.remove('asset_symbol') ??
          original.remove('from_asset'),
    );
    if (asset != null) {
      normalized['asset'] = asset;
    }

    final dynamic secondaryAsset = sanitizeValue(
      original.remove('secondary_asset') ?? original.remove('to_asset'),
    );
    if (secondaryAsset != null) {
      normalized['secondary_asset'] = secondaryAsset;
    }

    dynamic network = sanitizeValue(
      original.remove('network') ??
          original.remove('asset_network') ??
          original.remove('from_chain'),
    );
    dynamic secondaryNetwork = sanitizeValue(
      original.remove('secondary_network') ?? original.remove('to_chain'),
    );
    final dynamic networksRaw = original.remove('networks');
    if ((network == null || secondaryNetwork == null) && networksRaw != null) {
      final parsed = _splitNetworkPair(networksRaw.toString());
      network ??= parsed.primary;
      secondaryNetwork ??= parsed.secondary;
    }
    if (network != null) {
      normalized['network'] = network;
    }
    if (secondaryNetwork != null) {
      normalized['secondary_network'] = secondaryNetwork;
    }

    final dynamic amount =
        original.remove('amount') ??
        original.remove('trade_size') ??
        original.remove('reward_amount');
    if (amount != null) {
      normalized['amount'] = amount;
    }

    final dynamic fee = original.remove('fee');
    if (fee != null) {
      normalized['fee'] = fee;
    }

    final dynamic collectionName = original.remove('collection_name');
    if (collectionName != null) {
      normalized['collection_name'] = collectionName;
    }

    final dynamic tokenId = original.remove('token_id');
    if (tokenId != null) {
      normalized['token_id'] = tokenId;
    }

    final dynamic pair = original.remove('pair');
    if (pair != null) {
      normalized['pair'] = pair;
    }

    final dynamic strategyType = original.remove('strategy_type');
    if (strategyType != null) {
      normalized['strategy_type'] = strategyType;
    }

    final dynamic hdType =
        original.remove('hd_type') ?? original.remove('wallet_type');
    if (hdType != null) {
      normalized['hd_type'] = hdType;
    }

    final dynamic failureReasonExplicit = original.remove('failure_reason');
    final dynamic failReason = original.remove('fail_reason');
    final dynamic failError = original.remove('fail_error');
    final dynamic failStage = original.remove('fail_stage');
    final dynamic errorCode = original.remove('error_code');
    if (failureReasonExplicit != null) {
      normalized['failure_reason'] = failureReasonExplicit;
    } else {
      final parts = <String>[];

      void addPart(String label, dynamic value) {
        final trimmed = sanitizeValue(value);
        if (trimmed != null) {
          parts.add('$label:$trimmed');
        }
      }

      addPart('stage', failStage);
      final dynamic primaryReason = failReason ?? failError;
      addPart('reason', primaryReason);
      if (errorCode != null && errorCode != primaryReason) {
        addPart('code', errorCode);
      }

      if (parts.isNotEmpty) {
        normalized['failure_reason'] = parts.join('|');
      }
    }

    for (final key in [
      'screen_context',
      'stage_skipped',
      'method',
      'import_type',
    ]) {
      final value = original.remove(key);
      if (value != null) {
        normalized[key] = value;
      }
    }

    final settingName = original.remove('setting_name');
    if (settingName != null) {
      normalized['setting_name'] = settingName;
    }

    final coinsTotalsKeys = [
      'total_coins',
      'total_value_usd',
      'period',
      'timeframe',
      'growth_pct',
      'realized_pnl',
      'unrealized_pnl',
      'profit_usd',
      'backup_time',
      'duration_ms',
      'load_time_ms',
      'time_to_half_ms',
      'update_duration_ms',
      'interactive_delay_ms',
      'spinner_time_ms',
      'nft_count',
      'pairs_count',
      'base_capital',
      'account_index',
      'address_index',
      'wallet_size',
      'coins_count',
      'query_length',
      'dapp_name',
      'new_value',
      'channel',
      'scroll_delta',
      'page_name',
      'expected_reward_amount',
    ];
    for (final key in coinsTotalsKeys) {
      final value = original.remove(key);
      if (value != null) {
        normalized[key] = value;
      }
    }

    // Visit dimensions should also be part of the normalized map so they can be
    // routed to Matomo via trackDimensions(). Leaving them here means we can
    // reuse the same sanitized map for Firebase and app logging.
    for (final key in _visitDimensionIds.keys) {
      final value = original.remove(key);
      if (value != null) {
        normalized[key] = value;
      }
    }

    // Any remaining keys were already using consolidated names or are
    // provider-specific metadata – keep them to avoid data loss.
    normalized.addAll(original);

    return normalized;
  }

  Map<String, String> _extractVisitDimensionUpdates(
    Map<String, String> parameters,
  ) {
    final updates = <String, String>{};
    for (final entry in _visitDimensionIds.entries) {
      final value = parameters[entry.key];
      if (value == null) continue;
      final dimensionKey = 'dimension${entry.value}';
      if (_currentVisitDimensions[dimensionKey] != value) {
        updates[dimensionKey] = value;
      }
    }
    return updates;
  }

  Future<void> _setVisitDimensions(Map<String, String> updates) async {
    if (updates.isEmpty) return;
    try {
      _instance.trackDimensions(dimensions: updates);
      _currentVisitDimensions.addAll(updates);
    } catch (e, s) {
      if (kDebugMode) {
        log(
          'Failed to update Matomo visit dimensions: $e',
          path: 'analytics -> MatomoAnalyticsApi -> _setVisitDimensions',
          trace: s,
          isError: true,
        );
      }
    }
  }

  Map<String, String> _extractActionDimensions(Map<String, String> parameters) {
    final dimensions = <String, String>{};
    for (final entry in _actionDimensionIds.entries) {
      final value = parameters[entry.key];
      if (value == null) continue;
      dimensions['dimension${entry.value}'] = value;
    }
    return dimensions;
  }

  void _ensureAssetDimension(
    String eventName,
    Map<String, String> actionDimensions,
    Map<String, String> parameters,
  ) {
    if (!_assetDimensionRequiredEvents.contains(eventName)) {
      return;
    }

    final assetDimension = actionDimensions['dimension6'];
    if (assetDimension != null && assetDimension.trim().isNotEmpty) {
      return;
    }

    final fallback = parameters['asset'];
    if (fallback != null && fallback.trim().isNotEmpty) {
      actionDimensions['dimension6'] = fallback;
      return;
    }

    if (kDebugMode) {
      log(
        'Matomo asset dimension missing for $eventName. parameters=$parameters',
        path: 'analytics -> MatomoAnalyticsApi -> _ensureAssetDimension',
        isError: true,
      );
    }
  }

  ({String? primary, String? secondary}) _splitNetworkPair(String raw) {
    const separators = [',', '->', '|', '/'];
    for (final separator in separators) {
      if (raw.contains(separator)) {
        final parts = raw
            .split(separator)
            .map((part) => part.trim())
            .where((part) => part.isNotEmpty)
            .toList();
        if (parts.isEmpty) return (primary: null, secondary: null);
        if (parts.length == 1) {
          return (primary: parts[0], secondary: null);
        }
        return (primary: parts[0], secondary: parts[1]);
      }
    }
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return (primary: null, secondary: null);
    }
    return (primary: trimmed, secondary: null);
  }

  /// Extract category from event name (used for Matomo event categorization)
  String _extractCategory(String eventName) {
    // 1) Exact mapping from CSV
    final mapped = _eventCategoryMap[eventName];
    if (mapped != null) return mapped;

    // 2) Fallback by prefix → Business Category (keep in sync with CSV semantics)
    if (eventName.startsWith('onboarding_')) return 'User Acquisition';
    if (eventName.startsWith('wallet_')) return 'User Acquisition';
    if (eventName.startsWith('app_')) return 'User Engagement';
    if (eventName.startsWith('portfolio_')) return 'Portfolio';
    if (eventName.startsWith('asset_')) return 'Asset Mgmt';
    if (eventName.startsWith('send_')) return 'Transactions';
    if (eventName.startsWith('swap_')) return 'Trading (DEX)';
    if (eventName.startsWith('bridge_')) return 'Cross-Chain';
    if (eventName.startsWith('nft_')) return 'NFT Wallet';
    if (eventName.startsWith('marketbot_')) return 'Market Bot';
    if (eventName.startsWith('reward_')) return 'Rewards';
    if (eventName.startsWith('dapp_')) return 'Ecosystem';
    if (eventName.startsWith('settings_')) return 'Preferences';
    if (eventName.startsWith('error_')) return 'Stability';
    if (eventName.startsWith('hd_')) return 'HD Wallet Ops';
    if (eventName.startsWith('scroll_')) return 'UX Interaction';
    if (eventName.startsWith('searchbar_')) return 'Search';
    if (eventName.startsWith('theme_')) return 'Preferences';
    if (eventName.startsWith('coins_')) return 'Data Sync';
    if (eventName.startsWith('page_')) return 'Performance';

    return 'General';
  }

  /// Extract numeric value from parameters for Matomo event value
  double? _extractEventValue(Map<String, dynamic> parameters) {
    // Look for common numeric parameters that could serve as event value
    final potentialValueKeys = [
      'amount',
      'value',
      'count',
      'duration_ms',
      'profit_usd',
      'reward_amount',
      'base_capital',
      'trade_size',
      // From required_analytics_events.csv (keep in sync)
      'backup_time',
      'total_coins',
      'total_value_usd',
      'growth_pct',
      'realized_pnl',
      'unrealized_pnl',
      'fee',
      'load_time_ms',
      'nft_count',
      'pairs_count',
      'expected_reward_amount',
      'account_index',
      'address_index',
      'scroll_delta',
      'time_to_half_ms',
      'wallet_size',
      'coins_count',
      'update_duration_ms',
      'query_length',
      'interactive_delay_ms',
      'spinner_time_ms',
    ];

    for (final key in potentialValueKeys) {
      if (parameters.containsKey(key)) {
        final value = parameters[key];
        if (value is num) {
          return value.toDouble();
        }
        if (value is String) {
          final parsed = double.tryParse(value);
          if (parsed != null) return parsed;
        }
      }
    }
    return null;
  }

  String? _derivePrimaryEventLabel(
    AnalyticsEventData event,
    Map<String, dynamic> sanitizedParameters,
  ) {
    final primary = event.primaryParameter;
    if (primary == null) {
      return _extractPrimaryEventLabel(sanitizedParameters);
    }
    final sanitizedValue = sanitizedParameters[primary.key];
    if (sanitizedValue == null) {
      return _extractPrimaryEventLabel(sanitizedParameters);
    }
    final stringValue = sanitizedValue.toString().trim();
    if (stringValue.isEmpty || stringValue.toLowerCase() == 'null') {
      return _extractPrimaryEventLabel(sanitizedParameters);
    }
    return '${primary.key}: $stringValue';
  }

  /// Extract the most relevant parameter/value pair to describe the event.
  /// Returns the first non-empty parameter in insertion order, formatted as
  /// "key: value".
  String? _extractPrimaryEventLabel(Map<String, dynamic> parameters) {
    for (final entry in parameters.entries) {
      final dynamic value = entry.value;
      if (value == null) continue;
      final String stringValue = value.toString().trim();
      if (stringValue.isEmpty || stringValue.toLowerCase() == 'null') {
        continue;
      }
      return '${entry.key}: $stringValue';
    }
    return null;
  }

  @override
  Future<void> dispose() async {
    if (kDebugMode) {
      log(
        'MatomoAnalyticsApi disposed',
        path: 'analytics -> MatomoAnalyticsApi -> dispose',
      );
    }
  }
}
