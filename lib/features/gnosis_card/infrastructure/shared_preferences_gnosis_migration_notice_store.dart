import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_ports.dart';

/// Persists one-time migration acknowledgements without storing wallet IDs,
/// owner addresses, or provider migration references in plaintext.
class SharedPreferencesGnosisMigrationNoticeStore
    implements GnosisMigrationNoticeStore {
  static const _keyPrefix = 'gnosis_card_migration_notice_v1';

  @override
  Future<bool> isDismissed({
    required String walletIdentity,
    required String migrationId,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    return preferences.getBool(_key(walletIdentity, migrationId)) ?? false;
  }

  @override
  Future<void> dismiss({
    required String walletIdentity,
    required String migrationId,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_key(walletIdentity, migrationId), true);
  }

  String _key(String walletIdentity, String migrationId) {
    final walletHash = sha256.convert(utf8.encode(walletIdentity));
    final migrationHash = sha256.convert(utf8.encode(migrationId));
    return '${_keyPrefix}_${walletHash}_$migrationHash';
  }
}
