import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/shared/seed_backup/seed_backup_policy.dart';

Wallet _wallet({
  required bool hasBackup,
  WalletType type = WalletType.hdwallet,
  WalletProvenance provenance = WalletProvenance.generated,
}) {
  return Wallet(
    id: 'w',
    name: 'w',
    config: WalletConfig(
      seedPhrase: '',
      activatedCoins: const [],
      hasBackup: hasBackup,
      type: type,
      provenance: provenance,
    ),
  );
}

void testSeedBackupPolicy() {
  group('seedBackupGateRequired', () {
    test('no signed-in wallet is never gated', () {
      expect(seedBackupGateRequired(wallet: null), isFalse);
    });

    test('a backed-up wallet is never gated', () {
      expect(seedBackupGateRequired(wallet: _wallet(hasBackup: true)), isFalse);
    });

    test('an un-backed-up wallet on mainnet is gated', () {
      expect(seedBackupGateRequired(wallet: _wallet(hasBackup: false)), isTrue);
    });

    test('test coins are never gated, even without a backup', () {
      expect(
        seedBackupGateRequired(
          wallet: _wallet(hasBackup: false),
          isTestCoin: true,
        ),
        isFalse,
      );
    });

    test('hardware wallets are never gated, even if has_backup is false', () {
      // A failed metadata write must not strand a Trezor user behind a modal
      // that cannot complete - there is no mnemonic for the app to show.
      expect(
        seedBackupGateRequired(
          wallet: _wallet(hasBackup: false, type: WalletType.trezor),
        ),
        isFalse,
      );
    });

    test('an imported wallet that never confirmed backup is still gated', () {
      expect(
        seedBackupGateRequired(
          wallet: _wallet(
            hasBackup: false,
            provenance: WalletProvenance.imported,
          ),
        ),
        isTrue,
      );
    });
  });

  group('seedWasGeneratedForUser', () {
    test('true only for app-generated seeds', () {
      expect(
        seedWasGeneratedForUser(
          _wallet(hasBackup: false, provenance: WalletProvenance.generated),
        ),
        isTrue,
      );
      expect(
        seedWasGeneratedForUser(
          _wallet(hasBackup: false, provenance: WalletProvenance.imported),
        ),
        isFalse,
      );
      expect(
        seedWasGeneratedForUser(
          _wallet(hasBackup: false, provenance: WalletProvenance.unknown),
        ),
        isFalse,
      );
      expect(seedWasGeneratedForUser(null), isFalse);
    });
  });
}
