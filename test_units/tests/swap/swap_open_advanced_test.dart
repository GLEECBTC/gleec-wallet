import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/dex_repository.dart';
import 'package:web_dex/blocs/trading_entities_bloc.dart';
import 'package:web_dex/model/my_orders/my_order.dart';
import 'package:web_dex/model/swap.dart';
import 'package:web_dex/router/state/dex_state.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/services/arrr_activation/arrr_activation_service.dart';
import 'package:web_dex/services/orders_service/my_orders_service.dart';
import 'package:web_dex/views/common/pages/page_layout.dart';
import 'package:web_dex/views/dex/dex_page.dart';
import 'package:web_dex/views/dex/entity_details/trading_details.dart';

import 'swap_src_sdk_fakes.dart';
import 'swap_surface_ui_fakes.dart';

/// Open in Advanced, on a swap's outcome, names the swap in the route and
/// then shows the trading page, which must open on that swap's details.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SrcDex dex;

  setUpAll(loadSurfaceCopy);

  setUp(() {
    dex = SrcDex();
    useFreshRoutingState();
  });

  tearDown(resetSurfaceCopy);

  Future<void> showTradingPage(WidgetTester tester) => pumpSurface(
    tester,
    const DexPage(),
    settle: false,
    wrap: [
      (child) => MultiRepositoryProvider(
        providers: [
          RepositoryProvider<KomodoDefiSdk>.value(value: SrcSdk()),
          RepositoryProvider<TradingEntitiesBloc>.value(value: _NoEntities()),
          RepositoryProvider<CoinsRepo>.value(value: SrcCoinsRepo()),
          RepositoryProvider<MyOrdersService>.value(value: SrcOrders()),
          RepositoryProvider<DexRepository>.value(value: dex),
          RepositoryProvider<ArrrActivationService>.value(value: _NoArrr()),
        ],
        child: BlocProvider<AuthBloc>.value(
          value: _SignedOut(AuthBlocState.initial()),
          child: child,
        ),
      ),
    ],
  );

  // The trading page's order polling stops once its bloc has closed, after
  // cancels that complete outside the test's clock.
  Future<void> leave(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {});
    await tester.pump();
  }

  /// The trading form, which reads more of the app than is given here.
  void expectTradingForm(WidgetTester tester) {
    expect(find.byType(TradingDetails), findsNothing);
    expect(find.byType(PageLayout), findsOneWidget);
    expect(tester.takeException(), isNotNull);
  }

  testWidgets('opens on the swap the route named before it was built', (
    tester,
  ) async {
    routingState.dexState.setDetailsAction('swap-9');

    await showTradingPage(tester);

    final details = tester.widget<TradingDetails>(find.byType(TradingDetails));
    expect(details.uuid, 'swap-9');
    expect(details.kind, TradingEntityKind.swap);
    expect(dex.statusReads, ['swap-9']);
    await leave(tester);
  });

  testWidgets('opens on the trading form when details were left open on an '
      'earlier visit', (tester) async {
    routingState.dexState.setDetailsAction('order-1');
    await showTradingPage(tester);
    await leave(tester);

    await showTradingPage(tester);

    expectTradingForm(tester);
    expect(dex.statusReads, ['order-1']);
    await leave(tester);
  });

  testWidgets('opens on the trading form for a link to details, which cannot '
      'say whether it names a swap or an order', (tester) async {
    routingState.dexState
      ..action = DexAction.tradingDetails
      ..uuid = 'order-1';

    await showTradingPage(tester);

    expectTradingForm(tester);
    expect(dex.statusReads, isEmpty);
    await leave(tester);
  });
}

class _NoEntities implements TradingEntitiesBloc {
  @override
  Stream<List<MyOrder>> get outMyOrders => const Stream.empty();

  @override
  Stream<List<Swap>> get outSwaps => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoArrr implements ArrrActivationService {
  @override
  Stream<ZhtlcConfigurationRequest> get configurationRequests =>
      const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SignedOut extends Cubit<AuthBlocState> implements AuthBloc {
  _SignedOut(super.initialState);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
