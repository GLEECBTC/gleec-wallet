import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:collection/collection.dart' show MapEquality;
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:logging/logging.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/trading_status/trading_status_service.dart';
import 'package:web_dex/model/cex_price.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/wallet.dart';

part 'coins_event.dart';
part 'coins_state.dart';

/// Retry budget for the initial login activation fan-out. Deliberately much
/// tighter than [CoinsRepo.activateAssetsSync]'s defaults: on login a coin that
/// keeps failing should surface as suspended quickly rather than hold its row
/// in `activating` for minutes.
const int _loginActivationRetryAttempts = 4;
const Duration _loginActivationMaxRetryDelay = Duration(seconds: 2);

/// Mirrors [CoinsRepo.activateAssetsSync]'s own defaults, used for
/// user-initiated activation where patience beats failing fast.
const int _defaultActivationRetryAttempts = 15;
const Duration _defaultActivationMaxRetryDelay = Duration(seconds: 10);

/// Bounded retry budget for a single [CoinsPubkeysRequested].
///
/// The dispatch is driven by activation-state broadcasts, and those only fire
/// on a state *transition*. Once a coin has settled on `active` there is no
/// further trigger, so a fetch that fails is never retried by the caller - the
/// coin's addresses would stay missing for the rest of the session. (The
/// previous itemBuilder dispatch happened to retry forever, which is what made
/// dropping the error survivable there.) Retry here instead.
const int _pubkeyFetchAttempts = 3;
const Duration _pubkeyFetchRetryDelay = Duration(seconds: 2);

/// Responsible for coin activation, deactivation, syncing, and fiat price
class CoinsBloc extends Bloc<CoinsEvent, CoinsState> {
  CoinsBloc(this._kdfSdk, this._coinsRepo, this._tradingStatusService)
    : super(CoinsState.initial()) {
    on<CoinsStarted>(_onCoinsStarted, transformer: droppable());
    // TODO: move auth listener to ui layer: bloclistener should fire auth events
    on<CoinsBalanceMonitoringStarted>(_onCoinsBalanceMonitoringStarted);
    on<CoinsBalanceMonitoringStopped>(_onCoinsBalanceMonitoringStopped);
    on<CoinsBalancesRefreshed>(_onCoinsRefreshed, transformer: droppable());
    on<CoinsActivated>(_onCoinsActivated, transformer: concurrent());
    on<CoinsDeactivated>(_onCoinsDeactivated, transformer: concurrent());
    on<CoinsPricesUpdated>(_onPricesUpdated, transformer: droppable());
    on<CoinsSessionStarted>(_onLogin, transformer: restartable());
    on<CoinsSessionEnded>(_onLogout, transformer: restartable());
    on<CoinsWalletCoinUpdated>(_onWalletCoinUpdated, transformer: sequential());
    on<CoinsBalanceChanged>(_onBalanceChanged, transformer: droppable());
    on<CoinsPubkeysRequested>(
      _onCoinsPubkeysRequested,
      transformer: concurrent(),
    );
  }

  final KomodoDefiSdk _kdfSdk;
  final CoinsRepo _coinsRepo;
  final TradingStatusService _tradingStatusService;

  final _log = Logger('CoinsBloc');

  StreamSubscription<Coin>? _enabledCoinsSubscription;
  StreamSubscription<Coin>? _balanceChangesSubscription;
  Timer? _updateBalancesTimer;
  Timer? _updatePricesTimer;
  bool _isInitialActivationInProgress = false;

  /// Coins with an in-flight [CoinsPubkeysRequested], so repeated broadcasts
  /// for the same coin collapse into a single SDK fetch.
  final Set<String> _pubkeyRequestsInFlight = <String>{};

  /// Wallet whose initial activation is currently running, used to ignore a
  /// duplicate [CoinsSessionStarted] for the same wallet.
  String? _activatingWalletId;

  @override
  Future<void> close() async {
    await _enabledCoinsSubscription?.cancel();
    await _balanceChangesSubscription?.cancel();
    _updateBalancesTimer?.cancel();
    _updatePricesTimer?.cancel();

    await super.close();
  }

