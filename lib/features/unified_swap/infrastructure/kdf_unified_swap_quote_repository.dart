import 'dart:async';

import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart' as kdf;
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:web_dex/features/unified_swap/domain/route_activity_models.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_capability_policy.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_model_limits.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_product_policy.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_quote_models.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_quote_repository.dart';

typedef UnifiedSwapRecipientValidator =
    Future<bool> Function({required String ticker, required String address});

typedef UnifiedSwapExactRecipientValidator =
    Future<bool> Function({
      required UnifiedSwapAssetIdentity asset,
      required String address,
    });

abstract interface class KdfUnifiedSwapQuoteClient {
  Future<kdf.TradeRouteQuoteResult> quote({
    required kdf.TradeIntent intent,
    required List<kdf.RouteSource> routeSources,
    kdf.ValuationSnapshot? valuationSnapshot,
  });
}

abstract interface class KdfUnifiedSwapPreparationClient {
  Future<kdf.PrepareExecutionResult> prepareExecution({
    required String evaluationId,
    required String candidateId,
    required String candidateDigest,
    required String finalMinimumReceive,
    required DateTime consentExpiresAt,
    required List<kdf.PrepareExecutionStageLimits> stages,
  });
}

typedef UnifiedSwapPreparationLimitsPolicy =
    Future<List<kdf.PrepareExecutionStageLimits>?> Function({
      required UnifiedSwapIntent intent,
      required kdf.TradeRouteCandidate candidate,
    });

typedef UnifiedSwapExpectedSourceAddressResolver =
    Future<String?> Function(UnifiedSwapIntent intent);

typedef UnifiedSwapEligibilityCheck =
    Future<bool> Function(UnifiedSwapIntent intent);

typedef UnifiedSwapQuoteCandidateEligibility =
    bool Function({
      required UnifiedSwapIntent intent,
      required kdf.TradeRouteCandidate candidate,
    });

/// An unforgeable capability produced only after the retained quote, wallet
/// source, Review, stage limits, and every nested KDF digest have matched.
final class KdfVerifiedPreparedExecution {
  const KdfVerifiedPreparedExecution._({
    required this.prepared,
    required this.intent,
    required this.riskWarnings,
    required _ExactQuoteBinding binding,
    required List<kdf.PrepareExecutionStageLimits> limits,
  }) : _binding = binding,
       _limits = limits;

  final kdf.PrepareExecutionResult prepared;
  final UnifiedSwapIntent intent;
  final UnifiedSwapRiskWarnings riskWarnings;
  final _ExactQuoteBinding _binding;
  final List<kdf.PrepareExecutionStageLimits> _limits;
}

sealed class KdfPreparedExecutionRefresh {
  const KdfPreparedExecutionRefresh();
}

final class KdfPreparedExecutionReplacement
    extends KdfPreparedExecutionRefresh {
  const KdfPreparedExecutionReplacement({
    required this.decision,
    required this.verified,
  });

  final UnifiedSwapRefreshDecision decision;
  final KdfVerifiedPreparedExecution verified;
}

final class KdfPreparedExecutionFreshQuote extends KdfPreparedExecutionRefresh {
  const KdfPreparedExecutionFreshQuote({
    required this.intent,
    required this.evaluation,
  });

  final UnifiedSwapIntent intent;
  final UnifiedSwapQuoteEvaluation evaluation;
}

final class TradeRouteManagerQuoteClient
    implements KdfUnifiedSwapQuoteClient, KdfUnifiedSwapPreparationClient {
  const TradeRouteManagerQuoteClient(this.manager);

  final TradeRouteManager manager;

  @override
  Future<kdf.TradeRouteQuoteResult> quote({
    required kdf.TradeIntent intent,
    required List<kdf.RouteSource> routeSources,
    kdf.ValuationSnapshot? valuationSnapshot,
  }) => manager.quote(
    intent: intent,
    routeSources: routeSources,
    valuationSnapshot: valuationSnapshot,
  );

  @override
  Future<kdf.PrepareExecutionResult> prepareExecution({
    required String evaluationId,
    required String candidateId,
    required String candidateDigest,
    required String finalMinimumReceive,
    required DateTime consentExpiresAt,
    required List<kdf.PrepareExecutionStageLimits> stages,
  }) => manager.prepareExecution(
    evaluationId: evaluationId,
    candidateId: candidateId,
    candidateDigest: candidateDigest,
    finalMinimumReceive: finalMinimumReceive,
    consentExpiresAt: consentExpiresAt,
    stages: stages,
  );
}

