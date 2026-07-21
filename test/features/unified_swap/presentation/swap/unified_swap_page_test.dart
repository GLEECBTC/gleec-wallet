import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/features/unified_swap/application/route_execution_bloc.dart';
import 'package:web_dex/features/unified_swap/application/unified_swap_bloc.dart';
import 'package:web_dex/features/unified_swap/domain/route_activity_models.dart';
import 'package:web_dex/features/unified_swap/domain/route_execution_models.dart';
import 'package:web_dex/features/unified_swap/domain/route_execution_repository.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_capability_policy.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_product_policy.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_quote_models.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_quote_repository.dart';
import 'package:web_dex/features/unified_swap/infrastructure/unified_swap_config.dart';
import 'package:web_dex/features/unified_swap/presentation/swap/unified_swap_page.dart';

const _walletId = 'wallet-a';
const _routeId = '018f7f73-9ff0-7a11-bd30-1234567890ab';
const _sourceAddress = '0x1111111111111111111111111111111111111111';
const _recipient = '0x2222222222222222222222222222222222222222';
const _transactionHash =
    '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
final _now = DateTime.utc(2026, 7, 19, 10);

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
  contractAddress: '0x1234567890abcdef1234567890abcdef12345678',
);

void main() {
  group('UnifiedSwapPage', () {
    testWidgets(
      'shows exact entry identities and ranked, unranked, and inert routes',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(900, 1800);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final quoteRepository = _FakeQuoteRepository();
        final quoteBloc = UnifiedSwapBloc(
          quoteRepository: quoteRepository,
          now: () => _now,
          initialState: UnifiedSwapState(
            walletId: _walletId,
            intent: _intent(),
            status: UnifiedSwapQuoteStatus.ready,
            evaluation: _evaluation(),
          ),
        );
        final executionRepository = _FakeExecutionRepository();
        final executionBloc = RouteExecutionBloc(
          repository: executionRepository,
          now: () => _now,
          initialState: const RouteExecutionState(walletId: _walletId),
        );
        _closeAfterUnmount(tester, quoteBloc, executionBloc);

        await tester.pumpWidget(
          _app(quoteBloc: quoteBloc, executionBloc: executionBloc),
        );

        expect(find.byKey(const Key('swap-source-identity')), findsOneWidget);
        expect(
          find.byKey(const Key('swap-destination-identity')),
          findsOneWidget,
        );
        expect(find.textContaining('EVM chain 1'), findsWidgets);
        expect(find.textContaining('EVM chain 137'), findsWidgets);
        expect(find.text(_usdc.contractAddress!), findsOneWidget);
        final recipient = tester.widget<TextField>(
          find.byKey(const Key('swap-recipient-input')),
        );
        expect(recipient.controller?.text, _recipient);
        expect(find.byKey(const Key('swap-candidate-ranked')), findsOneWidget);
        expect(
          find.byKey(const Key('swap-candidate-unranked')),
          findsOneWidget,
        );
        expect(find.text('Not ranked'), findsOneWidget);

        await tester.scrollUntilVisible(
          find.byKey(const Key('swap-candidate-unknown')),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        final unknownInk = tester.widget<InkWell>(
          find
              .descendant(
                of: find.byKey(const Key('swap-candidate-unknown')),
                matching: find.byType(InkWell),
              )
              .first,
        );
        expect(unknownInk.onTap, isNull);
        expect(
          find.byKey(const Key('swap-review-unavailable')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'submits exact decimal input and reports chain-aware repository rejection',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(800, 1500);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final quoteRepository = _FakeQuoteRepository(
          failure: UnifiedSwapQuoteFailure.invalidIntent,
        );
        final quoteBloc = UnifiedSwapBloc(
          quoteRepository: quoteRepository,
          now: () => _now,
          initialState: UnifiedSwapState(
            walletId: _walletId,
            intent: _intent(),
          ),
        );
        final executionBloc = RouteExecutionBloc(
          repository: _FakeExecutionRepository(),
          initialState: const RouteExecutionState(walletId: _walletId),
        );
        _closeAfterUnmount(tester, quoteBloc, executionBloc);
        await tester.pumpWidget(
          _app(quoteBloc: quoteBloc, executionBloc: executionBloc),
        );

        await tester.enterText(
          find.byKey(const Key('swap-amount-input')),
          '0.000001',
        );
        await tester.enterText(
          find.byKey(const Key('swap-recipient-input')),
          _recipient,
        );
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();

        expect(quoteRepository.intents, hasLength(1));
        expect(quoteRepository.intents.single.sourceAmount, '1000000000000');
        expect(quoteRepository.intents.single.recipient, _recipient);
        expect(
          find.textContaining(
            'rejected this exact amount, source, or destination recipient',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('not a valid address'), findsNothing);
      },
    );

    testWidgets('moves from a selected route into its exact injected Review', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 1600);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final quoteBloc = UnifiedSwapBloc(
        quoteRepository: _FakeQuoteRepository(),
        now: () => _now,
        initialState: UnifiedSwapState(
          walletId: _walletId,
          intent: _intent(),
          status: UnifiedSwapQuoteStatus.ready,
          evaluation: _evaluation(),
          selectedCandidateId: 'ranked',
        ),
      );
      final executionBloc = RouteExecutionBloc(
        repository: _FakeExecutionRepository(),
        now: () => _now,
        initialState: const RouteExecutionState(walletId: _walletId),
      );
      _closeAfterUnmount(tester, quoteBloc, executionBloc);
      final reviewed = <String>[];
      await tester.pumpWidget(
        _app(
          quoteBloc: quoteBloc,
          executionBloc: executionBloc,
          reviewBuilder: ({required intent, required candidate}) async {
            reviewed.add(candidate.candidateId);
            return _review();
          },
        ),
      );

      final reviewButton = find.byKey(const Key('swap-review-route'));
      await tester.ensureVisible(reviewButton);
      await tester.tap(reviewButton);
      await tester.pumpAndSettle();

      expect(reviewed, ['ranked']);
      expect(find.byKey(const Key('unified-swap-review')), findsOneWidget);
      await tester.tap(find.text('Route & identities'));
      await tester.pumpAndSettle();
      expect(find.text(_sourceAddress), findsOneWidget);
      expect(find.text(_recipient), findsOneWidget);
    });

    testWidgets(
      'renders mandatory exact Review and starts only on confirmation',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(900, 2000);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final review = _review();
        final quoteBloc = UnifiedSwapBloc(
          quoteRepository: _FakeQuoteRepository(),
          initialState: UnifiedSwapState(
            walletId: _walletId,
            intent: _intent(),
          ),
        );
        final executionRepository = _FakeExecutionRepository();
        final executionBloc = RouteExecutionBloc(
          repository: executionRepository,
          now: () => _now,
          initialState: RouteExecutionState(
            walletId: _walletId,
            status: RouteExecutionLoadStatus.reviewRequired,
            review: review,
          ),
        );
        _closeAfterUnmount(tester, quoteBloc, executionBloc);
        await tester.pumpWidget(
          _app(quoteBloc: quoteBloc, executionBloc: executionBloc),
        );

        expect(find.byKey(const Key('unified-swap-review')), findsOneWidget);
        expect(find.text('Expected receive'), findsOneWidget);
        expect(find.text('Minimum receive'), findsOneWidget);
        await tester.tap(find.text('Costs & protection'));
        await tester.pumpAndSettle();
        expect(find.text('Fees and maximum network costs'), findsOneWidget);
        expect(find.text('Exact token approval'), findsOneWidget);
        await tester.tap(find.text('Route & identities'));
        await tester.pumpAndSettle();
        expect(find.text(_sourceAddress), findsOneWidget);
        expect(find.text(_recipient), findsOneWidget);
        final fullId = tester.widget<SelectableText>(
          find.byKey(const Key('swap-review-execution-id')),
        );
        expect(fullId.data, _routeId);
        expect(executionRepository.initCalls, isEmpty);

        final confirm = find.byKey(const Key('swap-review-confirm'));
        await tester.ensureVisible(confirm);
        await tester.tap(confirm);
        await tester.pumpAndSettle();

        expect(executionRepository.initCalls, [_routeId]);
        expect(find.byKey(const Key('unified-swap-execution')), findsOneWidget);
      },
    );

    testWidgets('keeps a Review with an unknown fee variant inert', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 1800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final quoteBloc = UnifiedSwapBloc(
        quoteRepository: _FakeQuoteRepository(),
        initialState: UnifiedSwapState(walletId: _walletId, intent: _intent()),
      );
      final executionRepository = _FakeExecutionRepository();
      final executionBloc = RouteExecutionBloc(
        repository: executionRepository,
        now: () => _now,
        initialState: RouteExecutionState(
          walletId: _walletId,
          status: RouteExecutionLoadStatus.reviewRequired,
          review: _review(
            fees: [
              RouteExecutionFee(
                kind: RouteFeeKind.unknown,
                asset: _eth,
                amount: '1',
                included: false,
                rawKindDiscriminator: 'future_fee',
              ),
            ],
          ),
        ),
      );
      _closeAfterUnmount(tester, quoteBloc, executionBloc);
      await tester.pumpWidget(
        _app(quoteBloc: quoteBloc, executionBloc: executionBloc),
      );

      expect(find.byKey(const Key('swap-review-inert')), findsOneWidget);
      final confirm = find.byKey(const Key('swap-review-confirm'));
      await tester.ensureVisible(confirm);
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      expect(executionRepository.initCalls, isEmpty);
    });

    testWidgets(
      'shows only server-authorized controls and announces copy after success',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(800, 1700);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final quoteBloc = UnifiedSwapBloc(
          quoteRepository: _FakeQuoteRepository(),
          initialState: UnifiedSwapState(
            walletId: _walletId,
            intent: _intent(),
          ),
        );
        final executionRepository = _FakeExecutionRepository();
        final executionBloc = RouteExecutionBloc(
          repository: executionRepository,
          initialState: RouteExecutionState(
            walletId: _walletId,
            status: RouteExecutionLoadStatus.observing,
            session: const RouteExecutionSession(
              routeExecutionId: _routeId,
              taskId: 7,
            ),
            progress: _progress(canCancel: true),
          ),
        );
        _closeAfterUnmount(tester, quoteBloc, executionBloc);
        final write = Completer<void>();
        final writes = <String>[];
        final announcements = <String>[];
        await tester.pumpWidget(
          _app(
            quoteBloc: quoteBloc,
            executionBloc: executionBloc,
            clipboardWriter: (value) {
              writes.add(value);
              return write.future;
            },
            announcement: (context, message) async {
              announcements.add(message);
            },
          ),
        );

        expect(find.byKey(const Key('swap-control-cancel')), findsOneWidget);
        expect(find.byKey(const Key('swap-control-stop')), findsNothing);
        await tester.tap(
          find.byKey(const Key('swap-progress-execution-id-copy')),
        );
        await tester.pump();
        expect(writes, [_routeId]);
        expect(announcements, isEmpty);

        write.complete();
        await tester.pumpAndSettle();
        expect(announcements, ['Execution ID copied.']);

        await tester.ensureVisible(
          find.byKey(const Key('swap-control-cancel')),
        );
        await tester.tap(find.byKey(const Key('swap-control-cancel')));
        await tester.pumpAndSettle();
        expect(executionRepository.cancelCalls, isEmpty);
        await tester.tap(find.byKey(const Key('swap-confirm-cancel')));
        await tester.pumpAndSettle();
        expect(executionRepository.cancelCalls, [_routeId]);
        expect(executionRepository.stopCalls, isEmpty);
      },
    );

    testWidgets(
      'keeps unknown execution inert and disposal never cancels backend work',
      (tester) async {
        final quoteBloc = UnifiedSwapBloc(
          quoteRepository: _FakeQuoteRepository(),
          initialState: UnifiedSwapState(
            walletId: _walletId,
            intent: _intent(),
          ),
        );
        final executionRepository = _FakeExecutionRepository();
        final executionBloc = RouteExecutionBloc(
          repository: executionRepository,
          initialState: RouteExecutionState(
            walletId: _walletId,
            status: RouteExecutionLoadStatus.unknown,
            session: const RouteExecutionSession(
              routeExecutionId: _routeId,
              taskId: 7,
            ),
            progress: _unknownProgress(),
          ),
        );
        _closeAfterUnmount(tester, quoteBloc, executionBloc);
        await tester.pumpWidget(
          _app(quoteBloc: quoteBloc, executionBloc: executionBloc),
        );

        expect(find.byKey(const Key('swap-execution-unknown')), findsOneWidget);
        expect(find.byKey(const Key('swap-control-cancel')), findsNothing);
        expect(find.byKey(const Key('swap-control-stop')), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        expect(executionRepository.cancelCalls, isEmpty);
        expect(executionRepository.stopCalls, isEmpty);
      },
    );

    testWidgets('resume never interrupts a fresh init that is still starting', (
      tester,
    ) async {
      final quoteBloc = UnifiedSwapBloc(
        quoteRepository: _FakeQuoteRepository(),
        initialState: UnifiedSwapState(walletId: _walletId, intent: _intent()),
      );
      final executionRepository = _FakeExecutionRepository();
      final executionBloc = RouteExecutionBloc(
        repository: executionRepository,
        initialState: RouteExecutionState(
          walletId: _walletId,
          status: RouteExecutionLoadStatus.starting,
          review: _review(),
        ),
      );
      _closeAfterUnmount(tester, quoteBloc, executionBloc);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UnifiedSwapPage(
              config: const UnifiedSwapConfig(
                quoteEnabled: true,
                initEnabled: true,
              ),
              quoteBloc: quoteBloc,
              executionBloc: executionBloc,
              now: () => _now,
            ),
          ),
        ),
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 50));

      expect(executionRepository.reattachCalls, isEmpty);
    });

    testWidgets('has no overflow across the required responsive text matrix', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final quoteBloc = UnifiedSwapBloc(
        quoteRepository: _FakeQuoteRepository(),
        initialState: UnifiedSwapState(
          walletId: _walletId,
          intent: _intent(),
          status: UnifiedSwapQuoteStatus.ready,
          evaluation: _evaluation(),
        ),
      );
      final executionBloc = RouteExecutionBloc(
        repository: _FakeExecutionRepository(),
        initialState: const RouteExecutionState(walletId: _walletId),
      );
      _closeAfterUnmount(tester, quoteBloc, executionBloc);
      const fixtures = [
        (size: Size(375, 1100), textScale: 4.0, dark: false),
        (size: Size(390, 1100), textScale: 2.0, dark: true),
        (size: Size(768, 1200), textScale: 4.0, dark: true),
        (size: Size(1024, 900), textScale: 2.0, dark: false),
        (size: Size(1440, 900), textScale: 1.0, dark: true),
      ];
      for (final fixture in fixtures) {
        tester.view.physicalSize = fixture.size;
        await tester.pumpWidget(
          _app(
            quoteBloc: quoteBloc,
            executionBloc: executionBloc,
            textScale: fixture.textScale,
            dark: fixture.dark,
          ),
        );
        await tester.pump();
        expect(
          tester.takeException(),
          isNull,
          reason: '${fixture.size} at ${fixture.textScale}x text',
        );
      }
    });
  });
}

