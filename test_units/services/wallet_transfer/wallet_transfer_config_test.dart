import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/services/wallet_transfer/wallet_transfer_config.dart';

void main() {
  group('backup relying party', () {
    test('is never reachable from the web wallet or its domain', () {
      for (final rpId in [
        'dex.gleec.com',
        'gleec.com',
        'backup.gleec.com',
        'deep.backup.gleec.com',
        'x.dex.gleec.com',
        'com',
      ]) {
        expect(
          WalletTransferConfig.isAllowedBackupRpId(rpId),
          isFalse,
          reason: rpId,
        );
      }
    });

    test('must be a plain lowercase host name', () {
      for (final rpId in [
        '',
        'Backup.Example.com',
        'https://backup.example.com',
        'backup.example.com/',
        'backup.example.com:443',
        '-bad.example.com',
        'backup..example.com',
        'localhost',
      ]) {
        expect(
          WalletTransferConfig.isAllowedBackupRpId(rpId),
          isFalse,
          reason: rpId,
        );
      }
    });

    test('a dedicated domain is allowed', () {
      for (final rpId in ['gleecbackup.com', 'recovery.gleec-wallet.app']) {
        expect(
          WalletTransferConfig.isAllowedBackupRpId(rpId),
          isTrue,
          reason: rpId,
        );
      }
    });

    test('backups are configured only with the switch and a valid host', () {
      expect(
        const WalletTransferConfig(
          passkeyBackupEnabled: true,
          backupRpId: 'gleecbackup.com',
        ).passkeyBackupConfigured,
        isTrue,
      );
      expect(
        const WalletTransferConfig(backupRpId: 'gleecbackup.com')
            .passkeyBackupConfigured,
        isFalse,
      );
      expect(
        const WalletTransferConfig(
          passkeyBackupEnabled: true,
          backupRpId: 'backup.gleec.com',
        ).passkeyBackupConfigured,
        isFalse,
      );
      expect(
        const WalletTransferConfig().moveEnabled,
        isFalse,
        reason: 'everything is off unless a build turns it on',
      );
    });
  });
}