  Future<void> _onCoinsPubkeysRequested(
    CoinsPubkeysRequested event,
    Emitter<CoinsState> emit,
  ) async {
    // Per-coin gate. This replaces a global `_isInitialActivationInProgress`
    // early-return, which blanked *every* coin's addresses until the slowest
    // activation in the batch finished (up to ~105s of retry backoff for a
    // single flapping coin). That gate existed only to damp the itemBuilder
    // dispatch storm; the dispatch now comes from activation completion
    // instead, so per-coin readiness is the correct condition.
    //
    // Coins are added to walletCoins before activation even starts to show
    // them in the UI regardless of activation state. A coin that is missing or
    // not yet active is an expected case, not a fault.
    final coin = state.walletCoins[event.coinId];
    if (coin == null || !coin.isActive) {
      _log.finer(
        'Skipping pubkeys request for ${event.coinId}: not an active wallet coin',
      );
      return;
    }

    if (!_pubkeyRequestsInFlight.add(event.coinId)) return;

    try {
      // Get pubkeys from the SDK through the repo
      final asset = _kdfSdk.assets.available[coin.id];
      if (asset == null) {
        _log.warning('No SDK asset for ${event.coinId}, cannot fetch pubkeys');
        return;
      }

      for (var attempt = 1; attempt <= _pubkeyFetchAttempts; attempt++) {
        if (isClosed) return;
        try {
          final pubkeys = await _kdfSdk.pubkeys.getPubkeys(asset);
          if (isClosed) return;

          // The coin may have been deactivated while the fetch was in flight.
          if (!(state.walletCoins[event.coinId]?.isActive ?? false)) return;

          // Update state with new pubkeys
          emit(
            state.copyWith(pubkeys: {...state.pubkeys, event.coinId: pubkeys}),
          );
          return;
        } catch (e, s) {
          if (attempt >= _pubkeyFetchAttempts) {
            _log.shout(
              'Failed to get pubkeys for ${event.coinId} after $attempt '
              'attempts',
              e,
              s,
            );
            return;
          }
          _log.warning(
            'Pubkeys attempt $attempt/$_pubkeyFetchAttempts failed for '
            '${event.coinId}, retrying',
            e,
            s,
          );
          await Future<void>.delayed(_pubkeyFetchRetryDelay * attempt);
        }
      }
    } finally {
      _pubkeyRequestsInFlight.remove(event.coinId);
    }
  }

  Future<void> _onCoinsStarted(
    CoinsStarted event,
    Emitter<CoinsState> emit,
  ) async {
    // Wait for trading status service to receive initial status before
    // populating coins list. This ensures geo-blocked assets are properly
    // filtered from the start, preventing them from appearing in the UI
    // before filtering is applied.
    //
    // TODO: UX Improvement - For faster startup, populate coins immediately
    // and reactively filter when trading status updates arrive. This would
    // eliminate startup delay (~100-500ms) but requires UI to handle dynamic
    // removal of blocked assets. See TradingStatusService._currentStatus for
    // related trade-offs.
    await _tradingStatusService.initialStatusReady;

    emit(state.copyWith(coins: _coinsRepo.getKnownCoinsMap()));

    final existingUser = await _kdfSdk.auth.currentUser;
    if (existingUser != null) {
      add(CoinsSessionStarted(existingUser));
    }

    add(CoinsPricesUpdated());
    _updatePricesTimer?.cancel();
    _updatePricesTimer = Timer.periodic(const Duration(minutes: 3), (_) {
      if (kDebugElectrumLogs) {
        _log.info(
          '[POLLING] Triggering periodic price update (every 3 minutes)',
        );
      }
      add(CoinsPricesUpdated());
    });

    // This is used to connect [CoinsBloc] to [CoinsManagerBloc] via [CoinsRepo],
    // since coins manager bloc activates and deactivates coins using the repository.
    // Other auto-activation sources, like the DEX, will also use the repository
    // to activate coins, so this subscription is needed to keep the coins bloc
    // in sync with the coins manager and other auto-activation sources.
    await _enabledCoinsSubscription?.cancel();
    _enabledCoinsSubscription = _coinsRepo.enabledAssetsChanges.stream.listen(
      (Coin coin) => add(CoinsWalletCoinUpdated(coin)),
    );

    // Subscribe to real-time balance changes from the repository
    await _balanceChangesSubscription?.cancel();
    _balanceChangesSubscription = _coinsRepo.balanceChanges.stream.listen(
      (Coin coin) => add(CoinsBalanceChanged(coin)),
    );
  }

