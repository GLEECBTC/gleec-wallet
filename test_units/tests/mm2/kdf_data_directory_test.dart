// The analyzer does not treat test_units as tests, so MM2.createSdk's
// @visibleForTesting reads as a violation here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:web_dex/app_config/kdf_data_directory.dart';
import 'package:web_dex/mm2/mm2.dart';

class _Sdk extends Fake implements KomodoDefiSdk {}

void main() {
  // A rename would start KDF in an empty folder on every desktop that had
  // already moved its data.
  test('KDF data folders keep their names', () {
    expect(gleecKdfDesktopDataDirectory.windowsFolder, 'Gleec');
    expect(gleecKdfDesktopDataDirectory.linuxFolder, 'com.gleec.GleecDEX');
  });

  test('the SDK is told where KDF data lives', () {
    final createSdk = MM2.createSdk;
    addTearDown(() => MM2.createSdk = createSdk);
    KomodoDefiSdkConfig? passed;
    MM2.createSdk = ({config, onLog}) {
      passed = config;
      return _Sdk();
    };

    MM2();

    expect(passed?.desktopDataDirectory, gleecKdfDesktopDataDirectory);
  });
}
