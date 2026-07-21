import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/features/unified_swap/application/route_execution_bloc.dart';
import 'package:web_dex/features/unified_swap/domain/route_activity_models.dart';
import 'package:web_dex/features/unified_swap/domain/route_execution_models.dart';
import 'package:web_dex/features/unified_swap/domain/route_execution_repository.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_capability_policy.dart';

void main() {
  final now = DateTime.utc(2026, 7, 18, 12);

  test(
    'execution cannot start without exact mandatory review consent',
    () async {
      final repository = _FakeRouteExecutionRepository();
      final bloc = RouteExecutionBloc(repository: repository, now: () => now);
      bloc.add(const RouteExecutionWalletChanged('wallet'));
      await _waitFor(() => bloc.state.walletId == 'wallet');

      bloc.add(
        const RouteExecutionReviewAccepted(
          reviewId: 'missing',
          consentDigest: 'missing',
        ),
      );
      await _waitFor(
        () => bloc.state.failure == RouteExecutionFailure.invalidReview,
      );

      expect(repository.initCalls, isEmpty);
      await bloc.close();
    },
  );

  test(
    'accepted exact review starts observation and exposes safe progress',
    () async {
      final repository = _FakeRouteExecutionRepository();
      final bloc = RouteExecutionBloc(repository: repository, now: () => now);
      bloc.add(const RouteExecutionWalletChanged('wallet'));
      await _waitFor(() => bloc.state.walletId == 'wallet');
      final review = _review(now);
      bloc.add(RouteExecutionReviewPresented(review));
      await _waitFor(
        () => bloc.state.status == RouteExecutionLoadStatus.reviewRequired,
      );
      bloc.add(
        RouteExecutionReviewAccepted(
          reviewId: review.reviewId,
          consentDigest: review.consentDigest,
        ),
      );
      await _waitFor(() => repository.initCalls.length == 1);
      repository.progress.add(_progress(now));
      await _waitFor(() => bloc.state.progress != null);

      expect(bloc.state.status, RouteExecutionLoadStatus.observing);
      expect(bloc.state.announcement, RouteLiveAnnouncement.sending);
      expect(bloc.state.routeExecutionId, _routeId);
      await bloc.close();
    },
  );

  test('duplicate review acceptance produces one fresh init', () async {
    final repository = _FakeRouteExecutionRepository();
    final pendingInit = Completer<RouteExecutionSession>();
    repository.initCompleter = pendingInit;
    final bloc = RouteExecutionBloc(repository: repository, now: () => now);
    bloc.add(const RouteExecutionWalletChanged('wallet'));
    await _waitFor(() => bloc.state.walletId == 'wallet');
    final review = _review(now);
    bloc.add(RouteExecutionReviewPresented(review));
    await _waitFor(
      () => bloc.state.status == RouteExecutionLoadStatus.reviewRequired,
    );
    final acceptance = RouteExecutionReviewAccepted(
      reviewId: review.reviewId,
      consentDigest: review.consentDigest,
    );

    bloc.add(acceptance);
    await _waitFor(
      () => bloc.state.status == RouteExecutionLoadStatus.starting,
    );
    bloc.add(acceptance);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(repository.initCalls, [_routeId]);
    pendingInit.complete(
      const RouteExecutionSession(routeExecutionId: _routeId, taskId: 1),
    );
    await _waitFor(() => repository.hasListener);
    expect(repository.initCalls, [_routeId]);
    await bloc.close();
  });

  test('resume cannot interrupt a fresh init in flight', () async {
    final repository = _FakeRouteExecutionRepository();
    final pendingInit = Completer<RouteExecutionSession>();
    repository.initCompleter = pendingInit;
    final bloc = RouteExecutionBloc(repository: repository, now: () => now);
    bloc.add(const RouteExecutionWalletChanged('wallet'));
    await _waitFor(() => bloc.state.walletId == 'wallet');
    final review = _review(now);
    bloc.add(RouteExecutionReviewPresented(review));
    await _waitFor(
      () => bloc.state.status == RouteExecutionLoadStatus.reviewRequired,
    );
    bloc.add(
      RouteExecutionReviewAccepted(
        reviewId: review.reviewId,
        consentDigest: review.consentDigest,
      ),
    );
    await _waitFor(
      () => bloc.state.status == RouteExecutionLoadStatus.starting,
    );

    bloc.add(const RouteExecutionAppResumed());
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(repository.reattachCalls, isEmpty);
    pendingInit.complete(
      const RouteExecutionSession(routeExecutionId: _routeId, taskId: 1),
    );
    await _waitFor(() => repository.hasListener);
    expect(repository.initCalls, [_routeId]);
    expect(repository.reattachCalls, isEmpty);
    await bloc.close();
  });

  test(
    'uncertain init reconciles by durable ID without retrying init',
    () async {
      final repository = _FakeRouteExecutionRepository()
        ..initFailure = const RouteExecutionException(
          RouteExecutionFailure.networkUnavailable,
        );
      final bloc = RouteExecutionBloc(repository: repository, now: () => now);
      bloc.add(const RouteExecutionWalletChanged('wallet'));
      await _waitFor(() => bloc.state.walletId == 'wallet');
      final review = _review(now);
      bloc.add(RouteExecutionReviewPresented(review));
      await _waitFor(
        () => bloc.state.status == RouteExecutionLoadStatus.reviewRequired,
      );

      bloc.add(
        RouteExecutionReviewAccepted(
          reviewId: review.reviewId,
          consentDigest: review.consentDigest,
        ),
      );
      await _waitFor(() => repository.hasListener);

      expect(repository.initCalls, [_routeId]);
      expect(repository.reattachCalls, [_routeId]);
      expect(bloc.state.status, RouteExecutionLoadStatus.observing);
      await bloc.close();
    },
  );

  test(
    'typed observation failure is preserved after reconciliation fails',
    () async {
      final repository = _FakeRouteExecutionRepository();
      final bloc = RouteExecutionBloc(repository: repository, now: () => now);
      bloc.add(const RouteExecutionWalletChanged('wallet'));
      await _waitFor(() => bloc.state.walletId == 'wallet');
      bloc.add(const RouteExecutionReattachRequested(_routeId));
      await _waitFor(() => repository.hasListener);
      repository.reattachFailure = const RouteExecutionException(
        RouteExecutionFailure.serviceUnavailable,
      );

      repository.progress.addError(
        const RouteExecutionException(RouteExecutionFailure.storageUnavailable),
      );
      await _waitFor(
        () => bloc.state.status == RouteExecutionLoadStatus.unknown,
      );

      expect(repository.reattachCalls, [_routeId, _routeId]);
      expect(bloc.state.failure, RouteExecutionFailure.storageUnavailable);
      await bloc.close();
    },
  );

  test(
    'unknown progress fails closed despite advertised cancel control',
    () async {
      final repository = _FakeRouteExecutionRepository();
      final bloc = RouteExecutionBloc(repository: repository, now: () => now);
      bloc.add(const RouteExecutionWalletChanged('wallet'));
      await _waitFor(() => bloc.state.walletId == 'wallet');
      bloc.add(const RouteExecutionReattachRequested(_routeId));
      await _waitFor(() => repository.reattachCalls.length == 1);
      repository.progress.add(
        _progress(
          now,
          outcome: RouteExecutionOutcome.unknown,
          phase: RouteExecutionPhase.unknown,
          canCancel: true,
        ),
      );
      await _waitFor(
        () => bloc.state.status == RouteExecutionLoadStatus.unknown,
      );
      bloc.add(const RouteExecutionCancelRequested());
      await _waitFor(
        () => bloc.state.failure == RouteExecutionFailure.controlNotAuthorized,
      );

      expect(repository.cancelCalls, isEmpty);
      await bloc.close();
    },
  );

  test('resume reattaches by durable route identity', () async {
    final repository = _FakeRouteExecutionRepository();
    final bloc = RouteExecutionBloc(repository: repository, now: () => now);
    bloc.add(const RouteExecutionWalletChanged('wallet'));
    await _waitFor(() => bloc.state.walletId == 'wallet');
    bloc.add(const RouteExecutionReattachRequested(_routeId));
    await _waitFor(() => repository.reattachCalls.length == 1);
    bloc.add(const RouteExecutionAppResumed());
    await _waitFor(() => repository.reattachCalls.length == 2);

    expect(repository.reattachCalls, [_routeId, _routeId]);
    await bloc.close();
  });

  test('closing observation never invokes backend cancel', () async {
    final repository = _FakeRouteExecutionRepository();
    final bloc = RouteExecutionBloc(repository: repository, now: () => now);
    bloc.add(const RouteExecutionWalletChanged('wallet'));
    await _waitFor(() => bloc.state.walletId == 'wallet');
    bloc.add(const RouteExecutionReattachRequested(_routeId));
    await _waitFor(() => repository.hasListener);

    await bloc.close();

    expect(repository.observationCancelCount, 1);
    expect(repository.cancelCalls, isEmpty);
    expect(repository.stopCalls, isEmpty);
  });
}

