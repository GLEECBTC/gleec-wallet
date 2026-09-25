import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/shared/utils/extensions/transaction_extensions.dart';

import 'coin_details_test_harness.dart';

/// Guards the TransactionHistoryBloc `myAddresses` expansion: with the GasFree
/// custody address included in the wallet-address set, `sanitize` must sort it
/// first in `to` so the UI's `.first` access shows the wallet's own address.
void testTransactionSanitizeCustody() {
  group('Transaction.sanitize with custody addresses', () {
    test('sorts wallet-owned custody address first in to', () {
      final coin = buildTestCoin();
      final tx = buildTestTransaction(
        assetId: coin.id,
        from: const ['eoa-address'],
        to: const ['external-address', 'custody-address'],
      );

      final sanitized = tx.sanitize({'eoa-address', 'custody-address'});

      expect(sanitized.to.first, 'custody-address');
    });

    test('keeps custody destination for a consolidation transfer', () {
      final coin = buildTestCoin();
      final tx = buildTestTransaction(
        assetId: coin.id,
        from: const ['eoa-address'],
        to: const ['custody-address'],
      );

      final sanitized = tx.sanitize({'eoa-address', 'custody-address'});

      expect(sanitized.to, ['custody-address']);
    });
  });
}

void main() {
  testTransactionSanitizeCustody();
}
