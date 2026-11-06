import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:web_dex/shared/constants.dart';
import 'package:web_dex/shared/swap/lifi_integrator_policy.dart';

void main() {
  test(
    'wallet supplies confirmed commission while reusable SDK defaults unset',
    () {
      expect(const KomodoDefiSdkConfig().lifiIntegrator, isNull);
      final policy = gleecLifiIntegratorConfig(
        enabled: 'true',
        name: 'gleec-dex-production',
        feeBps: '178',
        lifiFeeBps: '22',
      )!;
      expect(policy.toJson(), {
        'name': 'gleec-dex-production',
        'fee_bps': 178,
        'lifi_fee_bps': 22,
      });
      final sdk = const KomodoDefiSdkConfig().copyWith(lifiIntegrator: policy);
      expect(sdk.copyWith().lifiIntegrator, policy);
      expect(sdk.copyWith(clearLifiIntegrator: true).lifiIntegrator, isNull);
    },
  );
  test('compiled LI.FI profile reaches SDK and KDF startup fields', () async {
    // CI supplies this independently of the file being tested, so missing or
    // overridden production defines cannot be mistaken for a passing fixture.
    const environment = String.fromEnvironment(
      'LIFI_TEST_EXPECTED_ENVIRONMENT',
      defaultValue: 'production',
    );
    expect(environment, 'production');
    final expected = {
      'name': 'gleec-dex-$environment',
      'fee_bps': 178,
      'lifi_fee_bps': 22,
    };
    final sdk = KomodoDefiSdkConfig(
      lifiIntegrator: gleecLifiIntegratorConfig(),
      lifiProxyUrl: validatedLifiProxyUrl(lifiProxyUrl),
    );
    expect(sdk.lifiIntegrator?.toJson(), expected);
    expect(sdk.lifiProxyUrl, 'https://quicknode.gleec.com/lifi');
    final home = await Directory.systemTemp.createTemp('lifi-policy-test-');
    addTearDown(() => home.delete(recursive: true));
    final startup = await KdfStartupConfig.generateWithDefaults(
      walletName: 'public-test-fixture',
      walletPassword: 'public-test-fixture',
      rpcPassword: 'public-test-fixture',
      enableHd: false,
      coinsPath: 'coins',
      userHome: home.path,
      dbDir: '${home.path}/db',
      seedNodes: const ['seed01.kmdefi.net'],
      lifiIntegrator: sdk.lifiIntegrator,
      lifiProxyUrl: sdk.lifiProxyUrl,
    );
    final params = startup.encodeStartParams();
    expect(params['lifi_integrator'], expected);
    expect(params['lifi_proxy_url'], sdk.lifiProxyUrl);
    expect(params, isNot(contains('lifi_api_key')));
  });
  test(
    'explicit disable omits policy and build overrides replace defaults',
    () {
      expect(gleecLifiIntegratorConfig(enabled: 'false'), isNull);
      expect(
        gleecLifiIntegratorConfig(
          name: 'another-integrator',
          feeBps: '100',
          lifiFeeBps: '20',
        )!.toJson(),
        {'name': 'another-integrator', 'fee_bps': 100, 'lifi_fee_bps': 20},
      );
    },
  );
  test(
    'invalid deployment settings fail instead of silently disabling fees',
    () {
      for (final bad in ['yes', '', '0']) {
        expect(
          () => gleecLifiIntegratorConfig(enabled: bad),
          throwsArgumentError,
        );
      }
      for (final bad in ['', 'lifi', ' lifi ']) {
        expect(() => gleecLifiIntegratorConfig(name: bad), throwsArgumentError);
      }
      for (final bad in ['1.78', '-1', '10000', 'invalid']) {
        expect(
          () => gleecLifiIntegratorConfig(feeBps: bad),
          throwsArgumentError,
        );
        expect(
          () => gleecLifiIntegratorConfig(lifiFeeBps: bad),
          throwsArgumentError,
        );
      }
      expect(
        () => gleecLifiIntegratorConfig(feeBps: '9990', lifiFeeBps: '10'),
        throwsArgumentError,
      );
    },
  );
}
