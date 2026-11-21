import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/trading_status/app_geo_status.dart';
import 'package:web_dex/bloc/trading_status/disallowed_feature.dart';
import 'package:web_dex/bloc/trading_status/trading_status_repository.dart';
import 'package:web_dex/bloc/trading_status/trading_status_service.dart';

class _Repository implements TradingStatusRepository {
  late Future<AppGeoStatus> Function() answer;
  int calls = 0;

  @override
  Future<AppGeoStatus> fetchStatus({bool? forceFail}) {
    calls++;
    return answer();
  }

  @override
  Future<bool> isTradingEnabled({bool? forceFail}) async =>
      (await fetchStatus(forceFail: forceFail)).tradingEnabled;

  @override
  void dispose() {}
}

final _parent = Asset.fromJson({
  'coin': 'TRX',
  'type': 'TRX',
  'name': 'TRON',
  'fname': 'TRON',
  'decimals': 6,
  'derivation_path': "m/44'/195'",
  'protocol': {
    'type': 'TRX',
    'protocol_data': {'network': 'Mainnet'},
  },
  'nodes': <Map<String, dynamic>>[],
}, knownIds: const {});

final _child = Asset.fromJson(
  {
    'coin': 'USDT-TRC20',
    'type': 'TRC-20',
    'name': 'Tether',
    'fname': 'Tether',
    'decimals': 6,
    'derivation_path': "m/44'/195'",
    'protocol': {
      'type': 'TRC20',
      'protocol_data': {
        'platform': 'TRX',
        'contract_address': 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
      },
    },
    'parent_coin': 'TRX',
    'nodes': <Map<String, dynamic>>[],
  },
  knownIds: {_parent.id},
);

void main() {
  group('TradingStatusService policy recovery', () {
    late _Repository repository;
    late ActivationPolicy policy;
    late TradingStatusService service;

    setUp(() {
      repository = _Repository();
      policy = ActivationPolicy();
      service = TradingStatusService(
        repository,
        activationPolicy: policy,
        lookupTimeout: const Duration(seconds: 2),
        retryInterval: const Duration(seconds: 3),
        pollingInterval: const Duration(seconds: 10),
      );
    });

    tearDown(() async {
      service.dispose();
      await policy.dispose();
    });

    test('starts gated and deduplicates concurrent first lookups', () async {
      final answer = Completer<AppGeoStatus>();
      repository.answer = () => answer.future;

      expect(
        service.currentStatus.lookupStatus,
        ActivationPolicyStatus.loading,
      );
      expect(service.isTradingEnabled, isFalse);
      expect(policy.current.canActivate(_parent.id), isFalse);
      final first = service.refreshStatus();
      final second = service.refreshStatus();
      expect(identical(first, second), isTrue);
      expect(repository.calls, 1);

      answer.complete(const AppGeoStatus());
      await first;
      await service.initialStatusReady;
      expect(service.isTradingEnabled, isTrue);
      expect(policy.current.canActivate(_parent.id), isTrue);
    });

    test(
      'timeout settles initialization, then retries without a late overwrite',
      () {
        fakeAsync((clock) {
          service.dispose();
          service = TradingStatusService(
            repository,
            activationPolicy: policy,
            lookupTimeout: const Duration(seconds: 2),
            retryInterval: const Duration(seconds: 3),
            pollingInterval: const Duration(seconds: 10),
          );
          final stale = Completer<AppGeoStatus>();
          var calls = 0;
          repository.answer = () {
            calls++;
            return calls == 1
                ? stale.future
                : Future.value(AppGeoStatus(disallowedAssets: {_parent.id}));
          };
          var initialized = false;
          var settled = false;
          unawaited(service.initialize().then((_) => initialized = true));
          unawaited(service.initialStatusReady.then((_) => settled = true));
          clock.flushMicrotasks();
          expect(calls, 1);
          clock.elapse(const Duration(seconds: 2));
          expect(initialized, isTrue);
          expect(settled, isTrue);
          expect(policy.current.status, ActivationPolicyStatus.unavailable);
          expect(policy.current.canActivate(_parent.id), isFalse);

          clock.elapse(const Duration(seconds: 3));
          expect(calls, 2);
          expect(service.isActivationReady, isTrue);
          expect(policy.current.isBlocked(_child.id), isTrue);

          stale.complete(const AppGeoStatus());
          clock.flushMicrotasks();
          expect(policy.current.isBlocked(_parent.id), isTrue);
          expect(policy.current.status, ActivationPolicyStatus.ready);
          service.dispose();
          clock.flushMicrotasks();
          expect(clock.nonPeriodicTimerCount, 0);
        });
      },
    );

    test(
      'keeps parent and feature restrictions through loading and failure',
      () {
        fakeAsync((clock) {
          final refresh = Completer<AppGeoStatus>();
          var calls = 0;
          repository.answer = () {
            calls++;
            return switch (calls) {
              1 => Future.value(
                AppGeoStatus(
                  disallowedAssets: {_parent.id},
                  disallowedFeatures: const {DisallowedFeature.trading},
                ),
              ),
              2 => refresh.future,
              _ => Future.value(const AppGeoStatus()),
            };
          };
          unawaited(service.initialize());
          clock.flushMicrotasks();
          expect(service.isAssetBlocked(_child.id), isTrue);
          expect(service.isTradingEnabled, isFalse);

          clock.elapse(const Duration(seconds: 10));
          expect(policy.current.status, ActivationPolicyStatus.loading);
          expect(service.isAssetBlocked(_child.id), isTrue);
          refresh.completeError(StateError('offline'));
          clock.flushMicrotasks();
          expect(policy.current.status, ActivationPolicyStatus.unavailable);
          expect(policy.current.isBlocked(_child.id), isTrue);
          expect(service.isTradingEnabled, isFalse);
          expect(service.filterAllowedAssets([_parent, _child]), isEmpty);

          clock.elapse(const Duration(seconds: 3));
          expect(policy.current.status, ActivationPolicyStatus.ready);
          expect(policy.current.canActivate(_child.id), isTrue);
          expect(service.isTradingEnabled, isTrue);
          service.dispose();
          clock.flushMicrotasks();
        });
      },
    );

    test('disposal prevents late publication and any further polling', () {
      fakeAsync((clock) {
        final answer = Completer<AppGeoStatus>();
        repository.answer = () => answer.future;
        final states = <ActivationPolicyStatus>[];
        final subscription = service.statusStream.listen(
          (status) => states.add(status.lookupStatus),
        );
        unawaited(service.initialize());
        clock.flushMicrotasks();
        service.dispose();
        answer.complete(const AppGeoStatus());
        clock.flushMicrotasks();
        clock.elapse(const Duration(minutes: 1));
        expect(states, [ActivationPolicyStatus.loading]);
        expect(policy.current.status, ActivationPolicyStatus.loading);
        expect(clock.nonPeriodicTimerCount, 0);
        expect(service.refreshStatus, throwsStateError);
        expect(repository.calls, 1);
        unawaited(subscription.cancel());
        clock.flushMicrotasks();
      });
    });
  });
}
