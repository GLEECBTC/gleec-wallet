import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:web_dex/services/wallet_backup/passkey_backup_types.dart';
import 'package:web_dex/services/wallet_backup/stores/backup_store_limits.dart';
import 'package:web_dex/services/wallet_backup/stores/google_drive_authorizer.dart';
import 'package:web_dex/services/wallet_backup/stores/google_drive_backup_store.dart';
import 'package:web_dex/services/wallet_backup/stores/icloud_keychain_backup_store.dart';
import 'package:web_dex/services/wallet_transfer/wallet_transfer_config.dart';

part 'backup_stores_authorizer_cases.dart';
part 'backup_stores_drive_cases.dart';
part 'backup_stores_keychain_cases.dart';

const _id = 'AAAAAAAAAAAAAAAAAAAAAA';
const _id2 = 'BBBBBBBBBBBBBBBBBBBBBB';
const _id3 = 'CCCCCCCCCCCCCCCCCCCCCC';

Matcher _fails(PasskeyBackupFailure failure) => throwsA(
  isA<PasskeyBackupException>()
      .having((e) => e.failure, 'failure', failure)
      // Nothing from a request, a reply or a token travels in the error.
      .having((e) => '$e', 'text', 'PasskeyBackupException(${failure.name})'),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('iCloud Keychain store', _keychainCases);
  group('Google Drive store', _driveCases);
  group('Google Drive authorizer', _authorizerCases);
}

/// Answers a channel the way a native bridge would, recording each call.
class _Bridge {
  _Bridge(this.channel) {
    _messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return reply?.call(call);
    });
  }

  final MethodChannel channel;
  final calls = <MethodCall>[];
  Object? Function(MethodCall call)? reply;

  static TestDefaultBinaryMessenger get _messenger =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// As a build without the bridge.
  void detach() => _messenger.setMockMethodCallHandler(channel, null);
}