/// Wallet-bound executable Case-A quote adapter.
///
/// This adapter deliberately has no path to `experimental::trade_route::evaluate`.
/// It validates the recipient with the wallet's chain-aware validator, builds
/// exact KDF asset/source identities, and maps unknown wire variants to inert
/// candidates without retaining provider payloads or backend error text.
final class KdfUnifiedSwapQuoteRepository
    implements UnifiedSwapQuoteRepository {
  KdfUnifiedSwapQuoteRepository({
    required KdfUnifiedSwapQuoteClient client,
    required String walletId,
    required UnifiedSwapRecipientValidator validateRecipient,
    UnifiedSwapExactRecipientValidator? validateExactRecipient,
    KdfUnifiedSwapPreparationClient? preparationClient,
    UnifiedSwapPreparationLimitsPolicy? preparationLimitsPolicy,
    UnifiedSwapExpectedSourceAddressResolver? expectedSourceAddress,
    UnifiedSwapEligibilityCheck? eligibilityCheck,
    UnifiedSwapQuoteCandidateEligibility? candidateEligibility,
    kdf.ValuationSnapshot? Function()? valuationSnapshot,
    DateTime Function()? now,
    this.consentLifetime = const Duration(minutes: 2),
    this.quoteDeadline = const Duration(seconds: 30),
    this.preparationDeadline = const Duration(seconds: 30),
  }) : _client = client,
       _preparationClient =
           preparationClient ??
           (client is KdfUnifiedSwapPreparationClient
               ? client as KdfUnifiedSwapPreparationClient
               : null),
       _preparationLimitsPolicy = preparationLimitsPolicy,
       _expectedSourceAddress = expectedSourceAddress,
       _eligibilityCheck = eligibilityCheck,
       _candidateEligibility = candidateEligibility,
       _walletId = _required(walletId, 'walletId'),
       _validateRecipient = validateRecipient,
       _validateExactRecipient = validateExactRecipient,
       _valuationSnapshot = valuationSnapshot ?? (() => null),
       _now = now ?? (() => DateTime.now().toUtc()) {
    if (consentLifetime <= Duration.zero ||
        consentLifetime > const Duration(minutes: 5)) {
      throw RangeError.range(
        consentLifetime.inSeconds,
        1,
        const Duration(minutes: 5).inSeconds,
        'consentLifetime.inSeconds',
      );
    }
    if (quoteDeadline <= Duration.zero ||
        preparationDeadline <= Duration.zero) {
      throw ArgumentError('Quote and preparation deadlines must be positive');
    }
  }

  final KdfUnifiedSwapQuoteClient _client;
  final KdfUnifiedSwapPreparationClient? _preparationClient;
  final UnifiedSwapPreparationLimitsPolicy? _preparationLimitsPolicy;
  final UnifiedSwapExpectedSourceAddressResolver? _expectedSourceAddress;
  final UnifiedSwapEligibilityCheck? _eligibilityCheck;
  final UnifiedSwapQuoteCandidateEligibility? _candidateEligibility;
  final String _walletId;
  final UnifiedSwapRecipientValidator _validateRecipient;
  final UnifiedSwapExactRecipientValidator? _validateExactRecipient;
  final kdf.ValuationSnapshot? Function() _valuationSnapshot;
  final DateTime Function() _now;
  final Duration consentLifetime;
  final Duration quoteDeadline;
  final Duration preparationDeadline;
  final Map<String, _ExactQuoteBinding> _exactQuotes = {};

  String get walletId => _walletId;

  @override
  Future<UnifiedSwapQuoteEvaluation> evaluate(UnifiedSwapIntent intent) async {
    if (!intent.sourceSelection.isExecutable ||
        intent.tokenFailure != null ||
        !intent.source.isValidEvmV1 ||
        intent.sourceAmount == '0') {
      throw const UnifiedSwapQuoteException(
        UnifiedSwapQuoteFailure.invalidIntent,
      );
    }

    final budget = _OperationBudget(quoteDeadline);
    try {
      if (!await budget.run(() => _isEligible(intent))) {
        throw const UnifiedSwapQuoteException(
          UnifiedSwapQuoteFailure.capabilityUnavailable,
        );
      }
      final exactValidator = _validateExactRecipient;
      final recipientIsValid = exactValidator == null
          ? await budget.run(
              () => _validateRecipient(
                ticker: intent.destination.ticker,
                address: intent.recipient,
              ),
            )
          : await budget.run(
              () => exactValidator(
                asset: intent.destination,
                address: intent.recipient,
              ),
            );
      if (!recipientIsValid) {
        throw const UnifiedSwapQuoteException(
          UnifiedSwapQuoteFailure.invalidIntent,
        );
      }

      final now = _now().toUtc();
      final snapshot = _freshValuationSnapshot(_valuationSnapshot(), now);
      final routeIntent = kdf.TradeIntent(
        fromAsset: _routeAsset(intent.source),
        toAsset: _routeAsset(intent.destination),
        sourceAmount: intent.sourceAmount,
        slippageBps: intent.slippageBps,
        sourceAddress: _sourceSelection(intent.sourceSelection),
        recipient: intent.recipient,
        toolPolicy: kdf.ToolPolicy(),
        consentExpiresAt: now.add(consentLifetime),
      );
      final result = await budget.run(
        () => _client.quote(
          intent: routeIntent,
          routeSources: _routeSources(intent.sourceSelection),
          valuationSnapshot: snapshot,
        ),
      );
      final receivedAt = _now().toUtc();
      _validateQuoteResult(result, routeIntent, receivedAt);
      if (!await budget.run(() => _isEligible(intent))) {
        throw const UnifiedSwapQuoteException(
          UnifiedSwapQuoteFailure.capabilityUnavailable,
        );
      }
      _pruneExactQuotes(receivedAt);
      final candidates = <UnifiedSwapQuoteCandidate>[];
      final bindings = <_ExactQuoteBinding>[];
      for (final candidate in result.candidates) {
        final digestIsValid = _hasValidCandidateDigest(candidate);
        final candidateIsEligible =
            _candidateEligibility?.call(intent: intent, candidate: candidate) ??
            true;
        final mapped = _candidate(
          candidate,
          evaluationExpiresAt: result.evaluationExpiresAt,
          valuationSnapshot: snapshot,
          digestIsValid: digestIsValid,
          candidateIsEligible: candidateIsEligible,
        );
        candidates.add(mapped);
        if (digestIsValid &&
            mapped.isSafelyExecutable &&
            !mapped.isExpiredAt(receivedAt)) {
          bindings.add(
            _ExactQuoteBinding(
              evaluationId: result.evaluationId,
              intent: intent,
              routeIntent: routeIntent,
              candidate: candidate,
              mappedCandidate: mapped,
            ),
          );
        }
      }
      final evaluation = UnifiedSwapQuoteEvaluation(
        evaluationId: result.evaluationId,
        intentRevision: intent.revision,
        candidates: candidates,
      );
      for (final binding in bindings) {
        _exactQuotes[binding.key] = binding;
      }
      _trimExactQuotes();
      return evaluation;
    } on UnifiedSwapQuoteException {
      rethrow;
    } on Object catch (error) {
      throw UnifiedSwapQuoteException(_failureFor(error));
    }
  }

  /// Revalidates one exact digest-verified quote at the Review boundary.
  ///
  /// Fee and degradation limits are a mandatory wallet policy input. This
  /// adapter never guesses a gas cap from aggregate quote fees.
  Future<KdfVerifiedPreparedExecution> prepareExecution({
    required UnifiedSwapIntent intent,
    required UnifiedSwapQuoteCandidate candidate,
  }) async {
    final now = _now().toUtc();
    final budget = _OperationBudget(preparationDeadline);
    _pruneExactQuotes(now);
    final binding = _findBinding(intent, candidate);
    if (_preparationClient == null ||
        _preparationLimitsPolicy == null ||
        _expectedSourceAddress == null ||
        binding == null ||
        !candidate.isExecutable ||
        candidate.isExpiredAt(now)) {
      throw const UnifiedSwapQuoteException(
        UnifiedSwapQuoteFailure.capabilityUnavailable,
      );
    }

    try {
      if (!await budget.run(() => _isEligible(intent))) {
        throw const UnifiedSwapQuoteException(
          UnifiedSwapQuoteFailure.capabilityUnavailable,
        );
      }
      final expectedSourceAddress = await _resolveSourceAddress(intent, budget);
      final limits = await budget.run(() => _limitsFor(binding));
      return await _prepareBinding(
        binding: binding,
        limits: limits,
        expectedSourceAddress: expectedSourceAddress,
        budget: budget,
      );
    } on UnifiedSwapQuoteException {
      rethrow;
    } on Object catch (error) {
      throw UnifiedSwapQuoteException(_failureFor(error));
    }
  }

  /// Quotes again and prepares the one unique semantic equivalent of the
  /// reviewed route. The quiet attempt is always bounded by the old consent.
  Future<KdfPreparedExecutionRefresh> refreshPreparedExecution({
    required KdfVerifiedPreparedExecution consented,
  }) async {
    final now = _now().toUtc();
    final budget = _OperationBudget(quoteDeadline + preparationDeadline);
    if (!consented.prepared.review.expiresAt.isAfter(now)) {
      throw const UnifiedSwapQuoteException(
        UnifiedSwapQuoteFailure.quoteExpired,
      );
    }

    try {
      final evaluation = await budget.run(() => evaluate(consented.intent));
      final expectedSourceAddress = await _resolveSourceAddress(
        consented.intent,
        budget,
      );
      final refreshedAt = _now().toUtc();
      final freshBindings = _exactQuotes.values
          .where(
            (binding) =>
                binding.evaluationId == evaluation.evaluationId &&
                binding.intent == consented.intent &&
                binding.mappedCandidate.isSafelyExecutable &&
                !binding.mappedCandidate.isExpiredAt(refreshedAt),
          )
          .toList(growable: false);
      if (freshBindings.isEmpty) {
        if (evaluation.candidates.isNotEmpty) {
          return KdfPreparedExecutionFreshQuote(
            intent: consented.intent,
            evaluation: evaluation,
          );
        }
        throw const UnifiedSwapQuoteException(
          UnifiedSwapQuoteFailure.quoteExpired,
        );
      }

      final oldFingerprint = _semanticFingerprint(
        consented._binding,
        consented.prepared.review.resolvedSourceAddress,
      );
      final matches = freshBindings
          .where(
            (binding) =>
                _semanticFingerprint(binding, expectedSourceAddress) ==
                oldFingerprint,
          )
          .toList(growable: false);
      if (matches.length != 1) {
        return KdfPreparedExecutionFreshQuote(
          intent: consented.intent,
          evaluation: evaluation,
        );
      }

      final binding = matches.single;
      final oldLimits = _remapPreparationLimits(
        from: consented._binding,
        to: binding,
        limits: consented._limits,
      );
      if (oldLimits == null) {
        return KdfPreparedExecutionFreshQuote(
          intent: consented.intent,
          evaluation: evaluation,
        );
      }

      late KdfVerifiedPreparedExecution replacement;
      var widenedForExplicitConsent = false;
      try {
        replacement = await _prepareBinding(
          binding: binding,
          limits: oldLimits,
          expectedSourceAddress: expectedSourceAddress,
          budget: budget,
        );
      } on Object catch (error) {
        if (!_isPreparationLimitExceeded(error)) rethrow;
        final replacementLimits = await budget.run(() => _limitsFor(binding));
        replacement = await _prepareBinding(
          binding: binding,
          limits: replacementLimits,
          expectedSourceAddress: expectedSourceAddress,
          budget: budget,
        );
        widenedForExplicitConsent = true;
      }

      final consentedSnapshot = _refreshSnapshot(consented);
      final replacementSnapshot = _refreshSnapshot(replacement);
      final decision = unifiedSwapRefreshDecision(
        consented: consentedSnapshot,
        replacement: replacementSnapshot,
        now: _now().toUtc(),
      );
      if (decision == UnifiedSwapRefreshDecision.freshQuoteRequired) {
        return KdfPreparedExecutionFreshQuote(
          intent: consented.intent,
          evaluation: evaluation,
        );
      }
      if (decision == UnifiedSwapRefreshDecision.unavailable) {
        throw const UnifiedSwapQuoteException(
          UnifiedSwapQuoteFailure.quoteExpired,
        );
      }
      return KdfPreparedExecutionReplacement(
        decision: widenedForExplicitConsent
            ? UnifiedSwapRefreshDecision.explicitConsentRequired
            : decision,
        verified: replacement,
      );
    } on UnifiedSwapQuoteException {
      rethrow;
    } on Object catch (error) {
      throw UnifiedSwapQuoteException(_failureFor(error));
    }
  }

  Future<String> _resolveSourceAddress(
    UnifiedSwapIntent intent,
    _OperationBudget budget,
  ) async {
    final address = await budget.run(() => _expectedSourceAddress!(intent));
    if (address == null || !RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(address)) {
      throw const UnifiedSwapQuoteException(
        UnifiedSwapQuoteFailure.capabilityUnavailable,
      );
    }
    return address;
  }

  Future<List<kdf.PrepareExecutionStageLimits>> _limitsFor(
    _ExactQuoteBinding binding,
  ) async {
    final limits = await _preparationLimitsPolicy!(
      intent: binding.intent,
      candidate: binding.candidate,
    );
    if (limits == null || !_validPreparationLimits(binding.candidate, limits)) {
      throw const UnifiedSwapQuoteException(
        UnifiedSwapQuoteFailure.capabilityUnavailable,
      );
    }
    return limits;
  }

  Future<KdfVerifiedPreparedExecution> _prepareBinding({
    required _ExactQuoteBinding binding,
    required List<kdf.PrepareExecutionStageLimits> limits,
    required String expectedSourceAddress,
    required _OperationBudget budget,
  }) async {
    if (!_validPreparationLimits(binding.candidate, limits)) {
      throw const UnifiedSwapQuoteException(
        UnifiedSwapQuoteFailure.capabilityUnavailable,
      );
    }
    final now = _now().toUtc();
    final consentExpiresAt = _earliest(
      binding.routeIntent.consentExpiresAt,
      binding.mappedCandidate.expiresAt,
      now.add(consentLifetime),
    );
    if (!consentExpiresAt.isAfter(now)) {
      throw const UnifiedSwapQuoteException(
        UnifiedSwapQuoteFailure.quoteExpired,
      );
    }
    final prepared = await budget.run(
      () => _preparationClient!.prepareExecution(
        evaluationId: binding.evaluationId,
        candidateId: binding.candidate.candidateId,
        candidateDigest: binding.candidate.candidateDigest,
        finalMinimumReceive: binding.candidate.minimumReceive,
        consentExpiresAt: consentExpiresAt,
        stages: limits,
      ),
    );
    final receivedAt = _now().toUtc();
    if (!_preparedResultMatches(
      binding,
      prepared,
      limits,
      consentExpiresAt,
      receivedAt,
      expectedSourceAddress,
    )) {
      throw const UnifiedSwapQuoteException(
        UnifiedSwapQuoteFailure.invalidIntent,
      );
    }
    if (!await budget.run(() => _isEligible(binding.intent))) {
      throw const UnifiedSwapQuoteException(
        UnifiedSwapQuoteFailure.capabilityUnavailable,
      );
    }
    final currentSourceAddress = await _resolveSourceAddress(
      binding.intent,
      budget,
    );
    if (currentSourceAddress.toLowerCase() !=
        expectedSourceAddress.toLowerCase()) {
      throw const UnifiedSwapQuoteException(
        UnifiedSwapQuoteFailure.capabilityUnavailable,
      );
    }
    final completedAt = _now().toUtc();
    if (!prepared.review.expiresAt.isAfter(completedAt) ||
        !prepared.routeConsent.consentExpiresAt.isAfter(completedAt)) {
      throw const UnifiedSwapQuoteException(
        UnifiedSwapQuoteFailure.quoteExpired,
      );
    }
    return KdfVerifiedPreparedExecution._(
      prepared: prepared,
      intent: binding.intent,
      riskWarnings: binding.mappedCandidate.riskWarnings,
      binding: binding,
      limits: List.unmodifiable(limits),
    );
  }

  _ExactQuoteBinding? _findBinding(
    UnifiedSwapIntent intent,
    UnifiedSwapQuoteCandidate candidate,
  ) {
    _ExactQuoteBinding? match;
    for (final binding in _exactQuotes.values) {
      if (binding.intent == intent && binding.mappedCandidate == candidate) {
        match = binding;
      }
    }
    return match;
  }

  Future<bool> _isEligible(UnifiedSwapIntent intent) async {
    final eligibilityCheck = _eligibilityCheck;
    if (eligibilityCheck == null) return false;
    try {
      return await eligibilityCheck(intent);
    } on Object {
      return false;
    }
  }

  void _pruneExactQuotes(DateTime now) {
    _exactQuotes.removeWhere(
      (_, binding) => binding.mappedCandidate.isExpiredAt(now),
    );
  }

  void _trimExactQuotes() {
    const maximumRetainedQuotes = 200;
    while (_exactQuotes.length > maximumRetainedQuotes) {
      _exactQuotes.remove(_exactQuotes.keys.first);
    }
  }
}

