import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';
import 'package:web_dex/views/swap/swap_shell.dart';
import 'package:web_dex/views/swap/swap_shell_controller.dart';

import 'swap_accessibility_checks.dart';
import 'swap_surface_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// Moving between Swap, Activity and Advanced: the controller behind it, the
/// pills that show where swaps need the user, and the deep links that must
/// land on the trading interface.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the swap shell', () {
    group('the controller', () {
      test('opens on the destination it is given', () {
        expect(SwapShellController().destination, SwapDestination.swap);
        expect(
          SwapShellController(initial: SwapDestination.advanced).destination,
          SwapDestination.advanced,
        );
      });

      test('moves once per change, and not to where it already is', () {
        var notified = 0;
        final shell = SwapShellController()..addListener(() => notified++);

        shell
          ..show(SwapDestination.swap)
          ..show(SwapDestination.advanced);

        expect(shell.destination, SwapDestination.advanced);
        expect(notified, 1);
      });

      test('opens Activity on a swap, or on its list', () {
        var notified = 0;
        final shell = SwapShellController()..addListener(() => notified++);
        const ref = (id: 'swap-1', source: SwapLiquiditySource.routed);

        shell.showActivity(swap: ref);
        expect(
          (shell.destination, shell.detail),
          (SwapDestination.activity, ref),
        );

        shell.showActivity();
        expect(shell.detail, isNull);
        expect(notified, 2);
      });

      test('closing a detail returns to the list, once', () {
        var notified = 0;
        final shell = SwapShellController()
          ..showActivity(
            swap: (id: 'swap-1', source: SwapLiquiditySource.atomic),
          )
          ..addListener(() => notified++);

        shell
          ..closeDetail()
          ..closeDetail();

        expect(shell.detail, isNull);
        expect(shell.destination, SwapDestination.activity);
        expect(notified, 1);
      });
    });

    group('the scope', () {
      testWidgets('hands out the controller without rebuilding its readers', (
        tester,
      ) async {
        final shell = SwapShellController();
        addTearDown(shell.dispose);
        var builds = 0;
        SwapShellController? found;
        await tester.pumpWidget(
          SwapShellScope(
            controller: shell,
            child: Builder(
              builder: (context) {
                builds++;
                found = SwapShellScope.of(context);
                return const SizedBox();
              },
            ),
          ),
        );

        shell.show(SwapDestination.activity);
        await tester.pump();

        expect(found, same(shell));
        expect(builds, 1);
      });

      testWidgets('is required above the swap surface', (tester) async {
        late BuildContext context;
        await tester.pumpWidget(
          Builder(
            builder: (inner) {
              context = inner;
              return const SizedBox();
            },
          ),
        );

        expect(() => SwapShellScope.of(context), throwsAssertionError);
      });
    });

    group('the destinations', () {
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

      Future<void> show(
        WidgetTester tester, {
        SwapDestination initial = SwapDestination.swap,
        Size size = const Size(420, 800),
        bool withServices = true,
      }) => pumpSurface(
        tester,
        SwapShell(
          initialDestination: initial,
          destinationBuilder: (destination) => Text('body:${destination.name}'),
        ),
        services: withServices ? services : null,
        size: size,
      );

      Finder pill(SwapDestination destination) => find.ancestor(
        of: find.byKey(Key('swap-destination-${destination.name}')),
        matching: find.byType(InkWell),
      );

      Color background(WidgetTester tester) => tester
          .widget<ColoredBox>(
            find
                .ancestor(
                  of: find.byKey(const Key('swap-shell')),
                  matching: find.byType(ColoredBox),
                )
                .first,
          )
          .color;

      testWidgets('marks the destination on screen', (tester) async {
        await show(tester);

        expect(
          tester.getSemantics(pill(SwapDestination.swap)),
          isSemantics(isButton: true, isSelected: true, hasTapAction: true),
        );
        expect(
          tester.getSemantics(pill(SwapDestination.advanced)),
          isSemantics(isButton: true, isSelected: false, hasTapAction: true),
        );
        expect(background(tester), SwapPalette.dark.canvas);
        await expectSwapAccessible(tester);
      });

      testWidgets('lets the trading interface draw its own background', (
        tester,
      ) async {
        await show(tester);
        await tester.tap(find.byKey(const Key('swap-destination-advanced')));
        await tester.pumpAndSettle();

        expect(find.text('body:advanced'), findsOneWidget);
        expect(background(tester), Colors.transparent);
      });

      testWidgets('counts running swaps on Activity, for a screen reader too', (
        tester,
      ) async {
        await registry.start(quoteOf());
        await registry.start(quoteOf(id: 'q2'));
        await show(tester);

        final dot = tester.widget<SwapCountDot>(find.byType(SwapCountDot));
        expect((dot.count, dot.tone), (2, null));
        expect(
          tester.getSemantics(pill(SwapDestination.activity)).label,
          startsWith('Activity, 2 active'),
        );
      });

      testWidgets('reads the Activity count once', (tester) async {
        await registry.start(quoteOf());
        await show(tester);

        expect(
          tester.getSemantics(pill(SwapDestination.activity)).label,
          'Activity, 1 active',
        );
      });

      testWidgets('turns the count to a warning when a swap needs attention', (
        tester,
      ) async {
        await registry.start(quoteOf());
        await show(tester);

        routed.lastStarted!.push(
          snapshotOf(
            id: 'routed-1',
            outcome: failed(SwapFailureReason.routeFailed),
          ),
        );
        await tester.pumpAndSettle();

        final dot = tester.widget<SwapCountDot>(find.byType(SwapCountDot));
        expect((dot.count, dot.tone), (1, SwapTone.warning));

        registry.acknowledge('routed-1');
        await tester.pumpAndSettle();
        expect(find.byType(SwapCountDot), findsNothing);
        expect(find.bySemanticsLabel(RegExp('active')), findsNothing);
      });

      testWidgets('shows no count without swap services', (tester) async {
        await show(tester, withServices: false);

        expect(find.byType(SwapCountDot), findsNothing);
        expect(find.text('body:swap'), findsOneWidget);
      });

      testWidgets('drops the icons before the labels on a narrow phone', (
        tester,
      ) async {
        await show(tester, size: const Size(320, 700));
        expect(find.byIcon(Icons.swap_horiz_rounded), findsNothing);
        expect(find.text('Advanced'), findsOneWidget);

        await show(tester, size: const Size(800, 700));
        expect(find.byIcon(Icons.swap_horiz_rounded), findsOneWidget);
        expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
        expect(find.byIcon(Icons.show_chart_rounded), findsOneWidget);
      });

      group('a deep link', () {
        testWidgets('to a swap in the trading interface opens Advanced', (
          tester,
        ) async {
          routingState.dexState.setDetailsAction('uuid-1');
          await show(tester);

          expect(find.text('body:advanced'), findsOneWidget);
        });

        testWidgets('to a maker order opens Advanced', (tester) async {
          routingState.dexState.orderType = 'maker';
          await show(tester);

          expect(find.text('body:advanced'), findsOneWidget);
        });

        testWidgets('that arrives later still lands on Advanced', (
          tester,
        ) async {
          await show(tester, initial: SwapDestination.activity);

          routingState.dexState.fromCurrency = 'ETH';
          await tester.pumpAndSettle();
          expect(find.text('body:activity'), findsOneWidget);

          routingState.dexState.setDetailsAction('uuid-2');
          await tester.pumpAndSettle();
          expect(find.text('body:advanced'), findsOneWidget);
        });

        testWidgets('is no longer followed once the surface closes', (
          tester,
        ) async {
          await show(tester);
          // ignore: invalid_use_of_protected_member
          expect(routingState.dexState.hasListeners, isTrue);

          await tester.pumpWidget(const SizedBox());

          // ignore: invalid_use_of_protected_member
          expect(routingState.dexState.hasListeners, isFalse);
        });
      });
    });
  });
}
