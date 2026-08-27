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
import 'package:web_dex/analytics/frame_timing_recorder.dart';
import 'package:web_dex/model/wallet.dart';

part 'coins_event.dart';
part 'coins_state.dart';

/// Frame-capture window covering the whole initial activation fan-out.
///
/// Named in the `WalletLoadMark.eventName` vocabulary so it lines up with the
/// load timings `tool/parse_wallet_load_log.dart` prints beside it.
const String _activationStormSpan = 'activation_storm';

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

/// Activation coverage at which the initial balance sweep is worth running.
const double _initialBalanceCoverage = 0.8;

/// How long to wait for that coverage before sweeping anyway.
const Duration _initialBalanceCoverageTimeout = Duration(minutes: 1);

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
    on<CoinsWalletRepairRequested>(
      _onWalletRepairRequested,
      transformer: droppable(),
    );
    on<CoinsPubkeysRequested>(
      _onCoinsPubkeysRequested,
      transformer: concurrent(),
    );

    // Observe from construction, before anything can activate a coin. The
    // activation stream replays current state to a late subscriber, so this is
    // belt-and-braces rather than the load-bearing guard it used to be - but
    // there is no reason for a plain stream subscription to lag the producer
    // it exists to observe.
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
    // Populate first, filter second (the UX improvement the comment above used
    // to describe as a TODO).
    //
    // This ordering is now load-bearing rather than defensive: `main()` no
    // longer awaits `TradingStatusService.initialize()` before `runApp`, so the
    // geo call is genuinely in flight when this handler runs and
    // `initialStatusReady` is genuinely not yet satisfied. Everything
    // downstream - the catalogue emit that clears `WalletOverview`'s
    // empty-state spinner, and the `CoinsSessionStarted` dispatch that starts
    // the whole activation fan-out - would otherwise sit behind a geo call that
    // none of it depends on.
    //
    // The window between the two emissions can show a geo-blocked asset in the
    // catalogue list. That was already true for the whole session on the
    // timeout path, so this narrows the exposure rather than widening it.
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

    // Still inside the handler, so `emit` remains valid.
    try {
      await _tradingStatusService.initialStatusReady.timeout(
        _initialTradingStatusTimeout,
      );
      if (!isClosed) {
        emit(state.copyWith(coins: _coinsRepo.getKnownCoinsMap()));
      }
    } on TimeoutException {
      _log.warning(
        'Trading status not ready after '
        '${_initialTradingStatusTimeout.inSeconds}s; leaving the catalogue '
        'unfiltered',
      );
    }
  }

  /// Bridges [CoinsRepo]'s coin streams into bloc events.
  ///
  /// The activation stream is the SDK's authoritative per-asset state, merged
  /// with the app-only states the SDK has no vocabulary for. It replays, so a
  /// subscriber can never miss a transition - which is what removed the need
  /// for the reconcile pass that used to poll KDF for the same information.
  ///
  /// This also connects [CoinsBloc] to [CoinsManagerBloc] via [CoinsRepo],
  /// since the coins manager activates and deactivates coins through the
  /// repository. Other auto-activation sources, like the DEX, use it too.
  void _listenToRepoBroadcasts() {
    _enabledCoinsSubscription = _coinsRepo.watchCoinActivationState().listen(
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
        // Nothing to do when the sweep found the same values it already had.
        // `updateIguanaBalances` re-emits every watched coin, and the only
        // field it changes is `sendableBalance`, which `Coin.props` excludes -
        // so most ticks reach `Bloc.emit` only for its equality check to
        // deep-walk both maps and drop the emit. Same reasoning as
        // `_onBalanceChanged`; see the comment there.
        if (state.walletCoins[key] == coin && state.coins[key] == coin) {
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

  /// Re-drives the app-owned work that follows a coin becoming active.
  ///
  /// Activation state itself no longer needs repairing: the SDK publishes it
  /// on a replayable stream, so a row can no longer be left behind by a
  /// broadcast nobody was listening for. What is still app-owned, and still
  /// has no other retrigger, is everything that *follows* activation:
  ///
  ///  * addresses, when the pubkey fetch exhausted its retry budget - the SDK
  ///    will not re-emit `active` for an asset that is already active;
  ///  * balance watchers, on either side of the SDK/repo boundary.
  Future<void> _onWalletRepairRequested(
    CoinsWalletRepairRequested event,
    Emitter<CoinsState> emit,
  ) async {
    final activeCoins = state.walletCoins.values
        .where((coin) => coin.isActive)
        .toList();
    if (activeCoins.isEmpty) return;

    for (final coin in activeCoins) {
      if (!state.pubkeys.containsKey(coin.id.id)) {
        add(CoinsPubkeysRequested(coin.id.id));
      }
    }

    final restarted = _coinsRepo.ensureBalanceWatchers(
      activeCoins.map((coin) => coin.id),
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

    // Bail before allocating anything when both maps already hold exactly what
    // this handler would write.
    //
    // That is the common case during activation, not a rare one. `Coin.props`
    // excludes `sendableBalance`, `state` is preserved just above, and
    // `Coin.address` is never assigned anywhere in `lib/` - so on a
    // balance-only tick `merged == existing` and nothing changes. Without this
    // guard the handler still copied `walletCoins` *and* spread the whole
    // ~800-entry `coins` catalogue, and `Bloc.emit`'s equality check then
    // deep-walked ~840 `Coin`s (each recursing into `parentCoin`, because
    // `equatable`'s `mapEquals` short-circuits only on `identical`) purely to
    // conclude "unchanged" and drop the emit.
    //
    // Comparing the two entries costs 8 props for one coin instead. The state
    // stream is unaffected by construction: every case where the emit was not
    // already being dropped fails one of these checks.
    // Covered by `test_units/tests/wallet/coins_bloc_balance_emit_test.dart`.
    final shouldBePresent = merged.isActive || merged.isActivating;
    if (state.coins[assetId] == merged &&
        state.walletCoins[assetId] == (shouldBePresent ? merged : null)) {
      return;
    }

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
      final missingWatcherCount = _repairWalletIfUnhealthy();

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

  /// Requests a repair when the wallet shows either app-owned symptom.
  ///
  /// Both render to the user as a row that spins forever, and
  /// [_onWalletRepairRequested] fixes both:
  ///  - `active` with no live balance updates on either side of the SDK/repo
  ///    boundary;
  ///  - `active` with no addresses, i.e. the pubkey fetch exhausted its
  ///    retries and nothing else would ever re-trigger it.
  ///
  /// Returns the SDK-side missing-watcher count - a strict subset of the
  /// balance-repair count - for the caller's fallback sweep.
  int _repairWalletIfUnhealthy() {
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
    // `stalled` is reported but no longer triggers a repair: activation state
    // is pushed by the SDK now, so a row still outside `active` is one the app
    // seeded and never submitted - which this repair never fixed anyway.
    if (needingBalanceRepair > 0 || missingAddresses > 0) {
      _log.info(
        'Wallet health: ${total - stalled}/$total active, $stalled stalled, '
        '$needingBalanceRepair without live balances '
        '($missingWatcherCount SDK-side), '
        '$missingAddresses without addresses',
      );
      add(CoinsWalletRepairRequested());
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
    // whereas gating it meant the first tick could be delayed by the full
    // timeout.
    add(CoinsBalanceMonitoringStarted());

    // ZHTLC assets are dropped from the fan-out unless they already have a
    // saved configuration, so counting them would put the threshold out of
    // reach for an ARRR-enabled-but-unconfigured wallet.
    // Mirror _activateCoins' one-asset-per-config-id selection. Counting every
    // candidate for an ambiguous config id would include assets the fan-out
    // never attempts and could make the threshold unreachable.
    final targetIds = coinsToActivate
        .map(_kdfSdk.assets.findAssetsByConfigId)
        .where((assets) => assets.isNotEmpty)
        .map((assets) => assets.first)
        .where((asset) => !_tradingStatusService.isAssetBlocked(asset.id))
        .where((asset) => asset.id.subClass != CoinSubClass.zhtlc)
        .map((asset) => asset.id)
        .toSet();
    if (targetIds.isEmpty) {
      add(CoinsBalancesRefreshed());
      return;
    }

    unawaited(() async {
      final stopwatch = Stopwatch()..start();
      var reached = false;
      try {
        // The SDK arms this deadline before awaiting anything and resolves it
        // from its replayable activation stream, so it cannot hang and cannot
        // miss a transition that happened before the wait started.
        reached = await _kdfSdk.waitForEnabledAssetsToPassThreshold(
          targetIds,
          threshold: _initialBalanceCoverage,
          timeout: _initialBalanceCoverageTimeout,
        );
      } catch (e, s) {
        _log.warning('Initial activation coverage wait failed', e, s);
      }
      if (isClosed) return;
      stopwatch.stop();
      // Logged at info so it survives release builds. This is the headline
      // post-login timing: how long from sign-in until enough coins are active
      // to sweep balances.
      _log.info(
        'Initial activation reached '
        '${reached ? "${(_initialBalanceCoverage * 100).round()}% coverage" : "the timeout"} '
        'after ${stopwatch.elapsedMilliseconds}ms '
        '(${targetIds.length} coins targeted)',
      );
      add(CoinsBalancesRefreshed());
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

    // The window the jank actually lives in. `WalletLoadMark.firstBalance`,
    // which brackets the `wallet_load` span, fires as soon as *one* asset has
    // both a balance and a price - while the rest of the fan-out is still
    // running. Measuring only that span systematically misses the storm.
    // No-op unless the build set FRAME_TIMING_CAPTURE.
    if (isInitialLogin) frameSpanStart(_activationStormSpan);

    // Ignore the return type here and let the broadcast handle the state updates as
    // coins are activated.
    try {
      await Future.wait(enableFutures);
    } finally {
      if (isInitialLogin) {
        frameSpanEnd(_activationStormSpan);
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