/// A monotonic budget shared by every async step in one operation.
///
/// Wall-clock timestamps are still used for quote validity, but changing the
/// device clock cannot extend an in-flight network/preparation deadline.
final class _OperationBudget {
  _OperationBudget(this.duration) : _stopwatch = Stopwatch()..start();

  final Duration duration;
  final Stopwatch _stopwatch;

  Future<T> run<T>(Future<T> Function() operation) {
    final remaining = duration - _stopwatch.elapsed;
    if (remaining <= Duration.zero) {
      return Future<T>.error(
        TimeoutException('Unified Swap operation deadline elapsed'),
      );
    }
    return operation().timeout(remaining);
  }
}

final class _ExactQuoteBinding {
  const _ExactQuoteBinding({
    required this.evaluationId,
    required this.intent,
    required this.routeIntent,
    required this.candidate,
    required this.mappedCandidate,
  });

  final String evaluationId;
  final UnifiedSwapIntent intent;
  final kdf.TradeIntent routeIntent;
  final kdf.TradeRouteCandidate candidate;
  final UnifiedSwapQuoteCandidate mappedCandidate;

  String get key =>
      '$evaluationId:${candidate.candidateId}:'
      '${candidate.candidateDigest}';
}

String _semanticFingerprint(
  _ExactQuoteBinding binding,
  String resolvedSourceAddress,
) {
  final stages = <Map<String, Object?>>[];
  for (final stage in binding.candidate.stages) {
    final common = _routeStageCommon(stage);
    if (common == null) throw StateError('Unknown route stage');
    stages.add({
      'kind': stage.stageType,
      'from': common.fromAsset.toJson(),
      'to': common.toAsset.toJson(),
      if (stage is kdf.ExternalLiquidityRouteStage) ...{
        'provider': stage.providerValue.rawValue,
        'selected_tools': stage.selectedTools.toJson(),
      },
    });
  }
  return kdf.tradeRouteCanonicalDigest({
    'route_source': binding.candidate.routeSourceValue.rawValue,
    'source': binding.routeIntent.fromAsset.toJson(),
    'destination': binding.routeIntent.toAsset.toJson(),
    'source_selector': binding.intent.sourceSelection.fingerprint,
    'resolved_source_address': _addressFingerprint(
      binding.routeIntent.fromAsset,
      resolvedSourceAddress,
    ),
    'recipient': _addressFingerprint(
      binding.routeIntent.toAsset,
      binding.routeIntent.recipient,
    ),
    'stages': stages,
  });
}

List<kdf.PrepareExecutionStageLimits>? _remapPreparationLimits({
  required _ExactQuoteBinding from,
  required _ExactQuoteBinding to,
  required List<kdf.PrepareExecutionStageLimits> limits,
}) {
  final oldStages = from.candidate.stages
      .whereType<kdf.ExternalLiquidityRouteStage>()
      .toList(growable: false);
  final newStages = to.candidate.stages
      .whereType<kdf.ExternalLiquidityRouteStage>()
      .toList(growable: false);
  if (oldStages.length != newStages.length ||
      !_validPreparationLimits(from.candidate, limits)) {
    return null;
  }
  final byStageId = {for (final limit in limits) limit.stageId: limit};
  final remapped = <kdf.PrepareExecutionStageLimits>[];
  for (var index = 0; index < oldStages.length; index++) {
    final oldLimit = byStageId[oldStages[index].common.stageId];
    if (oldLimit == null) return null;
    remapped.add(
      kdf.PrepareExecutionStageLimits(
        stageId: newStages[index].common.stageId,
        maxExpectedReceiveDegradationBps:
            oldLimit.maxExpectedReceiveDegradationBps,
        nonNetworkFeeLimits: oldLimit.nonNetworkFeeLimits,
        maxTotalNetworkFee: oldLimit.maxTotalNetworkFee,
      ),
    );
  }
  return remapped;
}

UnifiedSwapRefreshSnapshot _refreshSnapshot(
  KdfVerifiedPreparedExecution verified,
) {
  final review = verified.prepared.review;
  final stages = review.stages
      .whereType<kdf.KnownPreparedExecutionStageReview>()
      .toList(growable: false);
  if (stages.length != review.stages.length ||
      stages.length != verified._binding.candidate.stages.length) {
    throw StateError('Prepared stages are not structurally comparable');
  }

  final requiredNonNetworkFees = <String, String>{};
  final consentedNonNetworkFeeLimits = <String, String>{};
  final requiredNetworkFees = <String, String>{};
  final consentedNetworkFeeCaps = <String, String>{};
  for (final stage in stages) {
    for (final fee in stage.fees) {
      if (fee.feeTypeValue.knownValue == kdf.FeeType.network) continue;
      _addAmount(
        requiredNonNetworkFees,
        _semanticFeeKey(stage.stageIndex, fee.feeTypeValue.rawValue, fee.asset),
        fee.amount,
      );
    }
    for (final limit in stage.nonNetworkFeeLimits) {
      _addUniqueLimit(
        consentedNonNetworkFeeLimits,
        _semanticFeeKey(
          stage.stageIndex,
          limit.feeTypeValue.rawValue,
          limit.asset,
        ),
        limit.maxAmount,
      );
    }
    final requiredNetworkFee = stage.requiredMaxNetworkFee;
    if (requiredNetworkFee != null) {
      _addAmount(
        requiredNetworkFees,
        _semanticNetworkFeeKey(stage.stageIndex, requiredNetworkFee.asset),
        requiredNetworkFee.amount,
      );
    }
    final networkCap = stage.maxTotalNetworkFee;
    if (networkCap != null) {
      _addUniqueLimit(
        consentedNetworkFeeCaps,
        _semanticNetworkFeeKey(stage.stageIndex, networkCap.asset),
        networkCap.amount,
      );
    }
  }

  final candidate = verified._binding.candidate;
  return UnifiedSwapRefreshSnapshot(
    structure: UnifiedSwapRouteStructure(
      topology:
          '${candidate.routeSourceValue.rawValue}:${_topology(candidate.stages).name}',
      source: verified.intent.source,
      destination: verified.intent.destination,
      sourceSelectorFingerprint: verified.intent.sourceSelection.fingerprint,
      resolvedSourceAddress: review.resolvedSourceAddress,
      recipient: review.recipient,
      stageKinds: candidate.stages
          .map((stage) => stage.stageType)
          .toList(growable: false),
      selectedTools: _selectedToolFingerprints(candidate.stages),
      stageAssetPaths: candidate.stages
          .map((stage) {
            final common = _routeStageCommon(stage)!;
            return '${_routeAssetFingerprint(common.fromAsset)}>'
                '${_routeAssetFingerprint(common.toAsset)}';
          })
          .toList(growable: false),
    ),
    expectedReceive: review.expectedReceive,
    minimumReceive: review.minimumReceive,
    requiredNonNetworkFees: requiredNonNetworkFees,
    consentedNonNetworkFeeLimits: consentedNonNetworkFeeLimits,
    requiredNetworkFees: requiredNetworkFees,
    consentedNetworkFeeCaps: consentedNetworkFeeCaps,
    expiresAt: review.expiresAt,
    warnings: _refreshWarnings(verified, stages),
    preparedApprovals: [
      for (final stage in stages)
        if (stage.approval != null) _approvalAuthority(stage),
    ],
  );
}

UnifiedSwapPreparedApprovalAuthority _approvalAuthority(
  kdf.KnownPreparedExecutionStageReview stage,
) => switch (stage.approval) {
  kdf.NotApplicablePreparedApproval() => UnifiedSwapPreparedApprovalAuthority(
    stageIndex: stage.stageIndex,
    state: UnifiedSwapPreparedApprovalState.notApplicable,
  ),
  kdf.SufficientAllowancePreparedApproval(
    :final token,
    :final spender,
    :final requiredAmount,
  ) =>
    UnifiedSwapPreparedApprovalAuthority(
      stageIndex: stage.stageIndex,
      state: UnifiedSwapPreparedApprovalState.sufficientAllowance,
      token: _asset(token),
      spender: _canonicalEvmAddress(spender),
      requiredAmount: requiredAmount,
    ),
  kdf.ExactApprovalRequiredPreparedApproval(
    :final token,
    :final spender,
    :final requiredAmount,
    :final resetRequired,
  ) =>
    UnifiedSwapPreparedApprovalAuthority(
      stageIndex: stage.stageIndex,
      state: UnifiedSwapPreparedApprovalState.exactApprovalRequired,
      token: _asset(token),
      spender: _canonicalEvmAddress(spender),
      requiredAmount: requiredAmount,
      resetRequired: resetRequired,
    ),
  kdf.UnknownPreparedApproval() ||
  null => throw StateError('Prepared approval authority is not comparable'),
};

