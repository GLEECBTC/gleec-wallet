import 'package:decimal/decimal.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';
import 'package:web_dex/shared/utils/extensions/transaction_extensions.dart';

void testSanitizeTransaction() {
  group('Transaction.sanitize()', () {
    Transaction createTransaction({
      required List<String> from,
      required List<String> to,
      String? internalId,
    }) {
      return Transaction(
        id: 'test-id',
        internalId: internalId ?? 'test-internal-id',
        assetId: AssetId(
          id: 'BTC',
          name: 'Bitcoin',
          symbol: AssetSymbol(assetConfigId: 'BTC'),
          chainId: AssetChainId(chainId: 1),
          derivationPath: "m/44'/0'/0'/0/0",
          subClass: CoinSubClass.utxo,
        ),
        timestamp: DateTime.now(),
        confirmations: 6,
        blockHeight: 100000,
        from: from,
        to: to,
        fee: null,
        txHash: 'test-hash',
        memo: null,
        balanceChanges: BalanceChanges(
          netChange: Decimal.parse('1.0'),
          receivedByMe: Decimal.parse('1.0'),
          spentByMe: Decimal.zero,
          totalAmount: Decimal.parse('1.0'),
        ),
      );
    }

    group('Self-transfer edge case', () {
      test(
          'leaves address untouched when to and from are identical (self-transfer)',
          () {
        final selfAddress = 'self1';
        final tx = createTransaction(
          from: [selfAddress],
          to: [selfAddress],
        );
        final walletAddresses = {selfAddress};

        final result = tx.sanitize(walletAddresses);

        // The address should remain in both to and from
        expect(result.to, equals([selfAddress]));
        expect(result.from, equals([selfAddress]));
        // There should never be 0 to or from addresses
        expect(result.to, isNotEmpty);
        expect(result.from, isNotEmpty);
      });
    });

    group('Basic functionality', () {
      test('returns original transaction when from list is empty', () {
        final tx = createTransaction(from: [], to: ['addr1', 'addr2']);
        final walletAddresses = {'wallet1', 'wallet2'};

        final result = tx.sanitize(walletAddresses);

        expect(result, equals(tx));
        expect(result.to, equals(['addr1', 'addr2']));
      });

      test('removes sender from recipient list when sender is in to list', () {
        final tx = createTransaction(
          from: ['sender1'],
          to: ['sender1', 'recipient1', 'recipient2'],
        );
        final walletAddresses = <String>{};

        final result = tx.sanitize(walletAddresses);

        expect(result.to, equals(['recipient1', 'recipient2']));
        expect(result.to.contains('sender1'), isFalse);
      });

      test('returns original transaction when sender is not in to list', () {
        final tx = createTransaction(
          from: ['sender1'],
          to: ['recipient1', 'recipient2'],
        );
        final walletAddresses = <String>{};

        final result = tx.sanitize(walletAddresses);

        expect(result.to, equals(['recipient1', 'recipient2']));
      });

      test('handles case where sender is the only recipient', () {
        final tx = createTransaction(
          from: ['sender1'],
          to: ['sender1'],
        );
        final walletAddresses = <String>{};

        final result = tx.sanitize(walletAddresses);

        expect(result.to, ['sender1']);
      });

      test('handles case where to list is empty', () {
        final tx = createTransaction(
          from: ['sender1'],
          to: [],
        );
        final walletAddresses = {'wallet1'};

        final result = tx.sanitize(walletAddresses);

        expect(result.to, isEmpty);
      });
    });

    group('Address prioritization and sorting', () {
      test('prioritizes wallet addresses when multiple recipients exist', () {
        final tx = createTransaction(
          from: ['sender1'],
          to: ['sender1', 'external1', 'wallet1', 'external2', 'wallet2'],
        );
        final walletAddresses = {'wallet1', 'wallet2'};

        final result = tx.sanitize(walletAddresses);

        expect(result.to.length, equals(4));
        expect(result.to.contains('sender1'), isFalse);
        // Wallet addresses should come first
        expect(result.to[0], anyOf('wallet1', 'wallet2'));
        expect(result.to[1], anyOf('wallet1', 'wallet2'));
        expect(
            result.to[0] != result.to[1], isTrue); // They should be different
        // External addresses should come after
        expect(result.to[2], anyOf('external1', 'external2'));
        expect(result.to[3], anyOf('external1', 'external2'));
        expect(
            result.to[2] != result.to[3], isTrue); // They should be different
      });

      test('sorts wallet addresses first when walletAddresses is not empty',
          () {
        final tx = createTransaction(
          from: ['sender1'],
          to: ['external1', 'wallet1', 'external2', 'wallet2', 'external3'],
        );
        final walletAddresses = {'wallet1', 'wallet2'};

        final result = tx.sanitize(walletAddresses);

        // First element should be a wallet address
        expect(walletAddresses.contains(result.to.first), isTrue);

        // Find where wallet addresses end
        int walletAddressCount = 0;
        for (final addr in result.to) {
          if (walletAddresses.contains(addr)) {
            walletAddressCount++;
          } else {
            break;
          }
        }

        // Should have exactly 2 wallet addresses at the beginning
        expect(walletAddressCount, equals(2));
      });

      test(
          'does not sort when only one recipient remains after removing sender',
          () {
        final tx = createTransaction(
          from: ['sender1'],
          to: ['sender1', 'recipient1'],
        );
        final walletAddresses = {'wallet1'};

        final result = tx.sanitize(walletAddresses);

        expect(result.to, equals(['recipient1']));
      });

      test('does not sort when walletAddresses is empty', () {
        final tx = createTransaction(
          from: ['sender1'],
          to: ['sender1', 'recipient2', 'recipient1', 'recipient3'],
        );
        final walletAddresses = <String>{};

        final result = tx.sanitize(walletAddresses);

        // Should maintain original order (minus sender)
        expect(result.to, equals(['recipient2', 'recipient1', 'recipient3']));
      });

      test('handles mixed case where some recipients are wallet addresses', () {
        final tx = createTransaction(
          from: ['sender1'],
          to: [
            'sender1',
            'external1',
            'wallet1',
            'external2',
            'wallet2',
            'external3',
            'wallet3',
          ],
        );
        final walletAddresses = {'wallet1', 'wallet2', 'wallet3'};

        final result = tx.sanitize(walletAddresses);

        expect(result.to.length, equals(6));

        // Check that wallet addresses come first
        final walletAddressesInResult =
            result.to.where(walletAddresses.contains).toList();
        final externalAddressesInResult =
            result.to.where((addr) => !walletAddresses.contains(addr)).toList();

        expect(walletAddressesInResult.length, equals(3));
        expect(externalAddressesInResult.length, equals(3));

        // Wallet addresses should be at the beginning
        expect(result.to.take(3).every(walletAddresses.contains), isTrue);
        // External addresses should be at the end
        expect(
            result.to.skip(3).every((addr) => !walletAddresses.contains(addr)),
            isTrue);
      });
    });

    group('Edge cases', () {
      test('handles transaction with multiple senders (takes first)', () {
        final tx = createTransaction(
          from: ['sender1', 'sender2'],
          to: ['sender1', 'sender2', 'recipient1', 'wallet1'],
        );
        final walletAddresses = {'wallet1'};

        final result = tx.sanitize(walletAddresses);

        // Should only remove the first sender
        expect(result.to, equals(['wallet1', 'sender2', 'recipient1']));
        expect(result.to.contains('sender1'), isFalse);
        expect(result.to.contains('sender2'), isTrue);
      });

      test('handles case where sender appears multiple times in to list', () {
        final tx = createTransaction(
          from: ['sender1'],
          to: ['sender1', 'recipient1', 'sender1', 'wallet1'],
        );
        final walletAddresses = {'wallet1'};

        final result = tx.sanitize(walletAddresses);

        // Should remove all occurrences of sender1
        expect(result.to.where((addr) => addr == 'sender1').length, equals(0));
        expect(result.to, contains('recipient1'));
        expect(result.to, contains('wallet1'));
      });

      test('preserves transaction immutability by creating new transaction',
          () {
        final originalTo = ['sender1', 'recipient1', 'wallet1'];
        final tx = createTransaction(
          from: ['sender1'],
          to: List<String>.from(originalTo),
        );
        final walletAddresses = {'wallet1'};

        final result = tx.sanitize(walletAddresses);

        // Original transaction should be unchanged
        expect(tx.to, equals(originalTo));
        // Result should be different
        expect(result.to, isNot(equals(originalTo)));
        expect(result.to.contains('sender1'), isFalse);
      });

      test('handles empty wallet addresses set gracefully', () {
        final tx = createTransaction(
          from: ['sender1'],
          to: ['sender1', 'recipient2', 'recipient1'],
        );
        final walletAddresses = <String>{};

        final result = tx.sanitize(walletAddresses);

        expect(result.to, equals(['recipient2', 'recipient1']));
      });

      test('handles case where all recipients are wallet addresses', () {
        final tx = createTransaction(
          from: ['sender1'],
          to: ['sender1', 'wallet1', 'wallet2', 'wallet3'],
        );
        final walletAddresses = {'wallet1', 'wallet2', 'wallet3'};

        final result = tx.sanitize(walletAddresses);

        expect(result.to.length, equals(3));
        expect(result.to.every(walletAddresses.contains), isTrue);
        expect(result.to.contains('sender1'), isFalse);
      });

      test('handles case where no recipients are wallet addresses', () {
        final tx = createTransaction(
          from: ['sender1'],
          to: ['sender1', 'external1', 'external2', 'external3'],
        );
        final walletAddresses = {'wallet1', 'wallet2'};

        final result = tx.sanitize(walletAddresses);

        expect(result.to, equals(['external1', 'external2', 'external3']));
        expect(
            result.to.every((addr) => !walletAddresses.contains(addr)), isTrue);
      });
    });

    group('Wallet address prioritization for .first access', () {
      test('ensures wallet address is first for easy .first access', () {
        final tx = createTransaction(
          from: ['sender1'],
          to: ['sender1', 'external1', 'external2', 'wallet1', 'external3'],
        );
        final walletAddresses = {'wallet1'};

        final result = tx.sanitize(walletAddresses);

        // The first address should be the wallet address
        expect(result.to.first, equals('wallet1'));
        expect(walletAddresses.contains(result.to.first), isTrue);
      });

      test('ensures first wallet address when multiple wallet addresses exist',
          () {
        final tx = createTransaction(
          from: ['sender1'],
          to: ['sender1', 'external1', 'wallet2', 'external2', 'wallet1'],
        );
        final walletAddresses = {'wallet1', 'wallet2'};

        final result = tx.sanitize(walletAddresses);

        // The first address should be a wallet address
        expect(walletAddresses.contains(result.to.first), isTrue);
        // Both wallet addresses should be at the beginning
        expect(walletAddresses.contains(result.to[0]), isTrue);
        expect(walletAddresses.contains(result.to[1]), isTrue);
      });

      test('maintains proper order for UI display priority', () {
        final tx = createTransaction(
          from: ['sender1'],
          to: [
            'sender1',
            'external1',
            'external2',
            'wallet_priority',
            'external3',
            'wallet_secondary',
            'external4',
          ],
        );
        final walletAddresses = {'wallet_priority', 'wallet_secondary'};

        final result = tx.sanitize(walletAddresses);

        // Wallet addresses should be grouped at the beginning
        final firstTwoAddresses = result.to.take(2).toList();
        expect(firstTwoAddresses.every(walletAddresses.contains), isTrue);

        // External addresses should follow
        final remainingAddresses = result.to.skip(2).toList();
        expect(
            remainingAddresses.every((addr) => !walletAddresses.contains(addr)),
            isTrue);

        // Verify we can safely call .first for wallet address
        expect(walletAddresses.contains(result.to.first), isTrue);
      });
    });
  });
}