Widget _app({
  required UnifiedSwapBloc quoteBloc,
  required RouteExecutionBloc executionBloc,
  UnifiedSwapReviewBuilder? reviewBuilder,
  Future<void> Function(String)? clipboardWriter,
  Future<void> Function(BuildContext, String)? announcement,
  double textScale = 1,
  bool dark = false,
}) => MaterialApp(
  theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: Scaffold(
    body: UnifiedSwapPage(
      config: const UnifiedSwapConfig(quoteEnabled: true, initEnabled: true),
      quoteBloc: quoteBloc,
      executionBloc: executionBloc,
      reviewBuilder: reviewBuilder,
      clipboardWriter: clipboardWriter ?? (_) async {},
      announcement: announcement ?? (context, message) async {},
      manageLifecycle: false,
      now: () => _now,
    ),
  ),
);

UnifiedSwapIntent _intent({int revision = 1}) => UnifiedSwapIntent(
  revision: revision,
  source: _eth,
  destination: _usdc,
  sourceAmount: '1000000000000000000',
  sourceSelection: const UnifiedSwapActiveSourceSelection(),
  recipient: _recipient,
  sourceTokenTrust: UnifiedSwapTokenTrust.trusted,
  destinationTokenTrust: UnifiedSwapTokenTrust.trusted,
);