List<String> _refreshWarnings(
  KdfVerifiedPreparedExecution verified,
  List<kdf.KnownPreparedExecutionStageReview> stages,
) {
  final warnings = <String>{
    for (final warning in verified.prepared.review.warningValues)
      'route:${warning.rawValue}',
    for (final stage in stages)
      for (final warning in stage.warningValues)
        'stage:${stage.stageIndex}:${warning.rawValue}',
    if (verified.riskWarnings.highPriceImpact) 'risk:high_price_impact',
    if (verified.riskWarnings.lowLiquidity) 'risk:low_liquidity',
    if (verified.intent.unknownTokenConfirmed &&
        (verified.intent.sourceTokenTrust == UnifiedSwapTokenTrust.unknown ||
            verified.intent.destinationTokenTrust ==
                UnifiedSwapTokenTrust.unknown))
      'risk:unknown_token',
    if (verified.intent.externalRecipientConfirmed) 'risk:external_recipient',
  }.toList(growable: false)..sort();
  return warnings;
}

List<String> _selectedToolFingerprints(List<kdf.RouteStage> stages) {
  final tools = <String>[];
  for (var index = 0; index < stages.length; index++) {
    final stage = stages[index];
    if (stage is! kdf.ExternalLiquidityRouteStage) continue;
    tools.add('$index:provider:${stage.providerValue.rawValue}');
    tools.addAll(
      stage.selectedTools.bridges.map((tool) => '$index:bridge:$tool'),
    );
    tools.addAll(
      stage.selectedTools.exchanges.map((tool) => '$index:exchange:$tool'),
    );
  }
  return tools;
}

String _semanticFeeKey(int sequence, String kind, kdf.RouteAsset asset) =>
    '$sequence:$kind:${_routeAssetFingerprint(asset)}';

String _semanticNetworkFeeKey(int sequence, kdf.RouteAsset asset) =>
    '$sequence:network:${_routeAssetFingerprint(asset)}';

String _routeAssetFingerprint(kdf.RouteAsset asset) =>
    kdf.tradeRouteCanonicalDigest(asset.toJson());

String _addressFingerprint(kdf.RouteAsset asset, String address) {
  if (asset.chainFamilyValue.knownValue == kdf.ChainFamily.evm &&
      _isEvmAddress(address)) {
    return address.toLowerCase();
  }
  return address;
}

String _canonicalEvmAddress(String address) {
  if (!_isEvmAddress(address)) {
    throw StateError('Prepared approval spender is not an exact EVM address');
  }
  return address.toLowerCase();
}

bool _sameEvmAddress(String left, String right) =>
    _isEvmAddress(left) &&
    _isEvmAddress(right) &&
    left.toLowerCase() == right.toLowerCase();

bool _isEvmAddress(String value) =>
    RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(value);

void _addAmount(Map<String, String> values, String key, String amount) {
  values[key] =
      ((values[key] == null ? BigInt.zero : BigInt.parse(values[key]!)) +
              BigInt.parse(amount))
          .toString();
}

void _addUniqueLimit(Map<String, String> values, String key, String amount) {
  if (values.containsKey(key)) {
    throw StateError('Duplicate prepared fee limit');
  }
  values[key] = amount;
}

bool _isPreparationLimitExceeded(Object error) {
  String? type;
  if (error is kdf.RouteRpcError) {
    type = error.rawDiscriminator;
  } else if (error is kdf.GeneralErrorResponse) {
    type = error.errorType;
  } else if (error is kdf.MmRpcException) {
    type = error.errorType;
  }
  return type == 'FeeLimitExceeded' || type == 'NetworkFeeCapExceeded';
}

kdf.ValuationSnapshot? _freshValuationSnapshot(
  kdf.ValuationSnapshot? snapshot,
  DateTime now,
) {
  const maximumLifetime = Duration(minutes: 5);
  if (snapshot == null ||
      !snapshot.isExecutable ||
      !_boundedRaw(snapshot.currencyValue.rawValue) ||
      !_boundedRaw(snapshot.sourceValue.rawValue) ||
      snapshot.observedAt.toUtc().isAfter(now) ||
      !snapshot.validUntil.toUtc().isAfter(now) ||
      snapshot.validUntil.toUtc().difference(snapshot.observedAt.toUtc()) >
          maximumLifetime ||
      snapshot.prices.length > UnifiedSwapModelLimits.generalItems ||
      snapshot.prices.any(
        (price) =>
            !_validRouteAsset(price.asset) ||
            !_validDecimal(price.price) ||
            !price.observedAt.toUtc().isAtSameMomentAs(
              snapshot.observedAt.toUtc(),
            ),
      )) {
    return null;
  }
  final assetKeys = snapshot.prices
      .map((price) => _routeAssetFingerprint(price.asset))
      .toSet();
  if (assetKeys.length != snapshot.prices.length) return null;
  return snapshot;
}

kdf.RouteAsset _routeAsset(UnifiedSwapAssetIdentity asset) => kdf.RouteAsset(
  ticker: asset.ticker,
  chainFamily: switch (asset.chainFamily) {
    UnifiedSwapChainFamily.evm => kdf.ChainFamily.evm,
    UnifiedSwapChainFamily.tron => kdf.ChainFamily.tvm,
    UnifiedSwapChainFamily.utxo => kdf.ChainFamily.utxo,
    UnifiedSwapChainFamily.solana => kdf.ChainFamily.svm,
    UnifiedSwapChainFamily.sui => kdf.ChainFamily.sui,
    UnifiedSwapChainFamily.other => kdf.ChainFamily.mvm,
    UnifiedSwapChainFamily.unknown => throw const UnifiedSwapQuoteException(
      UnifiedSwapQuoteFailure.invalidIntent,
    ),
  },
  chainId: asset.chainId,
  assetKind: switch (asset.kind) {
    UnifiedSwapAssetKind.native => kdf.AssetKind.native,
    UnifiedSwapAssetKind.token => kdf.AssetKind.token,
    UnifiedSwapAssetKind.unknown => throw const UnifiedSwapQuoteException(
      UnifiedSwapQuoteFailure.invalidIntent,
    ),
  },
  contractAddress: asset.contractAddress,
  decimals: asset.decimals,
);

kdf.SourceAddressSelector _sourceSelection(
  UnifiedSwapSourceSelection selection,
) => switch (selection) {
  UnifiedSwapActiveSourceSelection() => kdf.SourceAddressSelector.active(),
  UnifiedSwapHdAddressSourceSelection(
    :final accountId,
    :final chain,
    :final addressId,
  ) =>
    kdf.SourceAddressSelector.hdAddress(
      accountId: accountId,
      chain: switch (chain) {
        UnifiedSwapHdChain.external => kdf.RouteBip44Chain.external,
        UnifiedSwapHdChain.internal => kdf.RouteBip44Chain.internal,
        UnifiedSwapHdChain.unknown => throw const UnifiedSwapQuoteException(
          UnifiedSwapQuoteFailure.invalidIntent,
        ),
      },
      addressId: addressId,
    ),
  UnifiedSwapHdPathSourceSelection(:final derivationPath) =>
    kdf.SourceAddressSelector.hdDerivationPath(derivationPath: derivationPath),
  UnifiedSwapUnknownSourceSelection() => throw const UnifiedSwapQuoteException(
    UnifiedSwapQuoteFailure.invalidIntent,
  ),
};

List<kdf.RouteSource> _routeSources(UnifiedSwapSourceSelection selection) =>
    selection is UnifiedSwapActiveSourceSelection
    ? const [kdf.RouteSource.kdf, kdf.RouteSource.lifi, kdf.RouteSource.mixed]
    : const [kdf.RouteSource.lifi];

UnifiedSwapQuoteCandidate _candidate(
  kdf.TradeRouteCandidate candidate, {
  required DateTime evaluationExpiresAt,
  required kdf.ValuationSnapshot? valuationSnapshot,
  required bool digestIsValid,
  required bool candidateIsEligible,
}) {
  final topology = _topology(candidate.stages);
  final rankIsKnown = candidate.rankStatusValue.isKnown;
  final valuation = _valuation(candidate, valuationSnapshot);
  final rankable =
      candidate.rankStatusValue.knownValue == kdf.RankStatus.ranked &&
      candidate.rank != null &&
      valuation != null;
  final unknowns = <String>[
    if (!digestIsValid) 'candidate_digest_mismatch',
    if (!candidateIsEligible) 'funding_authority_unavailable',
    if (!candidate.routeSourceValue.isKnown)
      candidate.routeSourceValue.rawValue,
    if (!rankIsKnown) candidate.rankStatusValue.rawValue,
    for (final stage in candidate.stages)
      if (!stage.isExecutable) stage.stageType,
    for (final warning in candidate.warningValues)
      if (!warning.isKnown) warning.rawValue,
  ];
  var expiresAt =
      candidate.expiresAt.toUtc().isBefore(evaluationExpiresAt.toUtc())
      ? candidate.expiresAt.toUtc()
      : evaluationExpiresAt.toUtc();
  if (rankable && valuation.validUntil.toUtc().isBefore(expiresAt)) {
    // Ranking is only defensible while the exact valuation proof is fresh.
    // Binding candidate expiry to that proof also makes the BLoC's existing
    // expiry timer remove the claim without relying on a widget rebuild.
    expiresAt = valuation.validUntil.toUtc();
  }
  return UnifiedSwapQuoteCandidate(
    candidateId: candidate.candidateId,
    candidateDigest: candidate.candidateDigest,
    topology: topology,
    expectedReceive: candidate.expectedReceive,
    minimumReceive: candidate.minimumReceive,
    fees: candidate.fees.map(_fee).toList(growable: false),
    expiresAt: expiresAt,
    rankable: rankable,
    rank: rankable ? candidate.rank : null,
    valuation: rankable ? valuation : null,
    priceImpactBps: _priceImpactBps(candidate, valuationSnapshot),
    estimatedDuration: candidate.estimatedDurationSeconds == null
        ? null
        : Duration(seconds: candidate.estimatedDurationSeconds!),
    stageCount: candidate.stages.length,
    isExecutable:
        digestIsValid &&
        candidateIsEligible &&
        candidate.isExecutable &&
        topology != UnifiedSwapTopology.unknown &&
        unknowns.isEmpty,
    rawUnknownDiscriminator: unknowns.isEmpty ? null : unknowns.join(','),
  );
}

