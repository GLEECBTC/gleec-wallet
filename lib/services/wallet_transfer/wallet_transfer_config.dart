import 'package:web_dex/services/wallet_access/platform/passkey/passkey_credential_backend.dart';

/// Rollout switches for moving a wallet between devices and for passkey
/// backups. Everything is off unless a build turns it on.
final class WalletTransferConfig {
  const WalletTransferConfig({
    this.moveEnabled = false,
    this.passkeyBackupEnabled = false,
    this.backupRpId = '',
    this.googleDriveEnabled = false,
    this.googleIosClientId = '',
  });

  static const fromEnvironment = WalletTransferConfig(
    moveEnabled: bool.fromEnvironment('WALLET_MOVE_ENABLED'),
    passkeyBackupEnabled: bool.fromEnvironment('WALLET_PASSKEY_BACKUP_ENABLED'),
    backupRpId: String.fromEnvironment('WALLET_BACKUP_RP_ID'),
    googleDriveEnabled: bool.fromEnvironment(
      'WALLET_BACKUP_GOOGLE_DRIVE_ENABLED',
    ),
    googleIosClientId: String.fromEnvironment(
      'WALLET_BACKUP_GOOGLE_IOS_CLIENT_ID',
    ),
  );

  final bool moveEnabled;
  final bool passkeyBackupEnabled;

  /// The relying party for backup passkeys: a host only the native apps use.
  final String backupRpId;
  final bool googleDriveEnabled;

  /// iOS OAuth client for Drive's app data folder. Android identifies the
  /// app by its package and signing certificate instead.
  final String googleIosClientId;

  static final _host = RegExp(
    r'^(?=.{1,253}$)([a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$',
  );

  bool get passkeyBackupConfigured =>
      passkeyBackupEnabled && isAllowedBackupRpId(backupRpId);

  /// The web wallet's registrable domain. Its certificates and DNS must not
  /// be able to reach backup passkeys.
  static const webSite = 'gleec.com';

  /// A backup passkey must be unreachable from the web wallet: a page there
  /// may use its own host or any parent as the relying party. The backup
  /// host also sits outside the web wallet's domain, so a wildcard
  /// certificate or a DNS change there cannot serve a page that asks for it.
  static bool isAllowedBackupRpId(String rpId) {
    if (!_host.hasMatch(rpId)) return false;
    return rpId != webSite &&
        !rpId.endsWith('.$webSite') &&
        _apartFrom(rpId, PasskeyCredentialBackend.relyingParty) &&
        _apartFrom(rpId, unlockRpId);
  }

  /// The relying party this build's unlock passkeys use, which a test build
  /// may point at a staging web host.
  static const unlockRpId = String.fromEnvironment(
    'WALLET_PASSKEY_RP_ID',
    defaultValue: PasskeyCredentialBackend.relyingParty,
  );

  /// A web page on [web] may use [web] or any parent of it.
  static bool _apartFrom(String rpId, String web) =>
      rpId != web && !web.endsWith('.$rpId') && !rpId.endsWith('.$web');
}
