import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:web_dex/shared/swap/lifi_integrator_policy.dart';

void main() {
  test(
    'wallet supplies confirmed commission while reusable SDK defaults unset',
    () {
      expect(const KomodoDefiSdkConfig().lifiIntegrator, isNull);
      final policy = gleecLifiIntegratorConfig()!;
      expect(policy.toJson(), {
        'name': 'gleec-dex-staging',
        'fee_bps': 178,
        'lifi_fee_bps': 22,
      });
      final sdk = const KomodoDefiSdkConfig().copyWith(lifiIntegrator: policy);
      expect(sdk.copyWith().lifiIntegrator, policy);
      expect(sdk.copyWith(clearLifiIntegrator: true).lifiIntegrator, isNull);
    },
  );
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
