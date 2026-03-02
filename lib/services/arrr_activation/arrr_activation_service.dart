import 'dart:async';

import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart'
    show ExponentialBackoff, retry;
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:logging/logging.dart';
import 'package:mutex/mutex.dart';
import 'package:web_dex/mm2/mm2.dart';
import 'package:web_dex/mm2/mm2_api/rpc/disable_coin/disable_coin_req.dart';

import 'arrr_config.dart';

/// Service layer - business logic coordination for ARRR activation
class ArrrActivationService {
  ArrrActivationService(this._sdk, this._mm2)
    : _configService = _sdk.activationConfigService {
    _startListeningToAuthChanges();
  }

  final ActivationConfigService _configService;
  final KomodoDefiSdk _sdk;
  final MM2 _mm2;
  final Logger _log = Logger('ArrrActivationService');

  /// Stream controller for configuration requests
  final StreamController<ZhtlcConfigurationRequest> _configRequestController =
      StreamController<ZhtlcConfigurationRequest>.broadcast();

  /// Completer to wait for configuration when needed
  final Map<AssetId, Completer<ZhtlcUserConfig?>> _configCompleters = {};

  /// Track ongoing activation flows per asset to prevent duplicate runs
  final Map<AssetId, Future<ArrrActivationResult>> _ongoingActivations = {};
  final Set<AssetId> _cancelledActivations = <AssetId>{};

  /// Subscription to auth state changes
  StreamSubscription<KdfUser?>? _authSubscription;

  /// Flag to track if the service is being disposed
  bool _isDisposing = false;

  /// Stream of configuration requests that UI can listen to
  Stream<ZhtlcConfigurationRequest> get configurationRequests =>
      _configRequestController.stream;

  /// Future-based activation (for CoinsRepo consumers)
  /// This method will wait for user configuration if needed
  Future<ArrrActivationResult> activateArrr(
    Asset asset, {
    ZhtlcUserConfig? initialConfig,
  }) {
    if (_isDisposing || _configRequestController.isClosed) {
      throw StateError('ArrrActivationService has been disposed');
    }

    final existingActivation = _ongoingActivations[asset.id];
    if (existingActivation != null) {
      _log.info(
        'Activation already in progress for ${asset.id.id} - reusing existing future',
      );
      return existingActivation;
    }

    late Future<ArrrActivationResult> activationFuture;
    activationFuture =
        _activateArrrInternal(asset, initialConfig: initialConfig).whenComplete(
          () {
            _ongoingActivations.remove(asset.id);
          },
        );
    _ongoingActivations[asset.id] = activationFuture;
    return activationFuture;
  }

  Future<ArrrActivationResult> _activateArrrInternal(
    Asset asset, {
    ZhtlcUserConfig? initialConfig,
  }) async {
    _cancelledActivations.remove(asset.id);

    var config = initialConfig ?? await _getOrRequestConfiguration(asset.id);

    if (config == null) {
      final requiredSettings = await _getRequiredSettings(asset.id);

      final configRequest = ZhtlcConfigurationRequest(
        asset: asset,
        requiredSettings: requiredSettings,
      );

      final completer = Completer<ZhtlcUserConfig?>();
      _configCompleters[asset.id] = completer;

      _log.info('Requesting configuration for ${asset.id.id}');

      // Check if stream controller is closed or service is disposing
      if (_isDisposing || _configRequestController.isClosed) {
        _log.severe(
          'Configuration request controller is closed or service is disposing for ${asset.id.id}',
        );
        _configCompleters.remove(asset.id);
        return ArrrActivationResultError(
          'Configuration system is not available',
        );
      }

      // Wait for UI listeners to be ready before emitting request
      await _waitForUIListeners(asset.id);

      try {
        _configRequestController.add(configRequest);
        _log.info('Configuration request emitted for ${asset.id.id}');
      } catch (e, stackTrace) {
        _log.severe(
          'Failed to emit configuration request for ${asset.id.id}',
          e,
          stackTrace,
        );
        return ArrrActivationResultError('Failed to request configuration: $e');
      }

      try {
        config = await completer.future.timeout(
          const Duration(minutes: 15),
          onTimeout: () {
            _log.warning('Configuration request timed out for ${asset.id.id}');
            return null;
          },
        );
      } finally {
        _configCompleters.remove(asset.id);
      }

      if (config == null) {
        _log.info('Configuration cancelled/timed out for ${asset.id.id}');
        return ArrrActivationResultError(
          'Configuration cancelled by user or timed out',
        );
      }

      _log.info('Configuration received for ${asset.id.id}');
    }

    _log.info('Starting activation with configuration for ${asset.id.id}');
    return _performActivation(asset, config);
  }