const _routeId = '41f12b3c-79ac-42e7-bde9-5d43bdd1c1cb';

RouteExecutionReview _review(DateTime now) => RouteExecutionReview(
  walletId: 'wallet',
  routeExecutionId: _routeId,
  reviewId: 'review',
  consentDigest: 'consent',
  candidateDigest: 'candidate',
  source: _eth,
  destination: _usdc,
  sourceAmount: '1000000000000000',
  expectedReceive: '1000000',
  minimumReceive: '995000',
  fees: const [],
  nonNetworkFeeLimits: const [],
  networkFeeCaps: const [],
  resolvedSourceAddress: '0x1111111111111111111111111111111111111111',
  recipient: '0x2222222222222222222222222222222222222222',
  estimatedDuration: const Duration(minutes: 2),
  steps: [
    RouteReviewStep(
      sequence: 0,
      stageId: 'stage',
      kind: RouteReviewStepKind.external,
      source: _eth,
      destination: _usdc,
      sourceAmount: '1000000000000000',
      expectedReceive: '1000000',
      minimumReceive: '995000',
    ),
  ],
  warnings: const [],
  approvals: const [],
  expiresAt: now.add(const Duration(minutes: 1)),
);

RouteExecutionProgress _progress(
  DateTime now, {
  RouteExecutionOutcome outcome = RouteExecutionOutcome.active,
  RouteExecutionPhase phase = RouteExecutionPhase.broadcasting,
  bool canCancel = false,
}) => RouteExecutionProgress(
  routeExecutionId: _routeId,
  outcome: outcome,
  phase: phase,
  stateRevision: 1,
  stageIndex: 0,
  stageCount: 1,
  controls: RouteControlCapabilities(
    canCancel: canCancel,
    canStopAfterCurrent: false,
    reconciliationOnly: false,
  ),
  pendingAction: null,
  holding: null,
  transactionHashes: const [],
  updatedAt: now,
  rawOutcomeDiscriminator: outcome == RouteExecutionOutcome.unknown
      ? 'future'
      : null,
  rawPhaseDiscriminator: phase == RouteExecutionPhase.unknown ? 'future' : null,
);

