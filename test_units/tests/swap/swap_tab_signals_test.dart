import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/views/swap/notices/swap_tab_signals.dart';

import 'swap_surface_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers what the browser tab says about swaps: its title and the dot on
/// its icon, for a swap running, one that needs the user, and one that
/// completed while they were away.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const brand = 0xFF8C41FF;
  const green = 0xFF16A34A;
  const amber = 0xFFF59E0B;
  const away = [AppLifecycleState.inactive, AppLifecycleState.hidden];
  const back = [AppLifecycleState.inactive, AppLifecycleState.resumed];

  late FakeExecutor routed;
  late SwapExecutionRegistry registry;
  late SurfaceServices services;
  late List<String> titles;
  late List<int?> badges;

  setUpAll(loadSurfaceCopy);

  setUp(() {
    routed = FakeExecutor(SwapLiquiditySource.routed);
    registry = SwapExecutionRegistry(
      executors: [routed],
      inFlight: () async => const [],
    );
    services = SurfaceServices(registry);
    titles = [];
    badges = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'SystemChrome.setApplicationSwitcherDescription') {
            titles.add((call.arguments as Map)['label'] as String);
          }
          return null;
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    await registry.dispose();
    await services.dispose();
    resetSurfaceCopy();
  });

  Future<void> show(WidgetTester tester, {bool enabled = true}) => pumpSurface(
    tester,
    SwapTabSignals(
      color: const Color(0xFF8C41FF),
      enabled: enabled,
      badge: badges.add,
      child: const SizedBox(),
    ),
    services: services,
  );

  Future<FakeHandle> follow(
    WidgetTester tester,
    SwapExecutionSnapshot snapshot,
  ) async {
    final handle = FakeHandle(snapshot);
    routed.resumable[snapshot.id] = handle;
    final updates = registry.watch(snapshot.id).listen((_) {});
    addTearDown(updates.cancel);
    await tester.pump();
    await tester.pump();
    return handle;
  }

  Future<void> hear(
    WidgetTester tester,
    FakeHandle handle,
    SwapExecutionSnapshot snapshot,
  ) async {
    handle.push(snapshot);
    await tester.pump();
    await tester.pump();
  }

  /// Steps the app's lifecycle through [states], as the platform does.
  Future<void> go(WidgetTester tester, List<AppLifecycleState> states) async {
    for (final state in states) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
    }
  }

  testWidgets('says a swap is running, with a dot in the brand colour', (
    tester,
  ) async {
    await show(tester);
    expect(titles.last, appTitle);

    await follow(tester, snapshotOf(id: 'one'));
    expect(titles.last, 'Swap in progress · Gleec Dex');
    expect(badges, [brand]);
  });

  testWidgets('counts the swaps running', (tester) async {
    await show(tester);
    await follow(tester, snapshotOf(id: 'one'));
    await follow(tester, snapshotOf(id: 'two'));

    expect(titles.last, '2 swaps in progress · Gleec Dex');
    expect(badges, [brand]);
  });

  testWidgets('says a completion the user was away for, until they are back', (
    tester,
  ) async {
    await show(tester);
    final handle = await follow(tester, snapshotOf(id: 'one'));
    await go(tester, away);
    addTearDown(() => go(tester, back));

    await hear(tester, handle, snapshotOf(id: 'one', outcome: completed()));
    expect(titles.last, 'Swap complete · Gleec Dex');
    expect(badges.last, green);

    await go(tester, back);
    expect(titles.last, appTitle);
    expect(badges.last, isNull);
  });

  testWidgets('leaves a completion seen in the tab to the app', (tester) async {
    await show(tester);
    final handle = await follow(tester, snapshotOf(id: 'one'));

    await hear(tester, handle, snapshotOf(id: 'one', outcome: completed()));
    expect(titles.last, appTitle);
    expect(badges, [brand, null]);
  });

  testWidgets('puts a swap waiting on the user before one running', (
    tester,
  ) async {
    await show(tester);
    await follow(tester, snapshotOf(id: 'one'));
    await follow(
      tester,
      snapshotOf(id: 'two', stage: SwapProgressStage.actionRequired),
    );

    expect(titles.last, 'Swap needs action · Gleec Dex');
    expect(badges.last, amber);
  });

  testWidgets('says a finished swap needs a look, until it is seen', (
    tester,
  ) async {
    await show(tester);
    await follow(
      tester,
      snapshotOf(id: 'one', outcome: failed(SwapFailureReason.routeFailed)),
    );
    expect(titles.last, 'Swap needs attention · Gleec Dex');
    expect(badges, [amber]);

    registry.acknowledge('one');
    await tester.pump();
    await tester.pump();
    expect(titles.last, appTitle);
    expect(badges, [amber, null]);
  });

  testWidgets('takes its dot off when it goes', (tester) async {
    await show(tester);
    await follow(tester, snapshotOf(id: 'one'));

    await pumpSurface(tester, const SizedBox(), services: services);
    expect(badges, [brand, null]);
  });

  testWidgets('leaves the tab alone off the web', (tester) async {
    await show(tester, enabled: false);
    await follow(tester, snapshotOf(id: 'one'));

    expect(titles.where((title) => title.contains('Swap')), isEmpty);
    expect(badges, isEmpty);
  });
}
