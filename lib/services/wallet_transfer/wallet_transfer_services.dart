import 'package:flutter/foundation.dart';
import 'package:web_dex/services/storage/base_storage.dart';
import 'package:web_dex/services/wallet_access/platform/passkey/passkey_authenticator.dart';
import 'package:web_dex/services/wallet_access/platform/passkey/passkey_registration.dart';
import 'package:web_dex/services/wallet_backup/passkey_backup_index.dart';
import 'package:web_dex/services/wallet_backup/passkey_backup_service.dart';
import 'package:web_dex/services/wallet_backup/passkey_backup_types.dart';
import 'package:web_dex/services/wallet_backup/stores/google_drive_authorizer.dart';
import 'package:web_dex/services/wallet_backup/stores/google_drive_backup_store.dart';
import 'package:web_dex/services/wallet_backup/stores/icloud_keychain_backup_store.dart';
import 'package:web_dex/services/wallet_move/wallet_move_protocol.dart';
import 'package:web_dex/services/wallet_move/wallet_move_types.dart';
import 'package:web_dex/services/wallet_transfer/wallet_transfer_config.dart';

/// The move and backup services for this build and platform, or null where
/// one cannot work, so the screens never offer it there.
({WalletMoveProtocol? move, PasskeyBackupController? backup})
createWalletTransferServices({
  required WalletTransferConfig config,
  required BaseStorage storage,
  TargetPlatform? platform,
}) {
  final target = kIsWeb ? null : (platform ?? defaultTargetPlatform);
  final phone =
      target == TargetPlatform.iOS || target == TargetPlatform.android;
  final backupPlatform = phone || target == TargetPlatform.macOS;
  return (
    move: config.moveEnabled && phone ? WalletMoveProtocolV1() : null,
    backup: config.passkeyBackupConfigured && backupPlatform
        ? PasskeyBackupService(
            config: config,
            registrar: MethodChannelPasskeyRegistrar(),
            authenticator: MethodChannelPasskeyAuthenticator(),
            stores: {
              if (target != TargetPlatform.android)
                BackupStoreKind.iCloudKeychain: ICloudKeychainBackupStore(),
              BackupStoreKind.googleDrive: GoogleDriveBackupStore(
                authorizer: PlatformGoogleDriveAuthorizer(config: config),
              ),
            },
            index: PasskeyBackupIndex(storage: storage),
          )
        : null,
  );
}