void _validateQuoteResult(
  kdf.TradeRouteQuoteResult result,
  kdf.TradeIntent intent,
  DateTime receivedAt,
) {
  final now = receivedAt.toUtc();
  const maximumQuoteLifetime = Duration(minutes: 5);
  final evaluationLifetime = result.evaluationExpiresAt.toUtc().difference(
    result.observedAt.toUtc(),
  );
  if (!_bounded(result.evaluationId) ||
      result.candidates.length >
          UnifiedSwapQuoteEvaluation.maximumCandidateCount ||
      !result.evaluationExpiresAt.toUtc().isAfter(now) ||
      result.observedAt.toUtc().isAfter(now) ||
      evaluationLifetime <= Duration.zero ||
      evaluationLifetime > maximumQuoteLifetime) {
    throw const UnifiedSwapQuoteException(UnifiedSwapQuoteFailure.quoteExpired);
  }

  final candidateIds = <String>{};
  final candidateDigests = <String>{};
  final ranks = <int>{};
  for (final candidate in result.candidates) {
    final ranked =
        candidate.rankStatusValue.knownValue == kdf.RankStatus.ranked;
    final candidateLifetime = candidate.expiresAt.toUtc().difference(
      candidate.quoteObservedAt.toUtc(),
    );
    if (!candidateIds.add(candidate.candidateId) ||
        !candidateDigests.add(candidate.candidateDigest) ||
        !_bounded(candidate.candidateId) ||
        !_bounded(
          candidate.candidateDigest,
          maximumLength: UnifiedSwapModelLimits.digestLength,
        ) ||
        !_boundedRaw(candidate.routeSourceValue.rawValue) ||
        !_boundedRaw(candidate.rankStatusValue.rawValue) ||
        candidate.warningValues.length > UnifiedSwapModelLimits.generalItems ||
        candidate.warningValues.any(
          (warning) => !_boundedRaw(warning.rawValue),
        ) ||
        candidate.fees.length > UnifiedSwapModelLimits.generalItems ||
        candidate.fees.any((fee) => !_validFee(fee)) ||
        ((candidate.netReceiveValue == null) !=
            (candidate.valuationObservedAt == null)) ||
        (candidate.netReceiveValue != null &&
            !_validDecimal(candidate.netReceiveValue!)) ||
        (candidate.valuationObservedAt != null &&
            (candidate.valuationObservedAt!.toUtc().isAfter(now) ||
                candidate.valuationObservedAt!.toUtc().isAfter(
                  result.observedAt.toUtc(),
                ))) ||
        (candidate.rank != null && !ranks.add(candidate.rank!)) ||
        ranked != (candidate.rank != null) ||
        (candidate.rank != null && candidate.rank! < 0) ||
        (candidate.estimatedDurationSeconds != null &&
            candidate.estimatedDurationSeconds! < 0) ||
        candidate.stages.isEmpty ||
        candidate.stages.length > UnifiedSwapModelLimits.routeStages ||
        !_validPositiveAmount(candidate.expectedReceive) ||
        !_validAmount(candidate.minimumReceive) ||
        BigInt.parse(candidate.minimumReceive) >
            BigInt.parse(candidate.expectedReceive) ||
        !candidate.expiresAt.toUtc().isAfter(now) ||
        candidate.quoteObservedAt.toUtc().isAfter(now) ||
        candidate.quoteObservedAt.toUtc().isAfter(result.observedAt.toUtc()) ||
        candidateLifetime <= Duration.zero ||
        candidateLifetime > maximumQuoteLifetime) {
      throw const UnifiedSwapQuoteException(
        UnifiedSwapQuoteFailure.capabilityUnavailable,
      );
    }

    final stageIds = <String>{};
    for (final stage in candidate.stages) {
      final common = _routeStageCommon(stage);
      if (common == null) {
        if (!_boundedRaw(stage.stageType)) {
          throw const UnifiedSwapQuoteException(
            UnifiedSwapQuoteFailure.capabilityUnavailable,
          );
        }
        continue;
      }
      if (!stageIds.add(common.stageId) ||
          !_validStageEnvelope(stage, common) ||
          !_validPositiveAmount(common.sourceAmount) ||
          !_validPositiveAmount(common.expectedReceive) ||
          !_validAmount(common.minimumReceive) ||
          BigInt.parse(common.minimumReceive) >
              BigInt.parse(common.expectedReceive) ||
          !common.expiresAt.toUtc().isAfter(now) ||
          common.expiresAt.toUtc().difference(
                candidate.quoteObservedAt.toUtc(),
              ) >
              maximumQuoteLifetime) {
        throw const UnifiedSwapQuoteException(
          UnifiedSwapQuoteFailure.capabilityUnavailable,
        );
      }
    }
    if (candidate.isExecutable &&
        !_candidatePathMatchesIntent(candidate, intent)) {
      throw const UnifiedSwapQuoteException(
        UnifiedSwapQuoteFailure.capabilityUnavailable,
      );
    }
  }
}

bool _candidatePathMatchesIntent(
  kdf.TradeRouteCandidate candidate,
  kdf.TradeIntent intent,
) {
  final stages = <kdf.RouteStageCommon>[];
  for (final stage in candidate.stages) {
    final common = _routeStageCommon(stage);
    if (common == null) return false;
    stages.add(common);
  }
  if (stages.isEmpty ||
      !_sameRouteAsset(stages.first.fromAsset, intent.fromAsset) ||
      stages.first.sourceAmount != intent.sourceAmount ||
      !_sameRouteAsset(stages.last.toAsset, intent.toAsset) ||
      stages.last.expectedReceive != candidate.expectedReceive ||
      stages.last.minimumReceive != candidate.minimumReceive ||
      !_sameRouteRecipient(
        stages.last.toAsset,
        stages.last.recipient,
        intent.recipient,
      )) {
    return false;
  }
  for (var index = 1; index < stages.length; index++) {
    final previous = stages[index - 1];
    final next = stages[index];
    final nextSourceAmount = BigInt.parse(next.sourceAmount);
    if (!_sameRouteAsset(previous.toAsset, next.fromAsset) ||
        nextSourceAmount < BigInt.parse(previous.minimumReceive) ||
        nextSourceAmount > BigInt.parse(previous.expectedReceive)) {
      return false;
    }
  }
  return true;
}

bool _sameRouteRecipient(kdf.RouteAsset asset, String left, String right) =>
    asset.chainFamilyValue.knownValue == kdf.ChainFamily.evm
    ? _sameEvmAddress(left, right)
    : left == right;

bool _validPositiveAmount(String value) =>
    _validAmount(value) && BigInt.parse(value) > BigInt.zero;

bool _validAmount(String value) =>
    value.length <= UnifiedSwapModelLimits.amountDigits &&
    RegExp(r'^(?:0|[1-9][0-9]*)$').hasMatch(value);

bool _validDecimal(String value) =>
    value.length <= UnifiedSwapModelLimits.amountDigits &&
    RegExp(r'^(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$').hasMatch(value);

bool _bounded(
  String value, {
  int maximumLength = UnifiedSwapModelLimits.identifierLength,
}) => UnifiedSwapModelLimits.isCanonicalString(
  value,
  maximumLength: maximumLength,
);

bool _boundedOptional(
  String? value, {
  int maximumLength = UnifiedSwapModelLimits.identifierLength,
}) => UnifiedSwapModelLimits.isOptionalCanonicalString(
  value,
  maximumLength: maximumLength,
);

bool _boundedRaw(String value) =>
    _bounded(value, maximumLength: UnifiedSwapModelLimits.discriminatorLength);

bool _validRouteAsset(kdf.RouteAsset asset) {
  if (!_bounded(
        asset.ticker,
        maximumLength: UnifiedSwapAssetIdentity.maximumTickerLength,
      ) ||
      !_bounded(
        asset.chainId,
        maximumLength: UnifiedSwapAssetIdentity.maximumChainIdLength,
      ) ||
      !_boundedRaw(asset.chainFamilyValue.rawValue) ||
      !_boundedRaw(asset.assetKindValue.rawValue) ||
      asset.decimals < 0 ||
      asset.decimals > 255 ||
      !_boundedOptional(
        asset.contractAddress,
        maximumLength: UnifiedSwapModelLimits.addressLength,
      )) {
    return false;
  }
  return switch (asset.assetKindValue.knownValue) {
    kdf.AssetKind.native => asset.contractAddress == null,
    kdf.AssetKind.token =>
      asset.contractAddress != null &&
          (asset.chainFamilyValue.knownValue != kdf.ChainFamily.evm ||
              _isEvmAddress(asset.contractAddress!)),
    null => true,
  };
}

bool _validFee(kdf.FeeComponent fee) =>
    _boundedRaw(fee.feeTypeValue.rawValue) &&
    _validRouteAsset(fee.asset) &&
    _validAmount(fee.amount) &&
    (fee.valuation == null ||
        (_boundedRaw(fee.valuation!.currencyValue.rawValue) &&
            _boundedRaw(fee.valuation!.sourceValue.rawValue) &&
            _validDecimal(fee.valuation!.amount)));

bool _validStageEnvelope(kdf.RouteStage stage, kdf.RouteStageCommon common) {
  if (!_bounded(common.stageId) ||
      !_validRouteAsset(common.fromAsset) ||
      !_validRouteAsset(common.toAsset) ||
      !_bounded(
        common.recipient,
        maximumLength: UnifiedSwapModelLimits.addressLength,
      ) ||
      common.fees.length > UnifiedSwapModelLimits.generalItems ||
      common.fees.any((fee) => !_validFee(fee)) ||
      common.warningValues.length > UnifiedSwapModelLimits.generalItems ||
      common.warningValues.any((warning) => !_boundedRaw(warning.rawValue))) {
    return false;
  }
  return switch (stage) {
    kdf.KdfAtomicRouteStage() =>
      _boundedRaw(stage.sideValue.rawValue) &&
          _validAmount(stage.tradeSourceAmount) &&
          stage.tradeSourceAmount == common.sourceAmount &&
          _validDecimal(stage.requestedVolume) &&
          _validDecimal(stage.price) &&
          _validDecimal(stage.minimumVolume) &&
          _validDecimal(stage.maximumVolume) &&
          _bounded(stage.orderUuid),
    kdf.ExternalLiquidityRouteStage() =>
      _boundedRaw(stage.providerValue.rawValue) &&
          _bounded(stage.providerRouteId) &&
          _boundedOptional(stage.externalCandidateId) &&
          _bounded(
            stage.providerStepDigest,
            maximumLength: UnifiedSwapModelLimits.digestLength,
          ) &&
          _validToolPolicy(stage.toolPolicy) &&
          _validSelectedTools(stage.selectedTools) &&
          (stage.providerTokens == null ||
              (_bounded(stage.providerTokens!.fromToken) &&
                  _bounded(stage.providerTokens!.toToken))) &&
          (stage.providerChainIds == null ||
              (_bounded(
                    stage.providerChainIds!.fromChain,
                    maximumLength:
                        UnifiedSwapAssetIdentity.maximumChainIdLength,
                  ) &&
                  _bounded(
                    stage.providerChainIds!.toChain,
                    maximumLength:
                        UnifiedSwapAssetIdentity.maximumChainIdLength,
                  ))),
    kdf.UnknownRouteStage() => false,
  };
}