  Future<void> _onCoinsRefreshed(
    CoinsBalancesRefreshed event,
    Emitter<CoinsState> emit,
  ) async {
    final coinUpdateStream = _coinsRepo.updateIguanaBalances(state.walletCoins);
    await emit.forEach(
      coinUpdateStream,
      onData: (Coin coin) {
        final key = coin.id.id;
        if (!state.walletCoins.containsKey(key)) {
          _log.warning(
            'Coin ${coin.abbr} not found in wallet coins, skipping update',
          );
          return state;
        }
        return state.copyWith(
          walletCoins: {...state.walletCoins, key: coin},
          coins: {...state.coins, key: coin},
        );
      },
    );
  }

  Future<void> _onWalletCoinUpdated(
    CoinsWalletCoinUpdated event,
    Emitter<CoinsState> emit,
  ) async {
    final coin = event.coin;
    final walletCoins = Map<String, Coin>.of(state.walletCoins);

    if (coin.isInactive || coin.isSuspended) {
      walletCoins.remove(coin.id.id);
      emit(state.copyWith(walletCoins: walletCoins));
      return;
    }

    final walletCoin = state.walletCoins[coin.id.id];
    final hasCoinStateChanged =
        walletCoin == null || walletCoin.state != coin.state;

    // Only update the wallet coins list if state has changed, since it does not
    // concern the coins list.
    if (hasCoinStateChanged) {
      emit(state.copyWith(walletCoins: {...walletCoins, coin.id.id: coin}));
    }

    // Request addresses once the coin is actually active. This used to be
    // dispatched from the wallet list's itemBuilder, which re-fired for every
    // row on every emission (SliverChildBuilderDelegate.shouldRebuild is
    // always true) into a concurrent() handler that emits - each emission
    // rebuilding the list again. Driving it from activation completion makes
    // it exactly one request per coin.
    //
    // Deliberately outside the hasCoinStateChanged branch: a duplicate
    // "active" broadcast must still trigger the fetch. state.pubkeys and
    // _pubkeyRequestsInFlight are the dedupe.
    if (coin.isActive && !state.pubkeys.containsKey(coin.id.id)) {
      add(CoinsPubkeysRequested(coin.id.id));
    }
  }

  /// Real-time balance update handler
  Future<void> _onBalanceChanged(
    CoinsBalanceChanged event,
    Emitter<CoinsState> emit,
  ) async {
    final updated = event.coin;
    final assetId = updated.id.id;
    final existing = state.walletCoins[assetId] ?? state.coins[assetId];
    if (existing == null) return;

    // Preserve persistent state fields such as activation state
    final merged = updated.copyWith(state: existing.state);

    final walletCoins = Map<String, Coin>.of(state.walletCoins);
    if (merged.isActive || merged.isActivating) {
      walletCoins[assetId] = merged;
    } else {
      walletCoins.remove(assetId);
    }

    emit(
      state.copyWith(
        walletCoins: walletCoins,
        coins: {...state.coins, assetId: merged},
      ),
    );
  }

  Future<void> _onCoinsBalanceMonitoringStopped(
    CoinsBalanceMonitoringStopped event,
    Emitter<CoinsState> emit,
  ) async {
    _updateBalancesTimer?.cancel();
  }

  Future<void> _onCoinsBalanceMonitoringStarted(
    CoinsBalanceMonitoringStarted event,
    Emitter<CoinsState> emit,
  ) async {
    _updateBalancesTimer?.cancel();
    _updateBalancesTimer = Timer.periodic(const Duration(minutes: 3), (timer) {
      final missingWatcherCount = _coinsRepo
          .countMissingBalanceWatchersForActiveWalletCoins(state.walletCoins);
      if (missingWatcherCount == 0) {
        return;
      }
      if (kDebugElectrumLogs) {
        _log.info(
          '[POLLING] Triggering fallback balance refresh (every 3 minutes) '
          'for $missingWatcherCount active assets without live watchers',
        );
      }
      add(CoinsBalancesRefreshed());
    });
  }

