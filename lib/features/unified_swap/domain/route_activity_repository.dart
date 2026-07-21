import 'package:web_dex/features/unified_swap/domain/route_activity_models.dart';

abstract interface class RouteActivityRepository {
  Future<RouteActivityPage> listExecutions({
    required String walletId,
    RouteActivityStatus? state,
    String? cursor,
    int limit = 50,
  });

  Future<RouteExecutionDetail> getExecution({
    required String walletId,
    required String routeExecutionId,
  });
}

class RouteActivityException implements Exception {
  const RouteActivityException(this.failure);

  final RouteActivityFailure failure;
}
