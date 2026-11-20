import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';
import 'package:web_dex/views/swap/execution/swap_execution_view.dart';
import 'package:web_dex/views/swap/execution/swap_timeline_view.dart';
import 'package:web_dex/views/swap/swap_shell_controller.dart';

import 'swap_accessibility_checks.dart';
import 'swap_surface_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// The swap screen with no swap to show yet: still loading, or the watch
/// over with no source knowing the swap. Each says which, and neither is a
/// dead end.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a swap screen with nothing to show', () {
    late GatedExecutor routed;
    late SwapExecutionRegistry registry;
    late SurfaceServices services;
    late RecordingSwapBloc swap;
    late SwapShellController shell;

    setUpAll(loadSurfaceCopy);

    setUp(() {
      routed = GatedExecutor(SwapLiquiditySource.routed);
      registry = testSwapRegistry(
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

    Finder hero(String text) => find.descendant(
      of: find.byType(SwapStatusHero),
      matching: find.text(text),
    );

    bool above(WidgetTester tester, Finder a, Finder b) =>
        tester.getBottomLeft(a).dy <= tester.getTopLeft(b).dy;

    group('when no source knows the swap', () {
      Future<void> open(WidgetTester tester, SwapExecutionContext context) =>
          pumpSurface(
            tester,
            SwapExecutionView(id: 'ghost', context: context),
            services: services,
            swap: swap,
            shell: shell,
            expandProgressDetails: true,
          );

      final activity = find.byKey(const Key('swap-not-found-activity'));
      final retry = find.byKey(const Key('swap-not-found-retry'));

      testWidgets('says so, and that it is not being tracked', (tester) async {
        await open(tester, SwapExecutionContext.flow);

        expect(hero('swapProgressNotFoundTitle'.tr()), findsOneWidget);
        expect(hero('swapProgressNotFoundBody'.tr()), findsOneWidget);
        expect(find.byIcon(Icons.search_off_rounded), findsOneWidget);
        expect(find.byType(SwapTimelineView), findsNothing);
        // The watch has ended: nothing here may claim it is still checking.
        expect(
          find.text(LocaleKeys.swapProgressUnknownTitle.tr()),
          findsNothing,
        );
        await expectSwapAccessible(tester);
      });

      testWidgets('offers Activity first, then another look', (tester) async {
        await open(tester, SwapExecutionContext.flow);

        expect(
          tester.widget<SwapButton>(activity).variant,
          SwapButtonVariant.primary,
        );
        expect(
          tester.widget<SwapButton>(retry).variant,
          SwapButtonVariant.secondary,
        );
        expect(above(tester, activity, retry), isTrue);

        await tester.tap(activity);
        await tester.pump();
        expect(swap.events, [const UnifiedSwapProgressLeft()]);
        expect(shell.destination, SwapDestination.activity);
        expect(shell.detail, isNull);
      });

      testWidgets('from Activity, goes back to the list', (tester) async {
        shell.showActivity(
          swap: (id: 'ghost', source: SwapLiquiditySource.routed),
        );
        await open(tester, SwapExecutionContext.activity);

        expect(
          tester.widget<SwapButton>(activity).label,
          'swapBackToActivity'.tr(),
        );
        await tester.tap(activity);
        await tester.pump();
        expect(shell.detail, isNull);
        expect(swap.events, isEmpty);
      });

      testWidgets('looking again finds a swap that has turned up', (
        tester,
      ) async {
        await open(tester, SwapExecutionContext.flow);
        expect(retry, findsOneWidget);

        routed.resumable['ghost'] = FakeHandle(snapshotOf(id: 'ghost'));
        await tester.tap(retry);
        await tester.pumpAndSettle();

        expect(hero('Confirming on Ethereum'), findsOneWidget);
        expect(retry, findsNothing);
        expect(services.viewing, {'ghost'});
      });
    });

    testWidgets('names what is loading once the placeholders hold still', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      routed.resumeGate = Completer<void>();
      await pumpSurface(
        tester,
        const SwapExecutionView(id: 'slow', context: SwapExecutionContext.flow),
        services: services,
        swap: swap,
        shell: shell,
        settle: false,
      );
      await tester.pump();
      final label = 'swapProgressLoading'.tr();

      // Heard from the first frame; seen once the shimmer has stopped.
      expect(find.bySemanticsLabel(label), findsOneWidget);
      expect(find.text(label), findsNothing);
      final blocks = tester.getRect(find.byType(SwapSkeleton).last);

      await tester.pump(const Duration(seconds: 3));
      expect(find.text(label), findsOneWidget);
      expect(tester.getRect(find.byType(SwapSkeleton).last), blocks);
      expect(find.byType(SwapSkeleton), findsNWidgets(4));
      handle.dispose();
    });
  });
}
