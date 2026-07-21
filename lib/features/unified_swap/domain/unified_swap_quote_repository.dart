import 'package:web_dex/features/unified_swap/domain/unified_swap_quote_models.dart';

abstract interface class UnifiedSwapQuoteRepository {
  Future<UnifiedSwapQuoteEvaluation> evaluate(UnifiedSwapIntent intent);
}

class UnifiedSwapQuoteException implements Exception {
  const UnifiedSwapQuoteException(this.failure);

  final UnifiedSwapQuoteFailure failure;
}