bool _validToolPolicy(kdf.ToolPolicy policy) =>
    _validToolFilter(policy.bridges) && _validToolFilter(policy.exchanges);

bool _validToolFilter(kdf.ToolFilter filter) =>
    _validToolNames(filter.allow) &&
    _validToolNames(filter.deny) &&
    _validToolNames(filter.prefer);

bool _validSelectedTools(kdf.SelectedTools selected) =>
    _validToolNames(selected.bridges) && _validToolNames(selected.exchanges);

bool _validToolNames(List<String> values) =>
    values.length <= UnifiedSwapModelLimits.nestedItems &&
    values.toSet().length == values.length &&
    values.every(_boundedRaw);

bool _hasValidCandidateDigest(kdf.TradeRouteCandidate candidate) {
  try {
    return kdf.tradeRouteCandidateDigest(candidate) ==
        candidate.candidateDigest;
  } on kdf.TradeRouteDigestException {
    return false;
  }
}

bool _validPreparationLimits(
  kdf.TradeRouteCandidate candidate,
  List<kdf.PrepareExecutionStageLimits> limits,
) {
  final externalStageIds = candidate.stages
      .whereType<kdf.ExternalLiquidityRouteStage>()
      .map((stage) => stage.common.stageId)
      .toSet();
  final suppliedStageIds = <String>{};
  for (final limit in limits) {
    if (!limit.isExecutable ||
        limit.maxExpectedReceiveDegradationBps >
            unifiedSwapQuietRefreshMaximumDegradationBps ||
        !suppliedStageIds.add(limit.stageId)) {
      return false;
    }
  }
  return suppliedStageIds.length == externalStageIds.length &&
      suppliedStageIds.containsAll(externalStageIds);
}

bool _preparedResultMatches(
  _ExactQuoteBinding binding,
  kdf.PrepareExecutionResult prepared,
  List<kdf.PrepareExecutionStageLimits> limits,
  DateTime consentExpiresAt,
  DateTime now,
  String expectedSourceAddress,
) {
  final review = prepared.review;
  final consent = prepared.routeConsent;
  if (!prepared.isExecutable ||
      review.evaluationId != binding.evaluationId ||
      review.candidateId != binding.candidate.candidateId ||
      review.candidateDigest != binding.candidate.candidateDigest ||
      consent.evaluationId != review.evaluationId ||
      consent.candidateId != review.candidateId ||
      consent.candidateDigest != review.candidateDigest ||
      review.routeSourceValue.rawValue !=
          binding.candidate.routeSourceValue.rawValue ||
      !_sameWire(
        review.sourceAsset.toJson(),
        binding.routeIntent.fromAsset.toJson(),
      ) ||
      !_sameWire(
        review.destinationAsset.toJson(),
        binding.routeIntent.toAsset.toJson(),
      ) ||
      !_sameWire(
        review.sourceAddressSelector.toJson(),
        binding.routeIntent.sourceAddress.toJson(),
      ) ||
      review.sourceAmount != binding.routeIntent.sourceAmount ||
      review.recipient != binding.routeIntent.recipient ||
      !_sameEvmAddress(review.resolvedSourceAddress, expectedSourceAddress) ||
      review.minimumReceive != binding.candidate.minimumReceive ||
      review.estimatedDurationSeconds !=
          binding.candidate.estimatedDurationSeconds ||
      !_sameWire(
        review.fees.map((fee) => fee.toJson()).toList(growable: false),
        binding.candidate.fees
            .map((fee) => fee.toJson())
            .toList(growable: false),
      ) ||
      !_sameWire(
        review.warningValues
            .map((warning) => warning.rawValue)
            .toList(growable: false),
        binding.candidate.warningValues
            .map((warning) => warning.rawValue)
            .toList(growable: false),
      ) ||
      !_withinDegradation(
        binding.candidate.expectedReceive,
        review.expectedReceive,
        unifiedSwapQuietRefreshMaximumDegradationBps,
      ) ||
      !review.expiresAt.isAtSameMomentAs(consentExpiresAt) ||
      !consent.consentExpiresAt.isAtSameMomentAs(consentExpiresAt) ||
      !review.expiresAt.isAfter(now) ||
      consent.routeIntent.sourceAmount != binding.routeIntent.sourceAmount ||
      consent.routeIntent.minimumReceive != binding.candidate.minimumReceive ||
      consent.routeIntent.slippageBps != binding.routeIntent.slippageBps ||
      consent.routeIntent.recipient != binding.routeIntent.recipient ||
      !_sameWire(
        consent.routeIntent.toolPolicy.toJson(),
        binding.routeIntent.toolPolicy.toJson(),
      ) ||
      !consent.routeIntent.consentExpiresAt.isAtSameMomentAs(
        consentExpiresAt,
      ) ||
      !_sameWire(
        consent.routeIntent.sourceAddress.toJson(),
        binding.routeIntent.sourceAddress.toJson(),
      ) ||
      !_sameWire(
        consent.routeIntent.fromAsset.toJson(),
        binding.routeIntent.fromAsset.toJson(),
      ) ||
      !_sameWire(
        consent.routeIntent.toAsset.toJson(),
        binding.routeIntent.toAsset.toJson(),
      ) ||
      !_preparedStageStructureMatches(binding.candidate, review, limits)) {
    return false;
  }
  try {
    final reviewDigest = consent.preparedReviewDigest;
    final reviewDigestValid =
        reviewDigest != null &&
        kdf.tradeRoutePreparedExecutionReviewDigest(review) == reviewDigest;
    final stagesValid = consent.externalStageConsents.every(
      (stage) => kdf.tradeRouteStageConsentDigest(stage) == stage.consentDigest,
    );
    final routeValid =
        kdf.tradeRouteConsentDigest(consent) == consent.routeConsentDigest;
    final authorityValid = _preparedConsentMatchesCandidate(
      binding,
      prepared,
      limits,
      expectedSourceAddress,
    );
    return reviewDigest != null &&
        reviewDigestValid &&
        stagesValid &&
        routeValid &&
        authorityValid;
  } on kdf.TradeRouteDigestException {
    return false;
  }
}

bool _preparedStageStructureMatches(
  kdf.TradeRouteCandidate candidate,
  kdf.PreparedExecutionReview review,
  List<kdf.PrepareExecutionStageLimits> limits,
) {
  if (candidate.stages.length != review.stages.length) return false;
  final limitsByStage = {for (final limit in limits) limit.stageId: limit};
  for (var index = 0; index < candidate.stages.length; index++) {
    final quoted = candidate.stages[index];
    final prepared = review.stages[index];
    if (prepared is! kdf.KnownPreparedExecutionStageReview ||
        prepared.stageIndex != index) {
      return false;
    }
    final common = switch (quoted) {
      kdf.KdfAtomicRouteStage(:final common) => common,
      kdf.ExternalLiquidityRouteStage(:final common) => common,
      kdf.UnknownRouteStage() => null,
    };
    if (common == null ||
        prepared.stageId != common.stageId ||
        !_sameWire(prepared.fromAsset.toJson(), common.fromAsset.toJson()) ||
        !_sameWire(prepared.toAsset.toJson(), common.toAsset.toJson()) ||
        prepared.sourceAmount != common.sourceAmount ||
        prepared.minimumReceive != common.minimumReceive ||
        prepared.recipient != common.recipient ||
        !_sameWire(
          prepared.fees.map((fee) => fee.toJson()).toList(growable: false),
          common.fees.map((fee) => fee.toJson()).toList(growable: false),
        ) ||
        !_sameWire(
          prepared.warningValues
              .map((warning) => warning.rawValue)
              .toList(growable: false),
          common.warningValues
              .map((warning) => warning.rawValue)
              .toList(growable: false),
        )) {
      return false;
    }
    switch (quoted) {
      case kdf.KdfAtomicRouteStage():
        if (prepared.kind != kdf.PreparedExecutionStageKind.kdfAtomic ||
            prepared.expectedReceive != common.expectedReceive ||
            prepared.selectedTools != null ||
            prepared.nonNetworkFeeLimits.isNotEmpty ||
            prepared.maxTotalNetworkFee != null ||
            prepared.requiredMaxNetworkFee != null ||
            prepared.resolvedSourceAddress != null ||
            prepared.approval != null) {
          return false;
        }
      case kdf.ExternalLiquidityRouteStage(:final selectedTools):
        final limit = limitsByStage[common.stageId];
        if (limit == null ||
            prepared.kind != kdf.PreparedExecutionStageKind.externalLiquidity ||
            !_sameWire(
              prepared.selectedTools?.toJson(),
              selectedTools.toJson(),
            ) ||
            !_withinDegradation(
              common.expectedReceive,
              prepared.expectedReceive,
              limit.maxExpectedReceiveDegradationBps,
            ) ||
            prepared.maxTotalNetworkFee == null ||
            prepared.requiredMaxNetworkFee == null ||
            prepared.resolvedSourceAddress == null ||
            prepared.approval == null ||
            !_sameWire(
              prepared.nonNetworkFeeLimits
                  .map((fee) => fee.toJson())
                  .toList(growable: false),
              limit.nonNetworkFeeLimits
                  .map((fee) => fee.toJson())
                  .toList(growable: false),
            ) ||
            !_sameWire(
              prepared.maxTotalNetworkFee!.toJson(),
              limit.maxTotalNetworkFee.toJson(),
            )) {
          return false;
        }
      case kdf.UnknownRouteStage():
        return false;
    }
  }
  return true;
}

