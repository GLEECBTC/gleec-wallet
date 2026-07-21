import 'package:uuid/uuid.dart';
import 'package:web_dex/features/unified_swap/domain/route_execution_acceptance_coordinator.dart';
import 'package:web_dex/features/unified_swap/domain/route_execution_models.dart';
import 'package:web_dex/features/unified_swap/domain/route_execution_repository.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_product_policy.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_model_limits.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_quote_models.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_quote_repository.dart';
import 'package:web_dex/features/unified_swap/infrastructure/kdf_route_execution_repository.dart';
import 'package:web_dex/features/unified_swap/infrastructure/kdf_unified_swap_quote_repository.dart';

typedef UnifiedSwapRouteExecutionIdFactory = String Function();
typedef UnifiedSwapAcceptanceTransactionIdFactory = String Function();

/// Joins the digest-verified quote and one-shot execution repositories.
///
/// No caller-supplied display model crosses this boundary: the Review is
/// projected from KDF's prepared response and registered with the exact
/// consent before it is returned to presentation.
final class KdfUnifiedSwapReviewCoordinator
    implements
        RouteExecutionAcceptanceCoordinator,
        RouteExecutionAcceptanceLifecycle,
        RouteExecutionAcceptanceTransactionCoordinator {
  KdfUnifiedSwapReviewCoordinator({
    required KdfUnifiedSwapQuoteRepository quoteRepository,
    required KdfRouteExecutionRepository executionRepository,
    UnifiedSwapRouteExecutionIdFactory? routeExecutionId,
    UnifiedSwapAcceptanceTransactionIdFactory? acceptanceTransactionId,
  }) : _quoteRepository = quoteRepository,
       _executionRepository = executionRepository,
       _routeExecutionId = routeExecutionId ?? _newRouteExecutionId,
       _acceptanceTransactionId =
           acceptanceTransactionId ?? _newAcceptanceTransactionId;

  final KdfUnifiedSwapQuoteRepository _quoteRepository;
  final KdfRouteExecutionRepository _executionRepository;
  final UnifiedSwapRouteExecutionIdFactory _routeExecutionId;
  final UnifiedSwapAcceptanceTransactionIdFactory _acceptanceTransactionId;
  final Map<String, KdfVerifiedPreparedExecution> _verifiedReviews = {};
  final Map<String, _PendingAcceptanceReplacement> _pendingReplacements = {};

  static const _maximumRetainedAuthorities = 100;

  Future<RouteExecutionReview> prepareReview({
    required UnifiedSwapIntent intent,
    required UnifiedSwapQuoteCandidate candidate,
  }) async {
    final verified = await _quoteRepository.prepareExecution(
      intent: intent,
      candidate: candidate,
    );
    final review = _executionRepository.registerVerifiedExecution(
      routeExecutionId: _routeExecutionId(),
      verified: verified,
    );
    if (_verifiedReviews.length >= _maximumRetainedAuthorities &&
        !_verifiedReviews.containsKey(review.reviewId)) {
      _executionRepository.discardPreparedReview(review);
      throw const RouteExecutionException(
        RouteExecutionFailure.serviceUnavailable,
      );
    }
    _verifiedReviews[review.reviewId] = verified;
    return review;
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
    _verifiedReviews.remove(review.reviewId);
    _abandonPendingFor(review);
  }

  @override
  void retireConsumedReview(RouteExecutionReview review) {
    _verifiedReviews.remove(review.reviewId);
    _abandonPendingFor(review);
  }

  @override
  RouteExecutionReview commitReplacement({
    required String transactionId,
    required RouteExecutionReview expectedReview,
    required RouteExecutionReview proposedReview,
  }) {
    final pending = _pendingReplacements.remove(transactionId);
    if (pending == null ||
        pending.expectedReview != expectedReview ||
        pending.proposedReview != proposedReview ||
        !identical(
          _verifiedReviews[expectedReview.reviewId],
          pending.expectedVerified,
        )) {
      throw const RouteExecutionException(RouteExecutionFailure.invalidReview);
    }

    final replacement = _executionRepository.replaceRegisteredReview(
      expectedReview: expectedReview,
      expectedReplacement: proposedReview,
      verified: pending.replacementVerified,
    );
    _verifiedReviews.remove(expectedReview.reviewId);
    _verifiedReviews[replacement.reviewId] = pending.replacementVerified;
    return replacement;
  }

  @override
  void abandonReplacement(String transactionId) {
    _pendingReplacements.remove(transactionId);
  }

  @override
  Future<RouteExecutionAcceptanceResult> revalidate(
    RouteExecutionReview consentedReview,
  ) async {
    _abandonPendingFor(consentedReview);
    final consented = _verifiedReviews[consentedReview.reviewId];
    if (consented == null) {
      return const RouteExecutionAcceptanceUnavailable(
        RouteExecutionFailure.invalidReview,
      );
    }
    try {
      final refresh = await _quoteRepository.refreshPreparedExecution(
        consented: consented,
      );
      switch (refresh) {
        case KdfPreparedExecutionFreshQuote(:final intent, :final evaluation):
          discardReview(consentedReview);
          return RouteExecutionAcceptanceFreshQuote(
            intent: intent,
            evaluation: evaluation,
          );
        case KdfPreparedExecutionReplacement(:final decision, :final verified):
          if (decision != UnifiedSwapRefreshDecision.quiet &&
              decision != UnifiedSwapRefreshDecision.explicitConsentRequired) {
            return const RouteExecutionAcceptanceUnavailable(
              RouteExecutionFailure.serviceUnavailable,
            );
          }
          final replacement = _executionRepository.previewRegisteredReplacement(
            expectedReview: consentedReview,
            verified: verified,
          );
          final transactionId = _acceptanceTransactionId();
          if (!UnifiedSwapModelLimits.isCanonicalString(transactionId) ||
              _pendingReplacements.length >= _maximumRetainedAuthorities ||
              _pendingReplacements.containsKey(transactionId)) {
            throw const RouteExecutionException(
              RouteExecutionFailure.invalidReview,
            );
          }
          _pendingReplacements[transactionId] = _PendingAcceptanceReplacement(
            expectedReview: consentedReview,
            proposedReview: replacement,
            expectedVerified: consented,
            replacementVerified: verified,
          );
          return switch (decision) {
            UnifiedSwapRefreshDecision.quiet => RouteExecutionAcceptanceQuiet(
              replacement,
              transactionId: transactionId,
            ),
            UnifiedSwapRefreshDecision.explicitConsentRequired =>
              RouteExecutionAcceptanceMaterialChange(
                consentedReview: consentedReview,
                replacementReview: replacement,
                transactionId: transactionId,
              ),
            UnifiedSwapRefreshDecision.freshQuoteRequired ||
            UnifiedSwapRefreshDecision.unavailable =>
              const RouteExecutionAcceptanceUnavailable(
                RouteExecutionFailure.serviceUnavailable,
              ),
          };
      }
    } on UnifiedSwapQuoteException catch (error) {
      return RouteExecutionAcceptanceUnavailable(
        _executionFailureFor(error.failure),
      );
    } on RouteExecutionException catch (error) {
      return RouteExecutionAcceptanceUnavailable(error.failure);
    } on Object {
      return const RouteExecutionAcceptanceUnavailable(
        RouteExecutionFailure.unknown,
      );
    }
  }

  void _abandonPendingFor(RouteExecutionReview review) {
    _pendingReplacements.removeWhere(
      (_, pending) =>
          pending.expectedReview == review || pending.proposedReview == review,
    );
  }
}