const _eth = UnifiedSwapAssetIdentity(
  ticker: 'ETH',
  chainFamily: UnifiedSwapChainFamily.evm,
  chainId: '1',
  kind: UnifiedSwapAssetKind.native,
  decimals: 18,
);

const _usdc = UnifiedSwapAssetIdentity(
  ticker: 'USDC',
  chainFamily: UnifiedSwapChainFamily.evm,
  chainId: '137',
  kind: UnifiedSwapAssetKind.token,
  decimals: 6,
  contractAddress: '0x1111111111111111111111111111111111111111',
);

class _FakeRouteExecutionRepository implements RouteExecutionRepository {
  _FakeRouteExecutionRepository() {
    progress = StreamController<RouteExecutionProgress>.broadcast(
      onCancel: () => observationCancelCount++,
    );
  }

  late final StreamController<RouteExecutionProgress> progress;
  final initCalls = <String>[];
  final reattachCalls = <String>[];
  final cancelCalls = <String>[];
  final stopCalls = <String>[];
  var observationCancelCount = 0;
  Completer<RouteExecutionSession>? initCompleter;
  RouteExecutionException? initFailure;
  RouteExecutionException? reattachFailure;

  bool get hasListener => progress.hasListener;

  @override
  Future<void> cancelExecution({
    required String walletId,
    required String routeExecutionId,
  }) async {
    cancelCalls.add(routeExecutionId);
  }

  @override
  Future<RouteExecutionSession> initReviewedExecution({
    required String walletId,
    required String routeExecutionId,
    required String reviewId,
    required String consentDigest,
  }) async {
    initCalls.add(routeExecutionId);
    final failure = initFailure;
    if (failure != null) throw failure;
    final completer = initCompleter;
    if (completer != null) return completer.future;
    return const RouteExecutionSession(routeExecutionId: _routeId, taskId: 1);
  }

  @override
  Stream<RouteExecutionProgress> observe(RouteExecutionSession session) =>
      progress.stream;

  @override
  Future<RouteExecutionSession> reattachExecution({
    required String walletId,
    required String routeExecutionId,
  }) async {
    reattachCalls.add(routeExecutionId);
    final failure = reattachFailure;
    if (failure != null) throw failure;
    return const RouteExecutionSession(routeExecutionId: _routeId, taskId: 2);
  }

  @override
  Future<RouteActionAcknowledgement> submitDecision({
    required String walletId,
    required RouteExecutionSession session,
    required RouteExecutionDecision decision,
  }) async => const RouteActionAcknowledgement(wasDelivered: true);

  @override
  Future<void> stopAfterCurrent({
    required String walletId,
    required String routeExecutionId,
  }) async {
    stopCalls.add(routeExecutionId);
  }
}

Future<void> _waitFor(bool Function() predicate) async {
  for (var index = 0; index < 100; index++) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  throw TimeoutException('Condition was not reached');
}
