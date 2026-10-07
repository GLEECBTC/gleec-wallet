import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/system_health/system_health_bloc.dart';
import 'package:web_dex/bloc/trading_status/trading_status_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/model/authorize_mode.dart';
import 'package:web_dex/shared/swap/swap_catalog.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_services.dart';
import 'package:web_dex/views/swap/swap_page.dart';
import 'package:web_dex/views/swap/swap_shell.dart';

import 'swap_src_sdk_fakes.dart';
import 'swap_surface_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers the swap surface across a sign-in its form started: the form is
/// rebuilt for the wallet, on the pair and amount it had. Signed out, the
/// form lists what it can swap without asking the wallet or KDF.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const carried = (
    pay: 'ETH',
    receive: 'USDC-ERC20',
    amount: '250',
    fiat: true,
  );

  late BlocObserver previousObserver;
  late RecordingBlocObserver observer;
  late SrcSdk sdk;
  late _Coins coins;
  late SwapServices services;
  late _AuthBloc auth;

  setUpAll(loadSurfaceCopy);

  setUp(() {
    previousObserver = Bloc.observer;
    Bloc.observer = observer = RecordingBlocObserver();
    sdk = SrcSdk();
    for (final id in [eth, usdc]) {
      sdk.assets.add(assetFor(id));
    }
    sdk.marketData.prices[eth] = d('3000');
    sdk.routedSwaps.eligible = {eth};
    coins = _Coins()..activated = {eth};
    services = servicesOf(sdk, coins: coins);
    auth = _AuthBloc();
    useFreshRoutingState();
  });

  tearDown(() async {
    Bloc.observer = previousObserver;
    await auth.close();
    await services.dispose();
    resetSurfaceCopy();
  });

  Future<void> show(WidgetTester tester) {
    final tradingStatus = FakeTradingStatusBloc();
    final systemHealth = FakeSystemHealthBloc();
    return pumpSurface(
      tester,
      const SwapShell(),
      services: services,
      wrap: [
        (child) => BlocProvider<TradingStatusBloc>.value(
          value: tradingStatus,
          child: child,
        ),
        (child) => BlocProvider<SystemHealthBloc>.value(
          value: systemHealth,
          child: child,
        ),
        (child) => BlocProvider<AuthBloc>.value(value: auth, child: child),
      ],
    );
  }

  UnifiedSwapBloc form(WidgetTester tester) =>
      BlocProvider.of<UnifiedSwapBloc>(tester.element(find.byType(SwapPage)));

  List<UnifiedSwapIntentApplied> intents() =>
      observer.eventsOf<UnifiedSwapIntentApplied>().toList();

  testWidgets('signing in rebuilds the form for the wallet, on the pair and '
      'amount it had', (tester) async {
    await show(tester);
    final signedOut = form(tester);
    expect(signedOut.state.signedIn, isFalse);

    services.beginSignIn(carried);
    await tester.pump();
    expect(intents(), isEmpty);

    auth.push(const AuthBlocState(mode: AuthorizeMode.logIn));
    await tester.pumpAndSettle();
    services.endSignIn(signedIn: true);

    final signedIn = form(tester);
    expect(signedIn, isNot(same(signedOut)));
    expect(intents(), [
      const UnifiedSwapIntentApplied(
        pay: 'ETH',
        receive: 'USDC-ERC20',
        amount: '250',
        amountMode: SwapAmountMode.fiat,
      ),
    ]);
    final state = signedIn.state;
    expect(state.signedIn, isTrue);
    expect((state.pay, state.receive), (eth, usdc));
    expect((state.inputText, state.amountMode), ('250', SwapAmountMode.fiat));
    // What this wallet has active, and what KDF routes of it.
    expect(state.catalog.activated, {eth});
    expect(state.catalog.of(SwapLiquiditySource.routed)!.quotable, {eth});
    expect(services.takePendingIntent(), isNull);

    // Closing a bloc awaits stream cancellations outside the fake clock.
    for (var i = 0; i < 10 && !signedOut.isClosed; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
    expect(signedOut.isClosed, isTrue);
  });

  testWidgets('a sign-in that ends without a wallet leaves the form be', (
    tester,
  ) async {
    await show(tester);
    final before = form(tester);

    services
      ..beginSignIn(carried)
      ..endSignIn(signedIn: false);
    await tester.pumpAndSettle();

    expect(form(tester), same(before));
    expect(intents(), isEmpty);
    expect(services.takePendingIntent(), isNull);
  });

  testWidgets('signed out, it lists what it can swap without asking the '
      'wallet or KDF', (tester) async {
    // Either would hold the list back: the wallet's answer queues for its
    // sign-in lock, and KDF's waits on the provider's networks.
    coins.gate = Completer<void>();
    sdk.routedSwaps.hangEligible = true;
    await show(tester);

    final state = form(tester).state;
    expect(state.loadingAssets, isFalse);
    expect(coins.reads, 0);
    expect(state.catalog.activated, isEmpty);
    expect(state.catalog.isIncomplete, isFalse);
    expect(state.catalog.assets, {eth, usdc});
  });

  testWidgets('signed in, it lists what it can swap before KDF does', (
    tester,
  ) async {
    sdk.routedSwaps.hangEligible = true;
    auth.push(const AuthBlocState(mode: AuthorizeMode.logIn));
    await show(tester);

    var routes = form(tester).state.catalog.of(SwapLiquiditySource.routed)!;
    expect(form(tester).state.loadingAssets, isFalse);
    // ETH is active, on a network the provider serves.
    expect(routes.quotable, {eth});
    expect(routes.status, SwapCatalogStatus.fresh);

    // KDF never lists: past its deadline the guess stays, marked unconfirmed.
    await tester.pump(const Duration(seconds: 11));
    routes = form(tester).state.catalog.of(SwapLiquiditySource.routed)!;
    expect(routes.quotable, {eth});
    expect(routes.status, SwapCatalogStatus.unavailable);
  });
}

/// The wallet's coins, counting reads of what is active and optionally
/// holding them open.
class _Coins extends SrcCoinsRepo {
  int reads = 0;
  Completer<void>? gate;

  @override
  Future<Set<AssetId>> getActivatedAssetIds({bool forceRefresh = false}) async {
    reads++;
    await gate?.future;
    return super.getActivatedAssetIds(forceRefresh: forceRefresh);
  }
}

/// Sign-in the test sets.
class _AuthBloc extends Cubit<AuthBlocState> implements AuthBloc {
  _AuthBloc() : super(AuthBlocState.initial());

  void push(AuthBlocState state) => emit(state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
