import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/faucet_button/faucet_button_bloc.dart';
import 'package:web_dex/bloc/faucet_button/faucet_button_event.dart';
import 'package:web_dex/bloc/faucet_button/faucet_button_state.dart';
import 'package:web_dex/views/wallet/coin_details/faucet/faucet_button.dart';

class _FakeFaucetBloc extends Cubit<FaucetState> implements FaucetBloc {
  _FakeFaucetBloc(super.initialState);

  FaucetEvent? lastEvent;

  @override
  void add(FaucetEvent event) {
    lastEvent = event;
    if (event is FaucetRequested) {
      emit(FaucetRequestInProgress(address: event.address));
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PubkeyInfo _address(String value) {
  return PubkeyInfo(
    address: value,
    derivationPath: "m/44'/141'/0'/0/0",
    chain: 'external',
    balance: BalanceInfo(
      total: Decimal.one,
      spendable: Decimal.one,
      unspendable: Decimal.zero,
    ),
    coinTicker: 'KMD',
  );
}

void testReceiveAddressFaucetWidgets() {
  group('Receive/address/faucet widgets', () {
    testWidgets('faucet button dispatches request for selected address', (
      tester,
    ) async {
      final bloc = _FakeFaucetBloc(const FaucetInitial());
      addTearDown(bloc.close);
      final address = _address('R-test-address');

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<FaucetBloc>.value(
            value: bloc,
            child: Scaffold(
              body: FaucetButton(coinAbbr: 'KMD', address: address),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(UiPrimaryButton));
      await tester.pump();

      expect(bloc.lastEvent, isA<FaucetRequested>());
      final event = bloc.lastEvent! as FaucetRequested;
      expect(event.coinAbbr, 'KMD');
      expect(event.address, address.address);
    });

    testWidgets('faucet button disabled while request pending', (tester) async {
      final address = _address('R-test-address');
      final bloc = _FakeFaucetBloc(
        FaucetRequestInProgress(address: address.address),
      );
      addTearDown(bloc.close);

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<FaucetBloc>.value(
            value: bloc,
            child: Scaffold(
              body: FaucetButton(coinAbbr: 'KMD', address: address),
            ),
          ),
        ),
      );

      final button = tester.widget<UiPrimaryButton>(
        find.byType(UiPrimaryButton),
      );
      expect(button.onPressed, isNull);
    });
  });
}

void main() {
  testReceiveAddressFaucetWidgets();
}
