import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/model/wallet.dart';

void testRecoveryEvidence() {
  group('recovery evidence migration', () {
    test('legacy backup flags never imply confirmed recovery words', () {
      final legacy = WalletConfig.fromJson({'has_backup': true});
      expect(legacy.hasBackup, isTrue);
      expect(legacy.recoveryEvidence, RecoveryEvidence.legacyUnknown);
      expect(legacy.hasRecoveryPhrase, isFalse);
      final roundTrip = WalletConfig.fromJson(legacy.toJson());
      expect(roundTrip.hasRecoveryPhrase, isFalse);
      expect(roundTrip.recoveryEvidence, RecoveryEvidence.legacyUnknown);
    });

    test('unknown future evidence cannot become a recovery claim', () {
      final config = WalletConfig.fromJson({
        'has_backup': true,
        'recovery_evidence': 'unrecognizedFutureProof',
      });
      expect(config.hasRecoveryPhrase, isFalse);
    });

    test(
      'encrypted-file evidence survives persistence without claiming a phrase',
      () {
        final config = WalletConfig.fromJson({
          'has_backup': true,
          'recovery_evidence': 'encryptedFileExported',
        });
        expect(config.hasRecoveryPhrase, isFalse);
        expect(
          WalletConfig.fromJson(config.copy().toJson()).recoveryEvidence,
          RecoveryEvidence.encryptedFileExported,
        );
      },
    );

    for (final evidence in ['phraseConfirmed', 'phraseSupplied']) {
      test(
        '$evidence is independent of legacy backup flag and password choice',
        () {
          final user = KdfUser(
            walletId: WalletId.withPubkeyHash(
              'Wallet',
              const AuthOptions(derivationMethod: DerivationMethod.hdWallet),
              'test-wallet-pubkey',
            ),
            isBip39Seed: true,
            metadata: {'has_backup': false, 'recovery_evidence': evidence},
          );
          final wallet = user.wallet;
          expect(wallet.config.hasRecoveryPhrase, isTrue);
          expect(
            wallet.copyWith(name: 'Renamed').config.hasRecoveryPhrase,
            isTrue,
          );
          expect(
            Wallet.fromJson(wallet.toJson()).config.hasRecoveryPhrase,
            isTrue,
          );
        },
      );
    }
  });
}
