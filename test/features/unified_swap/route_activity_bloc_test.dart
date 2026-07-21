import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/features/unified_swap/application/route_activity_bloc.dart';
import 'package:web_dex/features/unified_swap/domain/route_activity_models.dart';
import 'package:web_dex/features/unified_swap/domain/route_activity_repository.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_capability_policy.dart';

void main() {
  final now = DateTime.utc(2026, 7, 18, 12);

  test('wallet change discards an old wallet response', () async {
    final repository = _ControlledActivityRepository();
    final bloc = RouteActivityBloc(repository: repository);

    bloc.add(const RouteActivityWalletChanged('wallet-a'));
    await repository.waitForListRequests(1);
    bloc.add(const RouteActivityWalletChanged('wallet-b'));
    await repository.waitForListRequests(2);

    repository.completeList(
      1,
      RouteActivityPage(executions: [_summary('new', now)], nextCursor: null),
    );
    await _waitFor(() => bloc.state.executions.isNotEmpty);
    repository.completeList(
      0,
      RouteActivityPage(executions: [_summary('old', now)], nextCursor: null),
    );
    await Future<void>.delayed(Duration.zero);

    expect(bloc.state.walletId, 'wallet-b');
    expect(bloc.state.executions.single.routeExecutionId, 'new');
    await bloc.close();
  });

  test('empty page preserves its opaque continuation cursor', () async {
    final repository = _QueuedActivityRepository([
      RouteActivityPage(
        executions: [_summary('first', now)],
        nextCursor: 'cursor-1',
      ),
      RouteActivityPage(executions: const [], nextCursor: 'cursor-2'),
    ]);
    final bloc = RouteActivityBloc(repository: repository);

    bloc.add(const RouteActivityWalletChanged('wallet'));
    await _waitFor(() => bloc.state.status == RouteActivityLoadStatus.ready);
    bloc.add(const RouteActivityLoadMoreRequested());
    await _waitFor(() => repository.cursors.length == 2);
    await _waitFor(() => bloc.state.status == RouteActivityLoadStatus.ready);

    expect(bloc.state.executions.single.routeExecutionId, 'first');
    expect(bloc.state.nextCursor, 'cursor-2');
    expect(bloc.state.hasMore, isTrue);
    expect(repository.cursors, [null, 'cursor-1']);
    await bloc.close();
  });

  test('resume replaces list and refreshes selected detail from KDF', () async {
    final first = _summary('route', now);
    final updated = _summary(
      'route',
      now.add(const Duration(minutes: 1)),
      status: RouteActivityStatus.attentionRequired,
    );
    final repository = _QueuedActivityRepository(
      [
        RouteActivityPage(executions: [first], nextCursor: null),
        RouteActivityPage(executions: [updated], nextCursor: null),
      ],
      details: [_detail(first), _detail(updated)],
    );
    final bloc = RouteActivityBloc(repository: repository);

    bloc.add(const RouteActivityWalletChanged('wallet'));
    await _waitFor(() => bloc.state.status == RouteActivityLoadStatus.ready);
    bloc.add(const RouteActivityExecutionRequested('route'));
    await _waitFor(() => bloc.state.selectedExecution != null);
    bloc.add(const RouteActivityAppResumed());
    await _waitFor(
      () =>
          bloc.state.status == RouteActivityLoadStatus.ready &&
          bloc.state.executions.single.status ==
              RouteActivityStatus.attentionRequired,
    );

    expect(
      bloc.state.selectedExecution?.summary.status,
      RouteActivityStatus.attentionRequired,
    );
    expect(repository.detailRouteIds, ['route', 'route']);
    await bloc.close();
  });

  test('groups terminal outcomes without losing their exact states', () {
    final state = RouteActivityState(
      executions: [
        _summary('active', now),
        _summary(
          'attention',
          now,
          status: RouteActivityStatus.attentionRequired,
        ),
        _summary('completed', now, status: RouteActivityStatus.completed),
        _summary('cancelled', now, status: RouteActivityStatus.cancelled),
        _summary('failed', now, status: RouteActivityStatus.failed),
      ],
    );

    expect(
      state.grouped[RouteActivityGroup.active]!.map(
        (item) => item.routeExecutionId,
      ),
      ['active'],
    );
    expect(
      state.grouped[RouteActivityGroup.attentionRequired]!.map(
        (item) => item.routeExecutionId,
      ),
      ['attention'],
    );
    expect(
      state.grouped[RouteActivityGroup.completed]!.map((item) => item.status),
      [
        RouteActivityStatus.completed,
        RouteActivityStatus.cancelled,
        RouteActivityStatus.failed,
      ],
    );
  });
}

