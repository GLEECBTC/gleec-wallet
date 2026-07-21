import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:web_dex/features/unified_swap/domain/route_activity_models.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_capability_policy.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_product_policy.dart';

enum UnifiedSwapQuoteStatus { idle, loading, ready, expired, unavailable }

enum UnifiedSwapTopology {
  atomic,
  external,
  externalToAtomic,
  atomicToExternal,
  externalToAtomicToExternal,
  unknown,
}

enum UnifiedSwapQuoteFailure {
  capabilityUnavailable,
  quoteExpired,
  invalidIntent,
  suspiciousToken,
  unknownTokenConfirmationRequired,
  networkUnavailable,
  serviceUnavailable,
  unknown,
}

enum UnifiedSwapHdChain { external, internal, unknown }

sealed class UnifiedSwapSourceSelection extends Equatable {
  const UnifiedSwapSourceSelection();

  UnifiedSwapSourceSelectorKind get kind;
  bool get isExecutable;
  String get fingerprint;

  @override
  List<Object?> get props => [kind, isExecutable, fingerprint];
}

final class UnifiedSwapActiveSourceSelection
    extends UnifiedSwapSourceSelection {
  const UnifiedSwapActiveSourceSelection();

  @override
  UnifiedSwapSourceSelectorKind get kind =>
      UnifiedSwapSourceSelectorKind.active;
  @override
  bool get isExecutable => true;
  @override
  String get fingerprint => 'active';
}

final class UnifiedSwapHdAddressSourceSelection
    extends UnifiedSwapSourceSelection {
  UnifiedSwapHdAddressSourceSelection({
    required this.accountId,
    required this.chain,
    required this.addressId,
  }) {
    if (accountId < 0 || addressId < 0) {
      throw RangeError('HD address indexes must be non-negative');
    }
  }

  final int accountId;
  final UnifiedSwapHdChain chain;
  final int addressId;

  @override
  UnifiedSwapSourceSelectorKind get kind => UnifiedSwapSourceSelectorKind.hd;
  @override
  bool get isExecutable => chain != UnifiedSwapHdChain.unknown;
  @override
  String get fingerprint => 'hd:$accountId:${chain.name}:$addressId';

  @override
  List<Object?> get props => [accountId, chain, addressId];
}

final class UnifiedSwapHdPathSourceSelection
    extends UnifiedSwapSourceSelection {
  UnifiedSwapHdPathSourceSelection(this.derivationPath) {
    if (derivationPath.trim().isEmpty ||
        derivationPath.trim() != derivationPath) {
      throw ArgumentError.value(derivationPath, 'derivationPath');
    }
  }

  final String derivationPath;

  @override
  UnifiedSwapSourceSelectorKind get kind => UnifiedSwapSourceSelectorKind.hd;
  @override
  bool get isExecutable => true;
  @override
  String get fingerprint => 'hd_path:$derivationPath';

  @override
  List<Object?> get props => [derivationPath];
}

final class UnifiedSwapUnknownSourceSelection
    extends UnifiedSwapSourceSelection {
  UnifiedSwapUnknownSourceSelection(this.rawDiscriminator) {
    if (rawDiscriminator.trim().isEmpty) {
      throw ArgumentError.value(rawDiscriminator, 'rawDiscriminator');
    }
  }

  final String rawDiscriminator;

  @override
  UnifiedSwapSourceSelectorKind get kind =>
      UnifiedSwapSourceSelectorKind.unknown;
  @override
  bool get isExecutable => false;
  @override
  String get fingerprint => 'unknown:$rawDiscriminator';

  @override
  List<Object?> get props => [rawDiscriminator];
}