  Future<void> _onCoinsActivated(
    CoinsActivated event,
    Emitter<CoinsState> emit,
  ) async {
    // Start off by emitting the newly activated coins so that they all appear
    // in the list at once, rather than one at a time as they are activated
    emit(_prePopulateListWithActivatingCoins(event.coinIds));
    await _activateCoins(event.coinIds, emit);

    add(CoinsBalancesRefreshed());
  }

  Future<void> _onCoinsDeactivated(
    CoinsDeactivated event,
    Emitter<CoinsState> emit,
  ) async {
    final currentWalletCoins = state.walletCoins;
    final currentCoins = state.coins;
    final Set<String> coinIdsToDisable = {...event.coinIds};

    if (currentWalletCoins.isEmpty) {
      _log.warning('No wallet coins to disable');
      return;
    }

    // Disable all child coins of the parent coins being deactivated.
    for (final assetId in event.coinIds) {
      final coin = currentWalletCoins[assetId];
      if (coin != null) {
        coinIdsToDisable.addAll(
          currentWalletCoins.values
              .where((c) => c.parentCoin?.abbr == coin.abbr)
              .map((c) => c.abbr),
        );
      }
    }

    // Remove coins from the state early to avoid reactivation
    // via pubkey requests
    emit(
      _flushCoinsFromState(currentWalletCoins, coinIdsToDisable, currentCoins),
    );

    // Remove coins from the SDK metadata field before deactivating to
    // prevent reactivation on login or via state syncing tasks.
    final coinsToDisable = event.coinIds
        .map((id) => currentWalletCoins[id])
        .whereType<Coin>()
        .toList();
    await _coinsRepo.deactivateCoinsSync(coinsToDisable, notify: false);
  }

  CoinsState _flushCoinsFromState(
    Map<String, Coin> currentWalletCoins,
    Set<String> coinsToDisable,
    Map<String, Coin> currentCoins,
  ) {
    final updatedWalletCoins = Map.fromEntries(
      currentWalletCoins.entries.where(
        (entry) => !coinsToDisable.contains(entry.key),
      ),
    );
    final updatedCoins = Map<String, Coin>.of(currentCoins);
    for (final assetId in coinsToDisable) {
      final coin = currentWalletCoins[assetId]!;
      updatedCoins[coin.id.id] = coin.copyWith(state: CoinState.inactive);
    }
    return state.copyWith(walletCoins: updatedWalletCoins, coins: updatedCoins);
  }

  Future<void> _onPricesUpdated(
    CoinsPricesUpdated event,
    Emitter<CoinsState> emit,
  ) async {
    try {
      final fetchedPrices = await _coinsRepo.fetchCurrentPrices();
      if (fetchedPrices == null) {
        _log.severe('Coin prices list empty/null');
        return;
      }

      final prices = Map<String, CexPrice>.unmodifiable(
        Map<String, CexPrice>.from(fetchedPrices),
      );
      final didPricesChange = !const MapEquality().equals(state.prices, prices);
      if (!didPricesChange) {
        _log.info('Coin prices list unchanged');
        return;
      }

      Map<String, Coin> updateCoinsWithPrices(Map<String, Coin> coins) {
        final map = coins.map((key, coin) {
          // Use configSymbol to lookup for backwards compatibility with the old,
          // string-based price list (and fallback)
          final price = prices[coin.id.symbol.configSymbol.toUpperCase()];
          if (price != null) {
            return MapEntry(key, coin.copyWith(usdPrice: price));
          }
          return MapEntry(key, coin);
        });

        return Map<String, Coin>.unmodifiable(map);
      }

      emit(
        state.copyWith(
          prices: prices,
          coins: updateCoinsWithPrices(state.coins),
          walletCoins: updateCoinsWithPrices(state.walletCoins),
        ),
      );
    } catch (e, s) {
      _log.shout('Error on prices updated', e, s);
    }
  }

