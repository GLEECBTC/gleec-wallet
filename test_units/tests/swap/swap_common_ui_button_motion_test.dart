// The analyzer does not treat test_units as tests, so Bloc.emit's
// @visibleForTesting reads as a violation here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/unified_swap_repository.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';
import 'package:web_dex/views/swap/motion/swap_motion.dart';
import 'package:web_dex/views/swap/swap_page.dart';
import 'package:web_dex/views/swap/swap_shell_controller.dart';

import 'swap_common_ui_fakes.dart';
import 'swap_motion_fakes.dart';
import 'swap_surface_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// The smallest scale any effect painted in the last frame, when one is
/// scaling something down.
double? _smallestScale(WidgetTester tester) {
  final scales = tester.layers
      .whereType<TransformLayer>()
      .map((layer) => scaleOf(layer.transform!))
      .where((scale) => scale < 0.999);
  return scales.isEmpty ? null : scales.reduce(math.min);
}

/// Covers how the swap button answers a hand on it: it presses down, its
/// spinner pops in without moving the label abruptly, and Start keeps one
/// button, with one firm tap, from ready to starting.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a swap button', () {
    useSwapUi();

    Future<void> show(
      WidgetTester tester,
      Widget button, {
      bool settle = true,
    }) => pumpSwapUi(
      tester,
      Center(child: SizedBox(width: 300, child: button)),
      settle: settle,
    );

    testWidgets('presses down while held, and still presses', (tester) async {
      var pressed = 0;
      await show(
        tester,
        SwapButton(label: 'Start swap', onPressed: () => pressed++),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(SwapButton)),
      );
      await tester.pump();
      await tester.pump(SwapMotion.press);
      expect(_smallestScale(tester), closeTo(0.97, 1e-6));

      await gesture.up();
      await tester.pumpAndSettle();
      expect(_smallestScale(tester), isNull);
      expect(pressed, 1);
    });

    testWidgets('a button that cannot be pressed does not press down', (
      tester,
    ) async {
      await show(
        tester,
        const SwapButton(label: 'Enter amount', onPressed: null),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(SwapButton)),
      );
      await tester.pump();
      await tester.pump(SwapMotion.press);
      expect(_smallestScale(tester), isNull);
      await gesture.up();
    });

    testWidgets('its spinner is there, 16 px square, from the first frame, '
        'and pops in', (tester) async {
      await show(tester, const SwapButton(label: 'Checking…', onPressed: null));
      await show(
        tester,
        const SwapButton(label: 'Checking…', onPressed: null, busy: true),
        settle: false,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        tester.getSize(find.byType(CircularProgressIndicator)),
        const Size(16, 16),
      );

      await tester.pump(SwapMotion.pop ~/ 4);
      expect(_smallestScale(tester), lessThan(1));
    });

    testWidgets('its label glides aside as the spinner arrives', (
      tester,
    ) async {
      await show(tester, const SwapButton(label: 'Checking…', onPressed: null));
      final before = tester.getTopLeft(find.text('Checking…')).dx;
      await show(
        tester,
        const SwapButton(label: 'Checking…', onPressed: null, busy: true),
        settle: false,
      );
      await tester.pump(SwapMotion.grow ~/ 2);
      final midway = tester.getTopLeft(find.text('Checking…')).dx;
      await tester.pump(SwapMotion.grow);
      final after = tester.getTopLeft(find.text('Checking…')).dx;

      expect(after, isNot(before));
      expect(
        midway,
        inExclusiveRange(math.min(before, after), math.max(before, after)),
      );
    });
  });

  group('Start', () {
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
    });

    tearDown(() async {
      await swap.close();
      await registry.dispose();
      await services.dispose();
      shell.dispose();
      resetSurfaceCopy();
    });

    final quote = quoteOf();
    UnifiedSwapState reviewing(SwapReviewStatus status) => UnifiedSwapState(
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
      view: UnifiedSwapView.review,
      review: SwapReview(quote: quote, status: status),
    );

    Future<void> show(WidgetTester tester, SwapReviewStatus status) async {
      swap.emit(reviewing(status));
      await pumpSurface(
        tester,
        const SwapPage(),
        services: services,
        swap: swap,
        shell: shell,
      );
    }

    testWidgets('taps firmly on a phone as it commits, not on a retry', (
      tester,
    ) async {
      final played = recordHaptics(tester);
      await show(tester, SwapReviewStatus.ready);

      await tester.ensureVisible(find.byKey(const Key('swap-start')));
      await tester.tap(find.byKey(const Key('swap-start')));
      await tester.pump();
      expect(played, ['HapticFeedbackType.mediumImpact']);
      expect(swap.events.whereType<UnifiedSwapStartRequested>(), hasLength(1));

      swap.emit(reviewing(SwapReviewStatus.rejected));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Try again'));
      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(played, hasLength(1));
      expect(swap.events.whereType<UnifiedSwapStartRequested>(), hasLength(2));
    });

    testWidgets('one button carries on from ready through its checks', (
      tester,
    ) async {
      await show(tester, SwapReviewStatus.ready);
      final ready = tester.element(find.byKey(const Key('swap-start')));

      for (final status in [
        SwapReviewStatus.revalidating,
        SwapReviewStatus.starting,
      ]) {
        swap.emit(reviewing(status));
        await tester.pump();
        expect(tester.element(find.byKey(const Key('swap-start'))), ready);
      }
    });
  });
}
