import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/withdraw_form/withdraw_form_bloc.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/views/wallet/coin_details/withdraw_form/withdraw_form.dart';

Map<String, dynamic> _utxoConfig() => {
  'coin': 'KMD',
  'type': 'UTXO',
  'name': 'Komodo',
  'fname': 'Komodo',
  'wallet_only': false,
  'mm2': 1,
  'chain_id': 141,
  'decimals': 8,
  'is_testnet': false,
  'required_confirmations': 1,
  'derivation_path': "m/44'/141'/0'",
  'protocol': {'type': 'UTXO'},
};

class _FakeWithdrawFormBloc extends Cubit<WithdrawFormState>
    implements WithdrawFormBloc {
  _FakeWithdrawFormBloc(super.initialState);

  final List<WithdrawFormEvent> events = <WithdrawFormEvent>[];

  @override
  void add(WithdrawFormEvent event) {
    events.add(event);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _buildTestWidget(WithdrawFormBloc bloc) {
  return MaterialApp(
    home: MediaQuery(
      data: const MediaQueryData(size: Size(1280, 1200)),
      child: Builder(
        builder: (context) {
          updateScreenType(context);
          return BlocProvider<WithdrawFormBloc>.value(
            value: bloc,
            child: const Scaffold(
              body: SingleChildScrollView(
                child: WithdrawFormFillSection(suppressPreviewError: false),
              ),
            ),
          );
        },
      ),
    ),
  );
}

void main() {
  group('WithdrawFormFillSection', () {
    testWidgets('locks editable controls while preview is sending', (
      tester,
    ) async {
      final asset = Asset.fromJson(_utxoConfig(), knownIds: const {});
      final bloc = _FakeWithdrawFormBloc(
        WithdrawFormState(
          asset: asset,
          step: WithdrawFormStep.fill,
          recipientAddress: 'recipient',
          amount: '1',
          isSending: true,
        ),
      );
      addTearDown(bloc.close);

      await tester.pumpWidget(_buildTestWidget(bloc));

      final lockWidget = tester.widget<IgnorePointer>(
        find.byKey(const Key('withdraw-form-fill-input-lock')),
      );

      expect(lockWidget.ignoring, isTrue);
    });

    testWidgets('keeps editable controls enabled when not sending', (
      tester,
    ) async {
      final asset = Asset.fromJson(_utxoConfig(), knownIds: const {});
      final bloc = _FakeWithdrawFormBloc(
        WithdrawFormState(
          asset: asset,
          step: WithdrawFormStep.fill,
          recipientAddress: 'recipient',
          amount: '1',
          isSending: false,
        ),
      );
      addTearDown(bloc.close);

      await tester.pumpWidget(_buildTestWidget(bloc));

      final lockWidget = tester.widget<IgnorePointer>(
        find.byKey(const Key('withdraw-form-fill-input-lock')),
      );

      expect(lockWidget.ignoring, isFalse);
    });
  });
}