  Future<void> _onLogin(
    CoinsSessionStarted event,
    Emitter<CoinsState> emit,
  ) async {
    final Wallet signedInWallet = event.signedInUser.wallet;

    // Defensive idempotency. A duplicate sign-in event for the wallet that is
    // already activating would flush the coin cache (cancelling every balance
    // watcher registered so far) and re-seed every row as `activating`, i.e.
    // restart the whole load in front of the user. restartable() does not help:
    // this handler has no await, so a duplicate runs a second pass rather than
    // cancelling the first. An actual wallet switch still falls through and
    // flushes, which is correct.
    if (_isInitialActivationInProgress &&
        _activatingWalletId == signedInWallet.id) {
      _log.info(
        'Ignoring duplicate CoinsSessionStarted for ${signedInWallet.id}: '
        'initial activation already in progress',
      );
      return;
    }

    _isInitialActivationInProgress = true;
    _activatingWalletId = signedInWallet.id;
    try {
      // Ensure any cached addresses/pubkeys from a previous wallet are cleared
      // so that UI fetches fresh pubkeys for the newly logged-in wallet.
      emit(state.copyWith(pubkeys: {}));
      _coinsRepo.flushCache();
      final Wallet currentWallet = signedInWallet;

      // Start off by emitting the newly activated coins so that they all appear
      // in the list at once, rather than one at a time as they are activated
      final coinsToActivate = currentWallet.config.activatedCoins;

      // Filter out blocked coins before activation
      final allowedCoins = coinsToActivate.where((coinId) {
        final assets = _kdfSdk.assets.findAssetsByConfigId(coinId);
        if (assets.isEmpty) return false;
        return !_tradingStatusService.isAssetBlocked(assets.single.id);
      });

      emit(_prePopulateListWithActivatingCoins(allowedCoins));
      _scheduleInitialBalanceRefresh(allowedCoins);
      final activationFuture = _activateCoins(
        allowedCoins,
        emit,
        isInitialLogin: true,
      );
      unawaited(() async {
        try {
          await activationFuture;
        } catch (e, s) {
          _log.shout('Error during initial coin activation', e, s);
        } finally {
          _isInitialActivationInProgress = false;
          _activatingWalletId = null;
        }
      }());
    } catch (e, s) {
      _isInitialActivationInProgress = false;
      _activatingWalletId = null;
      _log.shout('Error on login', e, s);
    }
  }

  Future<void> _onLogout(
    CoinsSessionEnded event,
    Emitter<CoinsState> emit,
  ) async {
    _resetInitialActivationState();
    add(CoinsBalanceMonitoringStopped());

    // Flush before rebuilding the catalogue below, so the fresh Coin objects
    // are built against an empty balance cache rather than re-reading the
    // signed-out wallet's balances.
    _coinsRepo.flushCache();

    emit(
      state.copyWith(
        walletCoins: {},
        // Rebuild rather than carrying the signed-out wallet's Coin objects
        // forward: their balances belong to that wallet, and
        // _prePopulateListWithActivatingCoins seeds the next session's rows
        // from this map.
        coins: _coinsRepo.getKnownCoinsMap(),
        // Clear pubkeys to avoid showing addresses from the previous wallet
        // after logout or wallet switch.
        pubkeys: {},
      ),
    );
  }