@immutable
class UnifiedSwapIntent extends Equatable {
  UnifiedSwapIntent({
    required this.revision,
    required this.source,
    required this.destination,
    required String sourceAmount,
    required this.sourceSelection,
    required this.recipient,
    this.slippageBps = unifiedSwapDefaultSlippageBps,
    this.sourceTokenTrust = UnifiedSwapTokenTrust.unknown,
    this.destinationTokenTrust = UnifiedSwapTokenTrust.unknown,
    this.unknownTokenConfirmed = false,
    this.externalRecipientConfirmed = false,
  }) : sourceAmount = _smallestUnitAmount(sourceAmount) {
    if (revision < 0) {
      throw ArgumentError.value(revision, 'revision', 'Must not be negative');
    }
    if (recipient.trim().isEmpty) {
      throw ArgumentError.value(recipient, 'recipient', 'Must not be empty');
    }
    if (slippageBps < 0 || slippageBps > 10_000) {
      throw RangeError.range(slippageBps, 0, 10_000, 'slippageBps');
    }
  }

  final int revision;
  final UnifiedSwapAssetIdentity source;
  final UnifiedSwapAssetIdentity destination;
  final String sourceAmount;
  final UnifiedSwapSourceSelection sourceSelection;
  final String recipient;
  final int slippageBps;
  final UnifiedSwapTokenTrust sourceTokenTrust;
  final UnifiedSwapTokenTrust destinationTokenTrust;
  final bool unknownTokenConfirmed;
  final bool externalRecipientConfirmed;

  UnifiedSwapIntent copyWith({
    int? revision,
    UnifiedSwapAssetIdentity? source,
    UnifiedSwapAssetIdentity? destination,
    String? sourceAmount,
    UnifiedSwapSourceSelection? sourceSelection,
    String? recipient,
    int? slippageBps,
    UnifiedSwapTokenTrust? sourceTokenTrust,
    UnifiedSwapTokenTrust? destinationTokenTrust,
    bool? unknownTokenConfirmed,
    bool? externalRecipientConfirmed,
  }) => UnifiedSwapIntent(
    revision: revision ?? this.revision,
    source: source ?? this.source,
    destination: destination ?? this.destination,
    sourceAmount: sourceAmount ?? this.sourceAmount,
    sourceSelection: sourceSelection ?? this.sourceSelection,
    recipient: recipient ?? this.recipient,
    slippageBps: slippageBps ?? this.slippageBps,
    sourceTokenTrust: sourceTokenTrust ?? this.sourceTokenTrust,
    destinationTokenTrust: destinationTokenTrust ?? this.destinationTokenTrust,
    unknownTokenConfirmed: unknownTokenConfirmed ?? this.unknownTokenConfirmed,
    externalRecipientConfirmed:
        externalRecipientConfirmed ?? this.externalRecipientConfirmed,
  );

  UnifiedSwapQuoteFailure? get tokenFailure {
    final decisions = [
      unifiedSwapTokenDecision(sourceTokenTrust),
      unifiedSwapTokenDecision(destinationTokenTrust),
    ];
    if (decisions.contains(UnifiedSwapTokenDecision.blocked)) {
      return UnifiedSwapQuoteFailure.suspiciousToken;
    }
    if (!unknownTokenConfirmed &&
        decisions.contains(UnifiedSwapTokenDecision.confirmationRequired)) {
      return UnifiedSwapQuoteFailure.unknownTokenConfirmationRequired;
    }
    return null;
  }

  @override
  List<Object?> get props => [
    revision,
    ..._identityProps(source),
    ..._identityProps(destination),
    sourceAmount,
    sourceSelection,
    recipient,
    slippageBps,
    sourceTokenTrust,
    destinationTokenTrust,
    unknownTokenConfirmed,
    externalRecipientConfirmed,
  ];
}

@immutable
class UnifiedSwapQuoteCandidate extends Equatable {
  UnifiedSwapQuoteCandidate({
    required this.candidateId,
    required this.candidateDigest,
    required this.topology,
    required String expectedReceive,
    required String minimumReceive,
    required List<RouteExecutionFee> fees,
    required this.expiresAt,
    required this.rankable,
    required this.isExecutable,
    this.rank,
    this.valuation,
    this.priceImpactBps,
    this.authoritativeLowLiquidity = false,
    this.rawUnknownDiscriminator,
  }) : expectedReceive = _smallestUnitAmount(expectedReceive),
       minimumReceive = _smallestUnitAmount(minimumReceive),
       fees = List.unmodifiable(fees) {
    if (candidateId.isEmpty || candidateDigest.isEmpty) {
      throw ArgumentError('Candidate identity must not be empty');
    }
    if (topology == UnifiedSwapTopology.unknown && isExecutable) {
      throw ArgumentError('An unknown topology cannot be executable');
    }
    if (!rankable && rank != null) {
      throw ArgumentError('An unrankable candidate cannot have a rank');
    }
    if (rankable && (rank == null || valuation == null)) {
      throw ArgumentError(
        'A rankable candidate requires both a rank and wallet valuation',
      );
    }
    if (priceImpactBps != null &&
        (priceImpactBps! < 0 || priceImpactBps! > 10_000)) {
      throw RangeError.range(priceImpactBps!, 0, 10_000, 'priceImpactBps');
    }
  }

