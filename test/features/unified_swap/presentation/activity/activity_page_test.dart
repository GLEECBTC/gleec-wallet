import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/features/unified_swap/application/route_activity_bloc.dart';
import 'package:web_dex/features/unified_swap/domain/route_activity_models.dart'
    as models;
import 'package:web_dex/features/unified_swap/domain/route_activity_repository.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_capability_policy.dart';
import 'package:web_dex/features/unified_swap/presentation/activity/activity_page.dart';

void main() {
  group('RouteActivityPage', () {
    testWidgets('fails closed when its activity BLoC is missing', (
      tester,
    ) async {
      await tester.pumpWidget(_app());

      expect(
        find.byKey(const Key('activity-dependency-unavailable')),
        findsOneWidget,
      );
      expect(find.text('Activity is unavailable'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'shows authoritative groups, preserves full IDs, and keeps unknown inert',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(800, 2000);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final active = _summary(_activeId, models.RouteActivityStatus.active);
        final attention = _summary(
          _attentionId,
          models.RouteActivityStatus.attentionRequired,
        );
        final completed = _summary(
          _completedId,
          models.RouteActivityStatus.completed,
        );
        final unknown = _summary(
          _unknownId,
          models.RouteActivityStatus.unknown,
        );
        final repository = _FakeActivityRepository();
        final bloc = RouteActivityBloc(
          repository: repository,
          initialState: RouteActivityState(
            walletId: _walletId,
            status: RouteActivityLoadStatus.ready,
            executions: [active, attention, completed, unknown],
          ),
        );
        _closeBlocAfterUnmount(tester, bloc);
        final selected = <String>[];

        await tester.pumpWidget(
          _app(bloc: bloc, onExecutionSelected: selected.add),
        );

        expect(find.byKey(const Key('activity-group-active')), findsOneWidget);
        expect(
          find.byKey(const Key('activity-group-attentionRequired')),
          findsOneWidget,
        );
        final fullIdText = tester.widget<Text>(
          find.byKey(Key('activity-execution-id-$_activeId')),
        );
        expect(fullIdText.data, _activeId);
        expect(fullIdText.overflow, TextOverflow.ellipsis);

        final activeSemantics = tester.widget<Semantics>(
          find.byKey(Key('activity-card-semantics-$_activeId')),
        );
        expect(activeSemantics.properties.button, isTrue);
        expect(activeSemantics.properties.enabled, isTrue);

        await tester.tap(find.byKey(const Key('activity-group-completed')));
        await tester.pumpAndSettle();
        expect(find.byKey(Key('activity-card-$_completedId')), findsOneWidget);

        await tester.tap(
          find.byKey(const Key('activity-group-attentionRequired')),
        );
        await tester.pumpAndSettle();
        final unknownSemantics = tester.widget<Semantics>(
          find.byKey(Key('activity-card-semantics-$_unknownId')),
        );
        expect(unknownSemantics.properties.button, isFalse);
        expect(unknownSemantics.properties.enabled, isFalse);

        final unknownInkWell = tester.widget<InkWell>(
          find
              .descendant(
                of: find.byKey(Key('activity-card-$_unknownId')),
                matching: find.byType(InkWell),
              )
              .first,
        );
        expect(unknownInkWell.onTap, isNull);
        expect(selected, isEmpty);
        expect(repository.detailRouteIds, isEmpty);
        expect(
          find.byKey(const Key('activity-group-completed')),
          findsOneWidget,
        );
      },
    );

    testWidgets('loads the next opaque page without replacing prior cards', (
      tester,
    ) async {
      final first = _summary(_activeId, models.RouteActivityStatus.active);
      final second = _summary(
        _completedId,
        models.RouteActivityStatus.completed,
      );
      final repository = _FakeActivityRepository(
        pages: [
          models.RouteActivityPage(executions: [second], nextCursor: null),
        ],
      );
      final bloc = RouteActivityBloc(
        repository: repository,
        initialState: RouteActivityState(
          walletId: _walletId,
          status: RouteActivityLoadStatus.ready,
          executions: [first],
          nextCursor: 'opaque-page-two',
        ),
      );
      _closeBlocAfterUnmount(tester, bloc);
      await tester.pumpWidget(_app(bloc: bloc));

      final loadMore = find.byKey(const Key('activity-load-more'));
      await tester.ensureVisible(loadMore);
      await tester.tap(loadMore);
      await tester.pumpAndSettle();

      expect(repository.cursors, ['opaque-page-two']);
      expect(find.byKey(Key('activity-card-$_activeId')), findsOneWidget);
      await tester.tap(find.byKey(const Key('activity-group-completed')));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('activity-card-$_completedId')), findsOneWidget);
      expect(find.byKey(const Key('activity-load-more')), findsNothing);
    });

    testWidgets(
      'announces copy success only after the full-ID write succeeds',
      (tester) async {
        final write = Completer<void>();
        final written = <String>[];
        final announcements = <String>[];
        final bloc = RouteActivityBloc(
          repository: _FakeActivityRepository(),
          initialState: RouteActivityState(
            walletId: _walletId,
            status: RouteActivityLoadStatus.ready,
            executions: [
              _summary(_activeId, models.RouteActivityStatus.active),
            ],
          ),
        );
        _closeBlocAfterUnmount(tester, bloc);
        await tester.pumpWidget(
          _app(
            bloc: bloc,
            clipboardWriter: (value) {
              written.add(value);
              return write.future;
            },
            announcement: (context, message) async {
              announcements.add(message);
            },
          ),
        );

        await tester.tap(find.byKey(Key('activity-copy-$_activeId')));
        await tester.pump();

        expect(written, [_activeId]);
        expect(announcements, isEmpty);
        expect(find.text('Full execution ID copied.'), findsNothing);

        write.complete();
        await tester.pumpAndSettle();

        expect(announcements, ['Full execution ID copied.']);
        expect(find.text('Full execution ID copied.'), findsOneWidget);
      },
    );

    testWidgets('does not report success when clipboard writing fails', (
      tester,
    ) async {
      final announcements = <String>[];
      final bloc = RouteActivityBloc(
        repository: _FakeActivityRepository(),
        initialState: RouteActivityState(
          walletId: _walletId,
          status: RouteActivityLoadStatus.ready,
          executions: [_summary(_activeId, models.RouteActivityStatus.active)],
        ),
      );
      _closeBlocAfterUnmount(tester, bloc);
      await tester.pumpWidget(
        _app(
          bloc: bloc,
          clipboardWriter: (_) => Future<void>.error(StateError('denied')),
          announcement: (context, message) async {
            announcements.add(message);
          },
        ),
      );

      await tester.tap(find.byKey(Key('activity-copy-$_activeId')));
      await tester.pumpAndSettle();

      expect(announcements, isEmpty);
      expect(find.text('Full execution ID copied.'), findsNothing);
      expect(
        find.text('The execution ID could not be copied.'),
        findsOneWidget,
      );
    });

    testWidgets('shows only controls backed by current capabilities', (
      tester,
    ) async {
      final summary = _summary(_activeId, models.RouteActivityStatus.active);
      final detail = _detail(
        summary,
        controls: models.RouteControlCapabilities(
          canCancel: true,
          canStopAfterCurrent: true,
          reconciliationOnly: false,
        ),
      );
      final bloc = RouteActivityBloc(
        repository: _FakeActivityRepository(),
        initialState: RouteActivityState(
          walletId: _walletId,
          status: RouteActivityLoadStatus.ready,
          executions: [summary],
          selectedExecution: detail,
        ),
      );
      _closeBlocAfterUnmount(tester, bloc);
      final cancelled = <String>[];

      await tester.pumpWidget(
        _app(
          bloc: bloc,
          showDetails: true,
          initialRouteExecutionId: _activeId,
          onCancelRequested: cancelled.add,
        ),
      );

      expect(find.byKey(const Key('activity-control-cancel')), findsOneWidget);
      expect(find.byKey(const Key('activity-control-stop')), findsNothing);
      await tester.ensureVisible(
        find.byKey(const Key('activity-control-cancel')),
      );
      await tester.tap(find.byKey(const Key('activity-control-cancel')));
      await tester.pumpAndSettle();
      expect(cancelled, isEmpty);
      await tester.tap(find.byKey(const Key('activity-confirm-cancel')));
      await tester.pumpAndSettle();
      expect(cancelled, [_activeId]);
    });

    testWidgets(
      'confirms durable stop and recovery actions by exact route ID',
      (tester) async {
        final summary = _summary(
          _attentionId,
          models.RouteActivityStatus.attentionRequired,
        );
        final detail = _detail(
          summary,
          controls: models.RouteControlCapabilities(
            canCancel: false,
            canStopAfterCurrent: true,
            reconciliationOnly: false,
          ),
        );
        final bloc = RouteActivityBloc(
          repository: _FakeActivityRepository(),
          initialState: RouteActivityState(
            walletId: _walletId,
            status: RouteActivityLoadStatus.ready,
            executions: [summary],
            selectedExecution: detail,
          ),
        );
        _closeBlocAfterUnmount(tester, bloc);
        final stopped = <String>[];
        final recovered = <String>[];

        await tester.pumpWidget(
          _app(
            bloc: bloc,
            showDetails: true,
            initialRouteExecutionId: _attentionId,
            onStopAfterCurrentRequested: stopped.add,
            onRecoveryRequested: recovered.add,
          ),
        );

        await tester.ensureVisible(
          find.byKey(const Key('activity-control-stop')),
        );
        await tester.tap(find.byKey(const Key('activity-control-stop')));
        await tester.pumpAndSettle();
        expect(stopped, isEmpty);
        await tester.tap(find.byKey(const Key('activity-confirm-stop')));
        await tester.pumpAndSettle();
        expect(stopped, [_attentionId]);

        await tester.ensureVisible(
          find.byKey(const Key('activity-control-recovery')),
        );
        await tester.tap(find.byKey(const Key('activity-control-recovery')));
        await tester.pumpAndSettle();
        expect(recovered, isEmpty);
        await tester.tap(find.byKey(const Key('activity-confirm-recovery')));
        await tester.pumpAndSettle();
        expect(recovered, [_attentionId]);
      },
    );

    testWidgets('renders unknown-status controls as inert', (tester) async {
      final summary = _summary(_unknownId, models.RouteActivityStatus.unknown);
      final bloc = RouteActivityBloc(
        repository: _FakeActivityRepository(),
        initialState: RouteActivityState(
          walletId: _walletId,
          status: RouteActivityLoadStatus.ready,
          executions: [summary],
          selectedExecution: _detail(
            summary,
            controls: models.RouteControlCapabilities(
              canCancel: true,
              canStopAfterCurrent: true,
              reconciliationOnly: false,
            ),
          ),
        ),
      );
      _closeBlocAfterUnmount(tester, bloc);

      await tester.pumpWidget(
        _app(
          bloc: bloc,
          showDetails: true,
          initialRouteExecutionId: _unknownId,
          onCancelRequested: (_) {},
          onStopAfterCurrentRequested: (_) {},
        ),
      );

      expect(find.byKey(const Key('activity-controls-inert')), findsOneWidget);
      expect(find.byKey(const Key('activity-control-cancel')), findsNothing);
      expect(find.byKey(const Key('activity-control-stop')), findsNothing);
    });

    testWidgets('retries a deep-link detail after wallet scope is accepted', (
      tester,
    ) async {
      final summary = _summary(_activeId, models.RouteActivityStatus.active);
      final repository = _FakeActivityRepository(
        pages: [
          models.RouteActivityPage(executions: [summary], nextCursor: null),
        ],
        details: {_activeId: _detail(summary)},
      );
      final bloc = RouteActivityBloc(repository: repository);
      _closeBlocAfterUnmount(tester, bloc);

      await tester.pumpWidget(
        _app(bloc: bloc, showDetails: true, initialRouteExecutionId: _activeId),
      );
      expect(
        find.byKey(const Key('activity-wallet-unavailable')),
        findsOneWidget,
      );

      bloc.add(const RouteActivityWalletChanged(_walletId));
      await tester.pumpAndSettle();

      expect(repository.detailRouteIds, [_activeId]);
      expect(find.byKey(const Key('route-activity-detail')), findsOneWidget);
      expect(
        find.byKey(Key('activity-execution-id-$_activeId')),
        findsOneWidget,
      );
    });

    testWidgets('reconciles activity when the app resumes', (tester) async {
      final summary = _summary(_activeId, models.RouteActivityStatus.active);
      final repository = _FakeActivityRepository(
        pages: [
          models.RouteActivityPage(executions: [summary], nextCursor: null),
        ],
      );
      final bloc = RouteActivityBloc(
        repository: repository,
        initialState: RouteActivityState(
          walletId: _walletId,
          status: RouteActivityLoadStatus.ready,
          executions: [summary],
        ),
      );
      _closeBlocAfterUnmount(tester, bloc);
      await tester.pumpWidget(_app(bloc: bloc, manageLifecycle: true));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(repository.cursors, [null]);
    });

    testWidgets(
      'stacks without overflow across the required responsive text matrix',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final bloc = RouteActivityBloc(
          repository: _FakeActivityRepository(),
          initialState: RouteActivityState(
            walletId: _walletId,
            status: RouteActivityLoadStatus.ready,
            executions: [
              _summary(_activeId, models.RouteActivityStatus.active),
              _summary(
                _attentionId,
                models.RouteActivityStatus.attentionRequired,
              ),
              _summary(_completedId, models.RouteActivityStatus.completed),
            ],
            selectedExecution: _detail(
              _summary(_activeId, models.RouteActivityStatus.active),
            ),
          ),
        );
        _closeBlocAfterUnmount(tester, bloc);

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
            _app(bloc: bloc, textScale: fixture.textScale, dark: fixture.dark),
          );
          await tester.pump();
          expect(
            tester.takeException(),
            isNull,
            reason: 'list ${fixture.size} at ${fixture.textScale}x text',
          );

          await tester.pumpWidget(
            _app(
              bloc: bloc,
              showDetails: true,
              initialRouteExecutionId: _activeId,
              textScale: fixture.textScale,
              dark: fixture.dark,
            ),
          );
          await tester.pump();
          expect(
            tester.takeException(),
            isNull,
            reason: 'detail ${fixture.size} at ${fixture.textScale}x text',
          );
        }
      },
    );
  });
}