  void _scheduleInitialBalanceRefresh(Iterable<String> coinsToActivate) {
    if (isClosed) return;

    // Start the fallback balance monitor immediately rather than gating it on
    // the activation-coverage threshold below. It only re-fetches coins whose
    // SDK balance watcher failed to start, so starting it early is harmless -
    // whereas gating it meant the first tick could be delayed by up to the
    // full 60s timeout. That timeout is reachable in practice: targetIds here
    // is the pre-ZHTLC-filter list, while _activateCoins drops unconfigured
    // ZHTLC assets, so an ARRR-enabled-but-unconfigured wallet can never reach
    // 80% coverage.
    add(CoinsBalanceMonitoringStarted());

    final Set<String> targetIds = coinsToActivate.toSet();
    if (targetIds.isEmpty) {
      add(CoinsBalancesRefreshed());
      return;
    }

    unawaited(() async {
      final stopwatch = Stopwatch()..start();
      var triggeredByThreshold = false;
      var fired = false;
      final activeIds = <String>{};

      void _fire() {
        if (fired || isClosed) return;
        fired = true;
        stopwatch.stop();
        // Logged at info so it survives release builds (Logger.root.level is
        // INFO in release). This is the headline post-login timing: how long
        // from sign-in until enough coins are active to sweep balances.
        _log.info(
          'Initial activation reached ${triggeredByThreshold ? "80% coverage" : "the timeout"} '
          'after ${stopwatch.elapsedMilliseconds}ms '
          '(${activeIds.length}/${targetIds.length} coins active)',
        );
        add(CoinsBalancesRefreshed());
      }

      // Seed with currently activated assets from the SDK cache
      try {
        final activated = await _kdfSdk.activatedAssetsCache
            .getActivatedAssetIds(forceRefresh: true);
        for (final id in activated) {
          if (targetIds.contains(id.id)) {
            activeIds.add(id.id);
          }
        }
      } catch (_) {
        // Best-effort seeding; continue with streaming updates
      }

      bool _checkThreshold() {
        if (targetIds.isEmpty) return true;
        final coverage = activeIds.length / targetIds.length;
        if (coverage >= 0.8) {
          triggeredByThreshold = true;
          return true;
        }
        return false;
      }

      if (_checkThreshold()) {
        _fire();
        return;
      }

      StreamSubscription<Coin>? tempSub;
      tempSub = _coinsRepo.enabledAssetsChanges.stream.listen((coin) {
        if (isClosed || fired) return;
        if (!targetIds.contains(coin.id.id)) return;
        if (coin.isActive) {
          activeIds.add(coin.id.id);
          if (_checkThreshold()) {
            final sub = tempSub;
            tempSub = null;
            sub?.cancel();
            _fire();
          }
        }
      });

      // Fallback: timeout to avoid waiting indefinitely
      const timeout = Duration(minutes: 1);
      await Future<void>.delayed(timeout);
      final sub = tempSub;
      tempSub = null;
      await sub?.cancel();
      if (!fired) {
        triggeredByThreshold = false;
        _fire();
      }
    }());
  }

  void _resetInitialActivationState() {
    _isInitialActivationInProgress = false;
    _activatingWalletId = null;
    _pubkeyRequestsInFlight.clear();
  }

