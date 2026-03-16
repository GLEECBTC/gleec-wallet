import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_sdk/src/activation/activation_exceptions.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/transaction_history/transaction_history_event.dart';
import 'package:web_dex/bloc/transaction_history/transaction_history_state.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/text_error.dart';
import 'package:web_dex/shared/utils/extensions/transaction_extensions.dart';
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

  String _errorMessageFrom(Object error) {
    if (error is SdkError) {
      final localized = error.messageKey.tr(args: error.messageArgs);
      return localized == error.messageKey ? error.fallbackMessage : localized;
    }

    if (error is ActivationFailedException && error.originalError is SdkError) {
      final sdkError = error.originalError as SdkError;
      final localized = sdkError.messageKey.tr(args: sdkError.messageArgs);
      return localized == sdkError.messageKey
          ? sdkError.fallbackMessage
          : localized;
    }

    if (error is ActivationFailedException) {
      return 'Asset activation failed: ${error.message}';
    }

    return LocaleKeys.somethingWrong.tr();
  }

  @override
  Future<void> close() async {
    await _historySubscription?.cancel();
    return super.close();
  }

  Future<void> _onSubscribe(
    TransactionHistorySubscribe event,
    Emitter<TransactionHistoryState> emit,
  ) async {
    emit(const TransactionHistoryState.initial());

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
      final myAddresses = pubkeys.keys.map((p) => p.address).toSet();

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
    emit(state.copyWith(transactions: event.transactions, loading: false));
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