  /// Perform the actual activation with configuration
  Future<ArrrActivationResult> _performActivation(
    Asset asset,
    ZhtlcUserConfig config,
  ) async {
    const maxAttempts = 5;
    var attempt = 0;

    try {
      final result = await retry<ArrrActivationResult>(
        () async {
          if (_isActivationCancelled(asset.id)) {
            throw _ActivationCancelledException();
          }

          attempt += 1;
          _log.info(
            'Starting ARRR activation attempt $attempt for ${asset.id.id}',
          );

          await _cacheActivationStart(asset.id);

          ActivationProgress? lastActivationProgress;
          await for (final activationProgress in _sdk.assets.activateAsset(
            asset,
          )) {
            if (_isActivationCancelled(asset.id)) {
              throw _ActivationCancelledException();
            }
            await _cacheActivationProgress(asset.id, activationProgress);
            lastActivationProgress = activationProgress;
          }

          if (lastActivationProgress?.isSuccess ?? false) {
            await _cacheActivationComplete(asset.id);
            return ArrrActivationResultSuccess(
              Stream.value(
                ActivationProgress(
                  status: 'Activation completed successfully',
                  progressPercentage: 100,
                  isComplete: true,
                  progressDetails: ActivationProgressDetails(
                    currentStep: ActivationStep.complete,
                    stepCount: 1,
                  ),
                ),
              ),
            );
          }

          final errorMessage =
              lastActivationProgress?.sdkError?.fallbackMessage ??
              lastActivationProgress?.errorMessage ??
              'Unknown activation error';
          throw _RetryableZhtlcActivationException(errorMessage);
        },
        maxAttempts: maxAttempts,
        backoffStrategy: ExponentialBackoff(
          initialDelay: const Duration(seconds: 5),
          maxDelay: const Duration(seconds: 30),
        ),
        shouldRetry: (error) => error is _RetryableZhtlcActivationException,
        onRetry: (currentAttempt, error, delay) {
          _log.warning(
            'ARRR activation attempt $currentAttempt for ${asset.id.id} failed. '
            'Retrying in ${delay.inMilliseconds}ms. Error: $error',
          );
        },
      );

      return result;
    } on _ActivationCancelledException {
      _log.info('ARRR activation cancelled by user for ${asset.id.id}');
      await _cacheActivationError(asset.id, 'Activation cancelled by user');
      return const ArrrActivationResultError('Activation cancelled by user');
    } catch (e, stackTrace) {
      _log.severe(
        'ARRR activation failed after $maxAttempts attempts for ${asset.id.id}',
        e,
        stackTrace,
      );
      await _cacheActivationError(asset.id, e.toString());
      return ArrrActivationResultError(e.toString());
    }
  }

  Future<ZhtlcUserConfig?> _getOrRequestConfiguration(AssetId assetId) async {
    final existing = await _configService.getSavedZhtlc(assetId);
    if (existing != null) return existing;

    return null;
  }

  Future<List<ActivationSettingDescriptor>> _getRequiredSettings(
    AssetId assetId,
  ) async {
    return assetId.activationSettings();
  }

  /// Activation status caching for UI display
  final Map<AssetId, ArrrActivationStatus> _activationCache = {};
  final ReadWriteMutex _activationCacheMutex = ReadWriteMutex();

  Future<void> _cacheActivationStart(AssetId assetId) async {
    await _activationCacheMutex.protectWrite(() async {
      _activationCache[assetId] = ArrrActivationStatusInProgress(
        assetId: assetId,
        startTime: DateTime.now(),
      );
    });
  }

  Future<void> _cacheActivationProgress(
    AssetId assetId,
    ActivationProgress progress,
  ) async {
    if (_isActivationCancelled(assetId)) {
      return;
    }
    await _activationCacheMutex.protectWrite(() async {
      final current = _activationCache[assetId];
      if (current is ArrrActivationStatusInProgress) {
        _activationCache[assetId] = current.copyWith(
          progressPercentage: progress.progressPercentage?.toInt(),
          currentStep: progress.progressDetails?.currentStep,
          statusMessage: progress.status,
        );
      }
    });
  }

  Future<void> _cacheActivationComplete(AssetId assetId) async {
    if (_isActivationCancelled(assetId)) {
      return;
    }
    await _activationCacheMutex.protectWrite(() async {
      _activationCache[assetId] = ArrrActivationStatusCompleted(
        assetId: assetId,
        completionTime: DateTime.now(),
      );
    });
  }

  Future<void> _cacheActivationError(
    AssetId assetId,
    String errorMessage,
  ) async {
    await _activationCacheMutex.protectWrite(() async {
      _activationCache[assetId] = ArrrActivationStatusError(
        assetId: assetId,
        errorMessage: errorMessage,
        errorTime: DateTime.now(),
      );
    });
  }

