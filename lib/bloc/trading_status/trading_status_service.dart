import 'dart:async';

import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:logging/logging.dart';
import 'package:web_dex/bloc/trading_status/app_geo_status.dart';
import 'package:web_dex/bloc/trading_status/disallowed_feature.dart';
import 'package:web_dex/bloc/trading_status/trading_status_repository.dart';

/// Keeps cached UI restrictions available while independently gating activation
/// on a successful, current policy lookup.
class TradingStatusService {
  TradingStatusService(
    this._repository, {
    ActivationPolicy? activationPolicy,
    this.lookupTimeout = const Duration(seconds: 10),
    this.retryInterval = const Duration(seconds: 5),
    this.pollingInterval = const Duration(minutes: 1),
  }) : _activationPolicy = activationPolicy {
    _publishPolicy();
  }

  final TradingStatusRepository _repository;
  final ActivationPolicy? _activationPolicy;
  final Duration lookupTimeout;
  final Duration retryInterval;
  final Duration pollingInterval;
  final _log = Logger('TradingStatusService');
  final _statusController = StreamController<AppGeoStatus>.broadcast();
  final _initialStatusCompleter = Completer<void>();
  Timer? _timer;
  Future<AppGeoStatus>? _inFlight;
  bool _disposed = false;
  bool _initialized = false;

  AppGeoStatus _currentStatus = const AppGeoStatus(
    lookupStatus: ActivationPolicyStatus.loading,
    disallowedFeatures: {DisallowedFeature.trading},
  );

  Future<void> get initialStatusReady => _initialStatusCompleter.future;
  Stream<AppGeoStatus> get statusStream => _statusController.stream;
  AppGeoStatus get currentStatus => _currentStatus;
  bool get isTradingEnabled => _currentStatus.tradingEnabled;
  bool get isActivationReady =>
      _currentStatus.lookupStatus == ActivationPolicyStatus.ready;
  Set<AssetId> get blockedAssets => _currentStatus.disallowedAssets;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      await refreshStatus();
    } catch (_) {
      // Failure is represented by unavailable, with an automatic retry.
    }
  }

  Future<AppGeoStatus> refreshStatus({bool? forceFail}) {
    if (_disposed) throw StateError('Trading status service is disposed');
    return _inFlight ??= _refresh(
      forceFail: forceFail,
    ).whenComplete(() => _inFlight = null);
  }

  Future<AppGeoStatus> _refresh({bool? forceFail}) async {
    _timer?.cancel();
    _updateStatus(
      _currentStatus.withLookupStatus(ActivationPolicyStatus.loading),
    );
    try {
      final status = await _repository
          .fetchStatus(forceFail: forceFail)
          .timeout(lookupTimeout);
      if (_disposed) return status;
      _updateStatus(status.withLookupStatus(ActivationPolicyStatus.ready));
      _schedule(pollingInterval);
      return _currentStatus;
    } catch (error) {
      if (!_disposed) {
        _log.warning(
          'Geo policy lookup is unavailable; retaining restrictions',
        );
        _updateStatus(
          _currentStatus.withLookupStatus(ActivationPolicyStatus.unavailable),
        );
        _schedule(retryInterval);
      }
      rethrow;
    } finally {
      if (!_initialStatusCompleter.isCompleted) {
        _initialStatusCompleter.complete();
      }
    }
  }

  void _schedule(Duration interval) {
    _timer = Timer(interval, () {
      unawaited(refreshStatus().catchError((Object _) => _currentStatus));
    });
  }

  void _updateStatus(AppGeoStatus status) {
    _currentStatus = status;
    _publishPolicy();
    if (!_disposed) _statusController.add(status);
  }

  void _publishPolicy() => _activationPolicy?.update(
    ActivationPolicySnapshot(
      status: _currentStatus.lookupStatus,
      blockedAssets: _currentStatus.disallowedAssets,
    ),
  );

  bool isAssetBlocked(AssetId assetId) =>
      _currentStatus.isAssetBlocked(assetId);

  List<Asset> filterAllowedAssets(List<Asset> assets) =>
      assets.where((asset) => !isAssetBlocked(asset.id)).toList();

  Map<String, T> filterAllowedAssetsMap<T>(
    Map<String, T> assetsMap,
    AssetId Function(T) getAssetId,
  ) => Map.fromEntries(
    assetsMap.entries.where(
      (entry) => !isAssetBlocked(getAssetId(entry.value)),
    ),
  );

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    unawaited(_statusController.close());
  }
}
