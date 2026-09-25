// The analyzer does not treat test_units as tests, so Bloc.emit's
// @visibleForTesting reads as a violation here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/unified_swap_repository.dart';
import 'package:web_dex/views/swap/entry/swap_entry_view.dart';
import 'package:web_dex/views/swap/execution/swap_execution_view.dart';
import 'package:web_dex/views/swap/review/swap_review_view.dart';
import 'package:web_dex/views/swap/swap_page.dart';
import 'package:web_dex/views/swap/swap_shell_controller.dart';

import 'swap_accessibility_checks.dart';
import 'swap_surface_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// The Swap destination: the form, its review — over the form on a phone,
/// beside it on a wide screen — and the swap just started.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the Swap destination', () {
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

    Future<void> show(
      WidgetTester tester,
      UnifiedSwapState state, {
      Size size = const Size(420, 1600),
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
        settle: settle,
      );
    }

    testWidgets('shows the form until a review opens', (tester) async {
      await show(tester, form);

      expect(
        tester.widget<SwapEntryView>(find.byType(SwapEntryView)).panelOpen,
        isFalse,
      );
      expect(find.byType(SwapReviewView), findsNothing);
      expect(find.byKey(const Key('swap-primary-action')), findsOneWidget);
    });

    testWidgets('on a phone, the review takes the whole page', (tester) async {
      await show(tester, review);

      expect(find.byType(SwapEntryView), findsNothing);
      expect(
        tester.widget<SwapReviewView>(find.byType(SwapReviewView)).inPanel,
        isFalse,
      );
    });

    for (final (width, panel) in [(1000.0, 420.0), (1600.0, 520.0)]) {
      testWidgets('at ${width.round()} wide, the review sits beside the form, '
          '${panel.round()} wide', (tester) async {
        await show(tester, review, size: Size(width, 1000));

        final entry = tester.widget<SwapEntryView>(find.byType(SwapEntryView));
        final beside = tester.widget<SwapReviewView>(
          find.byType(SwapReviewView),
        );
        expect(entry.panelOpen, isTrue);
        expect(beside.inPanel, isTrue);
        expect(tester.getSize(find.byType(SwapReviewView)).width, panel);
        expect(
          tester.getTopLeft(find.byType(SwapReviewView)).dx,
          greaterThan(tester.getTopLeft(find.byType(SwapEntryView)).dx),
        );
        expect(find.byKey(const Key('swap-primary-action')), findsNothing);
      });
    }

    for (final (status, usable) in [
      (SwapReviewStatus.ready, true),
      (SwapReviewStatus.starting, false),
      (SwapReviewStatus.unconfirmed, false),
    ]) {
      testWidgets('while the review is ${status.name}, the form beside it is '
          '${usable ? 'usable' : 'set aside'}', (tester) async {
        await show(
          tester,
          form.copyWith(
            view: UnifiedSwapView.review,
            review: SwapReview(quote: quote, status: status),
          ),
          size: const Size(1000, 1000),
          // A start in flight shows a spinner that never settles.
          settle: status != SwapReviewStatus.starting,
        );

        expect(
          find.semantics.byLabel('Amount to pay'),
          usable ? findsOneWidget : findsNothing,
        );
        await tester.tap(
          find.byTooltip('Switch direction'),
          warnIfMissed: false,
        );
        await tester.pump();
        expect(swap.events.isNotEmpty, usable);
      });
    }

    testWidgets('decides by the space it has, not by the window', (
      tester,
    ) async {
      await pumpSurface(
        tester,
        const Center(child: SizedBox(width: 600, child: SwapPage())),
        services: services,
        swap: swap..emit(review),
        shell: shell,
        size: const Size(960, 1000),
      );

      expect(find.byType(SwapReviewView), findsOneWidget);
      expect(find.byType(SwapEntryView), findsNothing);
    });

    testWidgets('follows the swap just started', (tester) async {
      routed.resumable['routed-1'] = FakeHandle(snapshotOf(id: 'routed-1'));
      await show(
        tester,
        form.copyWith(
          view: UnifiedSwapView.progress,
          activeExecutionId: 'routed-1',
        ),
      );

      final view = tester.widget<SwapExecutionView>(
        find.byType(SwapExecutionView),
      );
      expect(view.id, 'routed-1');
      expect(view.context, SwapExecutionContext.flow);
      expect(find.text('Swap progress'), findsOneWidget);
      expect(find.text('Confirming on Ethereum'), findsWidgets);
      await expectSwapAccessible(tester);
    });

    testWidgets('shows the form if the swap it was following is gone', (
      tester,
    ) async {
      await show(tester, form.copyWith(view: UnifiedSwapView.progress));

      expect(find.byType(SwapEntryView), findsOneWidget);
      expect(find.byType(SwapExecutionView), findsNothing);
    });

    testWidgets('moves from the form to a new swap and on to the next', (
      tester,
    ) async {
      routed.resumable['routed-1'] = FakeHandle(snapshotOf(id: 'routed-1'));
      routed.resumable['routed-2'] = FakeHandle(
        snapshotOf(id: 'routed-2', outcome: completed()),
      );
      await show(tester, form);

      swap.emit(
        form.copyWith(
          view: UnifiedSwapView.progress,
          activeExecutionId: 'routed-1',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Confirming on Ethereum'), findsWidgets);

      swap.emit(
        form.copyWith(
          view: UnifiedSwapView.progress,
          activeExecutionId: 'routed-2',
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwapExecutionView>(find.byType(SwapExecutionView)).id,
        'routed-2',
      );
      expect(find.text('You received 3,001 USDC'), findsOneWidget);
      expect(find.text('Confirming on Ethereum'), findsNothing);

      swap.emit(form);
      await tester.pumpAndSettle();
      expect(find.byType(SwapExecutionView), findsNothing);
      expect(find.byType(SwapEntryView), findsOneWidget);
    });
  });
}
