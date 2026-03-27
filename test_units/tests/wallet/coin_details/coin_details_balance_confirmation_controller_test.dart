import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/views/wallet/coin_details/coin_details_info/coin_details_balance_confirmation_controller.dart';

BalanceInfo _balance(int amount) {
  final value = Decimal.fromInt(amount);
  return BalanceInfo(total: value, spendable: value, unspendable: Decimal.zero);
}

Future<void> _drainAsyncQueue([int iterations = 10]) async {
  for (var i = 0; i < iterations; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void testCoinDetailsBalanceConfirmationController() {
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
      'pre-bootstrap stream update stays unconfirmed even when cached value is non-zero',
      () {
        final controller = CoinDetailsBalanceConfirmationController(
          fetchConfirmedBalance: () async => _balance(0),
        );

        expect(controller.isConfirmed, isFalse);

        controller.onStreamBalance(_balance(7));

        expect(controller.isConfirmed, isFalse);
        expect(controller.latestBalance?.spendable, Decimal.fromInt(7));
      },
    );

    test(
      'stream update confirms balance after a bootstrap attempt completes',
      () async {
        final controller = CoinDetailsBalanceConfirmationController(
          fetchConfirmedBalance: () async {
            throw StateError('temporary bootstrap failure');
          },
        );

        expect(controller.isConfirmed, isFalse);

        await controller.bootstrap();
        controller.onStreamBalance(_balance(7));

        expect(controller.isConfirmed, isTrue);
        expect(controller.latestBalance?.spendable, Decimal.fromInt(7));
      },
    );

    test('bootstrap failures trigger bounded startup retries', () async {
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
      await _drainAsyncQueue();

      expect(attempts, 3, reason: 'Initial bootstrap + 2 retries');
      expect(controller.startupRetryAttempts, 2);
      expect(controller.isConfirmed, isFalse);
    });

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
      await _drainAsyncQueue();
      await controller.onStartupStreamError();
      await _drainAsyncQueue();

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

void main() {
  testCoinDetailsBalanceConfirmationController();
}