Widget _app({
  RouteActivityBloc? bloc,
  bool showDetails = false,
  String? initialRouteExecutionId,
  ValueChanged<String>? onExecutionSelected,
  ValueChanged<String>? onCancelRequested,
  ValueChanged<String>? onStopAfterCurrentRequested,
  ValueChanged<String>? onRecoveryRequested,
  Future<void> Function(String)? clipboardWriter,
  Future<void> Function(BuildContext, String)? announcement,
  bool manageLifecycle = false,
  double textScale = 1,
  bool dark = false,
}) {
  return MaterialApp(
    theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(
      body: RouteActivityPage(
        bloc: bloc,
        showDetails: showDetails,
        initialRouteExecutionId: initialRouteExecutionId,
        onExecutionSelected: onExecutionSelected,
        onCancelRequested: onCancelRequested,
        onStopAfterCurrentRequested: onStopAfterCurrentRequested,
        onRecoveryRequested: onRecoveryRequested,
        clipboardWriter: clipboardWriter ?? (_) async {},
        announcement: announcement ?? (context, message) async {},
        manageLifecycle: manageLifecycle,
      ),
    ),
  );
}

void _closeBlocAfterUnmount(WidgetTester tester, RouteActivityBloc bloc) {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    // flutter_bloc's consumer cancellation completes asynchronously after
    // widget disposal. Initiating close is sufficient here; awaiting it would
    // deadlock this test teardown against that cancellation.
    unawaited(bloc.close());
  });
}