UnifiedSwapQuoteEvaluation _evaluation() => UnifiedSwapQuoteEvaluation(
  evaluationId: 'evaluation-1',
  intentRevision: 1,
  candidates: [
    _candidate(id: 'ranked', rankable: true, rank: 1),
    _candidate(id: 'unranked'),
    UnifiedSwapQuoteCandidate(
      candidateId: 'unknown',
      candidateDigest: 'unknown-digest',
      topology: UnifiedSwapTopology.unknown,
      expectedReceive: '2500000',
      minimumReceive: '2450000',
      fees: const [],
      expiresAt: _now.add(const Duration(minutes: 2)),
      rankable: false,
      isExecutable: false,
      rawUnknownDiscriminator: 'future_route',
    ),
  ],
);

UnifiedSwapQuoteCandidate _candidate({
  required String id,
  bool rankable = false,
  int? rank,
}) => UnifiedSwapQuoteCandidate(
  candidateId: id,
  candidateDigest: '$id-digest',
  topology: UnifiedSwapTopology.external,
  expectedReceive: '2500000',
  minimumReceive: '2450000',
  fees: [
    RouteExecutionFee(
      kind: RouteFeeKind.network,
      asset: _eth,
      amount: '1000000000000000',
      included: false,
    ),
  ],
  expiresAt: _now.add(const Duration(minutes: 2)),
  rankable: rankable,
  rank: rank,
  valuation: rankable
      ? UnifiedSwapValuationProof(
          currency: 'USD',
          observedAt: _now,
          validUntil: _now.add(const Duration(minutes: 2)),
          netMinimumReceive: '2450000',
        )
      : null,
  isExecutable: true,
);

