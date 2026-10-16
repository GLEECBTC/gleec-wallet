// The analyzer does not treat test_units as tests, so Bloc.emit's
// @visibleForTesting reads as a violation here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/swap_activity/swap_activity_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/unified_swap_repository.dart';
import 'package:web_dex/views/swap/activity/swap_activity_view.dart';
import 'package:web_dex/views/swap/common/swap_format.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';
import 'package:web_dex/views/swap/swap_page.dart';
import 'package:web_dex/views/swap/swap_shell_controller.dart';

import 'swap_common_ui_fakes.dart';
import 'swap_surface_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// The heading of the screen holding keyboard focus, if focus is on one.
String? _focusedHeading() => FocusManager.instance.primaryFocus?.context
    ?.findAncestorWidgetOfExactType<SwapPageHeading>()
    ?.title;

/// Covers where the keyboard and screen readers land as swap screens come
/// and go, and what Escape does on them.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a swap screen', () {
    useSwapUi();

    late ValueNotifier<String> shown;
    late int left;
    setUp(() {
      shown = ValueNotifier('One');
      left = 0;
    });

    Future<void> pump(WidgetTester tester) => pumpSwapUi(
      tester,
      Column(
        children: [
          // Stands in for the shell's tabs, which stay put between screens.
          TextButton(onPressed: () {}, child: const Text('Tab')),
          Expanded(
            child: ValueListenableBuilder<String>(
              valueListenable: shown,
              builder: (context, title, _) => SwapScreen(
                key: ValueKey(title),
                onEscape: () => left++,
                child: Column(
                  children: [
                    SwapPageHeading(
                      title: title,
                      leading: TextButton(
                        onPressed: () {},
                        child: Text('Back from $title'),
                      ),
                    ),
                    TextButton(onPressed: () {}, child: Text('Act on $title')),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );

    Future<void> focus(WidgetTester tester, String text) async {
      Focus.of(tester.element(find.text(text))).requestFocus();
      await tester.pump();
    }

    Future<void> showNext(WidgetTester tester) async {
      shown.value = 'Two';
      await tester.pump();
      await tester.pump();
    }

    String? focusedText() => FocusManager.instance.primaryFocus?.context
        ?.findAncestorWidgetOfExactType<TextButton>()
        ?.child
        .toString();

    testWidgets('takes the focus the screen before it took away', (
      tester,
    ) async {
      await pump(tester);
      await focus(tester, 'Act on One');

      await showNext(tester);
      expect(_focusedHeading(), 'Two');
    });

    testWidgets('leaves focus that something else still holds', (tester) async {
      await pump(tester);
      await focus(tester, 'Tab');

      await showNext(tester);
      expect(focusedText(), contains('Tab'));
    });

    testWidgets('is never a Tab stop, but Tab carries on from it', (
      tester,
    ) async {
      await pump(tester);
      await focus(tester, 'Act on One');
      await showNext(tester);
      final heading = FocusManager.instance.primaryFocus;

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      expect(focusedText(), contains('Act on Two'));
      for (var i = 0; i < 4; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        expect(FocusManager.instance.primaryFocus, isNot(heading));
      }

      heading!.requestFocus();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(focusedText(), contains('Back from Two'));
    });

    testWidgets('does on Escape what leaving does, from anywhere on it', (
      tester,
    ) async {
      await pump(tester);
      await focus(tester, 'Act on One');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(left, 1);

      await showNext(tester);
      expect(_focusedHeading(), 'Two');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(left, 2);
    });

    testWidgets('tells screen readers it is a new screen, named by its '
        'heading', (tester) async {
      await pump(tester);

      expect(
        tester.getSemantics(find.byType(SwapScreen)),
        isSemantics(scopesRoute: true),
      );
      expect(
        tester.getSemantics(find.text('One')),
        isSemantics(label: 'One', isHeader: true, namesRoute: true),
      );
    });

    testWidgets('leaves a dialog above it the keyboard', (tester) async {
      await pump(tester);
      unawaited(
        showDialog<void>(
          context: tester.element(find.text('Tab')),
          builder: (_) => const Text('Busy'),
        ),
      );
      await tester.pumpAndSettle();
      final inDialog = FocusManager.instance.primaryFocus;

      await showNext(tester);
      expect(FocusManager.instance.primaryFocus, inDialog);
    });
  });

  group('the progress screen', () {
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

    Future<void> show(WidgetTester tester, UnifiedSwapState state) async {
      swap.emit(state);
      await pumpSurface(
        tester,
        const SwapPage(),
        services: services,
        swap: swap,
        shell: shell,
      );
    }

    Future<void> moveTo(WidgetTester tester, UnifiedSwapState state) async {
      swap.emit(state);
      await tester.pumpAndSettle();
    }

    testWidgets('takes the keyboard from the review as the swap starts', (
      tester,
    ) async {
      await show(tester, review);
      expect(_focusedHeading(), 'Review swap');

      await moveTo(tester, progress);
      expect(_focusedHeading(), 'Swap progress');
    });

    testWidgets('leaves on Escape as Close does, and the form takes the '
        'keyboard back', (tester) async {
      await show(tester, review);
      await moveTo(tester, progress);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(swap.events, [const UnifiedSwapProgressLeft()]);

      await moveTo(tester, form);
      expect(_focusedHeading(), 'Swap');
    });

    testWidgets('leaves the keyboard on a tab that still holds it', (
      tester,
    ) async {
      await pumpSurface(
        tester,
        Column(
          children: [
            TextButton(onPressed: () {}, child: const Text('Tab')),
            const Expanded(child: SwapPage()),
          ],
        ),
        services: services,
        swap: swap,
        shell: shell,
        settle: false,
      );
      Focus.of(tester.element(find.text('Tab'))).requestFocus();
      await tester.pump();
      swap.emit(progress);
      await tester.pumpAndSettle();

      expect(_focusedHeading(), isNull);
    });
  });

  group("Activity's detail", () {
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
      history.entries = [
        for (var i = 0; i < 3; i++)
          snapshotOf(id: 'swap-$i', createdAt: DateTime(2020, 3, 1, i)),
      ];
      for (final entry in history.entries) {
        routed.resumable[entry.id] = FakeHandle(entry);
      }
    });

    tearDown(() async {
      await swap.close();
      await registry.dispose();
      await services.dispose();
      shell.dispose();
      resetSurfaceCopy();
    });

    Future<void> show(WidgetTester tester) => pumpSurface(
      tester,
      const SwapActivityView(),
      services: services,
      swap: swap,
      shell: shell,
      wrap: [
        (child) => BlocProvider(
          create: (_) =>
              SwapActivityBloc(history: history, registry: registry)
                ..add(const SwapActivityStarted()),
          child: child,
        ),
      ],
    );

    /// The row of the swap started at [hour].
    FocusNode? rowFocus(WidgetTester tester, int hour) => tester
        .widget<InkWell>(
          find.ancestor(
            of: find.text(SwapFormat.time(DateTime(2020, 3, 1, hour))),
            matching: find.byType(InkWell),
          ),
        )
        .focusNode;

    Future<void> open(WidgetTester tester, int hour) async {
      rowFocus(tester, hour)!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
    }

    testWidgets('takes the keyboard from the row that opened it', (
      tester,
    ) async {
      await show(tester);
      await open(tester, 1);

      expect(shell.detail?.id, 'swap-1');
      expect(_focusedHeading(), 'Activity');
    });

    for (final (how, leave) in [
      (
        'Back',
        (WidgetTester tester) async {
          await tester.tap(find.byTooltip('Back'));
          await tester.pumpAndSettle();
        },
      ),
      (
        'Escape',
        (WidgetTester tester) async {
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
        },
      ),
    ]) {
      testWidgets('$how hands the keyboard back to that row', (tester) async {
        await show(tester);
        await open(tester, 1);

        await leave(tester);
        expect(shell.detail, isNull);
        expect(FocusManager.instance.primaryFocus, rowFocus(tester, 1));
      });
    }
  });
}
