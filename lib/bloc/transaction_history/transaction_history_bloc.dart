import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/transaction_history/transaction_history_event.dart';
import 'package:web_dex/bloc/transaction_history/transaction_history_state.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/text_error.dart';
import 'package:web_dex/shared/utils/extensions/transaction_extensions.dart';
import 'package:web_dex/shared/utils/kdf_error_display.dart';
import 'package:web_dex/shared/utils/utils.dart';

class TransactionHistoryBloc
    extends Bloc<TransactionHistoryEvent, TransactionHistoryState> {
  TransactionHistoryBloc({required KomodoDefiSdk sdk})
    : _sdk = sdk,
      super(const TransactionHistoryState.initial()) {
    on<TransactionHistorySubscribe>(_onSubscribe, transformer: restartable());
    on<TransactionHistoryStartedLoading>(_onStartedLoading);
    on<TransactionHistoryUpdated>(_onUpdated);
    on<TransactionHistoryAddressesUpdated>(_onAddressesUpdated);
    on<TransactionHistoryFailure>(_onFailure);
  }

  final KomodoDefiSdk _sdk;
  StreamSubscription<List<Transaction>>? _historySubscription;

  /// The coin the current list belongs to, so a re-subscribe for the *same*
  /// coin can keep showing it.
  AssetId? _subscribedCoinId;

  /// The coin itself, for the ERC-type filter applied when building the view.
  Coin? _subscribedCoin;

  /// Rows exactly as the SDK produced them.
  ///
  /// Display sanitization is applied when emitting rather than when receiving,
  /// so the wallet's addresses arriving late re-sorts rows already on screen
  /// instead of leaving them sorted against an empty set.
  List<Transaction> _rawTransactions = const [];

  /// The wallet's own addresses, empty until they resolve.
  Set<String> _myAddresses = const {};

  String _errorMessageFrom(Object error) => formatKdfUserFacingError(error);

  @override
  Future<void> close() async {
    await _historySubscription?.cancel();
    return super.close();
  }

  Future<void> _onSubscribe(
    TransactionHistorySubscribe event,
    Emitter<TransactionHistoryState> emit,
  ) async {
    // Only blank the list when the coin actually changed. Re-subscribing for
    // the same coin - the retry button, a completed withdrawal, `restartable()`
    // re-firing - used to reset to an empty list and therefore drop straight
    // back to the full-page spinner, discarding rows that were already correct.
    final isSameCoin = _subscribedCoinId == event.coin.id;
    if (isSameCoin) {
      emit(state.copyWith(clearError: true));
    } else {
      emit(const TransactionHistoryState.initial());
      _rawTransactions = const [];
      _myAddresses = const {};
    }
    _subscribedCoinId = event.coin.id;
    _subscribedCoin = event.coin;

    if (!hasTxHistorySupport(event.coin)) {
      emit(
        state.copyWith(
          loading: false,
          error: TextError(
            error: 'Transaction history is not supported for this coin.',
          ),
          transactions: const [],
        ),
      );
      return;
    }

    try {
      await _historySubscription?.cancel();

      add(const TransactionHistoryStartedLoading());
      final asset = _sdk.assets.available[event.coin.id];
      if (asset == null) {
        throw Exception('Asset ${event.coin.id} not found in known coins list');
      }

      // Subscribe BEFORE resolving addresses.
      //
      // This used to await `pubkeys.lastKnown(id) ?? getPubkeys(asset)` first.
      // `lastKnown` only reads the in-memory cache, and `getPubkeys` falls
      // through to a fresh fetch - which awaits `activateAsset` with retry -
      // whenever the persisted pubkey cache misses. So an unbounded,
      // network-bound call sat in front of a transaction cache that was ready
      // on disk, and the page rendered a spinner over a list it already had.
      //
      // Addresses only decide how recipients are ordered for display, so they
      // are resolved off the critical path and applied when they land.
      _historySubscription = _sdk.transactions
          .watchTransactionHistoryMerged(asset)
          .listen(
            (transactions) {
              add(TransactionHistoryUpdated(transactions: transactions));
            },
            onError: (error) {
              add(
                TransactionHistoryFailure(
                  error: TextError(error: _errorMessageFrom(error)),
                ),
              );
            },
          );

      unawaited(_resolveMyAddresses(asset));
    } catch (e, s) {
      log(
        'Error loading transaction history: $e',
        isError: true,
        path: 'transaction_history_bloc->_onSubscribe',
        trace: s,
      );

      add(
        TransactionHistoryFailure(
          error: TextError(error: _errorMessageFrom(e)),
        ),
      );
    }
  }

  /// Resolves the wallet's own addresses without blocking the list.
  ///
  /// Two passes on purpose. [PubkeyManager.hydratedPubkeys] is documented as
  /// never fetching and never activating, so it answers from cache or not at
  /// all - that covers the common case in milliseconds. The authoritative
  /// [PubkeyManager.getPubkeys] follows, and may activate, but by then the
  /// rows are already on screen and it can only improve the ordering.
  Future<void> _resolveMyAddresses(Asset asset) async {
    Future<void> apply(AssetPubkeys? pubkeys) async {
      if (pubkeys == null || isClosed) return;
      // Include GasFree custody addresses so sanitize sorts them first in
      // `to` (custody deposits and consolidations display the wallet's own
      // address, not the counterparty).
      final addresses = pubkeys.keys
          .expand(
            (p) => [
              p.address,
              if ((p.gasfreeAddress ?? '').isNotEmpty) p.gasfreeAddress!,
            ],
          )
          .toSet();
      if (addresses.isEmpty) return;
      add(
        TransactionHistoryAddressesUpdated(
          assetId: asset.id,
          addresses: addresses,
        ),
      );
    }

    try {
      apply(_sdk.pubkeys.lastKnown(asset.id));
      await apply(await _sdk.pubkeys.hydratedPubkeys(asset));
      await apply(await _sdk.pubkeys.getPubkeys(asset));
    } catch (e) {
      // Ordering-only metadata. Failing to resolve it must not surface as a
      // transaction history error - the rows are correct either way.
      log(
        'Could not resolve wallet addresses for ${asset.id.id}: $e',
        path: 'transaction_history_bloc->_resolveMyAddresses',
      );
    }
  }

  void _onAddressesUpdated(
    TransactionHistoryAddressesUpdated event,
    Emitter<TransactionHistoryState> emit,
  ) {
    // A late resolution from a previous subscription must not re-sort the
    // list that replaced it.
    if (event.assetId != _subscribedCoinId) return;
    if (event.addresses.length == _myAddresses.length &&
        event.addresses.containsAll(_myAddresses)) {
      return;
    }
    _myAddresses = event.addresses;
    if (_rawTransactions.isEmpty) return;
    emit(state.copyWith(transactions: _buildView()));
  }

  void _onUpdated(
    TransactionHistoryUpdated event,
    Emitter<TransactionHistoryState> emit,
  ) {
    _rawTransactions = event.transactions ?? const [];
    emit(
      state.copyWith(
        transactions: _buildView(),
        loading: false,
        clearError: true,
      ),
    );
  }

  /// Applies display-only transforms to the rows the SDK produced.
  ///
  /// Kept out of the stream's `transform` so it can be re-applied when the
  /// wallet's addresses arrive, rather than being baked into rows at the
  /// moment they were received.
  List<Transaction> _buildView() {
    final coin = _subscribedCoin;
    final view = _rawTransactions
        .map((tx) => tx.sanitize(_myAddresses))
        .toList(growable: true);
    if (coin != null && coin.isErcType) {
      _flagTransactions(view, coin);
    }
    return view;
  }

  void _onStartedLoading(
    TransactionHistoryStartedLoading event,
    Emitter<TransactionHistoryState> emit,
  ) {
    emit(state.copyWith(loading: true));
  }

  void _onFailure(
    TransactionHistoryFailure event,
    Emitter<TransactionHistoryState> emit,
  ) {
    emit(state.copyWith(loading: false, error: event.error));
  }
}

void _flagTransactions(List<Transaction> transactions, Coin coin) {
  if (!coin.isErcType) return;
  transactions.removeWhere(
    (tx) => tx.balanceChanges.totalAmount.toDouble() == 0.0,
  );
}
