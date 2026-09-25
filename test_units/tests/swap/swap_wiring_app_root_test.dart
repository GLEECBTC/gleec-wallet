// test_units is analysed as app code, where the plugins' test mocks warn.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_dex/bloc/app_bloc_root.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/blocs/trading_entities_bloc.dart';
import 'package:web_dex/mm2/mm2_api/mm2_api.dart';
import 'package:web_dex/model/main_menu_value.dart';
import 'package:web_dex/model/stored_settings.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/shared/swap/swap_services.dart';

import 'swap_test_fixtures.dart';
import 'swap_wiring_fakes.dart';

/// The app owns one set of swap services for its whole lifetime.
void main() {
  group('App-wide swap services', () {
    late FakeSdk sdk;
    late FakeMm2Api mm2;
    late MainMenuValue previousMenu;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      previousMenu = routingState.selectedMenu;
      sdk = FakeSdk();
      mm2 = FakeMm2Api();
    });

    tearDown(() => routingState.selectedMenu = previousMenu);

    const probe = Key('probe');

    /// Mounts the root's repository providers over [probe] instead of the app.
    Future<void> mountAppRepositories(WidgetTester tester) async {
      final root = AppBlocRoot(
        storedPrefs: StoredSettings.initial(),
        komodoDefiSdk: sdk,
      );
      late Widget repositories;
      await tester.pumpWidget(
        MultiRepositoryProvider(
          providers: [
            RepositoryProvider<Mm2Api>.value(value: mm2),
            RepositoryProvider<CoinsRepo>.value(value: FakeCoinsRepo({eth})),
          ],
          child: Builder(
            builder: (context) {
              // ignore: invalid_use_of_protected_member
              repositories = root.build(context);
              return const SizedBox();
            },
          ),
        ),
      );

      // Listed as a provider of another MultiRepositoryProvider, the root's
      // providers wrap that one's child instead of their own - the whole app.
      await tester.pumpWidget(
        MultiRepositoryProvider(
          providers: [repositories as dynamic],
          child: const SizedBox(key: probe),
        ),
      );
      // Stops the orders poller the root also starts.
      tester.element(find.byKey(probe)).read<TradingEntitiesBloc>().dispose();
    }

    testWidgets('resumes swaps at sign-in with no swap screen ever opened', (
      tester,
    ) async {
      await mountAppRepositories(tester);

      sdk.auth.users.add(softwareUser());
      await tester.pump(Duration.zero);

      expect(sdk.routedSwaps.inFlightCalls, 1);
      expect(mm2.recentRequests, hasLength(1));
      expect(mm2.recentRequests.single.limit, 50);
      expect(mm2.recentRequests.single.pageNumber, 1);
    });

    testWidgets('gives every screen the same services, over the app\'s coins', (
      tester,
    ) async {
      await mountAppRepositories(tester);
      final below = tester.element(find.byKey(probe));

      final services = below.read<SwapServices>();

      expect(identical(below.read<SwapServices>(), services), isTrue);
      expect(await services.activatedAssets(), {eth});
    });

    testWidgets('stops following sign-ins once the app is gone', (
      tester,
    ) async {
      await mountAppRepositories(tester);
      expect(sdk.auth.users.hasListener, isTrue);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(Duration.zero);

      expect(sdk.auth.users.hasListener, isFalse);
      sdk.auth.users.add(softwareUser());
      await tester.pump(Duration.zero);
      expect(sdk.routedSwaps.inFlightCalls, 0);
    });
  });
}
