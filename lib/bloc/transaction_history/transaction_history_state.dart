import 'package:equatable/equatable.dart';
import 'package:web_dex/mm2/mm2_api/rpc/base.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

final class TransactionHistoryState extends Equatable {
  const TransactionHistoryState({
    required this.transactions,
    required this.loading,
    required this.error,
  });

  final List<Transaction> transactions;
  final bool loading;
  final BaseError? error;

  @override
  List<Object?> get props => [transactions, loading, error];

  const TransactionHistoryState.initial()
      : transactions = const [],
        loading = false,
        error = null;

  /// [clearError] is required because [error] is nullable: `error ?? this.error`
  /// cannot express "drop the previous error". Without it a retry kept
  /// rendering the failure it was retrying.
  TransactionHistoryState copyWith({
    List<Transaction>? transactions,
    bool? loading,
    BaseError? error,
    bool clearError = false,
  }) {
    return TransactionHistoryState(
      transactions: transactions ?? this.transactions,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}
