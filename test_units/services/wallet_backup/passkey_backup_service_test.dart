import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/services/storage/base_storage.dart';
import 'package:web_dex/services/wallet_access/platform/passkey/passkey_authenticator.dart';
import 'package:web_dex/services/wallet_access/platform/passkey/passkey_registration_types.dart';
import 'package:web_dex/services/wallet_access/wallet_access_types.dart';
import 'package:web_dex/services/wallet_backup/passkey_backup_index.dart';
import 'package:web_dex/services/wallet_backup/passkey_backup_record.dart';
import 'package:web_dex/services/wallet_backup/passkey_backup_service.dart';
import 'package:web_dex/services/wallet_backup/passkey_backup_types.dart';
import 'package:web_dex/services/wallet_transfer/wallet_transfer_config.dart';
import 'package:web_dex/services/wallet_transfer/wallet_transfer_secret.dart';

part 'passkey_backup_service_create_cases.dart';
part 'passkey_backup_service_fakes.dart';
part 'passkey_backup_service_index_cases.dart';
part 'passkey_backup_service_restore_cases.dart';

void main() {
  group('passkey backup creation', _createCases);
  group('passkey backup restore', _restoreCases);
  group('passkey backup availability', _availabilityCases);
  group('passkey backup index', _indexCases);
}