  // Public method for UI to check activation status
  Future<ArrrActivationStatus?> getActivationStatus(AssetId assetId) async {
    return _activationCacheMutex.protectRead(
      () async => _activationCache[assetId],
    );
  }

  // Public method for UI to get all cached activation statuses
  Future<Map<AssetId, ArrrActivationStatus>> get activationStatuses async {
    return _activationCacheMutex.protectRead(
      () async =>
          Map<AssetId, ArrrActivationStatus>.unmodifiable(_activationCache),
    );
  }

  // Clear cached status when no longer needed
  Future<void> clearActivationStatus(AssetId assetId) async {
    await _activationCacheMutex.protectWrite(
      () async => _activationCache.remove(assetId),
    );
  }

  Future<void> cancelActivation(AssetId assetId) async {
    _log.info('Cancelling activation for ${assetId.id}');
    _cancelledActivations.add(assetId);
    cancelConfiguration(assetId);
    await _cacheActivationError(assetId, 'Activation cancelled by user');
  }

  /// Submit configuration for a pending request
  /// Called by UI when user provides configuration
  Future<void> submitConfiguration(
    AssetId assetId,
    ZhtlcUserConfig config,
  ) async {
    if (_isDisposing) {
      _log.warning('Ignoring configuration submission - service is disposing');
      return;
    }
    _log.info('Submitting configuration for ${assetId.id}');

    // Save configuration to SDK
    final completer = _configCompleters[assetId];
    try {
      await _configService.saveZhtlcConfig(assetId, config);
      _log.info('Configuration saved to SDK for ${assetId.id}');
    } catch (e) {
      final error = ArrrActivationResultError(
        'Failed to save configuration: $e',
      );
      _log.severe(
        'Failed to save configuration to SDK for ${assetId.id}',
        error,
      );
      completer?.completeError(error);
      return;
    }

    if (completer != null && !completer.isCompleted) {
      completer.complete(config);
    } else {
      _log.warning('No pending completer found for ${assetId.id}');
    }
  }

  /// Cancel configuration for a pending request
  /// Called by UI when user cancels configuration
  void cancelConfiguration(AssetId assetId) {
    _log.info('Cancelling configuration for ${assetId.id}');
    final completer = _configCompleters[assetId];
    if (completer != null && !completer.isCompleted) {
      completer.complete(null);
    } else {
      _log.warning('No pending completer found for ${assetId.id}');
    }
  }

  /// Get diagnostic information about the configuration request system
  Map<String, dynamic> getConfigurationSystemDiagnostics() {
    return {
      'hasListeners': _configRequestController.hasListener,
      'isClosed': _configRequestController.isClosed,
      'pendingCompleters': _configCompleters.keys.map((id) => id.id).toList(),
      'handledConfigurations': _configCompleters.length,
    };
  }

  /// Test method to verify configuration request system is working
  /// This will log diagnostic information
  void diagnoseConfigurationSystem() {
    final diagnostics = getConfigurationSystemDiagnostics();
    _log.info('Configuration system diagnostics: $diagnostics');

    if (!_configRequestController.hasListener) {
      _log.warning(
        'No listeners detected for configuration requests. '
        'Make sure ZhtlcConfigurationHandler is in the widget tree.',
      );
    }

    if (_configRequestController.isClosed) {
      _log.severe('Configuration request controller is closed!');
    }
  }

  /// Wait for UI listeners to be ready before emitting configuration requests
  /// This ensures the ZhtlcConfigurationHandler is properly initialized
  Future<void> _waitForUIListeners(AssetId assetId) async {
    const maxWaitTime = Duration(seconds: 10);
    const checkInterval = Duration(milliseconds: 100);
    final stopwatch = Stopwatch()..start();

    while (!_configRequestController.hasListener &&
        stopwatch.elapsed < maxWaitTime) {
      _log.info('Waiting for UI listeners to be ready for ${assetId.id}...');
      await Future.delayed(checkInterval);
    }

    if (!_configRequestController.hasListener) {
      _log.warning(
        'No UI listeners detected after ${maxWaitTime.inSeconds} seconds for ${assetId.id}. '
        'Make sure ZhtlcConfigurationHandler is in the widget tree.',
      );
    } else {
      _log.info(
        'UI listeners ready for ${assetId.id} after ${stopwatch.elapsed.inMilliseconds}ms',
      );
    }

    stopwatch.stop();
  }

  /// Start listening to authentication state changes
  void _startListeningToAuthChanges() {
    _authSubscription?.cancel();
    _authSubscription = _sdk.auth.watchCurrentUser().listen(
      (user) => unawaited(_handleAuthStateChange(user)),
    );
  }

