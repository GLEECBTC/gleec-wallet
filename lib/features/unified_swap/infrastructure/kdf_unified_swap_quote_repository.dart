import 'dart:async';

import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart' as kdf;
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:web_dex/features/unified_swap/domain/route_activity_models.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_capability_policy.dart';
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

/// An unforgeable capability produced only after the retained quote, wallet
/// source, Review, stage limits, and every nested KDF digest have matched.
final class KdfVerifiedPreparedExecution {
  const KdfVerifiedPreparedExecution._({
    required this.prepared,
    required this.intent,
  });

  final kdf.PrepareExecutionResult prepared;
  final UnifiedSwapIntent intent;
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
    kdf.ValuationSnapshot? Function()? valuationSnapshot,
    DateTime Function()? now,
    this.consentLifetime = const Duration(minutes: 2),
  }) : _client = client,
       _preparationClient =
           preparationClient ??
           (client is KdfUnifiedSwapPreparationClient
               ? client as KdfUnifiedSwapPreparationClient
               : null),
       _preparationLimitsPolicy = preparationLimitsPolicy,
       _expectedSourceAddress = expectedSourceAddress,
       _eligibilityCheck = eligibilityCheck,
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
  }

  final KdfUnifiedSwapQuoteClient _client;
  final KdfUnifiedSwapPreparationClient? _preparationClient;
  final UnifiedSwapPreparationLimitsPolicy? _preparationLimitsPolicy;
  final UnifiedSwapExpectedSourceAddressResolver? _expectedSourceAddress;
  final UnifiedSwapEligibilityCheck? _eligibilityCheck;
  final String _walletId;
  final UnifiedSwapRecipientValidator _validateRecipient;
  final UnifiedSwapExactRecipientValidator? _validateExactRecipient;
  final kdf.ValuationSnapshot? Function() _valuationSnapshot;
  final DateTime Function() _now;
  final Duration consentLifetime;
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

    try {
      if (!await _isEligible(intent)) {
        throw const UnifiedSwapQuoteException(
          UnifiedSwapQuoteFailure.capabilityUnavailable,
        );
      }
      final exactValidator = _validateExactRecipient;
      final recipientIsValid = exactValidator == null
          ? await _validateRecipient(
              ticker: intent.destination.ticker,
              address: intent.recipient,
            )
          : await exactValidator(
              asset: intent.destination,
              address: intent.recipient,
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
      final result = await _client.quote(
        intent: routeIntent,
        routeSources: _routeSources(intent.sourceSelection),
        valuationSnapshot: snapshot,
      );
      _pruneExactQuotes(now);
      final candidates = <UnifiedSwapQuoteCandidate>[];
      for (final candidate in result.candidates) {
        final digestIsValid = _hasValidCandidateDigest(candidate);
        final mapped = _candidate(
          candidate,
          evaluationExpiresAt: result.evaluationExpiresAt,
          valuationSnapshot: snapshot,
          digestIsValid: digestIsValid,
        );
        candidates.add(mapped);
        if (digestIsValid && !mapped.isExpiredAt(now)) {
          final binding = _ExactQuoteBinding(
            evaluationId: result.evaluationId,
            intent: intent,
            routeIntent: routeIntent,
            candidate: candidate,
            mappedCandidate: mapped,
          );
          _exactQuotes[binding.key] = binding;
        }
      }
      _trimExactQuotes();
      return UnifiedSwapQuoteEvaluation(
        evaluationId: result.evaluationId,
        intentRevision: intent.revision,
        candidates: candidates,
      );
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
    _pruneExactQuotes(now);
    final client = _preparationClient;
    final limitsPolicy = _preparationLimitsPolicy;
    final sourceAddressResolver = _expectedSourceAddress;
    final binding = _findBinding(intent, candidate);
    if (client == null ||
        limitsPolicy == null ||
        sourceAddressResolver == null ||
        binding == null ||
        !candidate.isExecutable ||
        candidate.isExpiredAt(now)) {
      throw const UnifiedSwapQuoteException(
        UnifiedSwapQuoteFailure.capabilityUnavailable,
      );
    }

    try {
      if (!await _isEligible(intent)) {
        throw const UnifiedSwapQuoteException(
          UnifiedSwapQuoteFailure.capabilityUnavailable,
        );
      }
      final expectedSourceAddress = await sourceAddressResolver(intent);
      if (expectedSourceAddress == null ||
          !RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(expectedSourceAddress)) {
        throw const UnifiedSwapQuoteException(
          UnifiedSwapQuoteFailure.capabilityUnavailable,
        );
      }
      final limits = await limitsPolicy(
        intent: intent,
        candidate: binding.candidate,
      );
      if (limits == null ||
          !_validPreparationLimits(binding.candidate, limits)) {
        throw const UnifiedSwapQuoteException(
          UnifiedSwapQuoteFailure.capabilityUnavailable,
        );
      }
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
      final prepared = await client.prepareExecution(
        evaluationId: binding.evaluationId,
        candidateId: binding.candidate.candidateId,
        candidateDigest: binding.candidate.candidateDigest,
        finalMinimumReceive: binding.candidate.minimumReceive,
        consentExpiresAt: consentExpiresAt,
        stages: limits,
      );
      if (!_preparedResultMatches(
        binding,
        prepared,
        limits,
        consentExpiresAt,
        now,
        expectedSourceAddress,
      )) {
        throw const UnifiedSwapQuoteException(
          UnifiedSwapQuoteFailure.invalidIntent,
        );
      }
      return KdfVerifiedPreparedExecution._(prepared: prepared, intent: intent);
    } on UnifiedSwapQuoteException {
      rethrow;
    } on Object catch (error) {
      throw UnifiedSwapQuoteException(_failureFor(error));
    }
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

kdf.ValuationSnapshot? _freshValuationSnapshot(
  kdf.ValuationSnapshot? snapshot,
  DateTime now,
) {
  if (snapshot == null ||
      !snapshot.isExecutable ||
      snapshot.observedAt.toUtc().isAfter(now) ||
      !snapshot.validUntil.toUtc().isAfter(now)) {
    return null;
  }
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
    if (!candidate.routeSourceValue.isKnown)
      candidate.routeSourceValue.rawValue,
    if (!rankIsKnown) candidate.rankStatusValue.rawValue,
    for (final stage in candidate.stages)
      if (!stage.isExecutable) stage.stageType,
    for (final warning in candidate.warningValues)
      if (!warning.isKnown) warning.rawValue,
  ];
  final expiresAt =
      candidate.expiresAt.toUtc().isBefore(evaluationExpiresAt.toUtc())
      ? candidate.expiresAt.toUtc()
      : evaluationExpiresAt.toUtc();
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
    isExecutable:
        digestIsValid &&
        candidate.isExecutable &&
        topology != UnifiedSwapTopology.unknown &&
        unknowns.isEmpty,
    rawUnknownDiscriminator: unknowns.isEmpty ? null : unknowns.join(','),
  );
}

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
      review.resolvedSourceAddress.toLowerCase() !=
          expectedSourceAddress.toLowerCase() ||
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
        expectedStageSource == null ||
        !RegExp(
          r'^0x[0-9a-fA-F]{40}$',
        ).hasMatch(authority.resolvedSourceAddress) ||
        authority.resolvedSourceAddress.toLowerCase() !=
            expectedStageSource.toLowerCase() ||
        preparedStage.resolvedSourceAddress == null ||
        preparedStage.resolvedSourceAddress!.toLowerCase() !=
            authority.resolvedSourceAddress.toLowerCase()) {
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
  );
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
  if (!RegExp(r'^(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$').hasMatch(value)) {
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
    left.contractAddress?.toLowerCase() ==
        right.contractAddress?.toLowerCase() &&
    left.decimals == right.decimals;

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