models.RouteActivitySummary _summary(
  String id,
  models.RouteActivityStatus status,
) => models.RouteActivitySummary(
  routeExecutionId: id,
  status: status,
  source: _eth,
  destination: _usdc,
  createdAt: _now.subtract(const Duration(minutes: 5)),
  updatedAt: _now,
  completedAt: status.isTerminal ? _now : null,
  rawStatusDiscriminator: status == models.RouteActivityStatus.unknown
      ? 'future_route_state'
      : null,
);

models.RouteExecutionDetail _detail(
  models.RouteActivitySummary summary, {
  models.RouteControlCapabilities? controls,
}) => models.RouteExecutionDetail(
  summary: summary,
  consent: models.RouteExecutionConsent(
    routeExecutionId: summary.routeExecutionId,
    consentDigest: 'consent-digest',
    candidateDigest: 'candidate-digest',
    source: _eth,
    destination: _usdc,
    sourceAmount: '1000000000000000000',
    expectedReceive: '2500000',
    minimumReceive: '2450000',
    fees: const [],
    nonNetworkFeeLimits: const [],
    networkFeeCaps: const [],
    resolvedSourceAddress: '0x1111111111111111111111111111111111111111',
    recipient: '0x2222222222222222222222222222222222222222',
  ),
  controls:
      controls ??
      models.RouteControlCapabilities(
        canCancel: false,
        canStopAfterCurrent: false,
        reconciliationOnly: true,
      ),
  holding: null,
  stages: const [],
  revisions: const [],
);