RouteExecutionReview _review({List<RouteExecutionFee>? fees}) =>
    RouteExecutionReview(
      walletId: _walletId,
      routeExecutionId: _routeId,
      reviewId: 'review-1',
      consentDigest: 'consent-digest',
      candidateDigest: 'ranked-digest',
      source: _eth,
      destination: _usdc,
      sourceAmount: '1000000000000000000',
      expectedReceive: '2500000',
      minimumReceive: '2450000',
      fees:
          fees ??
          [
            RouteExecutionFee(
              kind: RouteFeeKind.network,
              asset: _eth,
              amount: '1000000000000000',
              included: false,
            ),
          ],
      nonNetworkFeeLimits: [
        RouteExecutionFeeLimit(
          stageId: 'stage-1',
          kind: RouteFeeKind.bridge,
          asset: _usdc,
          maximumAmount: '10000',
        ),
      ],
      networkFeeCaps: [
        RouteStageNetworkFeeCap(
          stageId: 'stage-1',
          asset: _eth,
          maximumAmount: '2000000000000000',
        ),
      ],
      resolvedSourceAddress: _sourceAddress,
      recipient: _recipient,
      estimatedDuration: const Duration(minutes: 8),
      steps: [
        RouteReviewStep(
          sequence: 0,
          stageId: 'stage-1',
          kind: RouteReviewStepKind.external,
          source: _eth,
          destination: _usdc,
          sourceAmount: '1000000000000000000',
          expectedReceive: '2500000',
          minimumReceive: '2450000',
        ),
      ],
      warnings: const [
        RouteReviewWarning(kind: RouteReviewWarningKind.externalRecipient),
      ],
      approvals: [
        RouteApprovalScope(
          stageId: 'stage-1',
          token: _usdc,
          spender: '0x3333333333333333333333333333333333333333',
          exactAmount: '1000000',
          resetRequired: true,
        ),
      ],
      expiresAt: _now.add(const Duration(minutes: 2)),
    );