RouteActivitySummary _summary(
  String id,
  DateTime now, {
  RouteActivityStatus status = RouteActivityStatus.active,
}) => RouteActivitySummary(
  routeExecutionId: id,
  status: status,
  source: _nativeEth,
  destination: _usdcPolygon,
  createdAt: now.subtract(const Duration(minutes: 2)),
  updatedAt: now,
  completedAt: status.isTerminal ? now : null,
);

RouteExecutionDetail _detail(RouteActivitySummary summary) =>
    RouteExecutionDetail(
      summary: summary,
      consent: RouteExecutionConsent(
        routeExecutionId: summary.routeExecutionId,
        consentDigest: 'consent',
        candidateDigest: 'candidate',
        source: _nativeEth,
        destination: _usdcPolygon,
        sourceAmount: '1000000000000000',
        expectedReceive: '1000000',
        minimumReceive: '995000',
        fees: const [],
        nonNetworkFeeLimits: const [],
        networkFeeCaps: const [],
        resolvedSourceAddress: '0x1111111111111111111111111111111111111111',
        recipient: '0x2222222222222222222222222222222222222222',
      ),
      controls: RouteControlCapabilities(
        canCancel: false,
        canStopAfterCurrent: false,
        reconciliationOnly: true,
      ),
      holding: null,
      stages: const [],
      revisions: const [],
    );

const _nativeEth = UnifiedSwapAssetIdentity(
  ticker: 'ETH',
  chainFamily: UnifiedSwapChainFamily.evm,
  chainId: '1',
  kind: UnifiedSwapAssetKind.native,
  decimals: 18,
);

const _usdcPolygon = UnifiedSwapAssetIdentity(
  ticker: 'USDC',
  chainFamily: UnifiedSwapChainFamily.evm,
  chainId: '137',
  kind: UnifiedSwapAssetKind.token,
  decimals: 6,
  contractAddress: '0x1111111111111111111111111111111111111111',
);

class _ControlledActivityRepository implements RouteActivityRepository {
  final listRequests = <Completer<RouteActivityPage>>[];

  @override
  Future<RouteExecutionDetail> getExecution({
    required String walletId,
    required String routeExecutionId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<RouteActivityPage> listExecutions({
    required String walletId,
    RouteActivityStatus? state,
    String? cursor,
    int limit = 50,
  }) {
    final completer = Completer<RouteActivityPage>();
    listRequests.add(completer);
    return completer.future;
  }

  void completeList(int index, RouteActivityPage page) =>
      listRequests[index].complete(page);

  Future<void> waitForListRequests(int count) =>
      _waitFor(() => listRequests.length >= count);
}

class _QueuedActivityRepository implements RouteActivityRepository {
  _QueuedActivityRepository(this.pages, {this.details = const []});

  final List<RouteActivityPage> pages;
  final List<RouteExecutionDetail> details;
  final cursors = <String?>[];
  final detailRouteIds = <String>[];
  int _pageIndex = 0;
  int _detailIndex = 0;

  @override
  Future<RouteExecutionDetail> getExecution({
    required String walletId,
    required String routeExecutionId,
  }) async {
    detailRouteIds.add(routeExecutionId);
    return details[_detailIndex++];
  }

  @override
  Future<RouteActivityPage> listExecutions({
    required String walletId,
    RouteActivityStatus? state,
    String? cursor,
    int limit = 50,
  }) async {
    cursors.add(cursor);
    return pages[_pageIndex++];
  }
}

Future<void> _waitFor(bool Function() predicate) async {
  for (var index = 0; index < 100; index++) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  throw TimeoutException('Condition was not reached');
}