bool _preparedConsentMatchesCandidate(
  _ExactQuoteBinding binding,
  kdf.PrepareExecutionResult prepared,
  List<kdf.PrepareExecutionStageLimits> limits,
  String expectedSourceAddress,
) {
  final consent = prepared.routeConsent;
  if (consent.digestVersion != 1 ||
      consent.modeValue.knownValue != kdf.ExecutionMode.signAndBroadcast) {
    return false;
  }

  final routeIntentDigest = kdf.tradeRouteIntentDigest(consent.routeIntent);
  final limitsByStage = {for (final limit in limits) limit.stageId: limit};
  final atomicStages = binding.candidate.stages
      .whereType<kdf.KdfAtomicRouteStage>()
      .toList(growable: false);
  final externalStages = binding.candidate.stages
      .whereType<kdf.ExternalLiquidityRouteStage>()
      .toList(growable: false);
  if (atomicStages.length != consent.atomicOrderGuards.length ||
      externalStages.length != consent.externalStageConsents.length) {
    return false;
  }

  final guardByStageId = <String, kdf.AtomicOrderGuard>{};
  for (var index = 0; index < atomicStages.length; index++) {
    final stage = atomicStages[index];
    final guard = consent.atomicOrderGuards[index];
    if (!_atomicGuardMatchesStage(guard, stage, routeIntentDigest)) {
      return false;
    }
    guardByStageId[stage.common.stageId] = guard;
  }

  var externalIndex = 0;
  for (
    var stageIndex = 0;
    stageIndex < binding.candidate.stages.length;
    stageIndex++
  ) {
    final candidateStage = binding.candidate.stages[stageIndex];
    if (candidateStage is! kdf.ExternalLiquidityRouteStage) continue;
    final stageConsent = consent.externalStageConsents[externalIndex++];
    final stageIntent = stageConsent.stageIntent;
    final reference = stageConsent.candidateReference;
    final limit = limitsByStage[candidateStage.common.stageId];
    final preparedStage = prepared.review.stages[stageIndex];
    final executionSource = stageConsent.executionSource;
    final authority = stageConsent.preparedExecution;
    final expectedStageSource = stageIndex == 0
        ? expectedSourceAddress
        : _routeStageCommon(
            binding.candidate.stages[stageIndex - 1],
          )?.recipient;
    if (limit == null ||
        preparedStage is! kdf.KnownPreparedExecutionStageReview ||
        stageConsent.digestVersion != 1 ||
        stageConsent.modeValue.knownValue !=
            kdf.ExecutionMode.signAndBroadcast ||
        reference.evaluationId != binding.evaluationId ||
        reference.candidateId != binding.candidate.candidateId ||
        reference.candidateDigest != binding.candidate.candidateDigest ||
        reference.stageId != candidateStage.common.stageId ||
        !_sameWire(
          stageConsent.routeIntent.toJson(),
          consent.routeIntent.toJson(),
        ) ||
        stageIntent.routeIntentDigest != routeIntentDigest ||
        stageIntent.stageId != candidateStage.common.stageId ||
        !_sameWire(
          stageIntent.fromAsset.toJson(),
          candidateStage.common.fromAsset.toJson(),
        ) ||
        !_sameWire(
          stageIntent.toAsset.toJson(),
          candidateStage.common.toAsset.toJson(),
        ) ||
        stageIntent.sourceAmount != candidateStage.common.sourceAmount ||
        stageIntent.acceptedExpectedReceive != preparedStage.expectedReceive ||
        stageIntent.minimumReceive != candidateStage.common.minimumReceive ||
        stageIntent.maxExpectedReceiveDegradationBps !=
            limit.maxExpectedReceiveDegradationBps ||
        stageIntent.maxExpectedReceiveDegradationBps >
            unifiedSwapQuietRefreshMaximumDegradationBps ||
        stageIntent.slippageBps != binding.routeIntent.slippageBps ||
        !_sameWire(
          stageIntent.sourceAddress.toJson(),
          binding.routeIntent.sourceAddress.toJson(),
        ) ||
        stageIntent.recipient != candidateStage.common.recipient ||
        !_sameWire(
          stageIntent.toolPolicy.toJson(),
          candidateStage.toolPolicy.toJson(),
        ) ||
        !_sameWire(
          stageIntent.selectedTools.toJson(),
          candidateStage.selectedTools.toJson(),
        ) ||
        candidateStage.providerTokens == null ||
        candidateStage.providerChainIds == null ||
        !_sameWire(
          stageIntent.providerTokens.toJson(),
          candidateStage.providerTokens!.toJson(),
        ) ||
        !_sameWire(
          stageIntent.providerChainIds.toJson(),
          candidateStage.providerChainIds!.toJson(),
        ) ||
        !_sameWire(
          stageIntent.nonNetworkFeeLimits
              .map((fee) => fee.toJson())
              .toList(growable: false),
          limit.nonNetworkFeeLimits
              .map((fee) => fee.toJson())
              .toList(growable: false),
        ) ||
        !_sameWire(
          stageIntent.maxTotalNetworkFee.toJson(),
          limit.maxTotalNetworkFee.toJson(),
        ) ||
        !stageIntent.consentExpiresAt.isAtSameMomentAs(
          consent.consentExpiresAt,
        ) ||
        executionSource is! kdf.ProviderIntentExecutionSource ||
        executionSource.providerValue.rawValue !=
            candidateStage.providerValue.rawValue ||
        executionSource.materializationValue.knownValue !=
            kdf.ProviderMaterialization.advancedStep ||
        !executionSource.providerObservedAt.isAtSameMomentAs(
          binding.candidate.quoteObservedAt,
        ) ||
        executionSource.providerStep != null ||
        executionSource.providerStepReference == null ||
        executionSource.providerStepReference!.evaluationId !=
            binding.evaluationId ||
        executionSource.providerStepReference!.candidateId !=
            binding.candidate.candidateId ||
        executionSource.providerStepReference!.stageId !=
            candidateStage.common.stageId ||
        executionSource.providerStepReference!.providerStepDigest !=
            candidateStage.providerStepDigest ||
        executionSource.providerStepDigest !=
            candidateStage.providerStepDigest ||
        authority == null ||
        !authority.isExecutable ||
        expectedStageSource == null ||
        !_sameEvmAddress(
          authority.resolvedSourceAddress,
          expectedStageSource,
        ) ||
        preparedStage.resolvedSourceAddress == null ||
        !_sameEvmAddress(
          preparedStage.resolvedSourceAddress!,
          authority.resolvedSourceAddress,
        ) ||
        !_sameWire(
          preparedStage.approval?.toJson(),
          authority.approval.toJson(),
        ) ||
        !_sameWire(
          preparedStage.requiredMaxNetworkFee?.toJson(),
          authority.requiredMaxNetworkFee.toJson(),
        )) {
      return false;
    }

    final nextStage = stageIndex + 1 < binding.candidate.stages.length
        ? binding.candidate.stages[stageIndex + 1]
        : null;
    final expectedFollowingGuard = nextStage is kdf.KdfAtomicRouteStage
        ? guardByStageId[nextStage.common.stageId]
        : null;
    if (!_sameWire(
      stageConsent.atomicOrderGuard?.toJson(),
      expectedFollowingGuard?.toJson(),
    )) {
      return false;
    }
  }
  return true;
}

bool _atomicGuardMatchesStage(
  kdf.AtomicOrderGuard guard,
  kdf.KdfAtomicRouteStage stage,
  String routeIntentDigest,
) =>
    guard.guardVersion == 1 &&
    guard.routeIntentDigest == routeIntentDigest &&
    guard.orderUuid == stage.orderUuid &&
    guard.sideValue.rawValue == stage.sideValue.rawValue &&
    guard.baseTicker == stage.common.toAsset.ticker &&
    guard.relTicker == stage.common.fromAsset.ticker &&
    guard.limitPrice == stage.price &&
    guard.requestedVolume == stage.requestedVolume &&
    guard.minimumFillVolume == stage.minimumVolume &&
    guard.maximumFillVolume == stage.maximumVolume &&
    guard.orderSnapshotAt.isAtSameMomentAs(stage.orderSnapshotAt) &&
    guard.expiresAt.isAtSameMomentAs(stage.common.expiresAt);

kdf.RouteStageCommon? _routeStageCommon(kdf.RouteStage stage) =>
    switch (stage) {
      kdf.KdfAtomicRouteStage(:final common) => common,
      kdf.ExternalLiquidityRouteStage(:final common) => common,
      kdf.UnknownRouteStage() => null,
    };

bool _withinDegradation(String quoted, String prepared, int maximumBps) {
  final quotedValue = BigInt.parse(quoted);
  final preparedValue = BigInt.parse(prepared);
  if (preparedValue >= quotedValue) return true;
  if (quotedValue == BigInt.zero) return false;
  return (quotedValue - preparedValue) * BigInt.from(10000) <=
      quotedValue * BigInt.from(maximumBps);
}

bool _sameWire(Object? left, Object? right) {
  if (left == null || right == null) return left == right;
  try {
    return kdf.tradeRouteCanonicalDigest(left) ==
        kdf.tradeRouteCanonicalDigest(right);
  } on kdf.TradeRouteDigestException {
    return false;
  }
}

DateTime _earliest(DateTime first, DateTime second, DateTime third) {
  var value = first.toUtc();
  if (second.toUtc().isBefore(value)) value = second.toUtc();
  if (third.toUtc().isBefore(value)) value = third.toUtc();
  return value;
}

UnifiedSwapValuationProof? _valuation(
  kdf.TradeRouteCandidate candidate,
  kdf.ValuationSnapshot? snapshot,
) {
  final netReceive = candidate.netReceiveValue;
  final observedAt = candidate.valuationObservedAt;
  if (snapshot == null ||
      netReceive == null ||
      observedAt == null ||
      !observedAt.toUtc().isAtSameMomentAs(snapshot.observedAt.toUtc())) {
    return null;
  }
  return UnifiedSwapValuationProof(
    currency: snapshot.currencyValue.rawValue,
    observedAt: observedAt,
    validUntil: snapshot.validUntil,
    netMinimumReceive: netReceive,
    sourceValue: _sourceValuation(candidate, snapshot, observedAt),
  );
}

