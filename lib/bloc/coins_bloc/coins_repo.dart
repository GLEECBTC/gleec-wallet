import 'dart:async';
import 'dart:math' show min;

import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart' show NetworkImage;
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart'
    as kdf_rpc;
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart'
    show ExponentialBackoff, retry;
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_ui/komodo_ui.dart';
import 'package:logging/logging.dart';
import 'package:web_dex/app_config/app_config.dart'
    show excludedAssetList, kDebugElectrumLogs;
import 'package:web_dex/bloc/coins_bloc/asset_coin_extension.dart';
import 'package:web_dex/bloc/trading_status/trading_status_service.dart'
    show TradingStatusService;
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/mm2/mm2.dart';
import 'package:web_dex/mm2/mm2_api/rpc/base.dart';
import 'package:web_dex/mm2/mm2_api/rpc/bloc_response.dart';
import 'package:web_dex/mm2/mm2_api/rpc/withdraw/withdraw_errors.dart';
import 'package:web_dex/mm2/mm2_api/rpc/withdraw/withdraw_request.dart';
import 'package:web_dex/model/cex_price.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/kdf_auth_metadata_extension.dart';
import 'package:web_dex/model/text_error.dart';
import 'package:web_dex/model/withdraw_details/withdraw_details.dart';
import 'package:web_dex/services/arrr_activation/arrr_activation_service.dart';
import 'package:web_dex/services/fd_monitor_service.dart';
import 'package:web_dex/shared/utils/platform_tuner.dart';

/// Exception used to indicate that ZHTLC activation was cancelled by the user.
class ZhtlcActivationCancelled implements Exception {
  ZhtlcActivationCancelled(this.coinId);
  final String coinId;
  @override
  String toString() => 'ZhtlcActivationCancelled: $coinId';
}

class CoinsRepo {
  CoinsRepo({
    required KomodoDefiSdk kdfSdk,
    required MM2 mm2,
    required TradingStatusService tradingStatusService,
    required ArrrActivationService arrrActivationService,
  }) : _kdfSdk = kdfSdk,
       _mm2 = mm2,
       _tradingStatusService = tradingStatusService,
       _arrrActivationService = arrrActivationService {
    enabledAssetsChanges = StreamController<Coin>.broadcast(
      onListen: () => _enabledAssetListenerCount += 1,
      onCancel: () => _enabledAssetListenerCount -= 1,
    );
    balanceChanges = StreamController<Coin>.broadcast(
      onListen: () => _balanceListenerCount += 1,
      onCancel: () => _balanceListenerCount -= 1,
    );
  }

  final KomodoDefiSdk _kdfSdk;
  final MM2 _mm2;
  final TradingStatusService _tradingStatusService;
  final ArrrActivationService _arrrActivationService;

  final _log = Logger('CoinsRepo');

  /// { acc: { abbr: address }}, used in Fiat Page
  final Map<String, Map<String, String>> _addressCache = {};

  // TODO: Remove since this is also being cached in the SDK
  final Map<String, CexPrice> _pricesCache = {};

  // Cache structure for storing balance information to reduce SDK calls
  // This is a temporary solution until the full migration to SDK is complete
  // The type is being kept as ({ double balance, double spendable }) to minimize
  // the changes needed for full migration in the future
  final Map<String, ({double balance, double spendable})> _balancesCache = {};

  // Map to keep track of active balance watchers
  final Map<AssetId, StreamSubscription<BalanceInfo>> _balanceWatchers = {};

  /// Tracks in-flight activations per asset to prevent duplicate concurrent activations
  final Map<AssetId, Future<void>> _activationsInFlight = {};

  /// Initial activation gate: used by UI flows to wait until initial wallet
  /// activation completes in CoinsBloc before firing additional activations.
  bool _initialActivationInProgress = false;
  Completer<void>? _initialActivationCompleter;

  /// Mark start of the initial activation phase (called by CoinsBloc)
  void markInitialActivationStart() {
    _initialActivationInProgress = true;
    if (_initialActivationCompleter == null ||
        (_initialActivationCompleter?.isCompleted ?? true)) {
      _initialActivationCompleter = Completer<void>();
    }
  }