class _FakeActivityRepository implements RouteActivityRepository {
  _FakeActivityRepository({this.pages = const [], this.details = const {}});

  final List<models.RouteActivityPage> pages;
  final Map<String, models.RouteExecutionDetail> details;
  final List<String?> cursors = [];
  final List<String> detailRouteIds = [];
  int _pageIndex = 0;

  @override
  Future<models.RouteExecutionDetail> getExecution({
    required String walletId,
    required String routeExecutionId,
  }) async {
    detailRouteIds.add(routeExecutionId);
    final detail = details[routeExecutionId];
    if (detail == null) {
      throw const RouteActivityException(models.RouteActivityFailure.notFound);
    }
    return detail;
  }

  @override
  Future<models.RouteActivityPage> listExecutions({
    required String walletId,
    models.RouteActivityStatus? state,
    String? cursor,
    int limit = 50,
  }) async {
    cursors.add(cursor);
    if (_pageIndex >= pages.length) {
      throw const RouteActivityException(
        models.RouteActivityFailure.serviceUnavailable,
      );
    }
    return pages[_pageIndex++];
  }
}

const _walletId = 'wallet-activity-test';
const _activeId = '019f76a5-be02-77d0-a6e8-96e7d504b9cd';
const _attentionId = '019f76a5-be02-77d0-a6e8-96e7d504b9ce';
const _completedId = '019f76a5-be02-77d0-a6e8-96e7d504b9cf';
const _unknownId = '019f76a5-be02-77d0-a6e8-96e7d504b9d0';
final _now = DateTime.utc(2026, 7, 19, 12, 30);

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
  contractAddress: '0x3333333333333333333333333333333333333333',
);
