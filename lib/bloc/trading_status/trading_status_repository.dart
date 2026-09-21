import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:logging/logging.dart';
import 'package:web_dex/bloc/trading_status/app_geo_status.dart';
import 'package:web_dex/bloc/trading_status/disallowed_feature.dart';
import 'package:web_dex/bloc/trading_status/trading_status_api_provider.dart';

class TradingStatusRepository {
  TradingStatusRepository(this._sdk, {TradingStatusApiProvider? apiProvider})
    : _apiProvider = apiProvider ?? TradingStatusApiProvider();

  final TradingStatusApiProvider _apiProvider;
  final Logger _log = Logger('TradingStatusRepository');
  final KomodoDefiSdk _sdk;

  /// Fetches geo status and computes trading availability.
  ///
  /// Rules:
  /// - If GEO_BLOCK=disabled, trading is enabled.
  /// - Otherwise, trading is disabled if disallowed_features contains 'TRADING'.
  Future<AppGeoStatus> fetchStatus({bool? forceFail}) async {
    try {
      if (_isGeoBlockDisabled()) {
        _log.info('GEO_BLOCK is disabled. Trading enabled.');
        return const AppGeoStatus();
      }

      final bool shouldFail = forceFail ?? false;
      final String apiKey = _readFeedbackApiKey();

      if (apiKey.isEmpty && !shouldFail) {
        throw StateError('Geo policy API key is unavailable');
      }

      late final JsonMap data;
      if (shouldFail) {
        final res = await _apiProvider.fetchTradingBlacklist();
        return AppGeoStatus(
          disallowedFeatures: res.statusCode == 200
              ? const <DisallowedFeature>{}
              : const <DisallowedFeature>{DisallowedFeature.trading},
        );
      }

      data = await _apiProvider
          .fetchGeoStatus(apiKey: apiKey)
          .timeout(const Duration(seconds: 10));

      final featuresParsed = _parseFeatures(data);
      final Set<AssetId> disallowedAssets = _parseAssets(data);

      if (!featuresParsed.hasFeatures) {
        throw const FormatException('Geo policy response omitted restrictions');
      }

      return AppGeoStatus(
        disallowedAssets: disallowedAssets,
        disallowedFeatures: featuresParsed.features,
      );
    } on Exception catch (e, s) {
      _log.severe('Unexpected error during trading status check', e, s);
      rethrow;
    }
  }

  /// Backward-compatible helper for existing call sites.
  Future<bool> isTradingEnabled({bool? forceFail}) async {
    final status = await fetchStatus(forceFail: forceFail);
    return status.tradingEnabled;
  }

  // --- Configuration helpers -------------------------------------------------
  String _readGeoBlockFlag() => const String.fromEnvironment('GEO_BLOCK');
  String _readFeedbackApiKey() =>
      const String.fromEnvironment('FEEDBACK_API_KEY');
  bool _isGeoBlockDisabled() => _readGeoBlockFlag() == 'disabled';

  // --- Parsing helpers -------------------------------------------------------

  ({Set<DisallowedFeature> features, bool hasFeatures}) _parseFeatures(
    JsonMap data,
  ) {
    final List<String>? raw = data.valueOrNull<List<String>>(
      'disallowed_features',
    );
    final Set<DisallowedFeature> parsed = raw == null
        ? <DisallowedFeature>{}
        : raw.map(DisallowedFeature.parse).toSet();
    return (features: parsed, hasFeatures: raw != null);
  }

  Set<AssetId> _parseAssets(JsonMap data) {
    final List<String>? raw = data.valueOrNull<List<String>>(
      'disallowed_assets',
    );
    if (raw == null) return const <AssetId>{};

    final Set<AssetId> out = <AssetId>{};
    for (final symbol in raw) {
      try {
        final assets = _sdk.assets.findAssetsByConfigId(symbol);
        out.addAll(assets.map((a) => a.id));
      } catch (e, s) {
        _log.warning('Failed to resolve asset "$symbol"', e, s);
      }
    }
    return out;
  }

  void dispose() {
    _apiProvider.dispose();
  }
}
