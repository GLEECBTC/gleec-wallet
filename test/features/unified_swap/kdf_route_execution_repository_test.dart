import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart' as kdf;
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:web_dex/features/unified_swap/domain/route_activity_models.dart';
import 'package:web_dex/features/unified_swap/domain/route_execution_models.dart';
import 'package:web_dex/features/unified_swap/domain/route_execution_repository.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_capability_policy.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_product_policy.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_quote_models.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_quote_repository.dart';
import 'package:web_dex/features/unified_swap/infrastructure/kdf_route_execution_repository.dart';
import 'package:web_dex/features/unified_swap/infrastructure/kdf_unified_swap_quote_repository.dart';

const _walletId = 'wallet-1';
const _routeId = '41f12b3c-79ac-42e7-bde9-5d43bdd1c1cb';
const _otherRouteId = 'cd735b9a-9733-41c2-90f0-c34c18e45364';
const _actionId = 'cc73ef2d-d2bc-4e71-bd59-acf7cb5888aa';
const _timestamp = '2026-07-16T12:00:00Z';
final _now = DateTime.parse(_timestamp);

void main() {
  late kdf.RouteConsent consent;
  late kdf.TradeRouteCandidate candidate;
  late kdf.PrepareExecutionResult prepared;
  late KdfVerifiedPreparedExecution verified;
  late Map<String, dynamic> preparedResponseJson;

  setUpAll(() async {
    final vectors =
        jsonDecode(
              File(
                'sdk/packages/komodo_defi_rpc_methods/test/fixtures/'
                'trade_route/external_liquidity_digest_vectors.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    consent = kdf.RouteConsent.fromJson(
      _map(_map(vectors['route_consent'])['value']),
    );
    final candidateJson = _deepCopy(_map(_map(vectors['candidate'])['value']));
    candidateJson['candidate_digest'] = _map(vectors['candidate'])['digest'];
    candidate = kdf.TradeRouteCandidate.fromJson(candidateJson);
    preparedResponseJson = _map(
      jsonDecode(
        File(
          'sdk/packages/komodo_defi_rpc_methods/test/fixtures/trade_route/'
          'prepare_execution_response.json',
        ).readAsStringSync(),
      ),
    );
    prepared = _walletPrepared(_map(_deepCopy(preparedResponseJson)['result']));
    verified = await _verifyPrepared(candidate, prepared);
  });

  test(
    'fresh init requires and consumes the exact registered review',
    () async {
      final gateway = _FakeTradeRouteGateway()
        ..initHandler =
            ({
              required routeExecutionId,
              required idempotencyKey,
              required routeConsent,
            }) async => kdf.NewTaskResponse(mmrpc: '2.0', taskId: 41);
      final manager = TradeRouteManager.withGateway(gateway: gateway);
      addTearDown(manager.dispose);
      final repository = KdfRouteExecutionRepository(
        walletId: _walletId,
        manager: manager,
        executionEligibilityCheck: (_) async => true,
        now: () => _now,
      );
      addTearDown(repository.dispose);

      expect(
        () => repository.registerVerifiedExecution(
          routeExecutionId: 'not-a-route-id',
          verified: verified,
        ),
        throwsA(_failure(RouteExecutionFailure.invalidReview)),
      );

      final review = repository.registerVerifiedExecution(
        routeExecutionId: _routeId,
        verified: verified,
      );
      expect(review.nonNetworkFeeLimits.single.stageId, isNotEmpty);
      expect(review.networkFeeCaps.single.stageId, isNotEmpty);

      await expectLater(
        repository.initReviewedExecution(
          walletId: 'different-wallet',
          routeExecutionId: review.routeExecutionId,
          reviewId: review.reviewId,
          consentDigest: review.consentDigest,
        ),
        throwsA(_failure(RouteExecutionFailure.capabilityUnavailable)),
      );

      await expectLater(
        repository.initReviewedExecution(
          walletId: _walletId,
          routeExecutionId: _otherRouteId,
          reviewId: review.reviewId,
          consentDigest: review.consentDigest,
        ),
        throwsA(_failure(RouteExecutionFailure.invalidReview)),
      );
      expect(gateway.initConsents, isEmpty);

      final session = await repository.initReviewedExecution(
        walletId: _walletId,
        routeExecutionId: review.routeExecutionId,
        reviewId: review.reviewId,
        consentDigest: review.consentDigest,
      );

      expect(
        session,
        const RouteExecutionSession(routeExecutionId: _routeId, taskId: 41),
      );
      expect(gateway.initConsents.single, same(prepared.routeConsent));
      expect(gateway.initIdempotencyKeys, ['trade-route:$_routeId']);

      await expectLater(
        repository.initReviewedExecution(
          walletId: _walletId,
          routeExecutionId: review.routeExecutionId,
          reviewId: review.reviewId,
          consentDigest: review.consentDigest,
        ),
        throwsA(_failure(RouteExecutionFailure.invalidReview)),
      );
      expect(gateway.initConsents, hasLength(1));
    },
  );

  test('discard and expiry pruning remove unconsumed authority', () async {
    var now = _now;
    final gateway = _FakeTradeRouteGateway();
    final manager = TradeRouteManager.withGateway(gateway: gateway);
    addTearDown(manager.dispose);
    final repository = KdfRouteExecutionRepository(
      walletId: _walletId,
      manager: manager,
      executionEligibilityCheck: (_) async => true,
      now: () => now,
    );
    addTearDown(repository.dispose);

    final discarded = repository.registerVerifiedExecution(
      routeExecutionId: _routeId,
      verified: verified,
    );
    repository.discardPreparedReview(discarded);
    await expectLater(
      repository.initReviewedExecution(
        walletId: _walletId,
        routeExecutionId: discarded.routeExecutionId,
        reviewId: discarded.reviewId,
        consentDigest: discarded.consentDigest,
      ),
      throwsA(_failure(RouteExecutionFailure.invalidReview)),
    );

    final expiring = repository.registerVerifiedExecution(
      routeExecutionId: _routeId,
      verified: verified,
    );
    now = _now.add(const Duration(minutes: 1));
    repository.registerVerifiedExecution(
      routeExecutionId: _otherRouteId,
      verified: verified,
    );
    await expectLater(
      repository.initReviewedExecution(
        walletId: _walletId,
        routeExecutionId: expiring.routeExecutionId,
        reviewId: expiring.reviewId,
        consentDigest: expiring.consentDigest,
      ),
      throwsA(_failure(RouteExecutionFailure.invalidReview)),
    );
    expect(gateway.initConsents, isEmpty);
  });

  test(
    'throwing execution eligibility check fails closed before init',
    () async {
      final gateway = _FakeTradeRouteGateway();
      final manager = TradeRouteManager.withGateway(gateway: gateway);
      addTearDown(manager.dispose);
      final repository = KdfRouteExecutionRepository(
        walletId: _walletId,
        manager: manager,
        executionEligibilityCheck: (_) async =>
            throw StateError('private compliance failure'),
        now: () => _now,
      );
      addTearDown(repository.dispose);
      final review = repository.registerVerifiedExecution(
        routeExecutionId: _routeId,
        verified: verified,
      );

      await expectLater(
        repository.initReviewedExecution(
          walletId: _walletId,
          routeExecutionId: review.routeExecutionId,
          reviewId: review.reviewId,
          consentDigest: review.consentDigest,
        ),
        throwsA(
          isA<RouteExecutionException>()
              .having(
                (error) => error.failure,
                'failure',
                RouteExecutionFailure.capabilityUnavailable,
              )
              .having(
                (error) => error.toString(),
                'sanitized error',
                isNot(contains('private compliance failure')),
              ),
        ),
      );
      expect(gateway.initConsents, isEmpty);
    },
  );

  test(
    'tampered prepared Review fields fail closed after digest rebinding',
    () async {
      final mutations = <void Function(Map<String, dynamic>)>[
        (result) {
          final stage = _map((_map(result['review'])['stages']! as List).first);
          _map(stage['max_total_network_fee'])['amount'] = '999';
        },
        (result) {
          final stage = _map((_map(result['review'])['stages']! as List).first);
          stage['stage_id'] = '00000000-0000-4000-8000-000000000099';
        },
        (result) {
          final review = _map(result['review']);
          review['resolved_source_address'] = 'not-an-evm-address';
          final reviewStage = _map((review['stages']! as List).first);
          reviewStage['resolved_source_address'] = 'not-an-evm-address';
          final stageConsent = _map(
            (_map(result['route_consent'])['external_stage_consents']! as List)
                .first,
          );
          _map(stageConsent['prepared_execution'])['resolved_source_address'] =
              'not-an-evm-address';
        },
        (result) {
          final reviewStage = _map(
            (_map(result['review'])['stages']! as List).first,
          );
          final invalidApproval = {
            'approval_type': 'exact_approval_required',
            'token': _deepCopy(_map(reviewStage['from_asset'])),
            'spender': '0x7777777777777777777777777777777777777777',
            'current_allowance': '0',
            'required_amount': reviewStage['source_amount'],
            'reset_required': false,
          };
          reviewStage['approval'] = invalidApproval;
          final stageConsent = _map(
            (_map(result['route_consent'])['external_stage_consents']! as List)
                .first,
          );
          _map(stageConsent['prepared_execution'])['approval'] = _deepCopy(
            invalidApproval,
          );
        },
        (result) {
          _map(result['review'])['expires_at'] = '2026-07-16T12:00:39Z';
        },
      ];

      for (final mutate in mutations) {
        final resultJson = <String, dynamic>{
          'review': _deepCopy(prepared.review.toJson()),
          'route_consent': _deepCopy(prepared.routeConsent.toJson()),
        };
        mutate(resultJson);
        final tampered = _rebindOuterPreparationDigests(resultJson);
        final manager = TradeRouteManager.withGateway(
          gateway: _FakeTradeRouteGateway(),
        );
        final repository = KdfRouteExecutionRepository(
          walletId: _walletId,
          manager: manager,
          executionEligibilityCheck: (_) async => true,
          now: () => _now,
        );
        try {
          final tamperedVerified = await _verifyPrepared(candidate, tampered);
          expect(
            () => repository.registerVerifiedExecution(
              routeExecutionId: _routeId,
              verified: tamperedVerified,
            ),
            throwsA(_failure(RouteExecutionFailure.invalidReview)),
          );
        } on UnifiedSwapQuoteException catch (error) {
          expect(
            error.failure,
            anyOf(
              UnifiedSwapQuoteFailure.invalidIntent,
              UnifiedSwapQuoteFailure.capabilityUnavailable,
            ),
          );
        }
        repository.dispose();
        manager.dispose();
      }
    },
  );

  test('reattach performs durable get before safe-consent init', () async {
    final gateway = _FakeTradeRouteGateway();
    gateway.getHandler = ({required routeExecutionId}) async =>
        _executionResponse(consent, candidate);
    gateway.initHandler =
        ({
          required routeExecutionId,
          required idempotencyKey,
          required routeConsent,
        }) async => kdf.NewTaskResponse(mmrpc: '2.0', taskId: 77);
    final manager = TradeRouteManager.withGateway(gateway: gateway);
    addTearDown(manager.dispose);
    final repository = KdfRouteExecutionRepository(
      walletId: _walletId,
      manager: manager,
      executionEligibilityCheck: (_) async => true,
    );
    addTearDown(repository.dispose);

    final session = await repository.reattachExecution(
      walletId: _walletId,
      routeExecutionId: _routeId,
    );
    final durableProgress = await repository.observe(session).first;

    expect(gateway.calls, ['get:$_routeId', 'init:$_routeId']);
    expect(session.taskId, 77);
    expect(durableProgress.outcome, RouteExecutionOutcome.active);
    expect(durableProgress.phase, RouteExecutionPhase.broadcasting);
    expect(gateway.initConsents.single, isA<kdf.RouteActivityConsent>());
    expect(
      gateway.initConsents.single.toRequestJson(),
      _activityConsent(consent.toJson()),
    );
  });

  test('unknown task and typed status variants fail closed', () async {
    var statusCall = 0;
    final gateway = _FakeTradeRouteGateway();
    gateway.initHandler =
        ({
          required routeExecutionId,
          required idempotencyKey,
          required routeConsent,
        }) async => kdf.NewTaskResponse(mmrpc: '2.0', taskId: 9);
    gateway.statusHandler =
        ({required taskId, required forgetIfFinished}) async {
          statusCall++;
          if (statusCall == 1) {
            return _taskStatusResponse(
              status: 'InProgress',
              details: _statusJson(
                routePhase: 'future_route_phase',
                canCancel: true,
              ),
            );
          }
          return _taskStatusResponse(
            status: 'FutureTaskStatus',
            details: {'provider': 'secret-provider', 'raw': 'secret-payload'},
          );
        };
    final manager = TradeRouteManager.withGateway(
      gateway: gateway,
      defaultPollingInterval: const Duration(microseconds: 1),
    );
    addTearDown(manager.dispose);
    final repository = KdfRouteExecutionRepository(
      walletId: _walletId,
      manager: manager,
      executionEligibilityCheck: (_) async => true,
      now: () => _now,
    );
    addTearDown(repository.dispose);
    final session = await _freshSession(repository, verified);

    final progress = await repository.observe(session).first;
    expect(progress.outcome, RouteExecutionOutcome.unknown);
    expect(progress.phase, RouteExecutionPhase.unknown);
    expect(progress.rawOutcomeDiscriminator, 'future_route_phase');
    expect(progress.rawPhaseDiscriminator, 'future_route_phase');
    expect(progress.controls.canCancel, isTrue);
    expect(progress.isExecutable, isFalse);

    await expectLater(
      repository.observe(session),
      emitsError(_failure(RouteExecutionFailure.unknown)),
    );
  });

  test('maps exact progress controls, holding and fee-cap action', () async {
    final gateway = _FakeTradeRouteGateway();
    gateway.initHandler =
        ({
          required routeExecutionId,
          required idempotencyKey,
          required routeConsent,
        }) async => kdf.NewTaskResponse(mmrpc: '2.0', taskId: 10);
    gateway.statusHandler =
        ({required taskId, required forgetIfFinished}) async {
          return _taskStatusResponse(
            status: 'UserActionRequired',
            details: _statusJson(
              phase: 'broadcasting',
              routePhase: 'executing_stage',
              canStopAfterCurrent: true,
              pendingReason: 'network_fee_cap_exceeded',
              allowedActions: const ['reject_change'],
              holding: _holdingJson(),
            ),
          );
        };
    final manager = TradeRouteManager.withGateway(
      gateway: gateway,
      defaultPollingInterval: const Duration(hours: 1),
    );
    addTearDown(manager.dispose);
    final repository = KdfRouteExecutionRepository(
      walletId: _walletId,
      manager: manager,
      executionEligibilityCheck: (_) async => true,
      now: () => _now,
    );
    addTearDown(repository.dispose);
    final session = await _freshSession(repository, verified);

    final progress = await repository.observe(session).first;

    expect(progress.routeExecutionId, _routeId);
    expect(progress.stateRevision, 8);
    expect(progress.stageIndex, 0);
    expect(progress.stageCount, prepared.review.stages.length);
    expect(progress.phase, RouteExecutionPhase.broadcasting);
    expect(progress.controls.canCancel, isFalse);
    expect(progress.controls.canStopAfterCurrent, isTrue);
    expect(progress.controls.reconciliationOnly, isFalse);
    expect(progress.transactionHashes, ['0xsource']);
    expect(progress.updatedAt, _now);
    expect(progress.holding?.amount, '998000000');
    expect(progress.holding?.address, '0xholding');
    expect(progress.holding?.asset.chainFamily, UnifiedSwapChainFamily.evm);
    expect(progress.holding?.asset.kind, UnifiedSwapAssetKind.token);
    expect(
      progress.pendingAction?.reason,
      RoutePendingActionReason.networkFeeCapExceeded,
    );
    expect(progress.pendingAction?.rawReasonDiscriminator, isNull);
    expect(progress.pendingAction?.allowedActions, [
      RouteExecutionActionKind.rejectChange,
    ]);
    expect(progress.isExecutable, isTrue);
    expect(progress.toString(), isNot(contains('secret-provider-status')));
  });

  test('maps partial progress as a known recovery phase', () async {
    final gateway = _FakeTradeRouteGateway();
    gateway.initHandler =
        ({
          required routeExecutionId,
          required idempotencyKey,
          required routeConsent,
        }) async => kdf.NewTaskResponse(mmrpc: '2.0', taskId: 11);
    gateway.statusHandler =
        ({required taskId, required forgetIfFinished}) async =>
            _taskStatusResponse(
              status: 'InProgress',
              details: _statusJson(
                phase: 'partial',
                routePhase: 'partial',
                holding: _holdingJson(),
              ),
            );
    final manager = TradeRouteManager.withGateway(
      gateway: gateway,
      defaultPollingInterval: const Duration(hours: 1),
    );
    addTearDown(manager.dispose);
    final repository = KdfRouteExecutionRepository(
      walletId: _walletId,
      manager: manager,
      executionEligibilityCheck: (_) async => true,
      now: () => _now,
    );
    addTearDown(repository.dispose);
    final session = await _freshSession(repository, verified);

    final progress = await repository.observe(session).first;

    expect(progress.outcome, RouteExecutionOutcome.recovery);
    expect(progress.phase, RouteExecutionPhase.partial);
    expect(progress.rawPhaseDiscriminator, isNull);
    expect(progress.isExecutable, isTrue);
  });

  test('retains exact replacement proposal economics and digest', () async {
    final replacementConsent = _replacementConsent(
      prepared.routeConsent.externalStageConsents.single,
      expectedReceive: '997000000',
      minimumReceive: '992000000',
      providerStepDigest: 'provider-step-digest-v2',
      networkFeeAmount: '10',
    );
    final replacementSummary = _replacementSummaryJson(replacementConsent);
    expect(
      kdf.ReplacementSummary.fromJson(replacementSummary).isExecutable,
      isTrue,
    );
    final gateway = _FakeTradeRouteGateway();
    gateway.initHandler =
        ({
          required routeExecutionId,
          required idempotencyKey,
          required routeConsent,
        }) async => kdf.NewTaskResponse(mmrpc: '2.0', taskId: 12);
    gateway.statusHandler =
        ({required taskId, required forgetIfFinished}) async =>
            _taskStatusResponse(
              status: 'UserActionRequired',
              details: _statusJson(
                phase: 'awaiting_user_action',
                routePhase: 'awaiting_user_action',
                pendingReason: 'quote_changed',
                allowedActions: const ['accept_replacement', 'reject_change'],
                replacementSummary: replacementSummary,
              ),
            );
    final manager = TradeRouteManager.withGateway(
      gateway: gateway,
      defaultPollingInterval: const Duration(hours: 1),
    );
    addTearDown(manager.dispose);
    final repository = KdfRouteExecutionRepository(
      walletId: _walletId,
      manager: manager,
      executionEligibilityCheck: (_) async => true,
      now: () => _now,
    );
    addTearDown(repository.dispose);
    final session = await _freshSession(repository, verified);

    final progress = await repository.observe(session).first;
    final proposal = progress.pendingAction?.replacementProposal;

    expect(
      progress.pendingAction?.reason,
      RoutePendingActionReason.candidateChanged,
    );
    expect(proposal?.proposalDigest, 'proposal-digest-v1');
    expect(proposal?.providerStepDigest, 'provider-step-digest-v2');
    expect(proposal?.expectedReceive, '997000000');
    expect(proposal?.minimumReceive, '992000000');
    expect(proposal?.fees.single.kind, RouteFeeKind.network);
    expect(proposal?.requiredTotalNetworkFee?.amount, '10');
    expect(proposal?.isExecutable, isTrue);
    expect(progress.isExecutable, isTrue);
  });

  test('explicit controls use fresh durable authorization', () async {
    var getCall = 0;
    final gateway = _FakeTradeRouteGateway()
      ..getHandler = ({required routeExecutionId}) async {
        getCall++;
        return _executionResponse(
          consent,
          candidate,
          canCancel: getCall == 1,
          canStopAfterCurrent: getCall == 2,
        );
      }
      ..cancelHandler = ({required routeExecutionId}) async =>
          _cancelResponse();
    final manager = TradeRouteManager.withGateway(gateway: gateway);
    addTearDown(manager.dispose);
    final repository = KdfRouteExecutionRepository(
      walletId: _walletId,
      manager: manager,
      executionEligibilityCheck: (_) async => true,
    );
    addTearDown(repository.dispose);

    await repository.cancelExecution(
      walletId: _walletId,
      routeExecutionId: _routeId,
    );
    await repository.stopAfterCurrent(
      walletId: _walletId,
      routeExecutionId: _routeId,
    );

    expect(gateway.calls, [
      'get:$_routeId',
      'cancel:$_routeId',
      'get:$_routeId',
      'cancel:$_routeId',
    ]);
  });

  test('action acknowledgement is delivery-only and exact', () async {
    final gateway = _FakeTradeRouteGateway();
    gateway.initHandler =
        ({
          required routeExecutionId,
          required idempotencyKey,
          required routeConsent,
        }) async => kdf.NewTaskResponse(mmrpc: '2.0', taskId: 13);
    gateway.getHandler = ({required routeExecutionId}) async =>
        _executionResponse(
          consent,
          candidate,
          canStopAfterCurrent: true,
          pendingReason: 'recovery_required',
          allowedActions: const ['stop_after_current'],
        );
    gateway.actionHandler = ({required taskId, required userAction}) async =>
        _actionResponse();
    final manager = TradeRouteManager.withGateway(gateway: gateway);
    addTearDown(manager.dispose);
    final repository = KdfRouteExecutionRepository(
      walletId: _walletId,
      manager: manager,
      executionEligibilityCheck: (_) async => true,
      now: () => _now,
    );
    addTearDown(repository.dispose);
    final session = await _freshSession(repository, verified);

    final acknowledgement = await repository.submitDecision(
      walletId: _walletId,
      session: session,
      decision: const RouteExecutionDecision(
        kind: RouteExecutionActionKind.stopAfterCurrent,
        actionId: _actionId,
        expectedStateRevision: 8,
      ),
    );

    expect(acknowledgement.wasDelivered, isTrue);
    expect(gateway.actions.single.actionType, 'stop_after_current');
    expect(gateway.actions.single.actionId, _actionId);
    expect(gateway.actions.single.expectedStateRevision, 8);

    await expectLater(
      repository.submitDecision(
        walletId: _walletId,
        session: session,
        decision: const RouteExecutionDecision(
          kind: RouteExecutionActionKind.acceptReplacement,
          actionId: _actionId,
          expectedStateRevision: 8,
        ),
      ),
      throwsA(_failure(RouteExecutionFailure.actionNotAuthorized)),
    );
    expect(gateway.actions, hasLength(1));
  });

  test('accepts only the exact fresh KDF replacement consent', () async {
    final durableConsent = _durableConsentForAction(prepared.routeConsent);
    final replacementConsent = _replacementConsent(
      durableConsent.externalStageConsents.single,
      expectedReceive: '997000000',
      minimumReceive: '992000000',
      providerStepDigest: 'provider-step-digest-v2',
      networkFeeAmount: '10',
    );
    final summary = _replacementSummaryJson(replacementConsent);
    final gateway = _FakeTradeRouteGateway()
      ..initHandler =
          ({
            required routeExecutionId,
            required idempotencyKey,
            required routeConsent,
          }) async {
            return kdf.NewTaskResponse(mmrpc: '2.0', taskId: 14);
          }
      ..getHandler = ({required routeExecutionId}) async {
        return _executionResponse(
          durableConsent,
          candidate,
          pendingReason: 'quote_changed',
          allowedActions: const ['accept_replacement', 'reject_change'],
          replacementSummary: summary,
        );
      }
      ..actionHandler = ({required taskId, required userAction}) async {
        return _actionResponse();
      };
    final manager = TradeRouteManager.withGateway(gateway: gateway);
    addTearDown(manager.dispose);
    final repository = KdfRouteExecutionRepository(
      walletId: _walletId,
      manager: manager,
      executionEligibilityCheck: (_) async => true,
      now: () => _now,
    );
    addTearDown(repository.dispose);
    final session = await _freshSession(repository, verified);

    final acknowledgement = await repository.submitDecision(
      walletId: _walletId,
      session: session,
      decision: const RouteExecutionDecision(
        kind: RouteExecutionActionKind.acceptReplacement,
        actionId: _actionId,
        expectedStateRevision: 8,
        replacementProposalDigest: 'proposal-digest-v1',
      ),
    );

    expect(acknowledgement.wasDelivered, isTrue);
    final action = gateway.actions.single as kdf.RouteAcceptReplacementAction;
    expect(action.proposalDigest, 'proposal-digest-v1');
    expect(
      action.replacementStageConsent.toJson(),
      replacementConsent.toJson(),
    );
    expect(
      gateway.calls.where((call) => call == 'get:$_routeId'),
      hasLength(2),
    );
  });

  test(
    'rejects replacement consent tampering outside declared economics',
    () async {
      final durableConsent = _durableConsentForAction(prepared.routeConsent);
      final original = _replacementConsent(
        durableConsent.externalStageConsents.single,
        expectedReceive: '997000000',
        minimumReceive: '992000000',
        providerStepDigest: 'provider-step-digest-v2',
        networkFeeAmount: '10',
      );
      late Map<String, dynamic> currentSummary;
      final gateway = _FakeTradeRouteGateway()
        ..initHandler =
            ({
              required routeExecutionId,
              required idempotencyKey,
              required routeConsent,
            }) async {
              return kdf.NewTaskResponse(mmrpc: '2.0', taskId: 15);
            }
        ..getHandler = ({required routeExecutionId}) async {
          return _executionResponse(
            durableConsent,
            candidate,
            pendingReason: 'quote_changed',
            allowedActions: const ['accept_replacement', 'reject_change'],
            replacementSummary: currentSummary,
          );
        }
        ..actionHandler = ({required taskId, required userAction}) async {
          return _actionResponse();
        };
      final manager = TradeRouteManager.withGateway(gateway: gateway);
      addTearDown(manager.dispose);
      final repository = KdfRouteExecutionRepository(
        walletId: _walletId,
        manager: manager,
        executionEligibilityCheck: (_) async => true,
        now: () => _now,
      );
      addTearDown(repository.dispose);
      final session = await _freshSession(repository, verified);
      final mutations =
          <({String name, void Function(Map<String, dynamic>) apply})>[
            (
              name: 'digest version',
              apply: (json) => json['digest_version'] = 2,
            ),
            (
              name: 'execution mode',
              apply: (json) => json['mode'] = 'sign_only',
            ),
            (
              name: 'candidate reference',
              apply: (json) =>
                  _map(json['candidate_reference'])['candidate_digest'] =
                      'tampered-candidate-digest',
            ),
            (
              name: 'route recipient',
              apply: (json) => _map(json['route_intent'])['recipient'] =
                  'bc1qtamperedrecipient',
            ),
            (
              name: 'stage recipient',
              apply: (json) => _map(json['stage_intent'])['recipient'] =
                  '0x7777777777777777777777777777777777777777',
            ),
            (
              name: 'source amount',
              apply: (json) => _map(json['stage_intent'])['source_amount'] =
                  '999999999999999999',
            ),
            (
              name: 'source selector',
              apply: (json) => _map(json['stage_intent'])['source_address'] = {
                'selector_type': 'hd',
                'selector': {'derivation_path': "m/44'/60'/0'/0/1"},
              },
            ),
            (
              name: 'source asset',
              apply: (json) =>
                  _map(_map(json['stage_intent'])['from_asset'])['ticker'] =
                      'MATIC',
            ),
            (
              name: 'selected tools',
              apply: (json) =>
                  (_map(
                            _map(json['stage_intent'])['selected_tools'],
                          )['exchanges']!
                          as List<dynamic>)
                      .add('paraswap'),
            ),
            (
              name: 'provider observation',
              apply: (json) =>
                  _map(json['execution_source'])['provider_observed_at'] =
                      '2026-07-16T12:00:01Z',
            ),
            (
              name: 'provider step reference',
              apply: (json) => _map(
                _map(json['execution_source'])['provider_step_reference'],
              )['candidate_id'] = _otherRouteId,
            ),
            (
              name: 'resolved source address',
              apply: (json) =>
                  _map(json['prepared_execution'])['resolved_source_address'] =
                      '0x8888888888888888888888888888888888888888',
            ),
            (
              name: 'undeclared non-network fee',
              apply: (json) => _map(
                (_map(json['stage_intent'])['non_network_fee_limits']!
                        as List<dynamic>)
                    .single,
              )['max_amount'] = '1',
            ),
          ];

      for (final mutation in mutations) {
        final tampered = _mutatedReplacement(original, mutation.apply);
        currentSummary = _replacementSummaryJson(tampered);

        await expectLater(
          repository.submitDecision(
            walletId: _walletId,
            session: session,
            decision: const RouteExecutionDecision(
              kind: RouteExecutionActionKind.acceptReplacement,
              actionId: _actionId,
              expectedStateRevision: 8,
              replacementProposalDigest: 'proposal-digest-v1',
            ),
          ),
          throwsA(_failure(RouteExecutionFailure.actionNotAuthorized)),
          reason: mutation.name,
        );
      }

      currentSummary = _replacementSummaryJson(original);
      (currentSummary['changed_fields']! as List<dynamic>).add(
        'non_network_fees',
      );
      await expectLater(
        repository.submitDecision(
          walletId: _walletId,
          session: session,
          decision: const RouteExecutionDecision(
            kind: RouteExecutionActionKind.acceptReplacement,
            actionId: _actionId,
            expectedStateRevision: 8,
            replacementProposalDigest: 'proposal-digest-v1',
          ),
        ),
        throwsA(_failure(RouteExecutionFailure.actionNotAuthorized)),
        reason: 'declared but unchanged fee field',
      );
      expect(gateway.actions, isEmpty);
    },
  );

  test(
    'stream cancellation stops observation without backend cancel',
    () async {
      final gateway = _FakeTradeRouteGateway();
      gateway.initHandler =
          ({
            required routeExecutionId,
            required idempotencyKey,
            required routeConsent,
          }) async => kdf.NewTaskResponse(mmrpc: '2.0', taskId: 21);
      gateway.statusHandler =
          ({required taskId, required forgetIfFinished}) async =>
              _taskStatusResponse(status: 'InProgress', details: _statusJson());
      final manager = TradeRouteManager.withGateway(
        gateway: gateway,
        defaultPollingInterval: const Duration(hours: 1),
      );
      addTearDown(manager.dispose);
      final repository = KdfRouteExecutionRepository(
        walletId: _walletId,
        manager: manager,
        executionEligibilityCheck: (_) async => true,
        now: () => _now,
      );
      addTearDown(repository.dispose);
      final session = await _freshSession(repository, verified);
      final seen = Completer<void>();

      final subscription = repository.observe(session).listen((_) {
        if (!seen.isCompleted) seen.complete();
      });
      await seen.future.timeout(const Duration(seconds: 1));
      await subscription.cancel();

      expect(gateway.cancelledRouteIds, isEmpty);
      expect(gateway.forgetIfFinishedValues, everyElement(isFalse));
    },
  );

  test('typed failures never retain raw backend messages', () async {
    final gateway = _FakeTradeRouteGateway();
    gateway.getHandler = ({required routeExecutionId}) async {
      throw _rpcError(
        type: 'PersistenceError',
        data: {'operation': 'raw-secret-operation'},
      );
    };
    final manager = TradeRouteManager.withGateway(gateway: gateway);
    addTearDown(manager.dispose);
    final repository = KdfRouteExecutionRepository(
      walletId: _walletId,
      manager: manager,
      executionEligibilityCheck: (_) async => true,
    );
    addTearDown(repository.dispose);

    await expectLater(
      repository.reattachExecution(
        walletId: _walletId,
        routeExecutionId: _routeId,
      ),
      throwsA(_failure(RouteExecutionFailure.storageUnavailable)),
    );
  });
}

Matcher _failure(RouteExecutionFailure failure) =>
    isA<RouteExecutionException>()
        .having((error) => error.failure, 'failure', failure)
        .having(
          (error) => error.toString(),
          'sanitized error',
          isNot(contains('raw-secret')),
        );

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

Future<RouteExecutionSession> _freshSession(
  KdfRouteExecutionRepository repository,
  KdfVerifiedPreparedExecution verified,
) {
  final review = repository.registerVerifiedExecution(
    routeExecutionId: _routeId,
    verified: verified,
  );
  return repository.initReviewedExecution(
    walletId: _walletId,
    routeExecutionId: review.routeExecutionId,
    reviewId: review.reviewId,
    consentDigest: review.consentDigest,
  );
}

kdf.PrepareExecutionResult _walletPrepared(Map<String, dynamic> source) {
  final result = _deepCopy(source);
  final review = kdf.PreparedExecutionReview.fromJson(_map(result['review']));
  final consentJson = _map(result['route_consent']);
  final emptyToolPolicy = kdf.ToolPolicy().toJson();
  final routeIntentJson = _map(consentJson['route_intent']);
  routeIntentJson['tool_policy'] = _deepCopy(emptyToolPolicy);
  consentJson['route_intent'] = routeIntentJson;
  final stageJson = _map(
    (consentJson['external_stage_consents']! as List).single,
  );
  stageJson['route_intent'] = _deepCopy(routeIntentJson);
  _map(stageJson['stage_intent'])['max_expected_receive_degradation_bps'] = 25;
  final routeIntentDigest = kdf.tradeRouteIntentDigest(
    kdf.TradeIntent.fromJson(routeIntentJson),
  );
  _map(stageJson['stage_intent'])['route_intent_digest'] = routeIntentDigest;
  for (final guard in consentJson['atomic_order_guards']! as List) {
    _map(guard)['route_intent_digest'] = routeIntentDigest;
  }
  final followingGuard = stageJson['atomic_order_guard'];
  if (followingGuard != null) {
    _map(followingGuard)['route_intent_digest'] = routeIntentDigest;
  }
  var stage = kdf.StageConsent.fromJson(stageJson);
  stageJson['consent_digest'] = kdf.tradeRouteStageConsentDigest(stage);
  stage = kdf.StageConsent.fromJson(stageJson);
  consentJson['external_stage_consents'] = [stageJson];
  consentJson['prepared_review_digest'] = kdf
      .tradeRoutePreparedExecutionReviewDigest(review);
  var routeConsent = kdf.RouteConsent.fromJson(consentJson);
  consentJson['route_consent_digest'] = kdf.tradeRouteConsentDigest(
    routeConsent,
  );
  routeConsent = kdf.RouteConsent.fromJson(consentJson);
  return kdf.PrepareExecutionResult(review: review, routeConsent: routeConsent);
}

Future<KdfVerifiedPreparedExecution> _verifyPrepared(
  kdf.TradeRouteCandidate candidate,
  kdf.PrepareExecutionResult prepared,
) async {
  final client = _VerifiedPreparationClient(candidate, prepared);
  final external = prepared.routeConsent.externalStageConsents.single;
  final repository = KdfUnifiedSwapQuoteRepository(
    client: client,
    walletId: _walletId,
    eligibilityCheck: (_) async => true,
    validateRecipient: ({required ticker, required address}) async => true,
    expectedSourceAddress: (_) async =>
        '0x9999999999999999999999999999999999999999',
    preparationLimitsPolicy: ({required intent, required candidate}) async => [
      kdf.PrepareExecutionStageLimits(
        stageId: external.stageIntent.stageId,
        maxExpectedReceiveDegradationBps: 25,
        nonNetworkFeeLimits: external.stageIntent.nonNetworkFeeLimits,
        maxTotalNetworkFee: external.stageIntent.maxTotalNetworkFee,
      ),
    ],
    now: () => _now,
  );
  final intent = UnifiedSwapIntent(
    revision: 1,
    source: _eth,
    destination: _btc,
    sourceAmount: '1000000000000000000',
    sourceSelection: const UnifiedSwapActiveSourceSelection(),
    recipient: 'bc1qrecipient',
    sourceTokenTrust: UnifiedSwapTokenTrust.trusted,
    destinationTokenTrust: UnifiedSwapTokenTrust.trusted,
  );
  final evaluation = await repository.evaluate(intent);
  return repository.prepareExecution(
    intent: intent,
    candidate: evaluation.candidates.single,
  );
}

final class _VerifiedPreparationClient
    implements KdfUnifiedSwapQuoteClient, KdfUnifiedSwapPreparationClient {
  const _VerifiedPreparationClient(this.candidate, this.prepared);

  final kdf.TradeRouteCandidate candidate;
  final kdf.PrepareExecutionResult prepared;

  @override
  Future<kdf.TradeRouteQuoteResult> quote({
    required kdf.TradeIntent intent,
    required List<kdf.RouteSource> routeSources,
    kdf.ValuationSnapshot? valuationSnapshot,
  }) async => kdf.TradeRouteQuoteResult.fromJson({
    'evaluation_id': prepared.review.evaluationId,
    'observed_at': _timestamp,
    'evaluation_expires_at': prepared.review.expiresAt.toIso8601String(),
    'candidates': [candidate.toJson()],
  });

  @override
  Future<kdf.PrepareExecutionResult> prepareExecution({
    required String evaluationId,
    required String candidateId,
    required String candidateDigest,
    required String finalMinimumReceive,
    required DateTime consentExpiresAt,
    required List<kdf.PrepareExecutionStageLimits> stages,
  }) async => prepared;
}

final class _FakeTradeRouteGateway implements TradeRouteRpcGateway {
  Future<kdf.RouteExecutionDetailsResponse> Function({
    required String routeExecutionId,
  })?
  getHandler;
  Future<kdf.NewTaskResponse> Function({
    required String routeExecutionId,
    required String idempotencyKey,
    required kdf.TradeRouteInitConsent routeConsent,
  })?
  initHandler;
  Future<kdf.TradeRouteTaskStatusResponse> Function({
    required int taskId,
    required bool forgetIfFinished,
  })?
  statusHandler;
  Future<kdf.RouteCancelResponse> Function({required String routeExecutionId})?
  cancelHandler;
  Future<kdf.RouteActionResponse> Function({
    required int taskId,
    required kdf.RouteExecutionUserAction userAction,
  })?
  actionHandler;

  final calls = <String>[];
  final initConsents = <kdf.TradeRouteInitConsent>[];
  final initIdempotencyKeys = <String>[];
  final cancelledRouteIds = <String>[];
  final forgetIfFinishedValues = <bool>[];
  final actions = <kdf.RouteExecutionUserAction>[];

  @override
  Future<kdf.RouteCancelResponse> cancelTradeRoute({
    required String routeExecutionId,
  }) {
    calls.add('cancel:$routeExecutionId');
    cancelledRouteIds.add(routeExecutionId);
    final handler = cancelHandler;
    if (handler == null) throw StateError('Unexpected cancel call');
    return handler(routeExecutionId: routeExecutionId);
  }

  @override
  Future<kdf.RouteExecutionDetailsResponse> getExecution({
    required String routeExecutionId,
  }) {
    calls.add('get:$routeExecutionId');
    final handler = getHandler;
    if (handler == null) throw StateError('Unexpected get call');
    return handler(routeExecutionId: routeExecutionId);
  }

  @override
  Future<kdf.NewTaskResponse> initTradeRoute({
    required String routeExecutionId,
    required String idempotencyKey,
    required kdf.TradeRouteInitConsent routeConsent,
  }) {
    calls.add('init:$routeExecutionId');
    initConsents.add(routeConsent);
    initIdempotencyKeys.add(idempotencyKey);
    final handler = initHandler;
    if (handler == null) throw StateError('Unexpected init call');
    return handler(
      routeExecutionId: routeExecutionId,
      idempotencyKey: idempotencyKey,
      routeConsent: routeConsent,
    );
  }

  @override
  Future<kdf.ListRouteExecutionsResponse> listExecutions({
    required int limit,
    kdf.RouteActivityState? state,
    String? cursor,
  }) => throw StateError('Unexpected list call');

  @override
  Future<kdf.TradeRouteTaskStatusResponse> tradeRouteStatus({
    required int taskId,
    required bool forgetIfFinished,
  }) {
    calls.add('status:$taskId');
    forgetIfFinishedValues.add(forgetIfFinished);
    final handler = statusHandler;
    if (handler == null) throw StateError('Unexpected status call');
    return handler(taskId: taskId, forgetIfFinished: forgetIfFinished);
  }

  @override
  Future<kdf.RouteActionResponse> tradeRouteUserAction({
    required int taskId,
    required kdf.RouteExecutionUserAction userAction,
  }) {
    calls.add('action:$taskId');
    actions.add(userAction);
    final handler = actionHandler;
    if (handler == null) throw StateError('Unexpected action call');
    return handler(taskId: taskId, userAction: userAction);
  }
}

kdf.RouteExecutionDetailsResponse _executionResponse(
  kdf.RouteConsent consent,
  kdf.TradeRouteCandidate candidate, {
  bool canCancel = false,
  bool canStopAfterCurrent = false,
  String? pendingReason,
  List<String>? allowedActions,
  Map<String, dynamic>? replacementSummary,
}) => kdf.RouteExecutionDetailsResponse.parse({
  'mmrpc': '2.0',
  'result': {
    'route_execution_id': _routeId,
    'activity_state': 'active',
    'route_consent': _activityConsent(consent.toJson()),
    'candidate': candidate.toJson(),
    'resolved_source_address':
        consent
            .externalStageConsents
            .first
            .preparedExecution
            ?.resolvedSourceAddress ??
        '0x1111111111111111111111111111111111111111',
    'recipient_address': consent.routeIntent.recipient,
    'status': _statusJson(
      canCancel: canCancel,
      canStopAfterCurrent: canStopAfterCurrent,
      pendingReason: pendingReason,
      allowedActions: allowedActions,
      replacementSummary: replacementSummary,
    ),
    'route_revisions': <Object>[],
    'terminal_error': null,
    'created_at': _timestamp,
    'updated_at': _timestamp,
    'completed_at': null,
  },
});

kdf.TradeRouteTaskStatusResponse _taskStatusResponse({
  required String status,
  required Object details,
}) => kdf.TradeRouteTaskStatusResponse.parse({
  'mmrpc': '2.0',
  'result': {'status': status, 'details': details},
});

kdf.RouteCancelResponse _cancelResponse() => kdf.RouteCancelResponse.parse({
  'mmrpc': '2.0',
  'result': {
    'outcome': 'cancelled',
    'phase': 'validating',
    'stop_after_current': false,
    'tx_hashes': <String>[],
  },
});

kdf.RouteActionResponse _actionResponse() =>
    kdf.RouteActionResponse.parse({'mmrpc': '2.0', 'result': 'success'});

Map<String, dynamic> _statusJson({
  String phase = 'broadcasting',
  String routePhase = 'executing_stage',
  bool canCancel = false,
  bool canStopAfterCurrent = false,
  String? pendingReason,
  List<String>? allowedActions,
  Map<String, dynamic>? holding,
  Map<String, dynamic>? replacementSummary,
}) => {
  'route_execution_id': _routeId,
  'stage_index': 0,
  'phase': phase,
  'route_phase': routePhase,
  'state_revision': 8,
  'pending_user_action': pendingReason == null
      ? null
      : {
          'action_id': _actionId,
          'reason': pendingReason,
          'allowed_actions': allowedActions ?? const <String>[],
          'replacement_summary': replacementSummary,
        },
  'stop_after_current': false,
  'tx_hashes': ['0xsource'],
  'actual_holding': holding,
  'raw_provider_status': 'secret-provider-status',
  'raw_provider_substatus': 'secret-provider-substatus',
  'receiving_evidence': null,
  'refund_evidence': null,
  'approval_recovery': null,
  'stage_results': <Object>[],
  'controls': {
    'can_cancel': canCancel,
    'can_stop_after_current': canStopAfterCurrent,
    'reconciliation_only': false,
  },
  'created_at': _timestamp,
  'completed_at': null,
  'updated_at': _timestamp,
};

Map<String, dynamic> _holdingJson() => {
  'asset': {
    'ticker': 'USDC',
    'chain_family': 'evm',
    'chain_id': '1',
    'asset_kind': 'token',
    'contract_address': '0x3333333333333333333333333333333333333333',
    'decimals': 6,
  },
  'amount': '998000000',
  'address': '0xholding',
};

Map<String, dynamic> _nativeAssetJson() => {
  'ticker': 'ETH',
  'chain_family': 'evm',
  'chain_id': '1',
  'asset_kind': 'native',
  'contract_address': null,
  'decimals': 18,
};

Map<String, dynamic> _activityConsent(Map<String, dynamic> fullConsent) {
  final consent = _deepCopy(fullConsent);
  consent['consent_type'] = 'activity_reattachment';
  consent.remove('prepared_at');
  consent.remove('prepared_review_digest');
  final stages = consent['external_stage_consents']! as List<dynamic>;
  for (var index = 0; index < stages.length; index++) {
    final stage = _map(stages[index]);
    stage.remove('route_intent');
    stage.remove('prepared_execution');
    final source = _map(stage['execution_source']);
    source.remove('provider_step');
    stage['execution_source'] = source;
    stages[index] = stage;
  }
  return consent;
}

kdf.StageConsent _replacementConsent(
  kdf.StageConsent original, {
  required String expectedReceive,
  required String minimumReceive,
  required String providerStepDigest,
  required String networkFeeAmount,
}) {
  final json = _deepCopy(original.toJson());
  final intent = _map(json['stage_intent']);
  intent['accepted_expected_receive'] = expectedReceive;
  intent['minimum_receive'] = minimumReceive;
  _map(intent['max_total_network_fee'])['amount'] = networkFeeAmount;
  final source = _map(json['execution_source']);
  source['provider_step_digest'] = providerStepDigest;
  _map(source['provider_step_reference'])['provider_step_digest'] =
      providerStepDigest;
  _map(_map(json['prepared_execution'])['required_max_network_fee'])['amount'] =
      networkFeeAmount;
  var replacement = kdf.StageConsent.fromJson(json);
  json['consent_digest'] = kdf.tradeRouteStageConsentDigest(replacement);
  replacement = kdf.StageConsent.fromJson(json);
  return replacement;
}

kdf.StageConsent _mutatedReplacement(
  kdf.StageConsent source,
  void Function(Map<String, dynamic>) mutate,
) {
  final json = _deepCopy(source.toJson());
  mutate(json);
  final routeIntent = kdf.TradeIntent.fromJson(_map(json['route_intent']));
  _map(json['stage_intent'])['route_intent_digest'] = kdf
      .tradeRouteIntentDigest(routeIntent);
  var replacement = kdf.StageConsent.fromJson(json);
  json['consent_digest'] = kdf.tradeRouteStageConsentDigest(replacement);
  replacement = kdf.StageConsent.fromJson(json);
  return replacement;
}

Map<String, dynamic> _replacementSummaryJson(kdf.StageConsent replacement) => {
  'proposal_digest': 'proposal-digest-v1',
  'stage_id': replacement.stageIntent.stageId,
  'provider_step_digest':
      (replacement.executionSource as kdf.ProviderIntentExecutionSource)
          .providerStepDigest,
  'changed_fields': ['expected_receive', 'minimum_receive', 'network_fee_cap'],
  'expected_receive': replacement.stageIntent.acceptedExpectedReceive,
  'minimum_receive': replacement.stageIntent.minimumReceive,
  'fees': [
    {
      'fee_type': 'network',
      'asset': _nativeAssetJson(),
      'amount': replacement.stageIntent.maxTotalNetworkFee.amount,
      'included': false,
      'valuation': null,
    },
  ],
  'required_total_network_fee': {
    'asset': replacement.stageIntent.maxTotalNetworkFee.asset.toJson(),
    'amount': replacement.stageIntent.maxTotalNetworkFee.amount,
  },
  'selected_tools': replacement.stageIntent.selectedTools.toJson(),
  'expires_at': replacement.stageIntent.consentExpiresAt.toIso8601String(),
  'replacement_stage_consent': replacement.toJson(),
};

kdf.RouteConsent _durableConsentForAction(kdf.RouteConsent source) {
  final expiresAt = DateTime.now().toUtc().add(const Duration(hours: 1));
  final json = _deepCopy(source.toJson());
  json['consent_expires_at'] = expiresAt.toIso8601String();
  final routeIntentJson = _map(json['route_intent']);
  routeIntentJson['consent_expires_at'] = expiresAt.toIso8601String();
  final routeIntent = kdf.TradeIntent.fromJson(routeIntentJson);
  final routeIntentDigest = kdf.tradeRouteIntentDigest(routeIntent);
  for (final guardValue in json['atomic_order_guards']! as List<dynamic>) {
    final guard = _map(guardValue);
    guard['route_intent_digest'] = routeIntentDigest;
    guard['expires_at'] = expiresAt.toIso8601String();
  }
  for (final stageValue in json['external_stage_consents']! as List<dynamic>) {
    final stageJson = _map(stageValue);
    stageJson['route_intent'] = _deepCopy(routeIntentJson);
    final intent = _map(stageJson['stage_intent']);
    intent['route_intent_digest'] = routeIntentDigest;
    intent['consent_expires_at'] = expiresAt.toIso8601String();
    final guardValue = stageJson['atomic_order_guard'];
    if (guardValue != null) {
      final guard = _map(guardValue);
      guard['route_intent_digest'] = routeIntentDigest;
      guard['expires_at'] = expiresAt.toIso8601String();
    }
    final stage = kdf.StageConsent.fromJson(stageJson);
    stageJson['consent_digest'] = kdf.tradeRouteStageConsentDigest(stage);
  }
  var consent = kdf.RouteConsent.fromJson(json);
  json['route_consent_digest'] = kdf.tradeRouteConsentDigest(consent);
  consent = kdf.RouteConsent.fromJson(json);
  return consent;
}

kdf.PrepareExecutionResult _rebindOuterPreparationDigests(
  Map<String, dynamic> result,
) {
  final review = kdf.PreparedExecutionReview.fromJson(_map(result['review']));
  final routeConsentJson = _map(result['route_consent']);
  final externalStages =
      routeConsentJson['external_stage_consents']! as List<dynamic>;
  for (var index = 0; index < externalStages.length; index++) {
    final stageJson = _map(externalStages[index]);
    var stage = kdf.StageConsent.fromJson(stageJson);
    stageJson['consent_digest'] = kdf.tradeRouteStageConsentDigest(stage);
    stage = kdf.StageConsent.fromJson(stageJson);
    externalStages[index] = stageJson;
  }
  routeConsentJson['prepared_review_digest'] = kdf
      .tradeRoutePreparedExecutionReviewDigest(review);
  var routeConsent = kdf.RouteConsent.fromJson(routeConsentJson);
  routeConsentJson['route_consent_digest'] = kdf.tradeRouteConsentDigest(
    routeConsent,
  );
  routeConsent = kdf.RouteConsent.fromJson(routeConsentJson);
  return kdf.PrepareExecutionResult(review: review, routeConsent: routeConsent);
}

Map<String, dynamic> _deepCopy(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

Map<String, dynamic> _map(Object? value) => value! as Map<String, dynamic>;

const _eth = UnifiedSwapAssetIdentity(
  ticker: 'ETH',
  chainFamily: UnifiedSwapChainFamily.evm,
  chainId: '1',
  kind: UnifiedSwapAssetKind.native,
  decimals: 18,
);

const _btc = UnifiedSwapAssetIdentity(
  ticker: 'BTC',
  chainFamily: UnifiedSwapChainFamily.utxo,
  chainId: 'bitcoin-mainnet',
  kind: UnifiedSwapAssetKind.native,
  decimals: 8,
);
