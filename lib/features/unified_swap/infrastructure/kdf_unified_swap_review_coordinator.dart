import 'package:uuid/uuid.dart';
import 'package:web_dex/features/unified_swap/domain/route_execution_models.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_quote_models.dart';
import 'package:web_dex/features/unified_swap/infrastructure/kdf_route_execution_repository.dart';
import 'package:web_dex/features/unified_swap/infrastructure/kdf_unified_swap_quote_repository.dart';

typedef UnifiedSwapRouteExecutionIdFactory = String Function();

/// Joins the digest-verified quote and one-shot execution repositories.
///
/// No caller-supplied display model crosses this boundary: the Review is
/// projected from KDF's prepared response and registered with the exact
/// consent before it is returned to presentation.
final class KdfUnifiedSwapReviewCoordinator {
  KdfUnifiedSwapReviewCoordinator({
    required KdfUnifiedSwapQuoteRepository quoteRepository,
    required KdfRouteExecutionRepository executionRepository,
    UnifiedSwapRouteExecutionIdFactory? routeExecutionId,
  }) : _quoteRepository = quoteRepository,
       _executionRepository = executionRepository,
       _routeExecutionId = routeExecutionId ?? _newRouteExecutionId;

  final KdfUnifiedSwapQuoteRepository _quoteRepository;
  final KdfRouteExecutionRepository _executionRepository;
  final UnifiedSwapRouteExecutionIdFactory _routeExecutionId;

  Future<RouteExecutionReview> prepareReview({
    required UnifiedSwapIntent intent,
    required UnifiedSwapQuoteCandidate candidate,
  }) async {
    final verified = await _quoteRepository.prepareExecution(
      intent: intent,
      candidate: candidate,
    );
    return _executionRepository.registerVerifiedExecution(
      routeExecutionId: _routeExecutionId(),
      verified: verified,
    );
  }

  /// Prepares recovery authority for an existing durable route.
  ///
  /// Unlike a new route Review, this deliberately reuses the authoritative
  /// route execution ID. The resulting consent is still fresh, digest-bound,
  /// memory-only, and can only be consumed by `select_recovery_route`.
  Future<RouteExecutionReview> prepareRecoveryReview({
    required String routeExecutionId,
    required UnifiedSwapIntent intent,
    required UnifiedSwapQuoteCandidate candidate,
  }) async {
    final verified = await _quoteRepository.prepareExecution(
      intent: intent,
      candidate: candidate,
    );
    return _executionRepository.registerVerifiedExecution(
      routeExecutionId: routeExecutionId,
      verified: verified,
    );
  }

  void discardReview(RouteExecutionReview review) {
    _executionRepository.discardPreparedReview(review);
  }
}

String _newRouteExecutionId() => const Uuid().v4();
