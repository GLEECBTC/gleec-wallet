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
import 'package:web_dex/model/coin_type.dart';
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
  StreamSubscription<Transaction>? _newTransactionsSubscription;

  // TODO: Remove or move to SDK
  final Set<String> _processedTxIds = {};
  // Stable in-memory clock for transactions that arrive with a zero timestamp.
  // Ensures deterministic ordering of unconfirmed and just-confirmed items.
  final Map<String, DateTime> _firstSeenAtByInternalId = {};

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
    await _newTransactionsSubscription?.cancel();
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
      await _newTransactionsSubscription?.cancel();
      _processedTxIds.clear();
      _firstSeenAtByInternalId.clear();

      add(const TransactionHistoryStartedLoading());
      final asset = _sdk.assets.available[event.coin.id];
      if (asset == null) {
        throw Exception('Asset ${event.coin.id} not found in known coins list');
      }

      final pubkeys =
          _sdk.pubkeys.lastKnown(asset.id) ??
          await _sdk.pubkeys.getPubkeys(asset);
      final myAddresses = pubkeys.keys.map((p) => p.address).toSet();

      // Subscribe to historical transactions
      _historySubscription = _sdk.transactions
          .getTransactionsStreamed(asset)
          .listen(
            (newTransactions) {
              if (newTransactions.isEmpty) return;

              final Map<String, Transaction> byId = _transactionsByInternalId(
                state.transactions,
              );
              final Map<String, String> internalIdByTxHash = _txHashIndex(
                state.transactions,
                event.coin,
              );

              for (final tx in newTransactions) {
                final sanitized = tx.sanitize(myAddresses);
                _rememberFirstSeen(sanitized);
                final existingInternalId = _findExistingTransactionInternalId(
                  byId: byId,
                  internalIdByTxHash: internalIdByTxHash,
                  transaction: sanitized,
                  coin: event.coin,
                );

                if (existingInternalId != null &&
                    existingInternalId != sanitized.internalId) {
                  byId.remove(sanitized.internalId);
                }

                final canonicalInternalId =
                    existingInternalId ?? sanitized.internalId;
                final existing = byId[canonicalInternalId];
                if (existing == null) {
                  byId[canonicalInternalId] = sanitized;
                  _indexTransactionTxHash(
                    internalIdByTxHash,
                    transaction: sanitized,
                    internalId: canonicalInternalId,
                    coin: event.coin,
                  );
                  _processedTxIds.add(canonicalInternalId);
                  continue;
                }

                // Update existing entry with fresher data (confirmations, blockHeight, fee, memo)
                final merged = _mergeTransaction(existing, sanitized);
                byId[canonicalInternalId] = merged;
                _indexTransactionTxHash(
                  internalIdByTxHash,
                  transaction: merged,
                  internalId: canonicalInternalId,
                  coin: event.coin,
                );
                _processedTxIds.add(canonicalInternalId);
              }

              final updatedTransactions = byId.values.toList()
                ..sort(_compareTransactions);

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
            onDone: () {
              if (state.error == null && state.loading) {
                add(
                  TransactionHistoryUpdated(transactions: state.transactions),
                );
              }
              // Once historical load is complete, start watching for new transactions
              _subscribeToNewTransactions(asset, event.coin, myAddresses);
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

  void _subscribeToNewTransactions(
    Asset asset,
    Coin coin,
    Set<String> myAddresses,
  ) {
    _newTransactionsSubscription = _sdk.transactions
        .watchTransactions(asset)
        .listen(
          (newTransaction) {
            final sanitized = newTransaction.sanitize(myAddresses);
            _rememberFirstSeen(sanitized);

            final Map<String, Transaction> byId = _transactionsByInternalId(
              state.transactions,
            );
            final Map<String, String> internalIdByTxHash = _txHashIndex(
              state.transactions,
              coin,
            );
            final existingInternalId = _findExistingTransactionInternalId(
              byId: byId,
              internalIdByTxHash: internalIdByTxHash,
              transaction: sanitized,
              coin: coin,
            );

            if (existingInternalId != null &&
                existingInternalId != sanitized.internalId) {
              byId.remove(sanitized.internalId);
            }

            final canonicalInternalId =
                existingInternalId ?? sanitized.internalId;
            final existing = byId[canonicalInternalId];
            if (existing == null) {
              byId[canonicalInternalId] = sanitized;
              _indexTransactionTxHash(
                internalIdByTxHash,
                transaction: sanitized,
                internalId: canonicalInternalId,
                coin: coin,
              );
            } else {
              final merged = _mergeTransaction(existing, sanitized);
              byId[canonicalInternalId] = merged;
              _indexTransactionTxHash(
                internalIdByTxHash,
                transaction: merged,
                internalId: canonicalInternalId,
                coin: coin,
              );
            }

            _processedTxIds.add(canonicalInternalId);

            final updatedTransactions = byId.values.toList()
              ..sort(_compareTransactions);

            if (coin.isErcType) {
              _flagTransactions(updatedTransactions, coin);
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

  void _rememberFirstSeen(Transaction transaction) {
    _firstSeenAtByInternalId.putIfAbsent(
      transaction.internalId,
      () => transaction.timestamp.millisecondsSinceEpoch != 0
          ? transaction.timestamp
          : DateTime.now(),
    );
  }

  Map<String, Transaction> _transactionsByInternalId(
    Iterable<Transaction> transactions,
  ) => {
    for (final transaction in transactions) transaction.internalId: transaction,
  };

  Map<String, String> _txHashIndex(
    Iterable<Transaction> transactions,
    Coin coin,
  ) {
    if (!_usesTxHashLookup(coin)) return <String, String>{};

    final byTxHash = <String, String>{};
    for (final transaction in transactions) {
      final txHash = transaction.txHash;
      if (txHash != null && txHash.isNotEmpty) {
        byTxHash[txHash] = transaction.internalId;
      }
    }
    return byTxHash;
  }

  String? _findExistingTransactionInternalId({
    required Map<String, Transaction> byId,
    required Map<String, String> internalIdByTxHash,
    required Transaction transaction,
    required Coin coin,
  }) {
    if (byId.containsKey(transaction.internalId)) {
      return transaction.internalId;
    }

    if (!_usesTxHashLookup(coin)) {
      return null;
    }

    final txHash = transaction.txHash;
    if (txHash == null || txHash.isEmpty) {
      return null;
    }

    return internalIdByTxHash[txHash];
  }

  void _indexTransactionTxHash(
    Map<String, String> internalIdByTxHash, {
    required Transaction transaction,
    required String internalId,
    required Coin coin,
  }) {
    if (!_usesTxHashLookup(coin)) {
      return;
    }

    final txHash = transaction.txHash;
    if (txHash == null || txHash.isEmpty) {
      return;
    }

    internalIdByTxHash[txHash] = internalId;
  }

  bool _usesTxHashLookup(Coin coin) =>
      coin.type == CoinType.tendermint || coin.type == CoinType.tendermintToken;

  Transaction _mergeTransaction(Transaction existing, Transaction incoming) {
    final incomingTxHash = incoming.txHash;
    return existing.copyWith(
      confirmations: incoming.confirmations,
      blockHeight: incoming.blockHeight,
      fee: incoming.fee ?? existing.fee,
      memo: incoming.memo ?? existing.memo,
      // Update the timestamp to change date from "Now" once tx
      // is confirmed on the blockchain
      timestamp: incoming.timestamp,
      txHash: incomingTxHash != null && incomingTxHash.isNotEmpty
          ? incomingTxHash
          : existing.txHash,
    );
  }

  int _compareTransactions(Transaction left, Transaction right) {
    final unconfirmedTimestamp = DateTime.fromMillisecondsSinceEpoch(0);
    final leftIsUnconfirmed = left.timestamp == unconfirmedTimestamp;
    final rightIsUnconfirmed = right.timestamp == unconfirmedTimestamp;

    if (leftIsUnconfirmed && rightIsUnconfirmed) {
      final leftFirstSeen =
          _firstSeenAtByInternalId[left.internalId] ?? unconfirmedTimestamp;
      final rightFirstSeen =
          _firstSeenAtByInternalId[right.internalId] ?? unconfirmedTimestamp;
      final compareByFirstSeen = rightFirstSeen.compareTo(leftFirstSeen);
      if (compareByFirstSeen != 0) {
        return compareByFirstSeen;
      }
      return right.internalId.compareTo(left.internalId);
    }

    if (leftIsUnconfirmed) {
      return -1;
    }

    if (rightIsUnconfirmed) {
      return 1;
    }

    return right.timestamp.compareTo(left.timestamp);
  }
}

// Instance comparator now used; legacy top-level comparator removed.

void _flagTransactions(List<Transaction> transactions, Coin coin) {
  if (!coin.isErcType) return;
  transactions.removeWhere(
    (tx) => tx.balanceChanges.totalAmount.toDouble() == 0.0,
  );
}

class Pagination {
  Pagination({this.fromId, this.pageNumber});
  final String? fromId;
  final int? pageNumber;

  Map<String, dynamic> toJson() => {
    if (fromId != null) 'FromId': fromId,
    if (pageNumber != null) 'PageNumber': pageNumber,
  };
}

/// Represents different ways to paginate transaction history
sealed class TransactionPagination {
  const TransactionPagination();

  /// Get the limit of transactions to return, if applicable
  int? get limit;
}

/// Standard page-based pagination
class PagePagination extends TransactionPagination {
  const PagePagination({required this.pageNumber, required this.itemsPerPage});

  final int pageNumber;
  final int itemsPerPage;

  @override
  int get limit => itemsPerPage;
}

/// Pagination from a specific transaction ID
class TransactionBasedPagination extends TransactionPagination {
  const TransactionBasedPagination({
    required this.fromId,
    required this.itemCount,
  });

  final String fromId;
  final int itemCount;

  @override
  int get limit => itemCount;
}

/// Pagination by block range
class BlockRangePagination extends TransactionPagination {
  const BlockRangePagination({
    required this.fromBlock,
    required this.toBlock,
    this.maxItems,
  });

  final int fromBlock;
  final int toBlock;
  final int? maxItems;

  @override
  int? get limit => maxItems;
}

/// Pagination by timestamp range
class TimestampRangePagination extends TransactionPagination {
  const TimestampRangePagination({
    required this.fromTimestamp,
    required this.toTimestamp,
    this.maxItems,
  });

  final DateTime fromTimestamp;
  final DateTime toTimestamp;
  final int? maxItems;

  @override
  int? get limit => maxItems;
}

/// Contract-specific pagination (e.g., for ERC20 token transfers)
class ContractEventPagination extends TransactionPagination {
  const ContractEventPagination({
    required this.contractAddress,
    required this.fromBlock,
    this.toBlock,
    this.maxItems,
  });

  final String contractAddress;
  final int fromBlock;
  final int? toBlock;
  final int? maxItems;

  @override
  int? get limit => maxItems;
}
