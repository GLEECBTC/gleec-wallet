// The analyzer does not treat test_units as tests, so Bloc.emit's
// @visibleForTesting reads as a violation here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/swap_activity/swap_activity_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/unified_swap_repository.dart';
import 'package:web_dex/views/swap/activity/swap_activity_view.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';
import 'package:web_dex/views/swap/entry/swap_entry_view.dart';
import 'package:web_dex/views/swap/execution/swap_execution_view.dart';
import 'package:web_dex/views/swap/motion/swap_motion.dart';
import 'package:web_dex/views/swap/review/swap_review_view.dart';
import 'package:web_dex/views/swap/swap_page.dart';
import 'package:web_dex/views/swap/swap_shell.dart';
import 'package:web_dex/views/swap/swap_shell_controller.dart';

import 'swap_motion_fakes.dart';
import 'swap_surface_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// How far a screen arriving in the last frame was shifted sideways, when
/// one was; each shifted layer's shift.
List<double> _shifts(WidgetTester tester) => [
  for (final layer in tester.layers.whereType<TransformLayer>())
    if (layer.transform!.getTranslation().x.abs() > 0.5)
      layer.transform!.getTranslation().x,
];

/// Covers moving into and out of a swap: each screen arrives from the way
/// the user is going, the old one is gone at once, and nothing slides on
/// first show or with less motion.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('into and out of a swap', () {
    late FakeExecutor routed;
    late SwapExecutionRegistry registry;
    late SurfaceServices services;
    late RecordingSwapBloc swap;
    late SwapShellController shell;

    setUpAll(loadSurfaceCopy);

    setUp(() {
      routed = FakeExecutor(SwapLiquiditySource.routed);
      registry = SwapExecutionRegistry(
        executors: [routed],
        inFlight: () async => const [],
      );
      services = SurfaceServices(registry);
      swap = RecordingSwapBloc(registry);
      shell = SwapShellController();
      routed.resumable['routed-1'] = FakeHandle(snapshotOf(id: 'routed-1'));
    });

    tearDown(() async {
      await swap.close();
      await registry.dispose();
      await services.dispose();
      shell.dispose();
      resetSurfaceCopy();
    });

    final quote = quoteOf();
    final form = UnifiedSwapState(
      loadingAssets: false,
      pay: eth,
      receive: usdc,
      inputText: '1',
      balance: d('2'),
      evaluation: SwapEvaluationStatus.ready,
      quotes: UnifiedSwapQuotes(
        ranked: [quote],
        unrankable: const [],
        failures: const [],
      ),
      selectedId: quote.id,
    );
    final review = form.copyWith(
      view: UnifiedSwapView.review,
      review: SwapReview(quote: quote, status: SwapReviewStatus.ready),
    );
    final progress = form.copyWith(
      view: UnifiedSwapView.progress,
      activeExecutionId: 'routed-1',
    );

    Future<void> show(
      WidgetTester tester,
      UnifiedSwapState state, {
      Size size = const Size(420, 1600),
      bool reduceMotion = false,
      bool settle = true,
    }) async {
      swap.emit(state);
      await pumpSurface(
        tester,
        const SwapPage(),
        services: services,
        swap: swap,
        shell: shell,
        size: size,
        wrap: [
          if (reduceMotion)
            (child) => Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: child,
              ),
            ),
        ],
        settle: settle,
      );
    }

    /// Moves to [state] and returns the sideways shifts a third of the way
    /// into the change.
    Future<List<double>> moveTo(
      WidgetTester tester,
      UnifiedSwapState state,
    ) async {
      swap.emit(state);
      // The page hears the bloc in one frame and builds in the next.
      await tester.pump();
      await tester.pump();
      await tester.pump(SwapMotion.screen ~/ 3);
      return _shifts(tester);
    }

    testWidgets('a started swap arrives from the end edge, and the form is '
        'gone at once', (tester) async {
      await show(tester, form);
      swap.emit(progress);
      await tester.pump();
      await tester.pump();
      expect(find.byType(SwapEntryView), findsNothing);
      expect(find.byType(SwapExecutionView), findsOneWidget);

      await tester.pump(SwapMotion.screen ~/ 3);
      expect(_shifts(tester), [greaterThan(0)]);
      await tester.pumpAndSettle();
      expect(_shifts(tester), isEmpty);
    });

    testWidgets('the form comes back from the start edge', (tester) async {
      await show(tester, progress);
      expect(await moveTo(tester, form), [lessThan(0)]);
      await tester.pumpAndSettle();
    });

    testWidgets('a review on a phone arrives from the end edge', (
      tester,
    ) async {
      await show(tester, form);
      expect(await moveTo(tester, review), [greaterThan(0)]);
      await tester.pumpAndSettle();
      expect(find.byType(SwapReviewView), findsOneWidget);
    });

    testWidgets('nothing slides when the page first shows', (tester) async {
      await show(tester, progress, settle: false);
      await tester.pump(SwapMotion.screen ~/ 3);
      expect(_shifts(tester), isEmpty);
      await tester.pumpAndSettle();
    });

    testWidgets('a wide review slides its panel in beside a form that stays '
        'put', (tester) async {
      await show(tester, form, size: const Size(1440, 900));
      final shifts = await moveTo(tester, review);
      expect(shifts, [greaterThan(0)]);
      expect(find.byType(SwapEntryView), findsOneWidget);
      expect(find.byType(SwapReviewView), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('nothing slides with less motion', (tester) async {
      await show(tester, form, reduceMotion: true);
      expect(await moveTo(tester, progress), isEmpty);
      await tester.pumpAndSettle();
    });

    testWidgets('a screen has arrived within 36 frames', (tester) async {
      await show(tester, form);
      swap.emit(progress);
      for (var frame = 0; frame < 36; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(_shifts(tester), isEmpty);
      await tester.pumpAndSettle();
    });
  });

  group('Activity', () {
    late GatedExecutor routed;
    late SwapExecutionRegistry registry;
    late ScriptedHistory history;
    late SurfaceServices services;
    late RecordingSwapBloc swap;
    late SwapShellController shell;

    setUpAll(loadSurfaceCopy);

    setUp(() {
      routed = GatedExecutor(SwapLiquiditySource.routed);
      registry = SwapExecutionRegistry(
        executors: [routed],
        inFlight: () async => const [],
      );
      history = ScriptedHistory();
      services = SurfaceServices(registry, history: history);
      swap = RecordingSwapBloc(registry);
      shell = SwapShellController(initial: SwapDestination.activity);
    });

    tearDown(() async {
      await swap.close();
      await registry.dispose();
      await services.dispose();
      shell.dispose();
      resetSurfaceCopy();
    });

    testWidgets('a swap opens from the end edge, and Back returns from the '
        'start edge to where the list was', (tester) async {
      history.entries = [
        for (var i = 0; i < 12; i++)
          snapshotOf(id: 'swap-$i', createdAt: DateTime(2020, 3, 1, i)),
      ];
      for (final entry in history.entries) {
        routed.resumable[entry.id] = FakeHandle(entry);
      }
      await pumpSurface(
        tester,
        const SwapActivityView(),
        services: services,
        swap: swap,
        shell: shell,
        size: const Size(420, 700),
        wrap: [
          (child) => BlocProvider(
            create: (_) =>
                SwapActivityBloc(history: history, registry: registry)
                  ..add(const SwapActivityStarted()),
            child: child,
          ),
        ],
      );
      final list = find.byType(Scrollable).first;
      await tester.drag(list, const Offset(0, -300));
      await tester.pumpAndSettle();
      final scrolled = tester.state<ScrollableState>(list).position.pixels;
      expect(scrolled, greaterThan(0));

      await tester.tap(find.text('Confirming on Ethereum').hitTestable().first);
      await tester.pump();
      await tester.pump(SwapMotion.screen ~/ 3);
      expect(_shifts(tester), [greaterThan(0)]);
      await tester.pumpAndSettle();
      expect(shell.detail, isNotNull);

      await tester.tap(find.byTooltip('Back'));
      await tester.pump();
      await tester.pump(SwapMotion.screen ~/ 3);
      expect(_shifts(tester), [lessThan(0)]);
      await tester.pumpAndSettle();
      expect(
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .pixels,
        scrolled,
      );
    });
  });

  group('the Activity count', () {
    late FakeExecutor routed;
    late SwapExecutionRegistry registry;
    late SurfaceServices services;

    setUpAll(loadSurfaceCopy);

    setUp(() {
      routed = FakeExecutor(SwapLiquiditySource.routed);
      registry = SwapExecutionRegistry(
        executors: [routed],
        inFlight: () async => const [],
      );
      services = SurfaceServices(registry);
      useFreshRoutingState();
    });

    tearDown(() async {
      await registry.dispose();
      await services.dispose();
      resetSurfaceCopy();
    });

    testWidgets('pops in as a swap starts', (tester) async {
      await pumpSurface(
        tester,
        SwapShell(
          destinationBuilder: (destination) => Text('body:${destination.name}'),
        ),
        services: services,
        size: const Size(420, 800),
      );
      expect(routingState, isNotNull);

      await registry.start(quoteOf());
      await tester.pump();
      await tester.pump();
      await tester.pump(SwapMotion.pop ~/ 3);
      final scales = [
        for (final layer in tester.layers.whereType<TransformLayer>())
          scaleOf(layer.transform!),
      ];
      expect(scales.reduce(math.min), lessThan(1));

      await tester.pumpAndSettle();
      expect(find.byType(SwapCountDot), findsOneWidget);
    });
  });
}
