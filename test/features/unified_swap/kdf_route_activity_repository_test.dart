import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart' as kdf;
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:web_dex/features/unified_swap/domain/route_activity_models.dart';
import 'package:web_dex/features/unified_swap/domain/route_activity_repository.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_capability_policy.dart';
import 'package:web_dex/features/unified_swap/infrastructure/kdf_route_activity_repository.dart';

const _routeId = '00000000-0000-4000-8000-000000000051';
const _firstStageId = '00000000-0000-0000-0000-000000000002';
const _secondStageId = '00000000-0000-0000-0000-000000000003';

void main() {
  late Map<String, dynamic> vectors;
  late kdf.TradeRouteCandidate candidate;

  setUpAll(() {
    vectors =
        jsonDecode(
              File(
                'sdk/packages/komodo_defi_rpc_methods/test/fixtures/'
                'trade_route/external_liquidity_digest_vectors.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    candidate = kdf.TradeRouteCandidate.fromJson(
      _map(_map(vectors['candidate'])['value']),
    );
  });

  test(
    'forwards Activity pagination and preserves unknown identities',
    () async {
      final gateway = _FakeTradeRouteGateway()
        ..listHandler = ({required limit, state, cursor}) async {
          return kdf.ListRouteExecutionsResponse.parse({
            'mmrpc': '2.0',
            'result': {
              'executions': [
                _summaryJson(
                  activityState: 'future_activity_state',
                  fromAsset: _assetJson(
                    'ETH',
                    chainFamily: 'future_chain',
                    assetKind: 'future_asset_kind',
                  ),
                ),
              ],
              'next_cursor': 'cursor-next',
            },
          });
        };
      final manager = TradeRouteManager.withGateway(gateway: gateway);
      addTearDown(manager.dispose);
      final repository = KdfRouteActivityRepository(
        manager: manager,
        walletId: 'wallet-1',
      );

      final page = await repository.listExecutions(
        walletId: 'wallet-1',
        state: RouteActivityStatus.attentionRequired,
        cursor: 'cursor-current',
        limit: 17,
      );

      expect(gateway.listStates, [kdf.RouteActivityState.attentionRequired]);
      expect(gateway.listCursors, ['cursor-current']);

      await expectLater(
        repository.listExecutions(walletId: 'wallet-2'),
        throwsA(
          isA<RouteActivityException>().having(
            (error) => error.failure,
            'failure',
            RouteActivityFailure.invalidRequest,
          ),
        ),
      );
      expect(gateway.listCursors, ['cursor-current']);
      expect(gateway.listLimits, [17]);
      expect(page.nextCursor, 'cursor-next');
      expect(page.executions.single.status, RouteActivityStatus.unknown);
      expect(
        page.executions.single.rawStatusDiscriminator,
        'future_activity_state',
      );
      expect(
        page.executions.single.source.chainFamily,
        UnifiedSwapChainFamily.unknown,
      );
      expect(
        page.executions.single.source.rawChainFamilyDiscriminator,
        'future_chain',
      );
      expect(
        page.executions.single.source.rawKindDiscriminator,
        'future_asset_kind',
      );

      await expectLater(
        repository.listExecutions(walletId: 'wallet-1', cursor: ''),
        throwsA(
          isA<RouteActivityException>().having(
            (error) => error.failure,
            'failure',
            RouteActivityFailure.invalidCursor,
          ),
        ),
      );
      expect(gateway.listCursors, ['cursor-current']);
    },
  );

  test(
    'maps exact detail, revisions, holdings, fees and safe evidence',
    () async {
      final gateway = _FakeTradeRouteGateway()
        ..getHandler = ({required routeExecutionId}) async {
          return _detailsResponse(vectors, candidate);
        };
      final manager = TradeRouteManager.withGateway(gateway: gateway);
      addTearDown(manager.dispose);
      final repository = KdfRouteActivityRepository(
        manager: manager,
        walletId: 'wallet-1',
      );

      final detail = await repository.getExecution(
        walletId: 'wallet-1',
        routeExecutionId: _routeId,
      );

      expect(gateway.requestedRouteIds, [_routeId]);
      expect(detail.summary.status, RouteActivityStatus.attentionRequired);
      expect(detail.summary.source.chainFamily, UnifiedSwapChainFamily.evm);
      expect(detail.summary.createdAt, DateTime.utc(2026, 7, 16, 12));
      expect(detail.summary.updatedAt, DateTime.utc(2026, 7, 16, 12, 10));

      final consent = detail.consent;
      expect(consent.routeExecutionId, _routeId);
      expect(consent.consentDigest, 'excluded');
      expect(
        consent.candidateDigest,
        '2222222222222222222222222222222222222222222222222222222222222222',
      );
      expect(consent.sourceAmount, '100');
      expect(consent.expectedReceive, '100000');
      expect(consent.minimumReceive, '90000');
      expect(consent.resolvedSourceAddress, '0xresolved');
      expect(consent.recipient, '0x2222222222222222222222222222222222222222');
      expect(consent.fees.single.kind, RouteFeeKind.network);
      expect(consent.fees.single.amount, '21000000000000');
      expect(consent.nonNetworkFeeLimits.single.kind, RouteFeeKind.bridge);
      expect(consent.nonNetworkFeeLimits.single.maximumAmount, '12');
      expect(consent.networkFeeCaps.single.stageId, _secondStageId);
      expect(consent.networkFeeCaps.single.maximumAmount, '10');

      expect(detail.controls.canCancel, isFalse);
      expect(detail.controls.canStopAfterCurrent, isTrue);
      expect(detail.controls.reconciliationOnly, isFalse);
      expect(detail.holding?.amount, '998000000');
      expect(detail.holding?.address, '0xholding');

      final stage = detail.stages.single;
      expect(stage.sequence, 0);
      expect(stage.stageId, _firstStageId);
      expect(stage.phase, RouteStagePhase.recovery);
      expect(stage.startedAt, DateTime.utc(2026, 7, 16, 12, 1));
      expect(stage.updatedAt, DateTime.utc(2026, 7, 16, 12, 5));
      expect(stage.transactionHashes, ['0xsource']);
      expect(stage.holding?.amount, '998000000');
      expect(stage.evidence.map((item) => item.kind), [
        RouteEvidenceKind.sourceReceipt,
        RouteEvidenceKind.providerStatus,
        RouteEvidenceKind.unknown,
      ]);
      expect(stage.evidence.map((item) => item.reference), [
        '0xsource',
        '0xreceive',
        null,
      ]);
      expect(stage.evidence.last.rawKindDiscriminator, 'future_evidence');
      expect(stage.evidence[1].status, 'DONE');
      expect(stage.evidence[1].substatus, 'PARTIAL');
      final safeEvidence = stage.evidence
          .map(
            (item) =>
                '${item.kind}:${item.reference}:${item.status}:'
                '${item.substatus}:${item.rawKindDiscriminator}',
          )
          .join('|');
      expect(safeEvidence, isNot(contains('lifi')));
      expect(safeEvidence, isNot(contains('provider-secret')));
      expect(safeEvidence, isNot(contains('raw-secret')));
      expect(safeEvidence, contains('DONE'));

      final revision = detail.revisions.single;
      expect(revision.revision, 0);
      expect(revision.phase, RouteStagePhase.completed);
      expect(revision.holding?.address, '0xrevision-holding');
      expect(revision.createdAt, DateTime.utc(2026, 7, 16, 11));
      expect(revision.updatedAt, DateTime.utc(2026, 7, 16, 11, 5));
      expect(revision.completedAt, DateTime.utc(2026, 7, 16, 11, 6));
      expect(revision.archivedAt, DateTime.utc(2026, 7, 16, 11, 7));
      expect(revision.stages.single.stageId, _secondStageId);
      expect(revision.stages.single.holding?.address, '0xrevision-holding');
    },
  );

  test('maps typed failures without retaining backend messages', () async {
    final gateway = _FakeTradeRouteGateway();
    final manager = TradeRouteManager.withGateway(gateway: gateway);
    addTearDown(manager.dispose);
    final repository = KdfRouteActivityRepository(
      manager: manager,
      walletId: 'wallet-1',
    );

    gateway.listHandler = ({required limit, state, cursor}) async {
      throw _rpcError(
        type: 'InvalidRequest',
        data: {'field': 'cursor', 'reason': 'raw-secret-cursor-message'},
      );
    };
    await _expectFailure(
      repository.listExecutions(walletId: 'wallet-1', cursor: 'bad-cursor'),
      RouteActivityFailure.invalidCursor,
    );

    gateway.getHandler = ({required routeExecutionId}) async {
      throw _rpcError(
        type: 'RouteNotFound',
        data: {'route_execution_id': routeExecutionId},
      );
    };
    await _expectFailure(
      repository.getExecution(walletId: 'wallet-1', routeExecutionId: _routeId),
      RouteActivityFailure.notFound,
    );

    gateway.getHandler = ({required routeExecutionId}) async {
      throw _rpcError(
        type: 'PersistenceError',
        data: {'operation': 'raw-secret-storage-message'},
      );
    };
    await _expectFailure(
      repository.getExecution(walletId: 'wallet-1', routeExecutionId: _routeId),
      RouteActivityFailure.storageUnavailable,
    );

    gateway.getHandler = ({required routeExecutionId}) async {
      throw const kdf.Web3RpcErrorTransportException(
        'raw-secret-transport-message',
      );
    };
    await _expectFailure(
      repository.getExecution(walletId: 'wallet-1', routeExecutionId: _routeId),
      RouteActivityFailure.serviceUnavailable,
    );
  });
}

Future<void> _expectFailure(
  Future<Object?> operation,
  RouteActivityFailure expected,
) async {
  try {
    await operation;
    fail('Expected RouteActivityException');
  } on RouteActivityException catch (error) {
    expect(error.failure, expected);
    expect(error.toString(), isNot(contains('raw-secret')));
  }
}

kdf.GeneralErrorResponse _rpcError({
  required String type,
  required Object data,
}) => kdf.GeneralErrorResponse(
  mmrpc: '2.0',
  error: 'raw-secret-error-message',
  errorPath: null,
  errorTrace: null,
  errorType: type,
  errorData: data,
  object: const {},
);

kdf.RouteExecutionDetailsResponse _detailsResponse(
  Map<String, dynamic> vectors,
  kdf.TradeRouteCandidate candidate,
) {
  final consent = _activityConsent(vectors);
  final holding = _holdingJson('0xholding');
  final currentStage = _stageResultJson(
    stageId: _firstStageId,
    routePhase: 'partial',
    holding: holding,
    receivingEvidence: {
      'evidence_type': 'provider_status',
      'provider': 'lifi',
      'transaction_id': 'provider-secret-transaction',
      'tool': 'provider-secret-tool',
      'from_address': '0xprovider-secret-from',
      'to_address': '0xprovider-secret-to',
      'sending': null,
      'receiving': {
        'tx_hash': '0xreceive',
        'chain_id': '1',
        'amount': '998000000',
        'token': null,
      },
    },
    refundEvidence: {
      'evidence_type': 'future_evidence',
      'opaque': 'raw-secret-provider-payload',
    },
    sourceReceipt: _receiptJson(),
    startedAt: '2026-07-16T12:01:00Z',
    updatedAt: '2026-07-16T12:05:00Z',
  );
  final revisionHolding = _holdingJson('0xrevision-holding');
  final revisionStatus = _statusJson(
    phase: 'destination_confirmed',
    routePhase: 'completed',
    holding: revisionHolding,
    stageResults: const [],
    canCancel: false,
    canStopAfterCurrent: false,
    createdAt: '2026-07-16T11:00:00Z',
    updatedAt: '2026-07-16T11:05:00Z',
    completedAt: '2026-07-16T11:06:00Z',
  );
  final revisionStage = _stageResultJson(
    stageId: _secondStageId,
    routePhase: 'completed',
    holding: revisionHolding,
    receivingEvidence: {
      'evidence_type': 'external_action',
      'action_digest': 'revision-action-digest',
    },
    refundEvidence: null,
    sourceReceipt: null,
    startedAt: '2026-07-16T11:01:00Z',
    updatedAt: '2026-07-16T11:05:00Z',
    completedAt: '2026-07-16T11:06:00Z',
  );

  return kdf.RouteExecutionDetailsResponse.parse({
    'mmrpc': '2.0',
    'result': {
      'route_execution_id': _routeId,
      'activity_state': 'attention_required',
      'route_consent': consent,
      'candidate': candidate.toJson(),
      'resolved_source_address': '0xresolved',
      'recipient_address': '0x2222222222222222222222222222222222222222',
      'status': _statusJson(
        phase: 'manual_intervention',
        routePhase: 'manual_intervention',
        holding: holding,
        stageResults: [currentStage],
        canCancel: false,
        canStopAfterCurrent: true,
        createdAt: '2026-07-16T12:00:00Z',
        updatedAt: '2026-07-16T12:10:00Z',
        completedAt: null,
      ),
      'route_revisions': [
        {
          'revision': 0,
          'route_consent': _deepCopy(consent),
          'candidate': candidate.toJson(),
          'resolved_source_address': '0xrevision-resolved',
          'status': revisionStatus,
          'stages': [revisionStage],
          'archived_at': '2026-07-16T11:07:00Z',
        },
      ],
      'terminal_error': null,
      'created_at': '2026-07-16T12:00:00Z',
      'updated_at': '2026-07-16T12:10:00Z',
      'completed_at': null,
    },
  });
}

Map<String, dynamic> _activityConsent(Map<String, dynamic> vectors) {
  final consent = _deepCopy(_map(_map(vectors['route_consent'])['value']));
  consent['consent_type'] = 'activity_reattachment';
  final stages = consent['external_stage_consents']! as List<dynamic>;
  for (var index = 0; index < stages.length; index++) {
    final stage = _map(stages[index]);
    stage.remove('route_intent');
    final source = _map(stage['execution_source']);
    source.remove('provider_step');
    stage['execution_source'] = source;
    final intent = _map(stage['stage_intent']);
    intent['non_network_fee_limits'] = [
      {
        'fee_type': 'bridge',
        'asset': _assetJson('USDC', assetKind: 'token'),
        'max_amount': '12',
      },
    ];
    stage['stage_intent'] = intent;
    stages[index] = stage;
  }
  return consent;
}

Map<String, dynamic> _statusJson({
  required String phase,
  required String routePhase,
  required Map<String, dynamic>? holding,
  required List<Object> stageResults,
  required bool canCancel,
  required bool canStopAfterCurrent,
  required String createdAt,
  required String updatedAt,
  required String? completedAt,
}) => {
  'route_execution_id': _routeId,
  'stage_index': 0,
  'phase': phase,
  'route_phase': routePhase,
  'state_revision': 8,
  'pending_user_action': null,
  'stop_after_current': false,
  'tx_hashes': ['0xsource'],
  'actual_holding': holding,
  'raw_provider_status': 'DONE',
  'raw_provider_substatus': 'PARTIAL',
  'receiving_evidence': null,
  'refund_evidence': null,
  'approval_recovery': null,
  'stage_results': stageResults,
  'controls': {
    'can_cancel': canCancel,
    'can_stop_after_current': canStopAfterCurrent,
    'reconciliation_only': false,
  },
  'created_at': createdAt,
  'completed_at': completedAt,
  'updated_at': updatedAt,
};

Map<String, dynamic> _stageResultJson({
  required String stageId,
  required String routePhase,
  required Map<String, dynamic>? holding,
  required Object? receivingEvidence,
  required Object? refundEvidence,
  required Object? sourceReceipt,
  required String? startedAt,
  required String? updatedAt,
  String? completedAt,
}) => {
  'stage_id': stageId,
  'route_phase': routePhase,
  'tx_hashes': ['0xsource'],
  'actual_holding': holding,
  'raw_provider_status': 'DONE',
  'raw_provider_substatus': 'PARTIAL',
  'source_receipt': sourceReceipt,
  'receiving_evidence': receivingEvidence,
  'refund_evidence': refundEvidence,
  'started_at': startedAt,
  'updated_at': updatedAt,
  'completed_at': completedAt,
};

Map<String, dynamic> _holdingJson(String address) => {
  'asset': _assetJson('USDC', assetKind: 'token'),
  'amount': '998000000',
  'address': address,
};

Map<String, dynamic> _receiptJson() => {
  'chain_family': 'evm',
  'chain_id': '1',
  'tx_hash': '0xsource',
  'status': 'confirmed',
  'confirmations': 3,
  'block_hash': '0xblock',
  'block_height': '22810000',
  'gas_used': '21000',
  'effective_gas_price': '2',
  'network_fee': null,
  'revert_reason': null,
  'observed_at': '2026-07-16T12:04:00Z',
};

Map<String, dynamic> _summaryJson({
  required String activityState,
  required Map<String, dynamic> fromAsset,
}) => {
  'route_execution_id': _routeId,
  'activity_state': activityState,
  'route_source': 'lifi',
  'from_asset': fromAsset,
  'to_asset': _assetJson('BTC', chainFamily: 'utxo'),
  'source_amount': '100',
  'expected_receive': '95',
  'minimum_receive': '90',
  'resolved_source_address': '0xresolved',
  'recipient_address': 'bc1qrecipient',
  'stage_count': 1,
  'current_stage_index': 0,
  'phase': 'planned',
  'route_phase': 'validating',
  'controls': {
    'can_cancel': false,
    'can_stop_after_current': false,
    'reconciliation_only': false,
  },
  'requires_user_attention': true,
  'requires_user_action': false,
  'actual_holding': null,
  'terminal_error': null,
  'created_at': '2026-07-16T12:00:00Z',
  'updated_at': '2026-07-16T12:01:00Z',
  'completed_at': null,
};

Map<String, dynamic> _assetJson(
  String ticker, {
  String chainFamily = 'evm',
  String assetKind = 'native',
}) => {
  'ticker': ticker,
  'chain_family': chainFamily,
  'chain_id': chainFamily == 'utxo' ? 'bitcoin-mainnet' : '1',
  'asset_kind': assetKind,
  'contract_address': assetKind == 'token'
      ? '0x1111111111111111111111111111111111111111'
      : null,
  'decimals': assetKind == 'token' ? 6 : 18,
};

Map<String, dynamic> _map(Object? value) =>
    Map<String, dynamic>.from(value! as Map);

Map<String, dynamic> _deepCopy(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

typedef _ListHandler =
    Future<kdf.ListRouteExecutionsResponse> Function({
      required int limit,
      kdf.RouteActivityState? state,
      String? cursor,
    });
typedef _GetHandler =
    Future<kdf.RouteExecutionDetailsResponse> Function({
      required String routeExecutionId,
    });

final class _FakeTradeRouteGateway implements TradeRouteRpcGateway {
  _ListHandler? listHandler;
  _GetHandler? getHandler;
  final listStates = <kdf.RouteActivityState?>[];
  final listCursors = <String?>[];
  final listLimits = <int>[];
  final requestedRouteIds = <String>[];

  @override
  Future<kdf.RouteExecutionDetailsResponse> getExecution({
    required String routeExecutionId,
  }) {
    requestedRouteIds.add(routeExecutionId);
    final handler = getHandler;
    if (handler == null) throw StateError('Unexpected getExecution call');
    return handler(routeExecutionId: routeExecutionId);
  }

  @override
  Future<kdf.ListRouteExecutionsResponse> listExecutions({
    required int limit,
    kdf.RouteActivityState? state,
    String? cursor,
  }) {
    listStates.add(state);
    listCursors.add(cursor);
    listLimits.add(limit);
    final handler = listHandler;
    if (handler == null) throw StateError('Unexpected listExecutions call');
    return handler(limit: limit, state: state, cursor: cursor);
  }

  @override
  Future<kdf.NewTaskResponse> initTradeRoute({
    required String routeExecutionId,
    required String idempotencyKey,
    required kdf.TradeRouteInitConsent routeConsent,
  }) => throw StateError('Unexpected initTradeRoute call');

  @override
  Future<kdf.TradeRouteTaskStatusResponse> tradeRouteStatus({
    required int taskId,
    required bool forgetIfFinished,
  }) => throw StateError('Unexpected tradeRouteStatus call');

  @override
  Future<kdf.RouteActionResponse> tradeRouteUserAction({
    required int taskId,
    required kdf.RouteExecutionUserAction userAction,
  }) => throw StateError('Unexpected tradeRouteUserAction call');

  @override
  Future<kdf.RouteCancelResponse> cancelTradeRoute({
    required String routeExecutionId,
  }) => throw StateError('Unexpected cancelTradeRoute call');
}
