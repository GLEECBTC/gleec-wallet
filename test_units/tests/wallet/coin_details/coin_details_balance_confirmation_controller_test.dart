import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/views/wallet/coin_details/coin_details_info/coin_details_balance_confirmation_controller.dart';

BalanceInfo _balance(int amount) {
  final value = Decimal.fromInt(amount);
  return BalanceInfo(total: value, spendable: value, unspendable: Decimal.zero);
}

void main() {
  group('CoinDetailsBalanceConfirmationController', () {
    test(
      'keeps cached startup balance unconfirmed until bootstrap succeeds',
      () async {
        int fetchCalls = 0;
        final controller = CoinDetailsBalanceConfirmationController(
          initialBalance: _balance(0),
          fetchConfirmedBalance: () async {
            fetchCalls += 1;
            return _balance(12);
          },
        );

        expect(controller.isConfirmed, isFalse);
        expect(controller.latestBalance?.spendable, Decimal.zero);

        await controller.bootstrap();

        expect(fetchCalls, 1);
        expect(controller.isConfirmed, isTrue);
        expect(controller.latestBalance?.spendable, Decimal.fromInt(12));
      },
    );

    test(
      'stream update confirms balance when it carries a non-zero amount',
      () {
        final controller = CoinDetailsBalanceConfirmationController(
          fetchConfirmedBalance: () async => _balance(0),
        );

        expect(controller.isConfirmed, isFalse);

        controller.onStreamBalance(_balance(7));

        expect(controller.isConfirmed, isTrue);
        expect(controller.latestBalance?.spendable, Decimal.fromInt(7));
      },
    );

    test('startup stream errors trigger bounded bootstrap retries', () async {
      int attempts = 0;
      final controller = CoinDetailsBalanceConfirmationController(
        fetchConfirmedBalance: () async {
          attempts += 1;
          throw StateError('temporary startup issue');
        },
        maxStartupRetries: 2,
        retryBackoffBase: Duration.zero,
      );

      await controller.bootstrap();
      await controller.onStartupStreamError();
      await controller.onStartupStreamError();
      await controller.onStartupStreamError();

      expect(attempts, 3, reason: 'Initial bootstrap + 2 retries');
      expect(controller.startupRetryAttempts, 2);
      expect(controller.isConfirmed, isFalse);
    });

    test('dispose turns startup paths into no-ops', () async {
      int fetchCalls = 0;
      final controller = CoinDetailsBalanceConfirmationController(
        fetchConfirmedBalance: () async {
          fetchCalls += 1;
          return _balance(1);
        },
      );

      controller.dispose();
      await controller.bootstrap();
      await controller.onStartupStreamError();
      controller.onStreamBalance(_balance(9));

      expect(fetchCalls, 0);
      expect(controller.isConfirmed, isFalse);
      expect(controller.latestBalance, isNull);
    });
  });
}
