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
    on<TransactionHistoryFailure>(_onFailure);
  }

  final KomodoDefiSdk _sdk;
  StreamSubscription<List<Transaction>>? _historySubscription;

  /// The coin the current list belongs to, so a re-subscribe for the *same*
  /// coin can keep showing it.
  AssetId? _subscribedCoinId;

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
    }
    _subscribedCoinId = event.coin.id;

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

      final pubkeys =
          _sdk.pubkeys.lastKnown(asset.id) ??
          await _sdk.pubkeys.getPubkeys(asset);
      // Include GasFree custody addresses so sanitize sorts them first in
      // `to` (custody deposits and consolidations display the wallet's own
      // address, not the counterparty).
      final myAddresses = pubkeys.keys
          .expand(
            (p) => [
              p.address,
              if ((p.gasfreeAddress ?? '').isNotEmpty) p.gasfreeAddress!,
            ],
          )
          .toSet();

      Transaction sanitize(Transaction transaction) {
        return transaction.sanitize(myAddresses);
      }

      // High-level merged stream from SDK handles history + live updates.
      _historySubscription = _sdk.transactions
          .watchTransactionHistoryMerged(asset, transform: sanitize)
          .listen(
            (transactions) {
              final updatedTransactions = transactions.toList(growable: true);

              if (event.coin.isErcType) {
                _flagTransactions(updatedTransactions, event.coin);
              }

              add(TransactionHistoryUpdated(transactions: updatedTransactions));
            },
            onError: (error) {
              add(
                TransactionHistoryFailure(
                  error: TextError(error: _errorMessageFrom(error)),
                ),
              );
            },
          );
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

  void _onUpdated(
    TransactionHistoryUpdated event,
    Emitter<TransactionHistoryState> emit,
  ) {
    emit(
      state.copyWith(
        transactions: event.transactions,
        loading: false,
        clearError: true,
      ),
    );
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
