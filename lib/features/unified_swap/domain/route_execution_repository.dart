import 'package:web_dex/features/unified_swap/domain/route_execution_models.dart';

abstract interface class RouteExecutionRepository {
  Future<RouteExecutionSession> initReviewedExecution({
    required String walletId,
    required String routeExecutionId,
    required String reviewId,
    required String consentDigest,
  });

  Future<RouteExecutionSession> reattachExecution({
    required String walletId,
    required String routeExecutionId,
  });

  /// Cancelling a listener to this stream must stop observation only. It must
  /// never invoke a backend route control.
  Stream<RouteExecutionProgress> observe(RouteExecutionSession session);

  Future<void> cancelExecution({
    required String walletId,
    required String routeExecutionId,
  });

  Future<void> stopAfterCurrent({
    required String walletId,
    required String routeExecutionId,
  });

  Future<RouteActionAcknowledgement> submitDecision({
    required String walletId,
    required RouteExecutionSession session,
    required RouteExecutionDecision decision,
  });
}

class RouteExecutionException implements Exception {
  const RouteExecutionException(this.failure);

  final RouteExecutionFailure failure;
}
