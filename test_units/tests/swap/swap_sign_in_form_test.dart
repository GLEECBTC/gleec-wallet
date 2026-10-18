// The analyzer does not treat test_units as tests, so Bloc.emit's
// @visibleForTesting reads as a violation here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/taker_form/taker_bloc.dart';
import 'package:web_dex/bloc/taker_form/taker_state.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/model/authorize_mode.dart';
import 'package:web_dex/views/swap/entry/swap_entry_view.dart';
import 'package:web_dex/views/swap/entry/swap_sign_in.dart';
import 'package:web_dex/views/wallets_manager/wallets_manager_wrapper.dart';

import 'swap_entry_ui_fakes.dart';

/// Covers signing in from the swap form: what the form carries into the
/// sign-in, and how that sign-in is ended.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpSwapUi();

  late RecordingSwapBloc swap;
  late FakeSwapServices services;
  late _AuthBloc auth;

  setUp(() {
    swap = RecordingSwapBloc();
    services = FakeSwapServices();
    auth = _AuthBloc();
  });

  tearDown(() async {
    await swap.close();
    await auth.close();
  });

  // Two hundred and fifty dollars of ETH for USDC, without a wallet.
  final signedOut = swapBaseForm(input: '250').copyWith(
    signedIn: false,
    issue: SwapFormIssue.signedOut,
    amountMode: SwapAmountMode.fiat,
  );

  const here = Key('here');

  /// Shows [form] under the app's sign-in.
  Future<void> show(WidgetTester tester, UnifiedSwapState form) async {
    swap.emit(form);
    await pumpSwapUi(
      tester,
      const SizedBox(key: here),
      bloc: swap,
      services: services,
      providers: [BlocProvider<AuthBloc>.value(value: auth)],
    );
  }

  /// Somewhere under the form's bloc, services and the app's sign-in.
  BuildContext inForm(WidgetTester tester) => tester.element(find.byKey(here));

  Future<void> signIn(BuildContext _) async =>
      auth.push(const AuthBlocState(mode: AuthorizeMode.logIn));

  testWidgets('carries the pair and dollar amount into the sign-in', (
    tester,
  ) async {
    await show(tester, signedOut);
    await connectWalletFromSwap(inForm(tester), openManager: signIn);

    expect(services.signIns, [
      (pay: 'ETH', receive: 'USDC-ERC20', amount: '250', fiat: true),
    ]);
    expect(services.signInsEnded, [true]);
  });

  testWidgets('an amount in the asset stays in the asset', (tester) async {
    await show(
      tester,
      signedOut.copyWith(inputText: ' 1.5 ', amountMode: SwapAmountMode.token),
    );
    await connectWalletFromSwap(inForm(tester), openManager: signIn);

    expect(services.signIns.single.amount, '1.5');
    expect(services.signIns.single.fiat, isFalse);
  });

  testWidgets('an empty amount is not carried', (tester) async {
    await show(tester, signedOut.copyWith(inputText: '', clearReceive: true));
    await connectWalletFromSwap(inForm(tester), openManager: signIn);

    expect(services.signIns, [
      (pay: 'ETH', receive: null, amount: null, fiat: true),
    ]);
  });

  testWidgets('closing the wallet manager unsigned ends it without a wallet', (
    tester,
  ) async {
    await show(tester, signedOut);
    await connectWalletFromSwap(inForm(tester), openManager: (_) async {});

    expect(services.signIns, hasLength(1));
    expect(services.signInsEnded, [false]);
  });

  testWidgets('a wallet manager that fails still ends it', (tester) async {
    await show(tester, signedOut);

    await expectLater(
      connectWalletFromSwap(
        inForm(tester),
        openManager: (_) async => throw StateError('no dialog'),
      ),
      throwsStateError,
    );
    expect(services.signInsEnded, [false]);
  });

  testWidgets("the form's Connect wallet starts one in the app's manager", (
    tester,
  ) async {
    final taker = _TakerBloc();
    addTearDown(taker.close);
    swap.emit(signedOut);
    await pumpSwapUi(
      tester,
      const SwapEntryView(),
      bloc: swap,
      services: services,
      providers: [BlocProvider<TakerBloc>.value(value: taker)],
    );

    await tester.tap(swapPrimaryAction);
    await tester.pump();
    await tester.pump();

    expect(services.signIns, [
      (pay: 'ETH', receive: 'USDC-ERC20', amount: '250', fiat: true),
    ]);
    // Only the manager's own dependencies are missing here: the form handed
    // the sign-in to it, which is still open.
    expect(
      tester.takeException(),
      isA<ProviderNotFoundException>().having(
        (error) => error.widgetType,
        'widgetType',
        WalletsManagerWrapper,
      ),
    );
    expect(services.signInsEnded, isEmpty);
  });
}

/// Sign-in the test sets.
class _AuthBloc extends Cubit<AuthBlocState> implements AuthBloc {
  _AuthBloc() : super(AuthBlocState.initial());

  void push(AuthBlocState state) => emit(state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TakerBloc extends Cubit<TakerState> implements TakerBloc {
  _TakerBloc() : super(TakerState.initial());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