  /// [isInitialLogin] marks the automatic post-sign-in fan-out, which trades
  /// patience for responsiveness: a bounded retry budget and a single shared
  /// activated-assets refresh. User-initiated activation (coins manager, DEX)
  /// keeps the patient per-call defaults - there the user is explicitly waiting
  /// on one coin and would rather it eventually succeed than fail fast.
  Future<void> _activateCoins(
    Iterable<String> coins,
    Emitter<CoinsState> emit, {
    bool isInitialLogin = false,
  }) async {
    if (coins.isEmpty) {
      _log.warning('No coins to activate');
      return;
    }

    // Filter out assets that are not available in the SDK. This is to avoid activation
    // activation loops for assets not supported by the SDK.this may happen if the wallet
    // has assets that were removed from the SDK or the config has unsupported default
    // assets.
    final availableAssets = coins
        .map((coin) => _kdfSdk.assets.findAssetsByConfigId(coin))
        .where((assetsSet) => assetsSet.isNotEmpty)
        .map((assetsSet) => assetsSet.single);

    // Filter out blocked assets
    var coinsToActivate = _tradingStatusService.filterAllowedAssets(
      availableAssets.toList(),
    );

    // During initial login auto-activation, skip ZHTLC assets that would
    // trigger configuration dialogs (i.e. no saved configuration yet).
    if (_isInitialActivationInProgress) {
      coinsToActivate = await _filterAssetsForInitialActivation(
        coinsToActivate,
      );
    }

    // Batch-write all asset IDs to wallet metadata in a single call before
    // launching parallel activations. This avoids N concurrent read-modify-write
    // cycles on the same metadata key which caused last-write-wins data loss.
    await _coinsRepo.addAssetsToWalletMetadata(
      coinsToActivate.map((asset) => asset.id),
    );

    if (isInitialLogin) {
      // One forced activated-assets read for the whole fan-out instead of one
      // per asset. Placed immediately before the fan-out so the staleness
      // window is sub-millisecond, preserving the freshness guarantee that the
      // per-asset force-refresh was added for (#3463, NoSuchCoin race).
      try {
        await _coinsRepo.getActivatedAssetIds(forceRefresh: true);
      } catch (e, s) {
        _log.warning(
          'Failed to pre-fetch activated assets before login fan-out',
          e,
          s,
        );
      }
    }

    // The repo defaults (15 attempts, 500ms -> 10s exponential) are ~105s of
    // pure sleep per asset, during which the coin holds CoinState.activating
    // with no balance watcher. On login that presents as "the wallet never
    // loads" rather than as an error, so bound it there. A coin that exhausts
    // the budget flips to suspended sooner and is recovered by the 3-minute
    // CoinsBalanceMonitoringStarted sweep and by the SDK balance watcher's own
    // _ensureAssetActivated.
    final enableFutures = coinsToActivate
        .map(
          (asset) => _coinsRepo.activateAssetsSync(
            [asset],
            addToWalletMetadata: false,
            useSharedActivationCache: isInitialLogin,
            maxRetryAttempts: isInitialLogin
                ? _loginActivationRetryAttempts
                : _defaultActivationRetryAttempts,
            maxRetryDelay: isInitialLogin
                ? _loginActivationMaxRetryDelay
                : _defaultActivationMaxRetryDelay,
          ),
        )
        .toList();

    // Ignore the return type here and let the broadcast handle the state updates as
    // coins are activated.
    try {
      await Future.wait(enableFutures);
    } finally {
      if (isInitialLogin) {
        // Leave the shared cache fresh for the consumers that follow (balance
        // refresh, portfolio blocs), since the fan-out skipped its per-asset
        // invalidations. Runs even if an asset failed.
        _coinsRepo.invalidateActivatedAssetsCache();
      }
    }
  }

  /// Filters assets for initial auto-activation on login.
  ///
  /// - Keeps all non-ZHTLC assets
  /// - Keeps ZHTLC assets only if a saved configuration already exists
  Future<List<Asset>> _filterAssetsForInitialActivation(
    List<Asset> assets,
  ) async {
    final filtered = <Asset>[];
    for (final asset in assets) {
      if (asset.id.subClass != CoinSubClass.zhtlc) {
        filtered.add(asset);
        continue;
      }

      try {
        final saved = await _kdfSdk.activationConfigService.getSavedZhtlc(
          asset.id,
        );
        if (saved != null) {
          filtered.add(asset);
        } else {
          _log.info(
            'Skipping auto-activation of ZHTLC asset ${asset.id.id} during login: no saved configuration found',
          );
        }
      } catch (e, s) {
        _log.shout(
          'Error checking saved ZHTLC configuration for ${asset.id.id}',
          e,
          s,
        );
      }
    }
    return filtered;
  }

  CoinsState _prePopulateListWithActivatingCoins(Iterable<String> coins) {
    // Reuse the catalogue already in state where possible. Rebuilding it means
    // converting every available asset to a Coin (recursing into the parent for
    // each child token) synchronously on the frame the user is watching;
    // _onCoinsStarted has normally populated it already.
    final knownCoins = state.coins.isNotEmpty
        ? state.coins
        : _coinsRepo.getKnownCoinsMap();
    final activatingCoins = Map<String, Coin>.fromIterable(
      coins
          .map((coin) {
            final sdkCoin = knownCoins[coin];
            return sdkCoin?.copyWith(state: CoinState.activating);
          })
          .where((coin) => coin != null)
          .cast<Coin>()
          // Do not pre-populate zhtlc coins, as they require configuration
          // and longer activation times, and are handled separately.
          .where((coin) => coin.id.subClass != CoinSubClass.zhtlc),
      key: (element) => (element as Coin).id.id,
    );
    return state.copyWith(
      walletCoins: {...state.walletCoins, ...activatingCoins},
      coins: {...knownCoins, ...state.coins, ...activatingCoins},
    );
  }
}