RouteExecutionProgress _progress({required bool canCancel}) =>
    RouteExecutionProgress(
      routeExecutionId: _routeId,
      outcome: RouteExecutionOutcome.active,
      phase: RouteExecutionPhase.bridgePending,
      stateRevision: 4,
      stageIndex: 0,
      stageCount: 2,
      controls: RouteControlCapabilities(
        canCancel: canCancel,
        canStopAfterCurrent: false,
        reconciliationOnly: false,
      ),
      pendingAction: null,
      holding: RouteHolding(
        asset: _usdc,
        amount: '1000000',
        address: _recipient,
      ),
      transactionHashes: const [_transactionHash],
      updatedAt: _now,
    );

RouteExecutionProgress _unknownProgress() => RouteExecutionProgress(
  routeExecutionId: _routeId,
  outcome: RouteExecutionOutcome.unknown,
  phase: RouteExecutionPhase.unknown,
  stateRevision: 5,
  stageIndex: 0,
  stageCount: 1,
  controls: RouteControlCapabilities(
    canCancel: true,
    canStopAfterCurrent: true,
    reconciliationOnly: false,
  ),
  pendingAction: null,
  holding: null,
  transactionHashes: const [],
  updatedAt: _now,
  rawOutcomeDiscriminator: 'future_outcome',
  rawPhaseDiscriminator: 'future_phase',
);