final class _PendingAcceptanceReplacement {
  const _PendingAcceptanceReplacement({
    required this.expectedReview,
    required this.proposedReview,
    required this.expectedVerified,
    required this.replacementVerified,
  });

  final RouteExecutionReview expectedReview;
  final RouteExecutionReview proposedReview;
  final KdfVerifiedPreparedExecution expectedVerified;
  final KdfVerifiedPreparedExecution replacementVerified;
}

RouteExecutionFailure _executionFailureFor(
  UnifiedSwapQuoteFailure failure,
) => switch (failure) {
  UnifiedSwapQuoteFailure.capabilityUnavailable ||
  UnifiedSwapQuoteFailure.suspiciousToken ||
  UnifiedSwapQuoteFailure.unknownTokenConfirmationRequired =>
    RouteExecutionFailure.capabilityUnavailable,
  UnifiedSwapQuoteFailure.quoteExpired => RouteExecutionFailure.reviewExpired,
  UnifiedSwapQuoteFailure.invalidIntent => RouteExecutionFailure.invalidReview,
  UnifiedSwapQuoteFailure.networkUnavailable =>
    RouteExecutionFailure.networkUnavailable,
  UnifiedSwapQuoteFailure.serviceUnavailable =>
    RouteExecutionFailure.serviceUnavailable,
  UnifiedSwapQuoteFailure.unknown => RouteExecutionFailure.unknown,
};

String _newRouteExecutionId() => const Uuid().v4();

String _newAcceptanceTransactionId() => const Uuid().v4();
