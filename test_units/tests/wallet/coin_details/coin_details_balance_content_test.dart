import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/views/wallet/coin_details/coin_details_info/coin_details_info.dart';

import '../../utils/test_util.dart';

BalanceInfo _balance(int amount) {
  final value = Decimal.fromInt(amount);
  return BalanceInfo(total: value, spendable: value, unspendable: Decimal.zero);
}

Widget _buildTestWidget({
  required bool isConfirmed,
  required BalanceInfo? latestBalance,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: const MediaQueryData(size: Size(1280, 800)),
      child: Builder(
        builder: (context) {
          updateScreenType(context);
          return Scaffold(
            body: CoinDetailsBalanceContent(
              coin: setCoin(coinAbbr: 'TRX'),
              hideBalances: false,
              isConfirmed: isConfirmed,
              latestBalance: latestBalance,
              fiatBalance: const Text('fiat-probe'),
            ),
          );
        },
      ),
    ),
  );
}

void testCoinDetailsBalanceContent() {
  group('CoinDetailsBalanceContent', () {
    testWidgets(
      'desktop ghost state suppresses fiat balance until confirmation',
      (tester) async {
        await tester.pumpWidget(
          _buildTestWidget(isConfirmed: false, latestBalance: _balance(5)),
        );

        expect(find.byKey(const Key('coin-details-balance')), findsOneWidget);
        expect(find.text('fiat-probe'), findsNothing);

        await tester.pumpWidget(
          _buildTestWidget(isConfirmed: true, latestBalance: _balance(5)),
        );

        expect(find.text('fiat-probe'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 12));
      },
    );
  });
}

void main() {
  testCoinDetailsBalanceContent();
}