class _FakeQuoteRepository implements UnifiedSwapQuoteRepository {
  _FakeQuoteRepository({this.failure});

  final UnifiedSwapQuoteFailure? failure;
  final List<UnifiedSwapIntent> intents = [];

  @override
  Future<UnifiedSwapQuoteEvaluation> evaluate(UnifiedSwapIntent intent) async {
    intents.add(intent);
    if (failure case final failure?) throw UnifiedSwapQuoteException(failure);
    return UnifiedSwapQuoteEvaluation(
      evaluationId: 'evaluation-${intent.revision}',
      intentRevision: intent.revision,
      candidates: [_candidate(id: 'fresh')],
    );
  }
}

class _FakeExecutionRepository implements RouteExecutionRepository {
  final List<String> initCalls = [];
  final List<String> reattachCalls = [];
  final List<String> cancelCalls = [];
  final List<String> stopCalls = [];
  final List<RouteExecutionDecision> decisions = [];

  @override
  Future<RouteExecutionSession> initReviewedExecution({
    required String walletId,
    required String routeExecutionId,
    required String reviewId,
    required String consentDigest,
  }) async {
    initCalls.add(routeExecutionId);
    return RouteExecutionSession(routeExecutionId: routeExecutionId, taskId: 7);
  }

  @override
  Future<RouteExecutionSession> reattachExecution({
    required String walletId,
    required String routeExecutionId,
  }) async {
    reattachCalls.add(routeExecutionId);
    return RouteExecutionSession(routeExecutionId: routeExecutionId, taskId: 8);
  }

  @override
  Stream<RouteExecutionProgress> observe(RouteExecutionSession session) =>
      const Stream.empty();

  @override
  Future<void> cancelExecution({
    required String walletId,
    required String routeExecutionId,
  }) async {
    cancelCalls.add(routeExecutionId);
  }

  @override
  Future<void> stopAfterCurrent({
    required String walletId,
    required String routeExecutionId,
  }) async {
    stopCalls.add(routeExecutionId);
  }

  @override
  Future<RouteActionAcknowledgement> submitDecision({
    required String walletId,
    required RouteExecutionSession session,
    required RouteExecutionDecision decision,
  }) async {
    decisions.add(decision);
    return const RouteActionAcknowledgement(wasDelivered: true);
  }
}

void _closeAfterUnmount(
  WidgetTester tester,
  UnifiedSwapBloc quoteBloc,
  RouteExecutionBloc executionBloc,
) {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    unawaited(quoteBloc.close());
    unawaited(executionBloc.close());
  });
}
