import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:web_dex/analytics/events/transaction_events.dart';
import 'package:web_dex/bloc/analytics/analytics_bloc.dart';
import 'package:web_dex/bloc/analytics/analytics_repo.dart';
import 'package:web_dex/bloc/settings/settings_repository.dart';
import 'package:web_dex/model/stored_settings.dart';
import 'package:web_dex/shared/swap/swap_services.dart';
import 'package:web_dex/views/swap/notices/swap_notices.dart';

import 'swap_exec_fakes.dart' show FakeRoutedHandle, progressOf;
import 'swap_src_fakes.dart';
import 'swap_src_sdk_fakes.dart';
import 'swap_surface_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// Swap analytics come from the app-wide services, so a swap's outcome
/// reaches the reporter that saw it run, however often the screens around
/// it were rebuilt in between.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final finished = progressOf(
    uuid: 'r-1',
    phase: RoutedSwapPhase.finished,
    receipt: RoutedSwapReceipt(
      outcome: RoutedSwapOutcome.completed,
      amount: d('3000'),
      assetId: usdc,
    ),
  );

  late SrcSdk sdk;
  late FakeRoutedHandle swap;

  setUpAll(loadSurfaceCopy);

  tearDown(resetSurfaceCopy);

  setUp(() {
    sdk = SrcSdk();
    for (final id in [eth, usdc]) {
      sdk.assets.add(assetFor(id));
    }
    swap = FakeRoutedHandle(
      progressOf(uuid: 'r-1', phase: RoutedSwapPhase.bridging),
    );
    sdk.routedSwaps
      ..starts = ((_) => swap)
      ..handles['r-1'] = swap
      ..watchable = {'r-1'};
  });

  group('the swap services', () {
    late List<AnalyticsEventData> events;
    late SwapServices services;

    setUp(() {
      events = [];
      services = servicesOf(sdk, logAnalytics: events.add);
    });

    tearDown(() => services.dispose());

    Future<void> signIn() async {
      sdk.auth.users.add(userOf('alice'));
      await pumpEventQueue();
    }

    Future<void> start() => services.registry.start(
      quoteOf(
        payload: offerOf(from: eth, to: usdc),
      ),
    );

    test(
      'report a swap started here, with the signed-in wallet type',
      () async {
        await signIn();
        await start();
        swap.push(finished);
        await pumpEventQueue();

        final started = events.whereType<SwapInitiatedEventData>().single;
        expect(started.hdType, 'hdwallet');
        expect(started.routeCategory, 'same_chain');
        final succeeded = events.whereType<SwapSucceededEventData>().single;
        expect(succeeded.hdType, 'hdwallet');
      },
    );

    test('report the outcome of a swap picked back up at sign-in', () async {
      sdk.routedSwaps.inFlightIds = ['r-1'];
      await signIn();
      swap.push(finished);
      await pumpEventQueue();

      expect(events.whereType<SwapInitiatedEventData>(), isEmpty);
      expect(events.whereType<SwapSucceededEventData>(), hasLength(1));
    });

    test('report no wallet type when nobody is signed in', () async {
      await start();
      await pumpEventQueue();

      expect(events.whereType<SwapInitiatedEventData>().single.hdType, '');
    });
  });

  testWidgets('a swap that ran through a menu change has its outcome '
      'reported once', (tester) async {
    final analytics = _RecordingAnalytics();
    GetIt.I.registerSingleton<AnalyticsRepo>(analytics);
    addTearDown(() => GetIt.I.unregister<AnalyticsRepo>());
    // Built on the test's clock, as are the screens.
    final services = servicesOf(sdk);
    addTearDown(services.dispose);
    final bloc = AnalyticsBloc(
      analytics: analytics,
      storedData: StoredSettings.initial(),
      repository: SettingsRepository(storage: MemoryStorage()),
    );
    addTearDown(bloc.close);

    // The app keys its main layout by menu, so a menu change builds it anew.
    Future<void> showMenu(String menu) => pumpSurface(
      tester,
      SwapNoticeListener(key: ValueKey(menu), child: Text(menu)),
      services: services,
      wrap: [
        (child) => BlocProvider<AnalyticsBloc>.value(value: bloc, child: child),
      ],
    );

    sdk.routedSwaps.inFlightIds = ['r-1'];
    await showMenu('dex');
    sdk.auth.users.add(userOf('alice'));
    await tester.pumpAndSettle();

    await showMenu('wallet');
    // Lets the old layout finish tearing down, as it would in the app.
    await tester.runAsync(() async {});
    swap.push(finished);
    await tester.pumpAndSettle();

    expect(find.text('wallet'), findsOneWidget);
    expect(analytics.events.whereType<SwapSucceededEventData>(), hasLength(1));
  });
}

class _RecordingAnalytics implements AnalyticsRepo {
  final List<AnalyticsEventData> events = [];

  @override
  Future<void> queueEvent(AnalyticsEventData data) async => events.add(data);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