String? _sourceValuation(
  kdf.TradeRouteCandidate candidate,
  kdf.ValuationSnapshot snapshot,
  DateTime observedAt,
) {
  if (candidate.stages.isEmpty) return null;
  final source = _routeStageCommon(candidate.stages.first);
  if (source == null) return null;
  final prices = snapshot.prices
      .where((price) => _sameRouteAsset(price.asset, source.fromAsset))
      .toList(growable: false);
  if (prices.length != 1 ||
      !prices.single.observedAt.toUtc().isAtSameMomentAs(observedAt.toUtc())) {
    return null;
  }
  final price = _decimalUnits(prices.single.price);
  if (price == null || price.units <= BigInt.zero) return null;
  final units = BigInt.parse(source.sourceAmount) * price.units;
  return _scaledDecimal(units, source.fromAsset.decimals + price.scale);
}

String _scaledDecimal(BigInt units, int scale) {
  if (scale == 0) return units.toString();
  final padded = units.toString().padLeft(scale + 1, '0');
  final split = padded.length - scale;
  final whole = padded.substring(0, split);
  final fraction = padded.substring(split).replaceFirst(RegExp(r'0+$'), '');
  return fraction.isEmpty ? whole : '$whole.$fraction';
}

int? _priceImpactBps(
  kdf.TradeRouteCandidate candidate,
  kdf.ValuationSnapshot? snapshot,
) {
  final observedAt = candidate.valuationObservedAt?.toUtc();
  if (snapshot == null ||
      observedAt == null ||
      !observedAt.isAtSameMomentAs(snapshot.observedAt.toUtc()) ||
      candidate.stages.isEmpty) {
    return null;
  }
  final first = _routeStageCommon(candidate.stages.first);
  final last = _routeStageCommon(candidate.stages.last);
  if (first == null || last == null) return null;
  final sourcePrices = snapshot.prices.where(
    (price) => _sameRouteAsset(price.asset, first.fromAsset),
  );
  final destinationPrices = snapshot.prices.where(
    (price) => _sameRouteAsset(price.asset, last.toAsset),
  );
  if (sourcePrices.length != 1 || destinationPrices.length != 1) return null;
  final sourcePrice = sourcePrices.single;
  final destinationPrice = destinationPrices.single;
  if (!sourcePrice.observedAt.toUtc().isAtSameMomentAs(observedAt) ||
      !destinationPrice.observedAt.toUtc().isAtSameMomentAs(observedAt)) {
    return null;
  }
  final sourceDecimal = _decimalUnits(sourcePrice.price);
  final destinationDecimal = _decimalUnits(destinationPrice.price);
  if (sourceDecimal == null ||
      destinationDecimal == null ||
      sourceDecimal.units <= BigInt.zero ||
      destinationDecimal.units <= BigInt.zero) {
    return null;
  }
  final sourceValue =
      BigInt.parse(first.sourceAmount) *
      sourceDecimal.units *
      BigInt.from(10).pow(last.toAsset.decimals + destinationDecimal.scale);
  final destinationValue =
      BigInt.parse(candidate.expectedReceive) *
      destinationDecimal.units *
      BigInt.from(10).pow(first.fromAsset.decimals + sourceDecimal.scale);
  if (sourceValue <= BigInt.zero || destinationValue >= sourceValue) return 0;
  final impact =
      (sourceValue - destinationValue) * BigInt.from(10_000) ~/ sourceValue;
  return impact > BigInt.from(10_000) ? 10_000 : impact.toInt();
}

({BigInt units, int scale})? _decimalUnits(String value) {
  if (value.length > 256 ||
      !RegExp(r'^(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$').hasMatch(value)) {
    return null;
  }
  final separator = value.indexOf('.');
  final scale = separator < 0 ? 0 : value.length - separator - 1;
  return (units: BigInt.parse(value.replaceAll('.', '')), scale: scale);
}

bool _sameRouteAsset(kdf.RouteAsset left, kdf.RouteAsset right) =>
    left.ticker == right.ticker &&
    left.chainFamilyValue.rawValue == right.chainFamilyValue.rawValue &&
    left.chainId == right.chainId &&
    left.assetKindValue.rawValue == right.assetKindValue.rawValue &&
    _routeContractIdentity(left) == _routeContractIdentity(right) &&
    left.decimals == right.decimals;

String? _routeContractIdentity(kdf.RouteAsset asset) {
  final value = asset.contractAddress;
  if (asset.chainFamilyValue.knownValue == kdf.ChainFamily.evm &&
      value != null &&
      _isEvmAddress(value)) {
    return value.toLowerCase();
  }
  return value;
}

RouteExecutionFee _fee(kdf.FeeComponent fee) {
  final kind = switch (fee.feeTypeValue.knownValue) {
    kdf.FeeType.provider => RouteFeeKind.provider,
    kdf.FeeType.bridge => RouteFeeKind.bridge,
    kdf.FeeType.exchange => RouteFeeKind.exchange,
    kdf.FeeType.network => RouteFeeKind.network,
    kdf.FeeType.kdf => RouteFeeKind.kdf,
    null => RouteFeeKind.unknown,
  };
  return RouteExecutionFee(
    kind: kind,
    asset: _asset(fee.asset),
    amount: fee.amount,
    included: fee.included,
    rawKindDiscriminator: fee.feeTypeValue.isKnown
        ? null
        : fee.feeTypeValue.rawValue,
  );
}

UnifiedSwapAssetIdentity _asset(kdf.RouteAsset asset) =>
    UnifiedSwapAssetIdentity(
      ticker: asset.ticker,
      chainFamily: switch (asset.chainFamilyValue.knownValue) {
        kdf.ChainFamily.evm => UnifiedSwapChainFamily.evm,
        kdf.ChainFamily.tvm => UnifiedSwapChainFamily.tron,
        kdf.ChainFamily.utxo => UnifiedSwapChainFamily.utxo,
        kdf.ChainFamily.svm => UnifiedSwapChainFamily.solana,
        kdf.ChainFamily.sui => UnifiedSwapChainFamily.sui,
        kdf.ChainFamily.mvm => UnifiedSwapChainFamily.other,
        null => UnifiedSwapChainFamily.unknown,
      },
      chainId: asset.chainId,
      kind: switch (asset.assetKindValue.knownValue) {
        kdf.AssetKind.native => UnifiedSwapAssetKind.native,
        kdf.AssetKind.token => UnifiedSwapAssetKind.token,
        null => UnifiedSwapAssetKind.unknown,
      },
      decimals: asset.decimals,
      contractAddress: asset.contractAddress,
      rawChainFamilyDiscriminator: asset.chainFamilyValue.isKnown
          ? null
          : asset.chainFamilyValue.rawValue,
      rawKindDiscriminator: asset.assetKindValue.isKnown
          ? null
          : asset.assetKindValue.rawValue,
    );

UnifiedSwapTopology _topology(List<kdf.RouteStage> stages) {
  final kinds = stages
      .map(
        (stage) => switch (stage) {
          kdf.KdfAtomicRouteStage() => 'a',
          kdf.ExternalLiquidityRouteStage() => 'e',
          kdf.UnknownRouteStage() => '?',
        },
      )
      .fold(<String>[], (result, value) {
        if (result.isEmpty || result.last != value) result.add(value);
        return result;
      });
  return switch (kinds.join()) {
    'a' => UnifiedSwapTopology.atomic,
    'e' => UnifiedSwapTopology.external,
    'ea' => UnifiedSwapTopology.externalToAtomic,
    'ae' => UnifiedSwapTopology.atomicToExternal,
    'eae' => UnifiedSwapTopology.externalToAtomicToExternal,
    _ => UnifiedSwapTopology.unknown,
  };
}

UnifiedSwapQuoteFailure _failureFor(Object error) {
  String? type;
  if (error is kdf.RouteRpcError) {
    type = error.rawDiscriminator;
  } else if (error is kdf.GeneralErrorResponse) {
    type = error.errorType;
  } else if (error is kdf.MmRpcException) {
    type = error.errorType;
  }
  if (const {
    'InvalidRequest',
    'AddressSelectionError',
    'AssetMismatch',
    'ChainMismatch',
    'SenderMismatch',
    'RecipientMismatch',
    'AmountMismatch',
  }.contains(type)) {
    return UnifiedSwapQuoteFailure.invalidIntent;
  }
  if (const {
    'QuoteExpired',
    'EvaluationNotFound',
    'NoSuchTask',
    'QuoteChanged',
    'CandidateChanged',
  }.contains(type)) {
    return UnifiedSwapQuoteFailure.quoteExpired;
  }
  if (const {
    'AssetNotActivated',
    'UnsupportedCapability',
    'ProviderPairUnavailable',
    'SourceExecutorUnavailable',
    'SignerPolicyUnsupported',
    'ApprovalRequired',
    'OrderUnavailable',
    'AtomicGuardMismatch',
    'AtomicFillNotReady',
  }.contains(type)) {
    return UnifiedSwapQuoteFailure.capabilityUnavailable;
  }
  if (const {
    'Transport',
    'NetworkError',
    'Timeout',
    'ProviderTransport',
    'ProviderRateLimited',
    'ChainTransport',
  }.contains(type)) {
    return UnifiedSwapQuoteFailure.networkUnavailable;
  }
  if (const {
    'Internal',
    'PersistenceError',
    'ProviderError',
    'ProviderRejected',
    'ProviderResponseInvalid',
    'SimulationFailed',
    'RecoveryRequired',
    'ApprovalFailed',
    'SigningFailed',
    'ChainResponseInvalid',
    'BroadcastFailed',
    'TransactionReverted',
    'ApprovalSpenderMismatch',
    'ConsentDigestMismatch',
    'ProviderStepMismatch',
    'FeeLimitExceeded',
    'NetworkFeeCapExceeded',
    'IdempotencyConflict',
    'ActionRevisionConflict',
    'InvalidUserActionState',
    'ExecutionNotFound',
    'RouteNotFound',
  }.contains(type)) {
    return UnifiedSwapQuoteFailure.serviceUnavailable;
  }
  if (error is TimeoutException) {
    return UnifiedSwapQuoteFailure.networkUnavailable;
  }
  if (error is FormatException ||
      error is StateError ||
      error is ArgumentError ||
      error is TradeRouteManagerException) {
    return UnifiedSwapQuoteFailure.serviceUnavailable;
  }
  return UnifiedSwapQuoteFailure.unknown;
}

String _required(String value, String name) {
  if (value.trim().isEmpty || value.trim() != value) {
    throw ArgumentError.value(value, name, 'Must be trimmed and non-empty');
  }
  return value;
}
