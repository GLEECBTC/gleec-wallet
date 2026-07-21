import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart' as kdf;
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:web_dex/features/unified_swap/application/route_activity_bloc.dart';
import 'package:web_dex/features/unified_swap/application/route_execution_bloc.dart';
import 'package:web_dex/features/unified_swap/application/unified_swap_bloc.dart';
import 'package:web_dex/features/unified_swap/infrastructure/kdf_unified_swap_quote_repository.dart';
import 'package:web_dex/features/unified_swap/infrastructure/kdf_unified_swap_review_coordinator.dart';
import 'package:web_dex/features/unified_swap/presentation/unified_swap_wallet_scope.dart';

void main() {
  testWidgets('missing SDK composition renders the child fail closed', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: UnifiedSwapSdkScope(child: Text('unavailable'))),
    );
    expect(find.text('unavailable'), findsOneWidget);
  });

  testWidgets('wallet changes replace both scopes and rebuild Activity', (
    tester,
  ) async {
    final walletIds = StreamController<String?>.broadcast();
    final gateway = _Gateway();
    final manager = TradeRouteManager.withGateway(gateway: gateway);
    addTearDown(walletIds.close);
    addTearDown(manager.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedSwapWalletScope(
          currentWalletId: () async => 'wallet-1',
          walletIds: walletIds.stream,
          manager: manager,
          child: const _ScopeProbe(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('wallet-1|wallet-1'), findsOneWidget);
    expect(gateway.listCalls, 1);

    walletIds.add('wallet-2');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(
      tester.widgetList<Text>(find.byType(Text)).map((widget) => widget.data),
      contains('wallet-2|wallet-2'),
    );
    expect(gateway.listCalls, 2);

    walletIds.add(null);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(find.text('signed-out'), findsOneWidget);
    expect(gateway.cancelCalls, 0);
  });

  testWidgets('disposing the scope does not dispose the shared manager', (
    tester,
  ) async {
    final gateway = _Gateway();
    final manager = TradeRouteManager.withGateway(gateway: gateway);
    addTearDown(manager.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedSwapWalletScope(
          currentWalletId: () async => 'wallet-1',
          walletIds: const Stream.empty(),
          manager: manager,
          child: const _ScopeProbe(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    final page = await manager.listExecutions();
    expect(page.executions, isEmpty);
    expect(gateway.cancelCalls, 0);
  });

  testWidgets('optional production factory owns quote and Review scope', (
    tester,
  ) async {
    final gateway = _Gateway();
    final manager = TradeRouteManager.withGateway(gateway: gateway);
    addTearDown(manager.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedSwapWalletScope(
          currentWalletId: () async => 'wallet-1',
          walletIds: const Stream.empty(),
          manager: manager,
          quoteRepositoryFactory: ({required walletId, required manager}) =>
              KdfUnifiedSwapQuoteRepository(
                client: _NeverQuoteClient(),
                walletId: walletId,
                eligibilityCheck: (_) async => true,
                validateRecipient:
                    ({required ticker, required address}) async => true,
              ),
          routeExecutionId: () => '41f12b3c-79ac-42e7-bde9-5d43bdd1c1cb',
          child: const _ProductionScopeProbe(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('wallet-1|wallet-1|wallet-1|prepared'), findsOneWidget);
  });
}

class _ScopeProbe extends StatelessWidget {
  const _ScopeProbe();

  @override
  Widget build(BuildContext context) {
    try {
      final activityWallet = context.watch<RouteActivityBloc>().state.walletId;
      final executionWallet = context
          .watch<RouteExecutionBloc>()
          .state
          .walletId;
      return Text('$activityWallet|$executionWallet');
    } on Object {
      return const Text('signed-out');
    }
  }
}

class _ProductionScopeProbe extends StatelessWidget {
  const _ProductionScopeProbe();

  @override
  Widget build(BuildContext context) {
    try {
      final activityWallet = context.watch<RouteActivityBloc>().state.walletId;
      final executionWallet = context
          .watch<RouteExecutionBloc>()
          .state
          .walletId;
      final quoteWallet = context.watch<UnifiedSwapBloc>().state.walletId;
      context.read<KdfUnifiedSwapReviewCoordinator>();
      return Text('$activityWallet|$executionWallet|$quoteWallet|prepared');
    } on Object {
      return const Text('signed-out');
    }
  }
}

class _NeverQuoteClient implements KdfUnifiedSwapQuoteClient {
  @override
  Future<kdf.TradeRouteQuoteResult> quote({
    required kdf.TradeIntent intent,
    required List<kdf.RouteSource> routeSources,
    kdf.ValuationSnapshot? valuationSnapshot,
  }) => throw UnimplementedError();
}

class _Gateway implements TradeRouteRpcGateway {
  int listCalls = 0;
  int cancelCalls = 0;

  @override
  Future<kdf.ListRouteExecutionsResponse> listExecutions({
    required int limit,
    kdf.RouteActivityState? state,
    String? cursor,
  }) async {
    listCalls++;
    return kdf.ListRouteExecutionsResponse.parse({
      'mmrpc': '2.0',
      'result': {'executions': <Object>[], 'next_cursor': null},
    });
  }

  @override
  Future<kdf.RouteCancelResponse> cancelTradeRoute({
    required String routeExecutionId,
  }) {
    cancelCalls++;
    throw UnimplementedError();
  }

  @override
  Future<kdf.RouteExecutionDetailsResponse> getExecution({
    required String routeExecutionId,
  }) => throw UnimplementedError();

  @override
  Future<kdf.NewTaskResponse> initTradeRoute({
    required String routeExecutionId,
    required String idempotencyKey,
    required kdf.TradeRouteInitConsent routeConsent,
  }) => throw UnimplementedError();

  @override
  Future<kdf.TradeRouteTaskStatusResponse> tradeRouteStatus({
    required int taskId,
    required bool forgetIfFinished,
  }) => throw UnimplementedError();

  @override
  Future<kdf.RouteActionResponse> tradeRouteUserAction({
    required int taskId,
    required kdf.RouteExecutionUserAction userAction,
  }) => throw UnimplementedError();
}
