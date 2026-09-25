import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/bitrefill/bloc/bitrefill_bloc.dart';
import 'package:web_dex/bloc/coins_bloc/asset_coin_extension.dart';

Asset _bitrefillUsdtAsset() {
  final parent = Asset.fromJson({
    'coin': 'TRX',
    'type': 'TRX',
    'name': 'TRON',
    'fname': 'TRON',
    'wallet_only': true,
    'mm2': 1,
    'decimals': 6,
    'derivation_path': "m/44'/195'",
    'protocol': {
      'type': 'TRX',
      'protocol_data': {'network': 'Mainnet'},
    },
    'nodes': <Map<String, dynamic>>[],
  }, knownIds: const {});
  return Asset.fromJson(
    {
      'coin': 'USDT-TRC20',
      'type': 'TRC-20',
      'name': 'Tether',
      'fname': 'Tether',
      'wallet_only': true,
      'mm2': 1,
      'decimals': 6,
      'derivation_path': "m/44'/195'",
      'contract_address': 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
      'parent_coin': 'TRX',
      'protocol': {
        'type': 'TRC20',
        'protocol_data': {
          'platform': 'TRX',
          'contract_address': 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
        },
      },
      'nodes': <Map<String, dynamic>>[],
    },
    knownIds: {parent.id},
  );
}

void testBitrefillRefundUrl() {
  test(
    'Bitrefill refresh binds the selected refund address into the URL',
    () async {
      final bloc = BitrefillBloc();
      addTearDown(bloc.close);
      final coin = _bitrefillUsdtAsset().toCoin();
      const selected = 'TSelectedRefundAddress000000000001';

      final next = bloc.stream.firstWhere(
        (state) => state is BitrefillLoadSuccess,
      );
      bloc.add(
        const BitrefillLoadRequested(coin: null, refundAddress: selected),
      );
      final state = (await next) as BitrefillLoadSuccess;

      expect(Uri.parse(state.url).queryParameters['refund_address'], selected);

      final refreshed = bloc.stream.firstWhere(
        (state) =>
            state is BitrefillLoadSuccess &&
            Uri.parse(state.url).queryParameters['refund_address'] == selected,
      );
      bloc.add(BitrefillLoadRequested(coin: coin, refundAddress: selected));
      final refreshedState = (await refreshed) as BitrefillLoadSuccess;
      expect(
        Uri.parse(refreshedState.url).queryParameters['payment_methods'],
        'usdt_trc20',
      );
    },
  );
}