  /// Handle authentication state changes
  Future<void> _handleAuthStateChange(KdfUser? user) async {
    if (user == null) {
      // User signed out - cleanup all active operations
      await _cleanupOnSignOut();
    }
  }

  /// Clean up all user-specific state when user signs out
  Future<void> _cleanupOnSignOut() async {
    _log.info('User signed out - cleaning up active ZHTLC activations');
    _cancelledActivations.clear();

    // Cancel all pending configuration requests
    final pendingAssets = _configCompleters.keys.toList();
    for (final assetId in pendingAssets) {
      final completer = _configCompleters[assetId];
      if (completer != null && !completer.isCompleted) {
        _log.info('Cancelling pending configuration request for ${assetId.id}');
        completer.complete(null);
      }
    }
    _configCompleters.clear();

    // Clear activation cache as it's user-specific
    var activeAssets = <AssetId>[];
    await _activationCacheMutex.protectWrite(() async {
      activeAssets = _activationCache.keys.toList();
      for (final assetId in activeAssets) {
        _log.info('Clearing activation status for ${assetId.id}');
      }
      _activationCache.clear();
    });

    _log.info(
      'Cleanup completed - cancelled ${pendingAssets.length} pending configs and cleared ${activeAssets.length} activation statuses',
    );
  }

  /// Updates the configuration for an already activated ZHTLC coin
  /// This will:
  /// 1. Cancel any ongoing activation tasks for the asset
  /// 2. Disable the coin if it's currently active
  /// 3. Store the new configuration
  Future<void> updateZhtlcConfig(Asset asset, ZhtlcUserConfig newConfig) async {
    if (_isDisposing || _configRequestController.isClosed) {
      throw StateError('ArrrActivationService has been disposed');
    }

    _log.info('Updating ZHTLC configuration for ${asset.id.id}');

    try {
      // Cancel any pending configuration requests
      final completer = _configCompleters[asset.id];
      if (completer != null && !completer.isCompleted) {
        _log.info(
          'Cancelling pending configuration request for ${asset.id.id}',
        );
        completer.complete(null);
        _configCompleters.remove(asset.id);
      }

      // 2. Disable the coin if it's currently active
      await _disableCoin(asset.id.id);

      // 3. Store the new configuration
      _log.info('Saving new configuration for ${asset.id.id}');
      await _configService.saveZhtlcConfig(asset.id, newConfig);
    } catch (e, stackTrace) {
      _log.severe(
        'Failed to update ZHTLC configuration for ${asset.id.id}',
        e,
        stackTrace,
      );
      await _cacheActivationError(asset.id, e.toString());
    }
  }

  /// Disable a coin by calling the MM2 disable_coin RPC
  /// Copied from CoinsRepo._disableCoin for consistency
  Future<void> _disableCoin(String coinId) async {
    try {
      final activatedAssets = await _sdk.assets.getEnabledCoins();
      final isCurrentlyActive = activatedAssets.any(
        (configId) => configId == coinId,
      );
      if (isCurrentlyActive) {
        _log.info('Disabling currently active ZHTLC coin $coinId');
        await _mm2.call(DisableCoinReq(coin: coinId));
        _log.info('Successfully disabled coin $coinId');
      }
    } catch (e, s) {
      _log.shout('Error disabling $coinId', e, s);
      // Don't rethrow - we want to continue with the configuration update
    }
  }

  /// Dispose resources
  void dispose() {
    // Mark as disposing to prevent new operations
    _isDisposing = true;
    _cancelledActivations.clear();

    // Cancel auth subscription first
    _authSubscription?.cancel();

    // Complete any pending configuration requests with a specific error
    for (final completer in _configCompleters.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Service is being disposed'));
      }
    }
    _configCompleters.clear();

    // Close controller after ensuring all operations are complete
    if (!_configRequestController.isClosed) {
      _configRequestController.close();
    }
  }

  bool _isActivationCancelled(AssetId assetId) {
    return _cancelledActivations.contains(assetId);
  }
}

class _RetryableZhtlcActivationException implements Exception {
  const _RetryableZhtlcActivationException(this.message);

  final String message;

  @override
  String toString() => 'RetryableZhtlcActivationException: $message';
}

class _ActivationCancelledException implements Exception {
  const _ActivationCancelledException();

  @override
  String toString() => 'Activation cancelled by user';
}

/// Configuration request model for UI handling
class ZhtlcConfigurationRequest {
  const ZhtlcConfigurationRequest({
    required this.asset,
    required this.requiredSettings,
  });

  final Asset asset;
  final List<ActivationSettingDescriptor> requiredSettings;
}
