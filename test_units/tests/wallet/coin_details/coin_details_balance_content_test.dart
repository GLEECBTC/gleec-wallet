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

const _refreshingKey = Key('coin-details-balance-refreshing');

void testCoinDetailsBalanceContent() {
  group('CoinDetailsBalanceContent', () {
    testWidgets(
      'ghost state applies only when there is no cached balance to show',
      (tester) async {
        await tester.pumpWidget(
          _buildTestWidget(isConfirmed: false, latestBalance: null),
        );

        expect(find.byKey(const Key('coin-details-balance')), findsOneWidget);
        expect(find.byKey(_refreshingKey), findsNothing);
        expect(find.text('fiat-probe'), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 12));
      },
    );

    testWidgets(
      'unconfirmed cached balance renders immediately with a refresh affordance',
      (tester) async {
        await tester.pumpWidget(
          _buildTestWidget(isConfirmed: false, latestBalance: _balance(5)),
        );

        // The whole point: the number is on screen before confirmation.
        expect(find.text('5'), findsOneWidget);
        expect(find.byKey(_refreshingKey), findsOneWidget);
        expect(find.text('fiat-probe'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 12));
      },
    );

    testWidgets('confirmation drops the refresh affordance', (tester) async {
      await tester.pumpWidget(
        _buildTestWidget(isConfirmed: true, latestBalance: _balance(5)),
      );

      expect(find.text('5'), findsOneWidget);
      expect(find.byKey(_refreshingKey), findsNothing);
      expect(find.text('fiat-probe'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 12));
    });
  });
}

void main() {
  testCoinDetailsBalanceContent();
}
