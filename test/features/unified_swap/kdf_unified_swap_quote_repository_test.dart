import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart' as kdf;
import 'package:web_dex/features/unified_swap/domain/route_activity_models.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_capability_policy.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_product_policy.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_quote_models.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_quote_repository.dart';
import 'package:web_dex/features/unified_swap/infrastructure/kdf_unified_swap_quote_repository.dart';

void main() {
  late Map<String, dynamic> vectors;
  final now = DateTime.utc(2026, 7, 16, 12);

  setUpAll(() {
    vectors =
        jsonDecode(
              File(
                'sdk/packages/komodo_defi_rpc_methods/test/fixtures/trade_route/'
                'external_liquidity_digest_vectors.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
  });

  test(
    'uses executable Case-A quote and maps exact fees and valuation',
    () async {
      final candidate = _candidateJson(vectors);
      candidate['fees'] = [
        {
          'fee_type': 'network',
          'asset': _deepCopy(
            _map((candidate['stages']! as List<dynamic>).first)['from_asset']!
                as Map<String, dynamic>,
          ),
          'amount': '2',
          'included': false,
          'valuation': null,
        },
      ];
      _rebindCandidateDigest(candidate);
      final client = _FakeQuoteClient(_result(candidate));
      final repository = KdfUnifiedSwapQuoteRepository(
        client: client,
        walletId: 'wallet-a',
        eligibilityCheck: (_) async => true,
        validateRecipient: ({required ticker, required address}) async =>
            ticker == 'BTC' && address == _recipient,
        valuationSnapshot: () => _valuation(now),
        now: () => now,
      );

      final evaluation = await repository.evaluate(_intent(1));

      expect(repository.walletId, 'wallet-a');
      expect(client.calls, 1);
      expect(client.routeSources, const [
        kdf.RouteSource.kdf,
        kdf.RouteSource.lifi,
        kdf.RouteSource.mixed,
      ]);
      expect(
        client.intent!.sourceAddress,
        isA<kdf.ActiveSourceAddressSelector>(),
      );
      expect(client.intent!.fromAsset.ticker, 'ETH');
      expect(client.intent!.recipient, _recipient);
      final mapped = evaluation.candidates.single;
      expect(mapped.topology, UnifiedSwapTopology.externalToAtomic);
      expect(mapped.rankable, isTrue);
      expect(mapped.valuation?.currency, 'USD');
      expect(mapped.fees.single.kind, RouteFeeKind.network);
      expect(mapped.fees.single.asset.ticker, 'ETH');
      expect(mapped.fees.single.amount, '2');
      expect(mapped.isExecutable, isTrue);
    },
  );

  test(
    'derives the 3 percent warning from exact fresh valuation prices',
    () async {
      final candidate = _candidateJson(vectors);
      final parsed = kdf.TradeRouteCandidate.fromJson(candidate);
      final first = parsed.stages.first as kdf.ExternalLiquidityRouteStage;
      final last = parsed.stages.last as kdf.KdfAtomicRouteStage;
      final repository = KdfUnifiedSwapQuoteRepository(
        client: _FakeQuoteClient(_result(candidate)),
        walletId: 'wallet-a',
        eligibilityCheck: (_) async => true,
        validateRecipient: ({required ticker, required address}) async => true,
        valuationSnapshot: () => _valuation(
          now,
          prices: [
            kdf.AssetValuationPrice(
              asset: first.common.fromAsset,
              price: '2000',
              observedAt: now,
            ),
            kdf.AssetValuationPrice(
              asset: last.common.toAsset,
              price: '30000',
              observedAt: now,
            ),
          ],
        ),
        now: () => now,
      );

      final evaluation = await repository.evaluate(_intent(31));

      expect(evaluation.candidates.single.priceImpactBps, 9850);
      expect(evaluation.candidates.single.riskWarnings.highPriceImpact, isTrue);
    },
  );

  test('HD selection excludes direct and mixed atomic sources', () async {
    final client = _FakeQuoteClient(_result(_candidateJson(vectors)));
    final repository = KdfUnifiedSwapQuoteRepository(
      client: client,
      walletId: 'wallet-a',
      eligibilityCheck: (_) async => true,
      validateRecipient: ({required ticker, required address}) async => true,
      now: () => now,
    );
    final intent = _intent(
      2,
      sourceSelection: UnifiedSwapHdAddressSourceSelection(
        accountId: 0,
        chain: UnifiedSwapHdChain.external,
        addressId: 7,
      ),
    );

    await repository.evaluate(intent);

    expect(client.routeSources, const [kdf.RouteSource.lifi]);
    expect(client.intent!.sourceAddress.toJson(), {
      'selector_type': 'hd',
      'selector': {'account_id': 0, 'chain': 'External', 'address_id': 7},
    });
  });

  test('invalid recipient fails before any quote request', () async {
    final client = _FakeQuoteClient(_result(_candidateJson(vectors)));
    final repository = KdfUnifiedSwapQuoteRepository(
      client: client,
      walletId: 'wallet-a',
      eligibilityCheck: (_) async => true,
      validateRecipient: ({required ticker, required address}) async => false,
      now: () => now,
    );

    await expectLater(
      repository.evaluate(_intent(3)),
      throwsA(
        isA<UnifiedSwapQuoteException>().having(
          (error) => error.failure,
          'failure',
          UnifiedSwapQuoteFailure.invalidIntent,
        ),
      ),
    );
    expect(client.calls, 0);
  });

  test('missing and throwing eligibility checks fail closed', () async {
    for (final eligibilityCheck in <UnifiedSwapEligibilityCheck?>[
      null,
      (_) async => throw StateError('private compliance failure'),
    ]) {
      final client = _FakeQuoteClient(_result(_candidateJson(vectors)));
      final repository = KdfUnifiedSwapQuoteRepository(
        client: client,
        walletId: 'wallet-a',
        eligibilityCheck: eligibilityCheck,
        validateRecipient: ({required ticker, required address}) async => true,
        now: () => now,
      );

      await expectLater(
        repository.evaluate(_intent(30)),
        throwsA(
          isA<UnifiedSwapQuoteException>()
              .having(
                (error) => error.failure,
                'failure',
                UnifiedSwapQuoteFailure.capabilityUnavailable,
              )
              .having(
                (error) => error.toString(),
                'sanitized error',
                isNot(contains('private compliance failure')),
              ),
        ),
      );
      expect(client.calls, 0);
    }
  });

  test('an eligibility transition after quoting discards the result', () async {
    final client = _FakeQuoteClient(_result(_candidateJson(vectors)));
    var eligibilityCalls = 0;
    final repository = KdfUnifiedSwapQuoteRepository(
      client: client,
      walletId: 'wallet-a',
      eligibilityCheck: (_) async => ++eligibilityCalls == 1,
      validateRecipient: ({required ticker, required address}) async => true,
      now: () => now,
    );

    await expectLater(
      repository.evaluate(_intent(32)),
      throwsA(
        isA<UnifiedSwapQuoteException>().having(
          (error) => error.failure,
          'failure',
          UnifiedSwapQuoteFailure.capabilityUnavailable,
        ),
      ),
    );
    expect(client.calls, 1);
  });

  test(
    'missing or stale wallet valuation makes the candidate unrankable',
    () async {
      final client = _FakeQuoteClient(_result(_candidateJson(vectors)));
      final repository = KdfUnifiedSwapQuoteRepository(
        client: client,
        walletId: 'wallet-a',
        eligibilityCheck: (_) async => true,
        validateRecipient: ({required ticker, required address}) async => true,
        valuationSnapshot: () => _valuation(
          now,
          validUntil: now.subtract(const Duration(seconds: 1)),
        ),
        now: () => now,
      );

      final evaluation = await repository.evaluate(_intent(4));

      expect(client.valuationSnapshot, isNull);
      expect(evaluation.candidates.single.rankable, isFalse);
      expect(evaluation.candidates.single.rank, isNull);
      expect(evaluation.candidates.single.valuation, isNull);
    },
  );

  test('unknown KDF stage remains visible but non-executable', () async {
    final candidate = _candidateJson(vectors);
    candidate['stages'] = [
      {'stage_type': 'future_stage', 'safe': true},
    ];
    final client = _FakeQuoteClient(_result(candidate));
    final repository = KdfUnifiedSwapQuoteRepository(
      client: client,
      walletId: 'wallet-a',
      eligibilityCheck: (_) async => true,
      validateRecipient: ({required ticker, required address}) async => true,
      valuationSnapshot: () => _valuation(now),
      now: () => now,
    );

    final evaluation = await repository.evaluate(_intent(5));

    expect(evaluation.candidates.single.topology, UnifiedSwapTopology.unknown);
    expect(evaluation.candidates.single.isExecutable, isFalse);
    expect(
      evaluation.candidates.single.rawUnknownDiscriminator,
      contains('future_stage'),
    );
  });

  test(
    'candidate digest mismatch remains visible but non-executable',
    () async {
      final candidate = _candidateJson(vectors);
      candidate['candidate_digest'] = List.filled(64, '0').join();
      final client = _FakeQuoteClient(_result(candidate));
      final repository = KdfUnifiedSwapQuoteRepository(
        client: client,
        walletId: 'wallet-a',
        eligibilityCheck: (_) async => true,
        validateRecipient: ({required ticker, required address}) async => true,
        now: () => now,
      );

      final evaluation = await repository.evaluate(_intent(6));

      expect(evaluation.candidates.single.isExecutable, isFalse);
      expect(
        evaluation.candidates.single.rawUnknownDiscriminator,
        contains('candidate_digest_mismatch'),
      );
    },
  );

  test('prepares only the retained exact quote with explicit limits', () async {
    final preparedJson = _map(
      _map(
        jsonDecode(
          File(
            'sdk/packages/komodo_defi_rpc_methods/test/fixtures/trade_route/'
            'prepare_execution_response.json',
          ).readAsStringSync(),
        ),
      )['result'],
    );
    final prepared = _preparedWithQuietLimit(preparedJson);
    final client = _FakeQuoteClient(
      _result(
        _candidateJson(vectors),
        evaluationId: prepared.review.evaluationId,
        evaluationExpiresAt: prepared.review.expiresAt,
      ),
      prepared: prepared,
    );
    final externalConsent = prepared.routeConsent.externalStageConsents.single;
    final repository = KdfUnifiedSwapQuoteRepository(
      client: client,
      walletId: 'wallet-a',
      eligibilityCheck: (_) async => true,
      validateRecipient: ({required ticker, required address}) async => true,
      expectedSourceAddress: (_) async =>
          '0x9999999999999999999999999999999999999999',
      preparationLimitsPolicy: ({required intent, required candidate}) async {
        final stageIntent = externalConsent.stageIntent;
        return [
          kdf.PrepareExecutionStageLimits(
            stageId: stageIntent.stageId,
            maxExpectedReceiveDegradationBps: 25,
            nonNetworkFeeLimits: stageIntent.nonNetworkFeeLimits,
            maxTotalNetworkFee: stageIntent.maxTotalNetworkFee,
          ),
        ];
      },
      now: () => now,
    );
    final intent = _preparedIntent(7);
    final evaluation = await repository.evaluate(intent);

    final result = await repository.prepareExecution(
      intent: intent,
      candidate: evaluation.candidates.single,
    );

    expect(result.prepared, same(prepared));
    expect(client.preparationCalls, 1);
    expect(client.preparedEvaluationId, prepared.review.evaluationId);
    expect(client.preparedCandidateDigest, prepared.review.candidateDigest);
    expect(client.preparedMinimumReceive, prepared.review.minimumReceive);
    expect(client.preparedStages.single.maxExpectedReceiveDegradationBps, 25);
  });

  test('rechecks eligibility and normalizes failure before prepare', () async {
    final preparedJson = _map(
      _map(
        jsonDecode(
          File(
            'sdk/packages/komodo_defi_rpc_methods/test/fixtures/trade_route/'
            'prepare_execution_response.json',
          ).readAsStringSync(),
        ),
      )['result'],
    );
    final prepared = _preparedWithQuietLimit(preparedJson);
    final client = _FakeQuoteClient(
      _result(
        _candidateJson(vectors),
        evaluationId: prepared.review.evaluationId,
        evaluationExpiresAt: prepared.review.expiresAt,
      ),
      prepared: prepared,
    );
    var eligibilityCalls = 0;
    final external = prepared.routeConsent.externalStageConsents.single;
    final repository = KdfUnifiedSwapQuoteRepository(
      client: client,
      walletId: 'wallet-a',
      eligibilityCheck: (_) async {
        eligibilityCalls++;
        if (eligibilityCalls > 2) {
          throw StateError('private compliance failure');
        }
        return true;
      },
      validateRecipient: ({required ticker, required address}) async => true,
      expectedSourceAddress: (_) async =>
          '0x9999999999999999999999999999999999999999',
      preparationLimitsPolicy: ({required intent, required candidate}) async =>
          [
            kdf.PrepareExecutionStageLimits(
              stageId: external.stageIntent.stageId,
              maxExpectedReceiveDegradationBps: 25,
              nonNetworkFeeLimits: external.stageIntent.nonNetworkFeeLimits,
              maxTotalNetworkFee: external.stageIntent.maxTotalNetworkFee,
            ),
          ],
      now: () => now,
    );
    final intent = _preparedIntent(31);
    final evaluation = await repository.evaluate(intent);

    await expectLater(
      repository.prepareExecution(
        intent: intent,
        candidate: evaluation.candidates.single,
      ),
      throwsA(
        isA<UnifiedSwapQuoteException>().having(
          (error) => error.failure,
          'failure',
          UnifiedSwapQuoteFailure.capabilityUnavailable,
        ),
      ),
    );
    expect(client.preparationCalls, 0);
  });

  test(
    'rejects a re-digested Review that changes the retained route',
    () async {
      final preparedJson = _map(
        _map(
          jsonDecode(
            File(
              'sdk/packages/komodo_defi_rpc_methods/test/fixtures/trade_route/'
              'prepare_execution_response.json',
            ).readAsStringSync(),
          ),
        )['result'],
      );
      final reviewJson = _map(preparedJson['review']);
      reviewJson['expected_receive'] = '99999';
      final stages = reviewJson['stages']! as List<dynamic>;
      final lastStage = _map(stages.last);
      lastStage['expected_receive'] = '99999';
      stages[stages.length - 1] = lastStage;
      reviewJson['stages'] = stages;
      preparedJson['review'] = reviewJson;
      final prepared = _preparedWithQuietLimit(preparedJson);
      final externalConsent =
          prepared.routeConsent.externalStageConsents.single;
      final client = _FakeQuoteClient(
        _result(
          _candidateJson(vectors),
          evaluationId: prepared.review.evaluationId,
          evaluationExpiresAt: prepared.review.expiresAt,
        ),
        prepared: prepared,
      );
      final repository = KdfUnifiedSwapQuoteRepository(
        client: client,
        walletId: 'wallet-a',
        eligibilityCheck: (_) async => true,
        validateRecipient: ({required ticker, required address}) async => true,
        expectedSourceAddress: (_) async =>
            '0x9999999999999999999999999999999999999999',
        preparationLimitsPolicy: ({required intent, required candidate}) async {
          final stageIntent = externalConsent.stageIntent;
          return [
            kdf.PrepareExecutionStageLimits(
              stageId: stageIntent.stageId,
              maxExpectedReceiveDegradationBps: 25,
              nonNetworkFeeLimits: stageIntent.nonNetworkFeeLimits,
              maxTotalNetworkFee: stageIntent.maxTotalNetworkFee,
            ),
          ];
        },
        now: () => now,
      );
      final intent = _preparedIntent(8);
      final evaluation = await repository.evaluate(intent);

      await expectLater(
        repository.prepareExecution(
          intent: intent,
          candidate: evaluation.candidates.single,
        ),
        throwsA(
          isA<UnifiedSwapQuoteException>().having(
            (error) => error.failure,
            'failure',
            UnifiedSwapQuoteFailure.invalidIntent,
          ),
        ),
      );
    },
  );

  test('rejects coordinated re-digested hidden authority changes', () async {
    final fixture = _map(
      _map(
        jsonDecode(
          File(
            'sdk/packages/komodo_defi_rpc_methods/test/fixtures/trade_route/'
            'prepare_execution_response.json',
          ).readAsStringSync(),
        ),
      )['result'],
    );
    final mutations = <void Function(Map<String, dynamic>)>[
      (result) {
        final consent = _map(
          (_map(result['route_consent'])['external_stage_consents']! as List)
              .single,
        );
        final source = _map(consent['execution_source']);
        source['provider_step_digest'] =
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
        _map(source['provider_step_reference'])['provider_step_digest'] =
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
      },
      (result) {
        final routeConsent = _map(result['route_consent']);
        _map(
          (routeConsent['atomic_order_guards']! as List).single,
        )['requested_volume'] = '0.2';
        final stageConsent = _map(
          (routeConsent['external_stage_consents']! as List).single,
        );
        _map(stageConsent['atomic_order_guard'])['requested_volume'] = '0.2';
      },
      (result) {
        final stageConsent = _map(
          (_map(result['route_consent'])['external_stage_consents']! as List)
              .single,
        );
        _map(
          _map(stageConsent['stage_intent'])['provider_tokens'],
        )['to_token'] = '0x3333333333333333333333333333333333333333';
      },
      (result) {
        final stageConsent = _map(
          (_map(result['route_consent'])['external_stage_consents']! as List)
              .single,
        );
        _map(_map(stageConsent['stage_intent'])['tool_policy'])['exchanges'] = {
          'allow': ['future-tool'],
          'deny': <String>[],
          'prefer': ['future-tool'],
        };
      },
    ];

    for (var index = 0; index < mutations.length; index++) {
      final resultJson = _deepCopy(fixture);
      mutations[index](resultJson);
      final tampered = _preparedWithQuietLimit(resultJson);
      final externalConsent =
          tampered.routeConsent.externalStageConsents.single;
      final client = _FakeQuoteClient(
        _result(
          _candidateJson(vectors),
          evaluationId: tampered.review.evaluationId,
          evaluationExpiresAt: tampered.review.expiresAt,
        ),
        prepared: tampered,
      );
      final repository = KdfUnifiedSwapQuoteRepository(
        client: client,
        walletId: 'wallet-a',
        eligibilityCheck: (_) async => true,
        validateRecipient: ({required ticker, required address}) async => true,
        expectedSourceAddress: (_) async =>
            '0x9999999999999999999999999999999999999999',
        preparationLimitsPolicy:
            ({required intent, required candidate}) async => [
              kdf.PrepareExecutionStageLimits(
                stageId: externalConsent.stageIntent.stageId,
                maxExpectedReceiveDegradationBps: 25,
                nonNetworkFeeLimits:
                    externalConsent.stageIntent.nonNetworkFeeLimits,
                maxTotalNetworkFee:
                    externalConsent.stageIntent.maxTotalNetworkFee,
              ),
            ],
        now: () => now,
      );
      final intent = _preparedIntent(20 + index);
      final evaluation = await repository.evaluate(intent);

      await expectLater(
        repository.prepareExecution(
          intent: intent,
          candidate: evaluation.candidates.single,
        ),
        throwsA(
          isA<UnifiedSwapQuoteException>().having(
            (error) => error.failure,
            'failure',
            UnifiedSwapQuoteFailure.invalidIntent,
          ),
        ),
        reason: 'hidden authority mutation $index must fail closed',
      );
    }
  });

  test('rejects a duplicate candidate identity set', () async {
    final candidate = kdf.TradeRouteCandidate.fromJson(_candidateJson(vectors));
    final result = kdf.TradeRouteQuoteResult(
      evaluationId: '00000000-0000-4000-8000-000000000098',
      observedAt: now,
      evaluationExpiresAt: now.add(const Duration(minutes: 1)),
      candidates: [candidate, candidate],
    );
    final repository = KdfUnifiedSwapQuoteRepository(
      client: _FakeQuoteClient(result),
      walletId: 'wallet-a',
      eligibilityCheck: (_) async => true,
      validateRecipient: ({required ticker, required address}) async => true,
      now: () => now,
    );

    await expectLater(
      repository.evaluate(_intent(80)),
      throwsA(
        isA<UnifiedSwapQuoteException>().having(
          (error) => error.failure,
          'failure',
          UnifiedSwapQuoteFailure.capabilityUnavailable,
        ),
      ),
    );
  });

  test('rejects an already expired evaluation envelope', () async {
    final repository = KdfUnifiedSwapQuoteRepository(
      client: _FakeQuoteClient(
        _result(_candidateJson(vectors), evaluationExpiresAt: now),
      ),
      walletId: 'wallet-a',
      eligibilityCheck: (_) async => true,
      validateRecipient: ({required ticker, required address}) async => true,
      now: () => now,
    );

    await expectLater(
      repository.evaluate(_intent(81)),
      throwsA(
        isA<UnifiedSwapQuoteException>().having(
          (error) => error.failure,
          'failure',
          UnifiedSwapQuoteFailure.quoteExpired,
        ),
      ),
    );
  });

  test(
    'candidate policy keeps an unsupported route visible but inert',
    () async {
      final repository = KdfUnifiedSwapQuoteRepository(
        client: _FakeQuoteClient(_result(_candidateJson(vectors))),
        walletId: 'wallet-a',
        eligibilityCheck: (_) async => true,
        candidateEligibility: ({required intent, required candidate}) => false,
        validateRecipient: ({required ticker, required address}) async => true,
        now: () => now,
      );

      final evaluation = await repository.evaluate(_intent(82));

      expect(evaluation.candidates.single.isExecutable, isFalse);
      expect(
        evaluation.candidates.single.rawUnknownDiscriminator,
        contains('funding_authority_unavailable'),
      );
    },
  );

  test('rejects a quote envelope observed in the future', () async {
    final result = kdf.TradeRouteQuoteResult(
      evaluationId: '00000000-0000-4000-8000-000000000097',
      observedAt: now.add(const Duration(seconds: 1)),
      evaluationExpiresAt: now.add(const Duration(minutes: 1)),
      candidates: [kdf.TradeRouteCandidate.fromJson(_candidateJson(vectors))],
    );
    final repository = KdfUnifiedSwapQuoteRepository(
      client: _FakeQuoteClient(result),
      walletId: 'wallet-a',
      eligibilityCheck: (_) async => true,
      validateRecipient: ({required ticker, required address}) async => true,
      now: () => now,
    );

    await expectLater(
      repository.evaluate(_intent(83)),
      throwsA(
        isA<UnifiedSwapQuoteException>().having(
          (error) => error.failure,
          'failure',
          UnifiedSwapQuoteFailure.quoteExpired,
        ),
      ),
    );
  });

  test('rejects a disconnected asset path', () async {
    final candidate = _candidateJson(vectors);
    final stages = candidate['stages']! as List<dynamic>;
    _map(stages[1])['from_asset'] = {
      ..._map(_map(stages[1])['from_asset']),
      'ticker': 'DAI',
    };
    _rebindCandidateDigest(candidate);
    final repository = KdfUnifiedSwapQuoteRepository(
      client: _FakeQuoteClient(_result(candidate)),
      walletId: 'wallet-a',
      eligibilityCheck: (_) async => true,
      validateRecipient: ({required ticker, required address}) async => true,
      now: () => now,
    );

    await expectLater(
      repository.evaluate(_intent(84)),
      throwsA(
        isA<UnifiedSwapQuoteException>().having(
          (error) => error.failure,
          'failure',
          UnifiedSwapQuoteFailure.capabilityUnavailable,
        ),
      ),
    );
  });

  test('rejects impossible intermediate-stage economics', () async {
    final candidate = _candidateJson(vectors);
    final secondStage = _map((candidate['stages']! as List<dynamic>)[1]);
    secondStage['source_amount'] = '1';
    secondStage['trade_source_amount'] = '1';
    _rebindCandidateDigest(candidate);
    final repository = KdfUnifiedSwapQuoteRepository(
      client: _FakeQuoteClient(_result(candidate)),
      walletId: 'wallet-a',
      eligibilityCheck: (_) async => true,
      validateRecipient: ({required ticker, required address}) async => true,
      now: () => now,
    );

    await expectLater(
      repository.evaluate(_intent(85)),
      throwsA(
        isA<UnifiedSwapQuoteException>().having(
          (error) => error.failure,
          'failure',
          UnifiedSwapQuoteFailure.capabilityUnavailable,
        ),
      ),
    );
  });
}

final class _FakeQuoteClient
    implements KdfUnifiedSwapQuoteClient, KdfUnifiedSwapPreparationClient {
  _FakeQuoteClient(this.result, {this.prepared});

  final kdf.TradeRouteQuoteResult result;
  final kdf.PrepareExecutionResult? prepared;
  int calls = 0;
  int preparationCalls = 0;
  kdf.TradeIntent? intent;
  List<kdf.RouteSource>? routeSources;
  kdf.ValuationSnapshot? valuationSnapshot;
  String? preparedEvaluationId;
  String? preparedCandidateDigest;
  String? preparedMinimumReceive;
  List<kdf.PrepareExecutionStageLimits> preparedStages = const [];

  @override
  Future<kdf.TradeRouteQuoteResult> quote({
    required kdf.TradeIntent intent,
    required List<kdf.RouteSource> routeSources,
    kdf.ValuationSnapshot? valuationSnapshot,
  }) async {
    calls++;
    this.intent = intent;
    this.routeSources = routeSources;
    this.valuationSnapshot = valuationSnapshot;
    return result;
  }

  @override
  Future<kdf.PrepareExecutionResult> prepareExecution({
    required String evaluationId,
    required String candidateId,
    required String candidateDigest,
    required String finalMinimumReceive,
    required DateTime consentExpiresAt,
    required List<kdf.PrepareExecutionStageLimits> stages,
  }) async {
    preparationCalls++;
    preparedEvaluationId = evaluationId;
    preparedCandidateDigest = candidateDigest;
    preparedMinimumReceive = finalMinimumReceive;
    preparedStages = stages;
    return prepared ?? (throw StateError('Unexpected preparation request'));
  }
}

UnifiedSwapIntent _intent(
  int revision, {
  UnifiedSwapSourceSelection sourceSelection =
      const UnifiedSwapActiveSourceSelection(),
}) => UnifiedSwapIntent(
  revision: revision,
  source: _eth,
  destination: _btc,
  sourceAmount: '1000000000000000000',
  sourceSelection: sourceSelection,
  recipient: _recipient,
  sourceTokenTrust: UnifiedSwapTokenTrust.trusted,
  destinationTokenTrust: UnifiedSwapTokenTrust.trusted,
);

UnifiedSwapIntent _preparedIntent(int revision) => UnifiedSwapIntent(
  revision: revision,
  source: _eth,
  destination: _btc,
  sourceAmount: '1000000000000000000',
  sourceSelection: const UnifiedSwapActiveSourceSelection(),
  recipient: 'bc1qrecipient',
  sourceTokenTrust: UnifiedSwapTokenTrust.trusted,
  destinationTokenTrust: UnifiedSwapTokenTrust.trusted,
);

kdf.TradeRouteQuoteResult _result(
  Map<String, dynamic> candidate, {
  String evaluationId = '00000000-0000-4000-8000-000000000099',
  DateTime? evaluationExpiresAt,
}) => kdf.TradeRouteQuoteResult.fromJson({
  'evaluation_id': evaluationId,
  'observed_at': '2026-07-16T12:00:00Z',
  'evaluation_expires_at':
      (evaluationExpiresAt ?? DateTime.utc(2026, 7, 16, 12, 1))
          .toIso8601String(),
  'candidates': [candidate],
});

Map<String, dynamic> _candidateJson(Map<String, dynamic> vectors) {
  final fixture = _map(vectors['candidate']);
  final candidate = _deepCopy(_map(fixture['value']));
  candidate['candidate_digest'] = fixture['digest'];
  return candidate;
}

void _rebindCandidateDigest(Map<String, dynamic> candidate) {
  final parsed = kdf.TradeRouteCandidate.fromJson(candidate);
  candidate['candidate_digest'] = kdf.tradeRouteCandidateDigest(parsed);
}

kdf.PrepareExecutionResult _preparedWithQuietLimit(
  Map<String, dynamic> source,
) {
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
  final atomicGuards = consentJson['atomic_order_guards']! as List;
  for (final guard in atomicGuards) {
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
  var consent = kdf.RouteConsent.fromJson(consentJson);
  consentJson['route_consent_digest'] = kdf.tradeRouteConsentDigest(consent);
  consent = kdf.RouteConsent.fromJson(consentJson);
  return kdf.PrepareExecutionResult(review: review, routeConsent: consent);
}

kdf.ValuationSnapshot _valuation(
  DateTime now, {
  DateTime? validUntil,
  List<kdf.AssetValuationPrice> prices = const [],
}) => kdf.ValuationSnapshot(
  currency: kdf.ValuationCurrency.usd,
  source: kdf.ValuationSource.walletMarketData,
  observedAt: now,
  validUntil: validUntil ?? now.add(const Duration(minutes: 1)),
  prices: prices,
);

Map<String, dynamic> _deepCopy(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

Map<String, dynamic> _map(Object? value) => value! as Map<String, dynamic>;

const _recipient = 'bc1qrecipient';

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
