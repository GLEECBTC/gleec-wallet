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

/// How long [_onCoinsStarted] waits for the geo/trading status before
/// populating the coin catalogue anyway. [TradingStatusService.initialize]
/// completes its completer on both the success and the failure path, but the
/// underlying `fetchStatus()` has no timeout of its own, so a black-holed
/// endpoint would otherwise block startup indefinitely.
const Duration _initialTradingStatusTimeout = Duration(seconds: 10);

/// Delays for the post-fan-out reconciliation passes.
///
/// Two passes, because the two failure classes they repair settle on different
/// timelines. The first is long enough for the last in-flight activation
/// broadcasts to have been processed by [_onWalletCoinUpdated], and short
/// enough that a user watching a stuck row does not wait long. The second sits
/// past the pubkey retry budget ([_pubkeyFetchAttempts] with
/// [_pubkeyFetchRetryDelay] backoff, ~6s plus request time) so a coin whose
/// address fetch exhausted its retries is picked up rather than skipped while
/// the request is still in flight.
const List<Duration> _postActivationReconcileDelays = [
  Duration(seconds: 2),
  Duration(seconds: 20),
];

/// Ceiling on a single SDK call made on the login critical path.
///
/// Applies to reads whose only failure mode would otherwise be an unbounded
/// hang that strands every coin in `activating`.
const Duration _loginPathRpcTimeout = Duration(seconds: 30);

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
    on<CoinsActivationReconciled>(
      _onActivationReconciled,
      transformer: droppable(),
    );
    on<CoinsPubkeysRequested>(
      _onCoinsPubkeysRequested,
      transformer: concurrent(),
    );

    // Subscribe here rather than in [_onCoinsStarted].
    //
    // [CoinsRepo._broadcastAsset] DROPS an event when the stream has no
    // listener, and _onCoinsStarted only reached its `listen` calls after
    // `await _tradingStatusService.initialStatusReady` - a network round trip
    // with no timeout. A sign-in that lands inside that window ran the whole
    // activation fan-out against a listener-less stream, so every
    // `activating -> active` broadcast was discarded: rows stayed on
    // `activating` forever, CoinsPubkeysRequested was never dispatched (so coin
    // pages spun indefinitely) and no balance change ever reached the bloc.
    //
    // The second CoinsSessionStarted that _onCoinsStarted dispatches used to
    // paper over this by re-running the whole activation once the subscription
    // was live; the login idempotency guard (correctly) stopped that, which is
    // what turned a self-healing race into a permanent stall.
    //
    // These are plain stream subscriptions with no async setup, so there is no
    // reason for them to lag the producers they exist to observe.
    _listenToRepoBroadcasts();
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
          // Bounded: getPubkeys has no timeout of its own, and a hang here
          // would leave this coin's id in _pubkeyRequestsInFlight forever,
          // blocking not just this fetch but every later retry - including the
          // reconciler's, which is the only thing that would otherwise recover
          // the coin's addresses.
          final pubkeys = await _kdfSdk.pubkeys
              .getPubkeys(asset)
              .timeout(_loginPathRpcTimeout);
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
    // Best-effort wait for the initial trading status before populating the
    // coins list, so geo-blocked assets are not briefly shown before filtering
    // applies. Cosmetic, and deliberately not a guarantee: the wait is bounded
    // because a hung or slow geo endpoint must not hold the whole catalogue
    // hostage. On timeout the catalogue is populated unfiltered - asset-level
    // filtering keys off AppGeoStatus.disallowedAssets, which defaults to empty
    // (only disallowedFeatures defaults restrictive), and nothing here re-emits
    // when the real status lands, so blocked assets stay visible for the
    // session. Accepted: a stalled bouncer stranding the whole wallet is the
    // worse failure.
    //
    // TODO: UX Improvement - For faster startup, populate coins immediately
    // and reactively filter when trading status updates arrive. This would
    // eliminate startup delay (~100-500ms) but requires UI to handle dynamic
    // removal of blocked assets. It would also close the timeout gap above.
    // See TradingStatusService._currentStatus for related trade-offs.
    try {
      await _tradingStatusService.initialStatusReady.timeout(
        _initialTradingStatusTimeout,
      );
    } on TimeoutException {
      _log.warning(
        'Trading status not ready after '
        '${_initialTradingStatusTimeout.inSeconds}s; populating coins anyway',
      );
    }

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
  }

  /// Bridges [CoinsRepo]'s broadcast streams into bloc events.
  ///
  /// Called from the constructor so the subscriptions are live before anything
  /// can activate a coin. See the constructor comment for why this must not be
  /// deferred behind an await.
  ///
  /// This connects [CoinsBloc] to [CoinsManagerBloc] via [CoinsRepo], since the
  /// coins manager activates and deactivates coins through the repository.
  /// Other auto-activation sources, like the DEX, use the repository too.
  void _listenToRepoBroadcasts() {
    _enabledCoinsSubscription = _coinsRepo.enabledAssetsChanges.stream.listen(
      (Coin coin) => add(CoinsWalletCoinUpdated(coin)),
    );
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

  /// Repairs the bloc's activation view from KDF's authoritative state.
  ///
  /// See [CoinsActivationReconciled]. This is the safety net for anything that
  /// can be lost in transit between [CoinsRepo] and here: a broadcast delivered
  /// while nothing was listening, a watcher that died, a pubkey fetch that
  /// exhausted its retries. All three otherwise present identically to the user
  /// - a row that spins forever - so they need a single, cheap repair path
  /// rather than three separate ones.
  Future<void> _onActivationReconciled(
    CoinsActivationReconciled event,
    Emitter<CoinsState> emit,
  ) async {
    // Deliberately no `walletCoins.isEmpty` early return: an empty wallet list
    // is the *worst* version of this failure, not a reason to skip. If the rows
    // were never seeded (or were emitted while nothing was listening) KDF is
    // still the source of truth and the rows can be rebuilt from it.

    final Set<AssetId> activatedIds;
    try {
      // This handler is the safety net for every other stall and is
      // droppable(), so one stuck call would swallow every later reconcile for
      // the session. ActivatedAssetsCache bounds the read itself, so a wedged
      // node surfaces here as a TimeoutException rather than a hang.
      activatedIds = await _coinsRepo.getActivatedAssetIds(forceRefresh: true);
    } catch (e, s) {
      _log.warning(
        'Activation reconcile: failed to read activated assets',
        e,
        s,
      );
      return;
    }
    if (isClosed) return;
    if (activatedIds.isEmpty) {
      // Not necessarily benign: if rows are showing as active, KDF and the UI
      // now disagree completely. Say so rather than returning in silence -
      // this is the safety net, and a silent no-op here is exactly the shape
      // of failure it exists to make visible.
      if (state.walletCoins.isNotEmpty) {
        _log.warning(
          'Activation reconcile: KDF reports no enabled coins while the wallet '
          'shows ${state.walletCoins.length} row(s); nothing to reconcile '
          'against',
        );
      }
      return;
    }

    final activatedStringIds = activatedIds.map((id) => id.id).toSet();
    final knownCoins = state.coins.isNotEmpty
        ? state.coins
        : _coinsRepo.getKnownCoinsMap();

    // Build a new map rather than writing into the one being iterated.
    final walletCoins = <String, Coin>{};
    final repaired = <String>[];
    final restored = <String>[];

    state.walletCoins.forEach((id, coin) {
      if (coin.isActive || !activatedStringIds.contains(id)) {
        walletCoins[id] = coin;
        return;
      }
      // KDF has this asset enabled but the `active` broadcast never landed.
      walletCoins[id] = coin.copyWith(state: CoinState.active);
      repaired.add(id);
    });

    for (final assetId in activatedIds) {
      if (walletCoins.containsKey(assetId.id)) continue;
      final known = knownCoins[assetId.id];
      if (known == null) continue;
      // Enabled in KDF but absent from the wallet list entirely - the row was
      // never seeded, or was evicted by a suspended broadcast that a later
      // successful activation never corrected.
      walletCoins[assetId.id] = known.copyWith(state: CoinState.active);
      restored.add(assetId.id);
    }

    if (repaired.isNotEmpty || restored.isNotEmpty) {
      _log.warning(
        'Activation reconcile: repaired ${repaired.length} stuck row(s) '
        '${repaired.join(', ')}; restored ${restored.length} missing row(s) '
        '${restored.join(', ')}',
      );
      emit(state.copyWith(walletCoins: walletCoins));
    }

    // Re-drive the two things an `active` broadcast would have triggered, for
    // every active coin - not just the repaired ones. A coin can be correctly
    // marked active and still be missing its addresses (pubkey retries
    // exhausted) or its balance watcher (watcher errored out; the subscription
    // is removed on error/done and never restarted).
    final activeCoins = walletCoins.values.where((c) => c.isActive).toList();

    for (final coin in activeCoins) {
      if (!state.pubkeys.containsKey(coin.id.id)) {
        add(CoinsPubkeysRequested(coin.id.id));
      }
    }

    final restarted = _coinsRepo.ensureBalanceWatchers(
      activeCoins.map((c) => c.id),
    );
    if (restarted > 0) {
      add(CoinsBalancesRefreshed());
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
      final missingWatcherCount = _reconcileIfWalletUnhealthy();

      // Fallback balance sweep, distinct from the reconcile above: that only
      // refreshes when it actually restarted a repo-side watcher, which is
      // false on every tick after the first repair. An asset whose SDK-side
      // watcher never started - or gave up - would otherwise never have its
      // balance refreshed again.
      if (missingWatcherCount > 0) {
        add(CoinsBalancesRefreshed());
      }
    });
  }

  /// Reconciles when the wallet is in any of the three ways a row can be stuck.
  ///
  /// They are indistinguishable to the user - all three render as a spinner -
  /// and [_onActivationReconciled] repairs all three:
  ///  - not `active` this long into the session: a lost broadcast, not a slow
  ///    activation;
  ///  - `active` with no live balance updates on either side of the SDK/repo
  ///    boundary;
  ///  - `active` with no addresses, i.e. the pubkey fetch exhausted its retries
  ///    and nothing else would ever re-trigger it.
  ///
  /// Returns the SDK-side missing-watcher count - a strict subset of the
  /// balance-repair count - for the caller's fallback sweep.
  int _reconcileIfWalletUnhealthy() {
    final total = state.walletCoins.length;
    final stalled = state.walletCoins.values
        .where((coin) => !coin.isActive)
        .length;
    final needingBalanceRepair = _coinsRepo.countAssetsNeedingBalanceRepair(
      state.walletCoins,
    );
    final missingWatcherCount = _coinsRepo
        .countMissingBalanceWatchersForActiveWalletCoins(state.walletCoins);
    final missingAddresses = state.walletCoins.values
        .where(
          (coin) => coin.isActive && !state.pubkeys.containsKey(coin.id.id),
        )
        .length;

    // At info so it survives release builds - Logger.root.level is INFO there,
    // which makes every `fine` diagnostic on this path invisible in production.
    // Without this line a user's log cannot distinguish "never dispatched" from
    // "zero allowed coins" from "activated but the broadcast was lost".
    if (stalled > 0 || needingBalanceRepair > 0 || missingAddresses > 0) {
      _log.info(
        'Wallet health: ${total - stalled}/$total active, $stalled stalled, '
        '$needingBalanceRepair without live balances '
        '($missingWatcherCount SDK-side), '
        '$missingAddresses without addresses',
      );
      add(CoinsActivationReconciled());
    }
    return missingWatcherCount;
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
      final coin = currentWalletCoins[assetId];
      if (coin == null) continue;
      updatedCoins[coin.id.id] = coin.copyWith(state: CoinState.inactive);
    }

    // Drop the addresses too. _onWalletCoinUpdated only requests pubkeys for a
    // coin that has none, so a stale entry here means a reactivated coin keeps
    // showing the addresses it had before - and never refetches them.
    final updatedPubkeys = Map<String, AssetPubkeys>.of(state.pubkeys)
      ..removeWhere((id, _) => coinsToDisable.contains(id));

    return state.copyWith(
      walletCoins: updatedWalletCoins,
      coins: updatedCoins,
      pubkeys: updatedPubkeys,
    );
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
      // Reconcile rather than no-op. The duplicate used to re-run the whole
      // fan-out, which incidentally repaired any activation broadcast that was
      // lost in transit; suppressing it removed that repair. Reconciling costs
      // one activated-assets read and restores the same guarantee without
      // restarting the load in front of the user.
      add(CoinsActivationReconciled());
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

      // Filter out blocked coins before activation.
      //
      // Materialised, not lazy: the result is iterated three times below and
      // findAssetsByConfigId is an O(catalogue) scan, so a lazy iterable meant
      // three full scans per configured coin.
      //
      // `.single` here used to throw on a config id that resolves to more than
      // one asset, and the throw propagated to _onLogin's catch - aborting the
      // entire activation with no retry path, for every coin, because of one
      // ambiguous id. Tolerate it instead: block only if every candidate is
      // blocked, which is the conservative reading.
      final allowedCoins = coinsToActivate.where((coinId) {
        final assets = _kdfSdk.assets.findAssetsByConfigId(coinId);
        if (assets.isEmpty) return false;
        if (assets.length > 1) {
          _log.warning(
            'Config id $coinId resolves to ${assets.length} assets '
            '(${assets.map((a) => a.id.id).join(', ')})',
          );
        }
        return assets.any(
          (asset) => !_tradingStatusService.isAssetBlocked(asset.id),
        );
      }).toList();

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
          // Only clear the guard if this activation is still the current one.
          // A logout followed by a fresh sign-in can complete this detached
          // future after the *next* login has claimed the flags; clearing them
          // blindly would let a duplicate event restart that new session's load.
          if (_activatingWalletId == signedInWallet.id) {
            _isInitialActivationInProgress = false;
            _activatingWalletId = null;
          }
        }
        // The fan-out is done, so every activation broadcast that was going to
        // arrive has arrived. Anything still not `active` here was lost, not
        // pending: repair it rather than leaving the row spinning.
        var elapsed = Duration.zero;
        for (final delay in _postActivationReconcileDelays) {
          if (isClosed) return;
          await Future<void>.delayed(delay - elapsed);
          if (isClosed) return;
          elapsed = delay;
          add(CoinsActivationReconciled());
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
      StreamSubscription<Coin>? tempSub;
      Timer? fallbackTimer;

      void fire() {
        if (fired || isClosed) return;
        fired = true;
        stopwatch.stop();
        fallbackTimer?.cancel();
        fallbackTimer = null;
        final sub = tempSub;
        tempSub = null;
        unawaited(sub?.cancel());
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

      bool checkThreshold() {
        if (targetIds.isEmpty) return true;
        final coverage = activeIds.length / targetIds.length;
        if (coverage >= 0.8) {
          triggeredByThreshold = true;
          return true;
        }
        return false;
      }

      // Attach the listener and arm the fallback BEFORE the seed read, in that
      // order. Previously the seed read came first and was awaited inline, so
      // (a) any activation completing between the read and the attach was
      // missed, and (b) an untimed hang in the read meant the listener was
      // never attached and the fallback timer never armed - no threshold, no
      // timeout, no initial balance sweep at all.
      tempSub = _coinsRepo.enabledAssetsChanges.stream.listen((coin) {
        if (isClosed || fired) return;
        if (!targetIds.contains(coin.id.id)) return;
        if (!coin.isActive) return;
        activeIds.add(coin.id.id);
        if (checkThreshold()) fire();
      });

      fallbackTimer = Timer(const Duration(minutes: 1), () {
        triggeredByThreshold = false;
        fire();
      });

      // Seed with assets the SDK already reports as activated.
      try {
        final activated = await _kdfSdk.activatedAssetsCache
            .getActivatedAssetIds(forceRefresh: true);
        if (fired || isClosed) return;
        for (final id in activated) {
          if (targetIds.contains(id.id)) {
            activeIds.add(id.id);
          }
        }
      } catch (e) {
        // Best-effort seeding; the listener and the fallback still cover us.
        _log.fine('Initial activation seed read failed: $e');
        return;
      }

      if (checkThreshold()) fire();
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
    // `.first`, not `.single`: a config id that resolves to more than one asset
    // must not throw here. This runs inside the login fan-out, where the throw
    // would abort activation for every coin, not just the ambiguous one.
    final availableAssets = coins
        .map((coin) => _kdfSdk.assets.findAssetsByConfigId(coin))
        .where((assetsSet) => assetsSet.isNotEmpty)
        .map((assetsSet) => assetsSet.first);

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
    // Bounded, and failure-tolerant. This is a single serialised gate in front
    // of the entire fan-out, so an unbounded hang here means no coin activates
    // at all. Failing open is safe: the write is idempotent, activateAssetsSync
    // re-attempts it per asset when addToWalletMetadata is true, and the worst
    // case is that a coin is not remembered for the next session.
    try {
      await _coinsRepo
          .addAssetsToWalletMetadata(coinsToActivate.map((asset) => asset.id))
          .timeout(_loginPathRpcTimeout);
    } catch (e, s) {
      _log.warning(
        'Failed to write activated coins to wallet metadata; continuing with '
        'activation',
        e,
        s,
      );
    }

    if (isInitialLogin) {
      // One forced activated-assets read for the whole fan-out instead of one
      // per asset. Placed immediately before the fan-out so the staleness
      // window is sub-millisecond, preserving the freshness guarantee that the
      // per-asset force-refresh was added for (#3463, NoSuchCoin race).
      try {
        // A single serialised gate in front of the entire fan-out, so it must
        // not hang - ActivatedAssetsCache bounds the read itself. Failing open
        // is safe: activateAssetsSync still checks isAssetActivated per asset,
        // and SharedActivationCoordinator rechecks again before activating.
        await _coinsRepo.getActivatedAssetIds(forceRefresh: true);
      } catch (e, s) {
        _log.warning(
          'Failed to pre-fetch activated assets before login fan-out; '
          'continuing with per-asset checks',
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
    // Prefer the catalogue already in state: rebuilding it converts every
    // available asset to a Coin (recursing into the parent for each child
    // token) synchronously on the frame the user is watching, and
    // _onCoinsStarted has normally populated it already.
    //
    // Fall back per lookup rather than only when state.coins is empty. A
    // non-empty state.coins is not proof of a *complete* one - it is captured
    // once and only rebuilt on logout, so a catalogue built while the SDK asset
    // map was still loading would otherwise be reused for every login of the
    // session, and any coin missing from it would silently never get a row.
    var knownCoins = state.coins;
    Map<String, Coin>? rebuiltCoins;
    Coin? lookup(String id) {
      final fromState = knownCoins[id];
      if (fromState != null) return fromState;
      rebuiltCoins ??= _coinsRepo.getKnownCoinsMap();
      return rebuiltCoins![id];
    }

    final activatingCoins = <String, Coin>{};
    for (final coinId in coins) {
      final sdkCoin = lookup(coinId);
      if (sdkCoin == null) {
        _log.warning('No known coin for $coinId; it will have no wallet row');
        continue;
      }
      // Do not pre-populate zhtlc coins, as they require configuration
      // and longer activation times, and are handled separately.
      if (sdkCoin.id.subClass == CoinSubClass.zhtlc) continue;
      activatingCoins[sdkCoin.id.id] = sdkCoin.copyWith(
        state: CoinState.activating,
      );
    }

    if (rebuiltCoins != null) {
      // Keep the fuller catalogue so the next login does not pay for it again.
      knownCoins = {...rebuiltCoins!, ...knownCoins};
    }

    return state.copyWith(
      walletCoins: {...state.walletCoins, ...activatingCoins},
      coins: {...knownCoins, ...activatingCoins},
    );
  }
}
