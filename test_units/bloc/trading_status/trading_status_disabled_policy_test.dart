import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:web_dex/bloc/trading_status/trading_status_api_provider.dart';
import 'package:web_dex/bloc/trading_status/trading_status_repository.dart';
import 'package:web_dex/bloc/trading_status/trading_status_service.dart';

class _UnusedSdk extends Fake implements KomodoDefiSdk {}

void main() {
  test(
    'explicit GEO_BLOCK=disabled publishes ready unrestricted without network',
    () async {
      var requests = 0;
      final client = MockClient((_) async {
        requests++;
        throw StateError('The disabled policy must not request remote data');
      });
      final repository = TradingStatusRepository(
        _UnusedSdk(),
        apiProvider: TradingStatusApiProvider(httpClient: client),
      );
      final policy = ActivationPolicy();
      final service = TradingStatusService(
        repository,
        activationPolicy: policy,
      );
      addTearDown(() async {
        service.dispose();
        repository.dispose();
        await policy.dispose();
      });

      await service.initialize();
      expect(service.isActivationReady, isTrue);
      expect(service.isTradingEnabled, isTrue);
      expect(policy.current.status, ActivationPolicyStatus.ready);
      expect(policy.current.blockedAssets, isEmpty);
      // Explicit disable also takes precedence over the diagnostic failure path.
      final forced = await repository.fetchStatus(forceFail: true);
      expect(forced.lookupStatus, ActivationPolicyStatus.ready);
      expect(forced.disallowedFeatures, isEmpty);
      expect(forced.disallowedAssets, isEmpty);
      expect(requests, 0);
    },
    skip: const String.fromEnvironment('GEO_BLOCK') == 'disabled'
        ? false
        : 'Run this file with --dart-define=GEO_BLOCK=disabled',
  );
}