  final String candidateId;
  final String candidateDigest;
  final UnifiedSwapTopology topology;
  final String expectedReceive;
  final String minimumReceive;
  final List<RouteExecutionFee> fees;
  final DateTime expiresAt;
  final bool rankable;
  final bool isExecutable;
  final int? rank;
  final UnifiedSwapValuationProof? valuation;
  final int? priceImpactBps;
  final bool authoritativeLowLiquidity;
  final String? rawUnknownDiscriminator;

  bool isExpiredAt(DateTime value) => !expiresAt.isAfter(value.toUtc());

  UnifiedSwapRiskWarnings get riskWarnings => unifiedSwapRiskWarnings(
    priceImpactBps: priceImpactBps,
    expectedReceive: expectedReceive,
    minimumReceive: minimumReceive,
    authoritativeLowLiquidity: authoritativeLowLiquidity,
  );

  @override
  List<Object?> get props => [
    candidateId,
    candidateDigest,
    topology,
    expectedReceive,
    minimumReceive,
    fees,
    expiresAt,
    rankable,
    isExecutable,
    rank,
    valuation,
    priceImpactBps,
    authoritativeLowLiquidity,
    rawUnknownDiscriminator,
  ];
}

@immutable
class UnifiedSwapQuoteEvaluation extends Equatable {
  UnifiedSwapQuoteEvaluation({
    required this.evaluationId,
    required this.intentRevision,
    required List<UnifiedSwapQuoteCandidate> candidates,
  }) : candidates = List.unmodifiable(candidates) {
    if (evaluationId.isEmpty) {
      throw ArgumentError.value(
        evaluationId,
        'evaluationId',
        'Must not be empty',
      );
    }
  }

  final String evaluationId;
  final int intentRevision;
  final List<UnifiedSwapQuoteCandidate> candidates;

  DateTime? get earliestExpiry {
    DateTime? value;
    for (final candidate in candidates) {
      if (value == null || candidate.expiresAt.isBefore(value)) {
        value = candidate.expiresAt;
      }
    }
    return value;
  }

  List<UnifiedSwapQuoteCandidate> get rankedCandidates =>
      List.unmodifiable(candidates.where((candidate) => candidate.rankable));

  List<UnifiedSwapQuoteCandidate> get unrankableCandidates =>
      List.unmodifiable(candidates.where((candidate) => !candidate.rankable));

  bool canClaimBestNetReturnAt(DateTime now) =>
      canClaimUnifiedSwapBestNetReturn(
        valuations: candidates
            .map((candidate) => candidate.rankable ? candidate.valuation : null)
            .toList(growable: false),
        now: now,
      );

  @override
  List<Object?> get props => [evaluationId, intentRevision, candidates];
}

String _smallestUnitAmount(String value) {
  if (!RegExp(r'^(?:0|[1-9][0-9]*)$').hasMatch(value)) {
    throw ArgumentError.value(
      value,
      'amount',
      'Must be a non-negative integer in smallest units',
    );
  }
  return value;
}

List<Object?> _identityProps(UnifiedSwapAssetIdentity identity) => [
  identity.ticker,
  identity.chainFamily,
  identity.chainId,
  identity.kind,
  identity.decimals,
  identity.contractAddress?.toLowerCase(),
  identity.rawChainFamilyDiscriminator,
  identity.rawKindDiscriminator,
];
