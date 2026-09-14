import 'dart:async';
import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/security_settings/private_key_export_bloc.dart';
import 'package:web_dex/bloc/security_settings/private_key_export_event.dart';
import 'package:web_dex/bloc/security_settings/private_key_export_state.dart';
import 'package:web_dex/services/security/private_key_export_delivery.dart';
import 'package:web_dex/services/security/private_key_export_service.dart';

import '../../services/security/private_key_export_test_support.dart';

void main() => testPrivateKeyExportBloc();

void testPrivateKeyExportBloc() {
  group('PrivateKeyExportBloc', () {
    late FakePrivateKeyExportService service;
    late FakePrivateKeyExportDelivery delivery;
    late PrivateKeyExportBloc bloc;

    setUp(() {
      service = FakePrivateKeyExportService();
      delivery = FakePrivateKeyExportDelivery();
      bloc = PrivateKeyExportBloc(
        service: service,
        delivery: delivery,
        permanentlyExcludedAssetIds: const {'NFT_ETH'},
      );
    });
    tearDown(() async {
      if (!bloc.isClosed) await bloc.close();
      await service.changes.close();
    });

    Future<void> request({Set<AssetId> blocked = const {}}) async {
      bloc.add(PrivateKeyExportRequested(blockedAssets: blocked));
      await flushExportEvents();
      expect(bloc.state.phase, PrivateKeyExportPhase.awaitingPassword);
    }

    Future<void> ready({Set<AssetId> blocked = const {}}) async {
      await request(blocked: blocked);
      bloc.add(
        PrivateKeyExportPasswordSubmitted(
          bloc.state.operationId,
          SensitiveString(exportPasswordSentinel),
        ),
      );
      await flushExportEvents();
      expect(bloc.state.phase, PrivateKeyExportPhase.ready);
    }

    Future<void> reveal() async {
      bloc.add(const PrivateKeyExportVisibilityChanged(true));
      await flushExportEvents();
    }

    test('wrong password stays in prompt; no secrets in diagnostics', () async {
      service.authenticationError = const PrivateKeyExportException(
        PrivateKeyExportError.incorrectPassword,
      );
      await request();
      final event = PrivateKeyExportPasswordSubmitted(
        bloc.state.operationId,
        SensitiveString(exportPasswordSentinel),
      );
      bloc.add(event);
      await flushExportEvents();
      expect(bloc.state.phase, PrivateKeyExportPhase.awaitingPassword);
      expect(bloc.state.error, PrivateKeyExportError.incorrectPassword);
      expect(bloc.state.result, isNull);
      service.authenticationError = null;
      bloc.add(event);
      await flushExportEvents();
      expect(bloc.state.phase, PrivateKeyExportPhase.ready);
      EquatableConfig.stringify = true;
      addTearDown(() => EquatableConfig.stringify = false);
      expect(
        '$event ${bloc.state} ${bloc.state.props}',
        isNot(contains(exportPasswordSentinel)),
      );
      expect(
        '${bloc.state} ${bloc.state.props}',
        isNot(contains(exportKeySentinel)),
      );
      expect(bloc.state.showKeys, isFalse);
      expect(bloc.state.hasExported, isFalse);
    });

    test(
      'duplicate submit exports once; cancel discards late result',
      () async {
        service.pendingExport = Completer<PrivateKeyExportResult>();
        await request();
        final event = PrivateKeyExportPasswordSubmitted(
          bloc.state.operationId,
          SensitiveString(exportPasswordSentinel),
        );
        bloc
          ..add(event)
          ..add(event);
        await flushExportEvents();
        expect(service.authentications, 1);
        bloc.add(const PrivateKeyExportCancelled());
        await flushExportEvents();
        service.pendingExport!.complete(exportTestResult());
        await flushExportEvents();
        expect(bloc.state.phase, PrivateKeyExportPhase.idle);
        expect(bloc.state.result, isNull);
      },
    );

    test('auth epoch invalidates displayed keys and QR immediately', () async {
      await ready();
      await reveal();
      final asset = exportTestAsset('BTC');
      bloc.add(PrivateKeyExportKeyVisibilityToggled(asset, 0));
      bloc.add(PrivateKeyExportQrRequested(asset, 0));
      await flushExportEvents();
      expect(bloc.state.revealedKeys, isNotEmpty);
      expect(bloc.state.qrKey, isNotNull);
      service.current = false;
      service.changes.add(null);
      await flushExportEvents();
      expect(bloc.state.phase, PrivateKeyExportPhase.idle);
      expect(bloc.state.result, isNull);
      expect(bloc.state.qrKey, isNull);
      expect(bloc.state.revealedKeys, isEmpty);
    });

    test('hiding wins over an outstanding reveal check', () async {
      await ready();
      service.pendingCheck = Completer<void>();
      bloc.add(const PrivateKeyExportVisibilityChanged(true));
      await flushExportEvents();
      bloc.add(const PrivateKeyExportVisibilityChanged(false));
      await flushExportEvents();
      service.pendingCheck!.complete();
      await flushExportEvents();
      expect(bloc.state.showKeys, isFalse);
      expect(bloc.state.hasExported, isFalse);
    });

    test(
      'session is rechecked for reveal even without a stream event',
      () async {
        await ready();
        service.current = false;
        await reveal();
        expect(bloc.state.phase, PrivateKeyExportPhase.failed);
        expect(bloc.state.error, PrivateKeyExportError.sessionChanged);
        expect(bloc.state.result, isNull);
      },
    );

    test(
      'same-wallet logout while picker is open prevents file delivery',
      () async {
        await ready();
        await reveal();
        delivery.picker = Completer<void>();
        bloc.add(
          const PrivateKeyExportDeliveryRequested(
            PrivateKeyExportAction.download,
          ),
        );
        await flushExportEvents();
        expect(bloc.state.isDelivering, isTrue);
        service.current = false;
        service.changes.add(null);
        await flushExportEvents();
        delivery.picker!.complete();
        await flushExportEvents();
        expect(delivery.delivered, isNull);
        expect(bloc.state.result, isNull);
        expect(bloc.state.hasExported, isFalse);
      },
    );

    for (final closeWithHide in [false, true]) {
      test(
        'pending QR respects ${closeWithHide ? 'hide and re-enable' : 'close'} intent',
        () async {
          await ready();
          await reveal();
          service.pendingCheck = Completer<void>();
          bloc.add(PrivateKeyExportQrRequested(exportTestAsset('BTC'), 0));
          await flushExportEvents();
          if (closeWithHide) {
            bloc.add(const PrivateKeyExportVisibilityChanged(false));
            bloc.add(const PrivateKeyExportVisibilityChanged(true));
          } else {
            bloc.add(const PrivateKeyExportQrClosed());
          }
          await flushExportEvents();
          service.pendingCheck!.complete();
          await flushExportEvents();
          expect(bloc.state.showKeys, isTrue);
          expect(bloc.state.qrKey, isNull);
        },
      );
    }

    for (final outcome in PrivateKeyExportDeliveryOutcome.values) {
      test('delivery ${outcome.name} has honest completion status', () async {
        await ready();
        await reveal();
        expect(bloc.state.hasExported, isFalse);
        delivery.outcome = outcome;
        bloc.add(
          const PrivateKeyExportDeliveryRequested(
            PrivateKeyExportAction.download,
          ),
        );
        await flushExportEvents();
        expect(bloc.state.deliveryOutcome, outcome);
        expect(
          bloc.state.hasExported,
          outcome == PrivateKeyExportDeliveryOutcome.completed,
        );
      });
    }

    test(
      'copy contains only displayed assets with explicit coverage',
      () async {
        await ready(blocked: {exportTestAsset('ETH')});
        await reveal();
        bloc.add(
          const PrivateKeyExportDeliveryRequested(PrivateKeyExportAction.copy),
        );
        await flushExportEvents();
        final json =
            jsonDecode(delivery.delivered!.value) as Map<String, dynamic>;
        expect(json['version'], 1);
        expect(json['complete_for_displayed_assets'], isFalse);
        expect(json, isNot(contains('contains_active_address_only')));
        final assets = json['assets'] as List<dynamic>;
        expect(assets.map((a) => a['asset_id']['coin']), [
          'BTC',
          'TRX',
          'USDT-TRC20',
          'UNAVAILABLE',
        ]);
        expect(assets.first['coverage']['end_index'], 10);
        expect(
          delivery.delivered.toString(),
          isNot(contains(exportKeySentinel)),
        );
      },
    );

    test('blocked single-key copy cannot bypass displayed selection', () async {
      await ready(blocked: {exportTestAsset('ETH')});
      await reveal();
      bloc.add(
        PrivateKeyExportDeliveryRequested(
          PrivateKeyExportAction.copy,
          assetId: exportTestAsset('ETH'),
          keyIndex: 0,
        ),
      );
      await flushExportEvents();
      expect(delivery.calls, 0);
    });

    for (final assetName in ['TRX', 'USDT-TRC20']) {
      test('$assetName has no reveal, QR or single-key delivery', () async {
        await ready();
        await reveal();
        final asset = exportTestAsset(assetName);
        expect(bloc.state.canDeliver, isTrue);
        expect(bloc.state.keyAt(asset, 0), isNull);
        bloc
          ..add(PrivateKeyExportKeyVisibilityToggled(asset, 0))
          ..add(PrivateKeyExportQrRequested(asset, 0));
        for (final action in PrivateKeyExportAction.values) {
          bloc.add(
            PrivateKeyExportDeliveryRequested(
              action,
              assetId: asset,
              keyIndex: 0,
            ),
          );
        }
        await flushExportEvents();
        expect(bloc.state.revealedKeys, isEmpty);
        expect(bloc.state.qrKey, isNull);
        expect(delivery.calls, 0);
      });
    }

    for (final action in PrivateKeyExportAction.values) {
      test('${action.name} includes only supported keys', () async {
        await ready();
        await reveal();
        bloc.add(PrivateKeyExportDeliveryRequested(action));
        await flushExportEvents();
        final json =
            jsonDecode(delivery.delivered!.value) as Map<String, dynamic>;
        final assets = json['assets'] as List<dynamic>;
        final withKeys = assets.where(
          (asset) => (asset['keys'] as List).isNotEmpty,
        );
        expect(withKeys.map((asset) => asset['asset_id']['coin']), [
          'BTC',
          'ETH',
        ]);
        for (final asset in assets.where(
          (asset) => ['TRX', 'USDT-TRC20'].contains(asset['asset_id']['coin']),
        )) {
          expect(asset['keys'], isEmpty);
          expect(asset['unavailable_reason'], 'unsupportedProtocol');
        }
      });
    }

    test('a TRON-only wallet cannot deliver an empty export', () async {
      service.result = PrivateKeyExportResult(
        outcomes: exportTestResult().outcomes
            .where(
              (outcome) =>
                  outcome.assetId.subClass == CoinSubClass.trx ||
                  outcome.assetId.subClass == CoinSubClass.trc20,
            )
            .toList(),
      );
      await ready();
      await reveal();
      expect(bloc.state.canDeliver, isFalse);
      for (final action in PrivateKeyExportAction.values) {
        bloc.add(PrivateKeyExportDeliveryRequested(action));
      }
      await flushExportEvents();
      expect(delivery.calls, 0);
    });

    test(
      'geo-block inclusion never enables permanently excluded assets',
      () async {
        final nft = exportTestAsset('NFT_ETH');
        service.result = PrivateKeyExportResult(
          outcomes: [
            ...exportTestResult().outcomes,
            PrivateKeyExportOutcome.unavailable(
              assetId: nft,
              failure: PrivateKeyExportFailure.unsupportedProtocol,
            ),
          ],
        );
        await ready(blocked: {exportTestAsset('ETH'), nft});
        expect(bloc.state.displayedOutcomes.map((o) => o.assetId.id), [
          'BTC',
          'TRX',
          'USDT-TRC20',
          'UNAVAILABLE',
        ]);
        bloc.add(const PrivateKeyExportBlockedAssetsChanged(true));
        await flushExportEvents();
        expect(bloc.state.displayedOutcomes.map((o) => o.assetId.id), [
          'BTC',
          'ETH',
          'TRX',
          'USDT-TRC20',
          'UNAVAILABLE',
        ]);
        await reveal();
        bloc.add(
          const PrivateKeyExportDeliveryRequested(PrivateKeyExportAction.copy),
        );
        await flushExportEvents();
        final json =
            jsonDecode(delivery.delivered!.value) as Map<String, dynamic>;
        expect(
          (json['assets'] as List<dynamic>).map((a) => a['asset_id']['coin']),
          ['BTC', 'ETH', 'TRX', 'USDT-TRC20', 'UNAVAILABLE'],
        );
        expect(json['excluded_assets'], ['NFT_ETH']);
      },
    );

    test('close discards late results and the final retained state', () async {
      service.pendingExport = Completer<PrivateKeyExportResult>();
      await request();
      bloc.add(
        PrivateKeyExportPasswordSubmitted(
          bloc.state.operationId,
          SensitiveString(exportPasswordSentinel),
        ),
      );
      await flushExportEvents();
      final closing = bloc.close();
      service.pendingExport!.complete(exportTestResult());
      await closing;
      expect(bloc.state.result, isNull);
      expect(bloc.state.phase, PrivateKeyExportPhase.idle);
    });
  });
}

Future<void> flushExportEvents() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