  /// Mark completion of the initial activation phase (called by CoinsBloc)
  void markInitialActivationComplete() {
    _initialActivationInProgress = false;
    final completer = _initialActivationCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  /// Await completion of the initial activation phase.
  /// If not in progress, returns immediately. If in progress and a timeout is
  /// provided, waits up to the timeout, otherwise waits until completion.
  Future<void> waitForInitialActivationToComplete({
    Duration? timeout,
  }) async {
    if (!_initialActivationInProgress) return;
    final completer = _initialActivationCompleter;
    if (completer == null) return;
    try {
      if (timeout == null) {
        await completer.future;
      } else {
        await completer.future.timeout(timeout);
      }
    } catch (_) {
      // Swallow timeout/errors; callers should proceed even if gate didn’t finish
    }
  }

  Future<bool> _waitForCoinAvailability(
    AssetId assetId, {
    int maxRetries = 5,
    Duration baseDelay = const Duration(milliseconds: 600),
    Duration maxDelay = const Duration(milliseconds: 3000),
  }) async {
    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        final activated = await _kdfSdk.activatedAssetsCache
            .getActivatedAssetIds(forceRefresh: true);
        if (activated.contains(assetId)) return true;
      } catch (_) {}

      if (attempt < maxRetries - 1) {
        final delayMs = (baseDelay.inMilliseconds * (1 << attempt))
            .clamp(baseDelay.inMilliseconds, maxDelay.inMilliseconds);
        await Future<void>.delayed(Duration(milliseconds: delayMs));
      }
    }
    return false;
  }

  /// Hack used to broadcast activated/deactivated coins to the CoinsBloc to
  /// update the status of the coins in the UI layer. This is needed as there
  /// are direct references to [CoinsRepo] that activate/deactivate coins
  /// without the [CoinsBloc] being aware of the changes (e.g. [CoinsManagerBloc]).
  late final StreamController<Coin> enabledAssetsChanges;
  // why could they not implement this in streamcontroller or a wrapper :(
  int _enabledAssetListenerCount = 0;
  bool get _enabledAssetsHasListeners => _enabledAssetListenerCount > 0;
  void _broadcastAsset(Coin coin) {
    if (_enabledAssetsHasListeners) {
      enabledAssetsChanges.add(coin);
    } else {
      _log.warning(
        'No listeners for enabledAssetsChanges stream. '
        'Skipping broadcast for ${coin.id.id}',
      );
    }
  }

  /// Stream to broadcast real-time balance changes for coins
  late final StreamController<Coin> balanceChanges;
  int _balanceListenerCount = 0;
  bool get _balancesHasListeners => _balanceListenerCount > 0;
  void _broadcastBalanceChange(Coin coin) {
    if (_balancesHasListeners) {
      balanceChanges.add(coin);
    } else {
      _log.fine(
        'No listeners for balanceChanges stream. '
        'Skipping broadcast for ${coin.id.id}',
      );
    }
  }

  Future<BalanceInfo?> balance(AssetId id) => _kdfSdk.balances.getBalance(id);

  BalanceInfo? lastKnownBalance(AssetId id) => _kdfSdk.balances.lastKnown(id);

  /// Subscribe to balance updates for an asset using the SDK's balance manager
  void _subscribeToBalanceUpdates(Asset asset) {
    // Cancel any existing subscription for this asset
    _balanceWatchers[asset.id]?.cancel();

    if (_tradingStatusService.isAssetBlocked(asset.id)) {
      _log.info('Asset ${asset.id.id} is blocked. Skipping balance updates.');
      return;
    }

    // Start a new subscription
    _balanceWatchers[asset.id] = _kdfSdk.balances.watchBalance(asset.id).listen(
      (balanceInfo) {
        // Update the balance cache with the new values
        _balancesCache[asset.id.id] = (
          balance: balanceInfo.total.toDouble(),
          spendable: balanceInfo.spendable.toDouble(),
        );

        // Broadcast updated coin for UI to refresh via bloc
        _broadcastBalanceChange(_assetToCoinWithoutAddress(asset));
      },
    );
  }

  void flushCache() {
    // Intentionally avoid flushing the prices cache - prices are independent
    // of the user's session and should be updated on a regular basis.
    _addressCache.clear();
    _balancesCache.clear();

    // Cancel all balance watchers
    for (final subscription in _balanceWatchers.values) {
      subscription.cancel();
    }
    _balanceWatchers.clear();
    _invalidateActivatedAssetsCache();
  }

  void dispose() {
    for (final subscription in _balanceWatchers.values) {
      subscription.cancel();
    }
    _balanceWatchers.clear();

    enabledAssetsChanges.close();
    balanceChanges.close();
  }

  Future<Set<AssetId>> getActivatedAssetIds({bool forceRefresh = false}) {
    return _kdfSdk.activatedAssetsCache.getActivatedAssetIds(
      forceRefresh: forceRefresh,
    );
  }

  Future<bool> isAssetActivated(
    AssetId assetId, {
    bool forceRefresh = false,
  }) async {
    final activated = await getActivatedAssetIds(forceRefresh: forceRefresh);
    return activated.contains(assetId);
  }

  void _invalidateActivatedAssetsCache() {
    _kdfSdk.activatedAssetsCache.invalidate();
  }

  /// Returns all known coins, optionally filtering out excluded assets.
  /// If [excludeExcludedAssets] is true, coins whose id is in
  /// [excludedAssetList] are filtered out.
  List<Coin> getKnownCoins({bool excludeExcludedAssets = false}) {
    final assets = Map<AssetId, Asset>.of(_kdfSdk.assets.available);
    if (excludeExcludedAssets) {
      assets.removeWhere((key, _) => excludedAssetList.contains(key.id));
    }
    // Filter out blocked assets
    final allowedAssets = _tradingStatusService.filterAllowedAssets(
      assets.values.toList(),
    );
    return allowedAssets.map(_assetToCoinWithoutAddress).toList();
  }

  /// Returns a map of all known coins, optionally filtering out excluded assets.
  /// If [excludeExcludedAssets] is true, coins whose id is in
  /// [excludedAssetList] are filtered out.
  Map<String, Coin> getKnownCoinsMap({bool excludeExcludedAssets = false}) {
    final assets = Map<AssetId, Asset>.of(_kdfSdk.assets.available);
    if (excludeExcludedAssets) {
      assets.removeWhere((key, _) => excludedAssetList.contains(key.id));
    }
    final allowedAssets = _tradingStatusService.filterAllowedAssets(
      assets.values.toList(),
    );
    return Map.fromEntries(
      allowedAssets.map(
        (asset) => MapEntry(asset.id.id, _assetToCoinWithoutAddress(asset)),
      ),
    );
  }

  Coin? getCoinFromId(AssetId id) {
    final asset = _kdfSdk.assets.available[id];
    if (asset == null) return null;
    return _assetToCoinWithoutAddress(asset);
  }

  @Deprecated('Use KomodoDefiSdk assets or getCoinFromId instead.')
  Coin? getCoin(String coinId) {
    if (coinId.isEmpty) return null;

    try {
      final assets = _kdfSdk.assets.assetsFromTicker(coinId);
      if (assets.isEmpty || assets.length > 1) {
        _log.warning(
          'Coin "$coinId" not found. ${assets.length} results returned',
        );
        return null;
      }
      return _assetToCoinWithoutAddress(assets.single);
    } catch (_) {
      return null;
    }
  }

  @Deprecated(
    'Use KomodoDefiSdk assets or the '
    'Wallet [KdfUser].wallet extension instead.',
  )
  Future<List<Coin>> getWalletCoins() async {
    final walletAssets = await _kdfSdk.getWalletAssets();
    return _tradingStatusService
        .filterAllowedAssets(walletAssets)
        .map(_assetToCoinWithoutAddress)
        .toList();
  }

  Coin _assetToCoinWithoutAddress(Asset asset) {
    final coin = asset.toCoin();
    final balanceInfo = _balancesCache[coin.id.id];
    final price = _pricesCache[coin.id.symbol.configSymbol.toUpperCase()];

    Coin? parentCoin;
    if (asset.id.isChildAsset) {
      final parentCoinId = asset.id.parentId!;
      final parentAsset = _kdfSdk.assets.available[parentCoinId];
      if (parentAsset == null) {
        _log.warning('Parent coin $parentCoinId not found.');
        parentCoin = null;
      } else {
        parentCoin = _assetToCoinWithoutAddress(parentAsset);
      }
    }

    // For backward compatibility, still set the deprecated fields
    // This will be removed in a future migration step
    return coin.copyWith(
      sendableBalance: balanceInfo?.spendable,
      usdPrice: price,
      parentCoin: parentCoin,
    );
  }

  /// Attempts to get the balance of a coin. If the coin is not found, it will
  /// return a zero balance.
  Future<kdf_rpc.BalanceInfo> tryGetBalanceInfo(AssetId coinId) async {
    try {
      // Avoid triggering backend wallet-balance tasks for inactive assets.
      final isActive = await isAssetActivated(coinId);
      if (!isActive) {
        return kdf_rpc.BalanceInfo.zero();
      }
      final balanceInfo = await _kdfSdk.balances.getBalance(coinId);
      return balanceInfo;
    } catch (e, s) {
      _log.shout('Failed to get coin $coinId balance', e, s);
      return kdf_rpc.BalanceInfo.zero();
    }
  }

  /// Activates multiple assets synchronously with retry logic and exponential backoff.
  ///
  /// This method attempts to activate the provided [assets] with robust error handling
  /// and automatic retry functionality. If activation fails, it will retry with
  /// exponential backoff for up to the specified duration.
  ///
  /// **Retry Configuration:**
  /// - Default: 500ms → 1s → 2s → 4s → 8s → 10s → 10s... (15 attempts ≈ 105 seconds)
  /// - Configurable via [maxRetryAttempts], [initialRetryDelay], and [maxRetryDelay]
  ///
  /// **Parameters:**
  /// - [assets]: List of assets to activate
  /// - [notifyListeners]: Whether to broadcast state changes to listeners (default: true)
  /// - [addToWalletMetadata]: Whether to add assets to wallet metadata (default: true)
  /// - [maxRetryAttempts]: Maximum number of retry attempts (default: 15)
  /// - [initialRetryDelay]: Initial delay between retries (default: 500ms)
  /// - [maxRetryDelay]: Maximum delay between retries (default: 10s)
  ///
  /// **State Changes:**
  /// - `CoinState.activating`: Broadcast when activation begins
  /// - `CoinState.active`: Broadcast on successful activation
  /// - `CoinState.suspended`: Broadcast on final failure after all retries
  ///
  /// **Throws:**
  /// - `Exception`: If activation fails after all retry attempts
  ///
  /// **Note:** Assets are added to wallet metadata even if activation fails.
  Future<void> activateAssetsSync(
    List<Asset> assets, {
    bool notifyListeners = true,
    bool addToWalletMetadata = true,
    int maxRetryAttempts = 15,
    Duration initialRetryDelay = const Duration(milliseconds: 500),
    Duration maxRetryDelay = const Duration(seconds: 10),
  }) async {
    final isSignedIn = await _kdfSdk.auth.isSignedIn();
    if (!isSignedIn) {
      final coinIdList = assets.map((e) => e.id.id).join(', ');
      _log.warning('No wallet signed in. Skipping activation of [$coinIdList]');
      return;
    }

    // Debug logging for activation
    if (kDebugElectrumLogs) {
      final coinIdList = assets.map((e) => e.id.id).join(', ');
      final protocolBreakdown = <String, int>{};
      for (final asset in assets) {
        final protocol = asset.protocol.runtimeType.toString();
        protocolBreakdown[protocol] = (protocolBreakdown[protocol] ?? 0) + 1;
      }
      _log.info(
        '[ACTIVATION] Starting activation of ${assets.length} coins: [$coinIdList]',
      );
      _log.info('[ACTIVATION] Protocol breakdown: $protocolBreakdown');

      // Log detailed parameters for each asset being activated
      for (final asset in assets) {
        _log.info(
          '[ACTIVATION] Asset: ${asset.id.id}, Protocol: ${asset.protocol.runtimeType}, '
          'SubClass: ${asset.id.subClass}, ParentId: ${asset.id.parentId?.id ?? "none"}',
        );
      }
    }

    // Separate ZHTLC and regular assets
    final zhtlcAssets = assets
        .where((asset) => asset.id.subClass == CoinSubClass.zhtlc)
        .toList();
    final regularAssets = assets
        .where((asset) => asset.id.subClass != CoinSubClass.zhtlc)
        .toList();

    // Process ZHTLC assets separately
    if (zhtlcAssets.isNotEmpty) {
      await _activateZhtlcAssets(
        zhtlcAssets,
        zhtlcAssets.map((asset) => _assetToCoinWithoutAddress(asset)).toList(),
        notifyListeners: notifyListeners,
        addToWalletMetadata: addToWalletMetadata,
      );
    }

    // Continue with regular asset processing for non-ZHTLC assets
    if (regularAssets.isEmpty) return;

    // Update assets list to only include regular assets for remaining processing
    assets = regularAssets;

    if (addToWalletMetadata) {
      // Ensure the wallet metadata is updated with the assets before activation
      // This is to ensure that the wallet metadata is always in sync with the assets
      // being activated, even if activation fails.
      await _addAssetsToWalletMetdata(assets.map((asset) => asset.id));
    }

    Exception? lastActivationException;

    for (final asset in assets) {
      final coin = _assetToCoinWithoutAddress(asset);
      try {
        // Check if asset is already activated to avoid SDK exception.
        // The SDK throws an exception when trying to activate an already-activated
        // asset, so we need this manual check to prevent unnecessary retries.
        final isAlreadyActivated = await isAssetActivated(asset.id);

        if (isAlreadyActivated) {
          _log.info(
            'Asset ${asset.id.id} is already activated. Skipping activation.',
          );
        } else {
          // Deduplicate concurrent activations for the same asset
          final existing = _activationsInFlight[asset.id];
          if (existing != null) {
            _log.info(
              'Activation already in progress for ${asset.id.id}. Joining existing task.',
            );
            await existing;
          } else {
            if (notifyListeners) {
              _broadcastAsset(coin.copyWith(state: CoinState.activating));
            }

            // Start activation once and track in-flight future.
            // Avoid over-eager retries that can create duplicate backend tasks.
            final activationFuture = (() async {
              try {
                final progress =
                    await _kdfSdk.assets.activateAsset(asset).last;
                if (!progress.isSuccess) {
                  throw Exception(
                    progress.errorMessage ??
                        'Activation failed for ${asset.id.id}',
                  );
                }
              } catch (e) {
                final err = e.toString();
                final maybeIdempotentStorageError = err.contains('ConstraintError') ||
                    err.contains("wallet_account_id") ||
                    err.contains('Error saving HD account to storage');
                if (maybeIdempotentStorageError) {
                  // Treat as idempotent: wait briefly for coin to appear instead of re-initiating.
                  final becameActive = await _waitForCoinAvailability(asset.id);
                  if (becameActive) return;
                }
                rethrow;
              }
            })().whenComplete(() {
              _activationsInFlight.remove(asset.id);
            });

            _activationsInFlight[asset.id] = activationFuture;
            await activationFuture;

            _log.info('Asset activated: ${asset.id.id}');
          }
        }
        if (kDebugElectrumLogs) {
          _log.info(
            '[ACTIVATION] Successfully activated ${asset.id.id} (${asset.protocol.runtimeType})',
          );
          _log.info(
            '[ACTIVATION] Activation completed for ${asset.id.id}, '
            'Protocol: ${asset.protocol.runtimeType}, '
            'SubClass: ${asset.id.subClass}',
          );
        }
        if (notifyListeners) {
          _broadcastAsset(coin.copyWith(state: CoinState.active));
          if (coin.id.parentId != null) {
            final parentCoin = _assetToCoinWithoutAddress(
              _kdfSdk.assets.available[coin.id.parentId]!,
            );
            _broadcastAsset(parentCoin.copyWith(state: CoinState.active));
          }
        }
        _subscribeToBalanceUpdates(asset);
        if (kDebugElectrumLogs) {
          _log.info(
            '[ACTIVATION] Subscribed to balance updates for ${asset.id.id}',
          );
        }
        if (coin.id.parentId != null) {
          final parentAsset = _kdfSdk.assets.available[coin.id.parentId];
          if (parentAsset == null) {
            _log.warning('Parent asset not found: ${coin.id.parentId}');
          } else {
            _subscribeToBalanceUpdates(parentAsset);
          }
        }
      } catch (e, s) {
        lastActivationException = e is Exception ? e : Exception(e.toString());
        _log.shout(
          'Error activating asset after retries: ${asset.id.id}',
          e,
          s,
        );

        // Capture FD snapshot when KDF asset activation fails
        if (PlatformTuner.isIOS) {
          try {
            await FdMonitorService().logDetailedStatus();
            final stats = await FdMonitorService().getCurrentCount();
            _log.warning(
              'FD stats at asset activation failure for ${asset.id.id}: $stats',
            );
          } catch (fdError) {
            _log.warning('Failed to capture FD stats: $fdError');
          }
        }

        if (notifyListeners) {
          _broadcastAsset(asset.toCoin().copyWith(state: CoinState.suspended));
        }
      } finally {
        // Register outside of the try-catch to ensure icon is available even
        // in a suspended or failing activation status.
        if (coin.logoImageUrl?.isNotEmpty ?? false) {
          AssetIcon.registerCustomIcon(
            coin.id,
            NetworkImage(coin.logoImageUrl!),
          );
        }
      }
    }

    // Invalidate the activated assets cache once after processing all assets
    _invalidateActivatedAssetsCache();

    // Rethrow the last activation exception if there was one
    if (lastActivationException != null) {
      throw lastActivationException;
    }
  }

  Future<void> _addAssetsToWalletMetdata(Iterable<AssetId> assets) async {
    final parentIds = <String>{};
    for (final assetId in assets) {
      if (assetId.parentId != null) {
        parentIds.add(assetId.parentId!.id);
      }
    }

    if (assets.isNotEmpty || parentIds.isNotEmpty) {
      final allIdsToAdd = <String>{...assets.map((e) => e.id), ...parentIds};
      await _kdfSdk.addActivatedCoins(allIdsToAdd);
    }
  }

  /// Activates multiple coins synchronously with retry logic and exponential backoff.
  ///
  /// This method attempts to activate the provided [coins] with robust error handling
  /// and automatic retry functionality. It includes smart logic to skip already
  /// activated coins and retry failed activations with exponential backoff.
  ///
  /// **Retry Configuration:**
  /// - Default: 500ms → 1s → 2s → 4s → 8s → 10s → 10s... (15 attempts ≈ 105 seconds)
  /// - Configurable via [maxRetryAttempts], [initialRetryDelay], and [maxRetryDelay]
  ///
  /// **Parameters:**
  /// - [coins]: List of coins to activate
  /// - [notify]: Whether to broadcast state changes to listeners (default: true)
  /// - [addToWalletMetadata]: Whether to add assets to wallet metadata (default: true)
  /// - [maxRetryAttempts]: Maximum number of retry attempts (default: 15)
  /// - [initialRetryDelay]: Initial delay between retries (default: 500ms)
  /// - [maxRetryDelay]: Maximum delay between retries (default: 10s)
  ///
  /// **State Changes:**
  /// - `CoinState.activating`: Broadcast when activation begins
  /// - `CoinState.active`: Broadcast on successful activation or if already active
  /// - `CoinState.suspended`: Broadcast on final failure after all retries
  ///
  /// **Behavior:**
  /// - Skips coins that are already activated
  /// - Adds coins to wallet metadata regardless of activation status
  /// - Subscribes to balance updates for successfully activated coins
  ///
  /// **Throws:**
  /// - `Exception`: If activation fails after all retry attempts
  Future<void> activateCoinsSync(
    List<Coin> coins, {
    bool notify = true,
    bool addToWalletMetadata = true,
    int maxRetryAttempts = 15,
    Duration initialRetryDelay = const Duration(milliseconds: 500),
    Duration maxRetryDelay = const Duration(seconds: 10),
  }) async {
    final assets = coins
        .map((coin) => _kdfSdk.assets.available[coin.id])
        // use cast instead of `whereType` to ensure an exception is thrown
        // if the provided asset is not found in the SDK. An explicit
        // argument error might be more apt here.
        .cast<Asset>()
        .toList();

    return activateAssetsSync(
      assets,
      notifyListeners: notify,
      addToWalletMetadata: addToWalletMetadata,
      maxRetryAttempts: maxRetryAttempts,
      initialRetryDelay: initialRetryDelay,
      maxRetryDelay: maxRetryDelay,
    );
  }

  /// Deactivates the given coins and cancels their balance watchers.
  /// If [notify] is true, it will broadcast the deactivation to listeners.
  /// This method is used to deactivate coins that are no longer needed or
  /// supported by the user.
  ///
  /// NOTE: Only balance watchers are cancelled, the coins are not deactivated
  /// in the SDK or MM2. This is a temporary solution to avoid "NoSuchCoin"
  /// errors when trying to re-enable the coin later in the same session.
  Future<void> deactivateCoinsSync(
    List<Coin> coins, {
    bool notify = true,
  }) async {
    final allCoinIds = <String>{};
    final allChildCoins = <Coin>[];

    final activatedAssets = await _kdfSdk.activatedAssetsCache
        .getActivatedAssets();
    for (final coin in coins) {
      allCoinIds.add(coin.id.id);

      final children = activatedAssets
          .where((asset) => asset.id.parentId == coin.id)
          .map(_assetToCoinWithoutAddress)
          .toList();

      allChildCoins.addAll(children);
      allCoinIds.addAll(children.map((child) => child.id.id));
    }

    if (allCoinIds.isNotEmpty) {
      // assume success here, so we don't await this call and
      // block the deactivation process
      unawaited(_kdfSdk.removeActivatedCoins(allCoinIds.toList()));
    }

    final parentCancelFutures = coins.map((coin) async {
      await _balanceWatchers[coin.id]?.cancel();
      _balanceWatchers.remove(coin.id);
    });

    final childCancelFutures = allChildCoins.map((child) async {
      await _balanceWatchers[child.id]?.cancel();
      _balanceWatchers.remove(child.id);
    });

    // Skip the deactivation step for now, as it results in "NoSuchCoin" errors
    // when trying to re-enable the coin later in the same session.
    // TODO: Revisit this and create an issue on KDF to track the problem.
    final deactivationTasks = [
      ...coins.map((coin) async {
        // await _disableCoin(coin.id.id);
        if (notify) {
          _broadcastAsset(coin.copyWith(state: CoinState.inactive));
        }
      }),
      ...allChildCoins.map((child) async {
        // await _disableCoin(child.id.id);
        if (notify) {
          _broadcastAsset(child.copyWith(state: CoinState.inactive));
        }
      }),
    ];
    await Future.wait(deactivationTasks);
    await Future.wait([...parentCancelFutures, ...childCancelFutures]);
    _invalidateActivatedAssetsCache();
  }

  double? getUsdPriceByAmount(String amount, String coinAbbr) {
    final Coin? coin = getCoin(coinAbbr);
    final double? parsedAmount = double.tryParse(amount);
    final double? usdPrice = coin?.usdPrice?.price?.toDouble();

    if (coin == null || usdPrice == null || parsedAmount == null) {
      return null;
    }
    return parsedAmount * usdPrice;
  }

  /// Fetches current prices for a broad set of assets
  ///
  /// This method is used to fetch prices for a broad set of assets so unauthenticated users
  /// also see prices and 24h changes in lists and charts.
  ///
  /// Prefer activated assets if available (to limit requests when logged in),
  /// otherwise fall back to all available SDK assets.
  Future<Map<String, CexPrice>?> fetchCurrentPrices() async {
    // NOTE: key assumption here is that the Komodo Prices API supports most
    // (ideally all) assets being requested, resulting in minimal requests to
    // 3rd party fallback providers. If this assumption does not hold, then we
    // will hit rate limits and have reduced market metrics functionality.
    // This will happen regardless of chunk size. The rate limits are per IP
    // per hour.
    final activatedAssets = await _kdfSdk.getWalletAssets();
    final Iterable<Asset> targetAssets = activatedAssets.isNotEmpty
        ? activatedAssets
        : _kdfSdk.assets.available.values;

    // Filter out excluded and testnet assets, as they are not expected
    // to have valid prices available at any of the providers
    final filteredAssets = targetAssets
        .where((asset) => !excludedAssetList.contains(asset.id.id))
        .where((asset) => !asset.protocol.isTestnet)
        .toList();

    // Filter out blocked assets
    final validAssets = _tradingStatusService.filterAllowedAssets(
      filteredAssets,
    );

    // Process assets with bounded parallelism to avoid overwhelming providers
    await _fetchAssetPricesInChunks(validAssets);

    return _pricesCache;
  }

  /// Processes assets in chunks with bounded parallelism to avoid
  /// overloading providers.
  Future<void> _fetchAssetPricesInChunks(
    List<Asset> assets, {
    int chunkSize = 12,
  }) async {
    final boundedChunkSize = min(assets.length, chunkSize);
    final chunks = assets.slices(boundedChunkSize);

    for (final chunk in chunks) {
      await Future.wait(chunk.map(_fetchAssetPrice), eagerError: false);
    }
  }

  /// Fetches price data for a single asset and updates the cache
  Future<void> _fetchAssetPrice(Asset asset) async {
    try {
      // Use maybeFiatPrice to avoid errors for assets not tracked by CEX
      final fiatPrice = await _kdfSdk.marketData.maybeFiatPrice(asset.id);
      if (fiatPrice != null) {
        // Use configSymbol to lookup for backwards compatibility with the old,
        // string-based price list (and fallback)
        Decimal? change24h;
        try {
          change24h = await _kdfSdk.marketData.priceChange24h(asset.id);
        } catch (e) {
          _log.warning('Failed to get 24h change for ${asset.id.id}: $e');
          // Continue without 24h change data
        }

        final symbolKey = asset.id.symbol.configSymbol.toUpperCase();
        _pricesCache[symbolKey] = CexPrice(
          assetId: asset.id,
          price: fiatPrice,
          lastUpdated: DateTime.now(),
          change24h: change24h,
        );
      }
    } catch (e) {
      _log.warning('Failed to get price for ${asset.id.id}: $e');
    }
  }

  /// Updates balances for active coins by querying the SDK
  /// Yields coins that have balance changes
  Stream<Coin> updateIguanaBalances(Map<String, Coin> walletCoins) async* {
    // This method is now mostly a fallback, as we primarily use
    // the SDK's balance watchers to get live updates. We still
    // implement it for backward compatibility.
    final walletCoinsCopy = Map<String, Coin>.from(walletCoins);
    final coins = _tradingStatusService
        .filterAllowedAssetsMap(walletCoinsCopy, (coin) => coin.id)
        .values
        .where((coin) => coin.isActive)
        .toList();

    // Get balances from the SDK for all active coins
    for (final coin in coins) {
      try {
        // Use the SDK's balance manager to get the current balance
        final balanceInfo = await _kdfSdk.balances.getBalance(coin.id);

        // Convert to double for compatibility with existing code
        final newBalance = balanceInfo.total.toDouble();
        final newSpendable = balanceInfo.spendable.toDouble();

        // Get the current cached values
        final cachedBalance = _balancesCache[coin.id.id]?.balance;
        final cachedSpendable = _balancesCache[coin.id.id]?.spendable;

        // Check if balance has changed
        final balanceChanged =
            cachedBalance == null || newBalance != cachedBalance;
        final spendableChanged =
            cachedSpendable == null || newSpendable != cachedSpendable;

        // Only yield if there's a change
        if (balanceChanged || spendableChanged) {
          // Update the cache
          _balancesCache[coin.id.id] = (
            balance: newBalance,
            spendable: newSpendable,
          );

          final updatedCoin = coin.copyWith(sendableBalance: newSpendable);

          // Broadcast the updated balance so non-streaming assets still emit
          // real-time change events through the same path as streaming assets.
          _broadcastBalanceChange(updatedCoin);

          // Yield updated coin with new balance
          // We still set both the deprecated fields and rely on the SDK
          // for future access to maintain backward compatibility
          yield updatedCoin;
        }
      } catch (e, s) {
        _log.warning('Failed to update balance for ${coin.id}', e, s);
      }
    }
  }

  @Deprecated(
    'Use KomodoDefiSdk withdraw method instead. '
    'This will be removed in the future.',
  )
  Future<BlocResponse<WithdrawDetails, BaseError>> withdraw(
    WithdrawRequest request,
  ) async {
    Map<String, dynamic>? response;
    try {
      response = await _mm2.call(request) as Map<String, dynamic>?;
    } catch (e, s) {
      _log.shout('Error withdrawing ${request.params.coin}', e, s);
    }

    if (response == null) {
      _log.shout('Withdraw error: response is null');
      return BlocResponse(
        error: TextError(error: LocaleKeys.somethingWrong.tr()),
      );
    }

    if (response['error'] != null) {
      _log.shout('Withdraw error: ${response['error']}');
      return BlocResponse(
        error: withdrawErrorFactory.getError(response, request.params.coin),
      );
    }

    final WithdrawDetails withdrawDetails = WithdrawDetails.fromJson(
      response['result'] as Map<String, dynamic>? ?? {},
    );

    return BlocResponse(result: withdrawDetails);
  }

  Future<void> _activateZhtlcAssets(
    List<Asset> assets,
    List<Coin> coins, {
    bool notifyListeners = true,
    bool addToWalletMetadata = true,
  }) async {
    final activatedAssets = await _kdfSdk.activatedAssetsCache
        .getActivatedAssets();

    for (final asset in assets) {
      final coin = coins.firstWhere((coin) => coin.id == asset.id);

      // Check if asset is already activated
      final isAlreadyActivated = activatedAssets.any((a) => a.id == asset.id);

      if (isAlreadyActivated) {
        _log.info(
          'ZHTLC coin ${coin.id} is already activated. Broadcasting active state.',
        );

        // Add to wallet metadata if requested
        if (addToWalletMetadata) {
          await _addAssetsToWalletMetdata([asset.id]);
        }

        // Broadcast active state for already activated assets
        if (notifyListeners) {
          _broadcastAsset(coin.copyWith(state: CoinState.active));
          if (coin.id.parentId != null) {
            final parentCoin = _assetToCoinWithoutAddress(
              _kdfSdk.assets.available[coin.id.parentId]!,
            );
            _broadcastAsset(parentCoin.copyWith(state: CoinState.active));
          }
        }

        // Subscribe to balance updates for already activated assets
        _subscribeToBalanceUpdates(asset);
        if (coin.id.parentId != null) {
          final parentAsset = _kdfSdk.assets.available[coin.id.parentId];
          if (parentAsset == null) {
            _log.warning('Parent asset not found: ${coin.id.parentId}');
          } else {
            _subscribeToBalanceUpdates(parentAsset);
          }
        }

        // Register custom icon if available
        if (coin.logoImageUrl?.isNotEmpty ?? false) {
          AssetIcon.registerCustomIcon(
            coin.id,
            NetworkImage(coin.logoImageUrl!),
          );
        }
      } else {
        // Asset needs activation
        await _activateZhtlcAsset(
          asset,
          coin,
          notifyListeners: notifyListeners,
          addToWalletMetadata: addToWalletMetadata,
        );
      }
    }
  }

  /// Activates a ZHTLC asset using ArrrActivationService
  /// This will wait for user configuration if needed before proceeding with activation
  /// Mirrors the notify and addToWalletMetadata functionality of activateAssetsSync
  Future<void> _activateZhtlcAsset(
    Asset asset,
    Coin coin, {
    bool notifyListeners = true,
    bool addToWalletMetadata = true,
  }) async {
    try {
      _log.info('Starting ZHTLC activation for ${asset.id.id}');

      // Use the service's future-based activation which will handle configuration
      // The service will emit to its stream for UI to handle, and this future will
      // complete only after configuration is provided and activation succeeds.
      // This ensures CoinsRepo waits for user inputs for config params from the dialog
      // before proceeding with activation, and doesn't broadcast activation status
      // until config parameters are received and (desktop) params files downloaded.
      final result = await _arrrActivationService.activateArrr(asset);
      result.when(
        success: (progress) async {
          _log.info('ZHTLC asset activated successfully: ${asset.id.id}');

          // Add assets after activation regardless of success or failure
          if (addToWalletMetadata) {
            await _addAssetsToWalletMetdata([asset.id]);
          }

          if (notifyListeners) {
            _broadcastAsset(coin.copyWith(state: CoinState.activating));
          }

          if (notifyListeners) {
            _broadcastAsset(coin.copyWith(state: CoinState.active));
            if (coin.id.parentId != null) {
              final parentCoin = _assetToCoinWithoutAddress(
                _kdfSdk.assets.available[coin.id.parentId]!,
              );
              _broadcastAsset(parentCoin.copyWith(state: CoinState.active));
            }
          }

          _subscribeToBalanceUpdates(asset);
          if (coin.id.parentId != null) {
            final parentAsset = _kdfSdk.assets.available[coin.id.parentId];
            if (parentAsset == null) {
              _log.warning('Parent asset not found: ${coin.id.parentId}');
            } else {
              _subscribeToBalanceUpdates(parentAsset);
            }
          }

          if (coin.logoImageUrl?.isNotEmpty ?? false) {
            AssetIcon.registerCustomIcon(
              coin.id,
              NetworkImage(coin.logoImageUrl!),
            );
          }
          _invalidateActivatedAssetsCache();
        },
        error: (message) {
          _log.severe(
            'ZHTLC asset activation failed: ${asset.id.id} - $message',
          );

          // Only broadcast suspended state if it's not a user cancellation
          // User cancellations have the message "Configuration cancelled by user or timed out"
          final isUserCancellation = message.contains('cancelled by user');

          if (isUserCancellation) {
            // Bubble up a typed cancellation so the UI can revert the toggle
            throw ZhtlcActivationCancelled(asset.id.id);
          }

          if (notifyListeners) {
            _broadcastAsset(coin.copyWith(state: CoinState.suspended));
          }

          throw Exception('zcoin activaiton failed: $message');
        },
        needsConfiguration: (coinId, requiredSettings) {
          _log.severe(
            'ZHTLC activation should not return needsConfiguration in future-based call',
          );
          _log.severe(
            'Unexpected needsConfiguration result for ${asset.id.id}',
          );

          if (notifyListeners) {
            _broadcastAsset(coin.copyWith(state: CoinState.suspended));
          }

          throw Exception(
            'ZHTLC activation configuration not handled properly',
          );
        },
      );
    } catch (e, s) {
      _log.severe('Error activating ZHTLC asset ${asset.id.id}', e, s);

      // Broadcast suspended state if requested
      if (notifyListeners) {
        _broadcastAsset(coin.copyWith(state: CoinState.suspended));
      }

      rethrow;
    }
  }
}
