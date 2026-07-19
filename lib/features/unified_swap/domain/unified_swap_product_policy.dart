import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_capability_policy.dart';

const int unifiedSwapDefaultSlippageBps = 50;
const int unifiedSwapQuietRefreshMaximumDegradationBps = 25;
const int unifiedSwapHighPriceImpactBps = 300;
const int unifiedSwapLowLiquiditySpreadBps = 100;

enum UnifiedSwapTokenTrust { trusted, unknown, suspicious }

enum UnifiedSwapTokenDecision { allowed, confirmationRequired, blocked }

enum UnifiedSwapRefreshDecision {
  quiet,
  explicitConsentRequired,
  freshQuoteRequired,
  unavailable,
}

@immutable
class UnifiedSwapRiskWarnings extends Equatable {
  const UnifiedSwapRiskWarnings({
    required this.highPriceImpact,
    required this.lowLiquidity,
  });

  final bool highPriceImpact;
  final bool lowLiquidity;

  @override
  List<Object?> get props => [highPriceImpact, lowLiquidity];
}

@immutable
class UnifiedSwapValuationProof extends Equatable {
  const UnifiedSwapValuationProof({
    required this.currency,
    required this.observedAt,
    required this.validUntil,
    required this.netMinimumReceive,
  });

  final String currency;
  final DateTime observedAt;
  final DateTime validUntil;
  final String netMinimumReceive;

  bool isFreshAt(DateTime now) {
    final utcNow = now.toUtc();
    return currency.trim().isNotEmpty &&
        _isUnsignedDecimal(netMinimumReceive) &&
        !observedAt.toUtc().isAfter(utcNow) &&
        validUntil.toUtc().isAfter(utcNow) &&
        !validUntil.toUtc().isBefore(observedAt.toUtc());
  }

  @override
  List<Object?> get props => [
    currency,
    observedAt.toUtc(),
    validUntil.toUtc(),
    netMinimumReceive,
  ];
}

/// The fields whose change invalidates the old route structure and therefore
/// requires a completely fresh quote instead of a replacement confirmation.
@immutable
class UnifiedSwapRouteStructure extends Equatable {
  UnifiedSwapRouteStructure({
    required this.topology,
    required this.source,
    required this.destination,
    required this.sourceSelectorFingerprint,
    required this.resolvedSourceAddress,
    required this.recipient,
    required List<String> stageKinds,
    required List<String> selectedTools,
  }) : stageKinds = List.unmodifiable(stageKinds),
       selectedTools = List.unmodifiable(selectedTools) {
    if (sourceSelectorFingerprint.trim().isEmpty ||
        resolvedSourceAddress.trim().isEmpty ||
        recipient.trim().isEmpty ||
        stageKinds.any((value) => value.trim().isEmpty) ||
        selectedTools.any((value) => value.trim().isEmpty)) {
      throw ArgumentError('Route structure fields must be non-empty');
    }
  }

  final String topology;
  final UnifiedSwapAssetIdentity source;
  final UnifiedSwapAssetIdentity destination;
  final String sourceSelectorFingerprint;
  final String resolvedSourceAddress;
  final String recipient;
  final List<String> stageKinds;
  final List<String> selectedTools;

  @override
  List<Object?> get props => [
    topology,
    source.ticker,
    source.chainFamily,
    source.chainId,
    source.kind,
    source.decimals,
    source.contractAddress?.toLowerCase(),
    source.rawChainFamilyDiscriminator,
    source.rawKindDiscriminator,
    destination.ticker,
    destination.chainFamily,
    destination.chainId,
    destination.kind,
    destination.decimals,
    destination.contractAddress?.toLowerCase(),
    destination.rawChainFamilyDiscriminator,
    destination.rawKindDiscriminator,
    sourceSelectorFingerprint,
    resolvedSourceAddress.toLowerCase(),
    recipient.toLowerCase(),
    stageKinds,
    selectedTools,
  ];
}

/// Exact economic projection used to decide whether a same-structure refresh
/// may happen quietly. All values are integer smallest units and keyed by an
/// exact asset/fee identifier produced by the infrastructure boundary.
@immutable
class UnifiedSwapRefreshSnapshot extends Equatable {
  UnifiedSwapRefreshSnapshot({
    required this.structure,
    required String expectedReceive,
    required String minimumReceive,
    required Map<String, String> requiredNonNetworkFees,
    required Map<String, String> consentedNonNetworkFeeLimits,
    required Map<String, String> requiredNetworkFees,
    required Map<String, String> consentedNetworkFeeCaps,
    required this.expiresAt,
  }) : expectedReceive = _smallestUnitAmount(expectedReceive),
       minimumReceive = _smallestUnitAmount(minimumReceive),
       requiredNonNetworkFees = _amountMap(requiredNonNetworkFees),
       consentedNonNetworkFeeLimits = _amountMap(consentedNonNetworkFeeLimits),
       requiredNetworkFees = _amountMap(requiredNetworkFees),
       consentedNetworkFeeCaps = _amountMap(consentedNetworkFeeCaps) {
    if (BigInt.parse(this.minimumReceive) >
        BigInt.parse(this.expectedReceive)) {
      throw ArgumentError('minimumReceive must not exceed expectedReceive');
    }
  }

  final UnifiedSwapRouteStructure structure;
  final String expectedReceive;
  final String minimumReceive;
  final Map<String, String> requiredNonNetworkFees;
  final Map<String, String> consentedNonNetworkFeeLimits;
  final Map<String, String> requiredNetworkFees;
  final Map<String, String> consentedNetworkFeeCaps;
  final DateTime expiresAt;

  bool isExpiredAt(DateTime now) => !expiresAt.toUtc().isAfter(now.toUtc());

  @override
  List<Object?> get props => [
    structure,
    expectedReceive,
    minimumReceive,
    requiredNonNetworkFees,
    consentedNonNetworkFeeLimits,
    requiredNetworkFees,
    consentedNetworkFeeCaps,
    expiresAt.toUtc(),
  ];
}

UnifiedSwapTokenDecision unifiedSwapTokenDecision(
  UnifiedSwapTokenTrust trust,
) => switch (trust) {
  UnifiedSwapTokenTrust.trusted => UnifiedSwapTokenDecision.allowed,
  UnifiedSwapTokenTrust.unknown =>
    UnifiedSwapTokenDecision.confirmationRequired,
  UnifiedSwapTokenTrust.suspicious => UnifiedSwapTokenDecision.blocked,
};

UnifiedSwapRiskWarnings unifiedSwapRiskWarnings({
  required int? priceImpactBps,
  required String expectedReceive,
  required String minimumReceive,
  required bool authoritativeLowLiquidity,
}) {
  if (priceImpactBps != null &&
      (priceImpactBps < 0 || priceImpactBps > 10_000)) {
    throw RangeError.range(priceImpactBps, 0, 10_000, 'priceImpactBps');
  }
  final expected = BigInt.parse(_smallestUnitAmount(expectedReceive));
  final minimum = BigInt.parse(_smallestUnitAmount(minimumReceive));
  if (minimum > expected) {
    throw ArgumentError('minimumReceive must not exceed expectedReceive');
  }
  final spreadBps = expected == BigInt.zero
      ? 0
      : ((expected - minimum) * BigInt.from(10_000) ~/ expected).toInt();
  return UnifiedSwapRiskWarnings(
    highPriceImpact:
        priceImpactBps != null &&
        priceImpactBps >= unifiedSwapHighPriceImpactBps,
    lowLiquidity:
        authoritativeLowLiquidity ||
        spreadBps >= unifiedSwapLowLiquiditySpreadBps,
  );
}

UnifiedSwapRefreshDecision unifiedSwapRefreshDecision({
  required UnifiedSwapRefreshSnapshot consented,
  required UnifiedSwapRefreshSnapshot replacement,
  required DateTime now,
}) {
  if (consented.isExpiredAt(now) || replacement.isExpiredAt(now)) {
    return UnifiedSwapRefreshDecision.unavailable;
  }
  if (consented.structure != replacement.structure) {
    return UnifiedSwapRefreshDecision.freshQuoteRequired;
  }

  final oldExpected = BigInt.parse(consented.expectedReceive);
  final newExpected = BigInt.parse(replacement.expectedReceive);
  final degradationBps =
      oldExpected == BigInt.zero || newExpected >= oldExpected
      ? BigInt.zero
      : (oldExpected - newExpected) * BigInt.from(10_000) ~/ oldExpected;
  final minimumStillSatisfied =
      BigInt.parse(replacement.minimumReceive) >=
      BigInt.parse(consented.minimumReceive);
  final feesStillCapped =
      _amountsFitLimits(
        replacement.requiredNonNetworkFees,
        consented.consentedNonNetworkFeeLimits,
      ) &&
      _amountsFitLimits(
        replacement.requiredNetworkFees,
        consented.consentedNetworkFeeCaps,
      );

  if (degradationBps <=
          BigInt.from(unifiedSwapQuietRefreshMaximumDegradationBps) &&
      minimumStillSatisfied &&
      feesStillCapped) {
    return UnifiedSwapRefreshDecision.quiet;
  }
  return UnifiedSwapRefreshDecision.explicitConsentRequired;
}

/// "Best net return" is only meaningful when every displayed candidate has a
/// fresh wallet valuation in the same currency and the KDF ranked all of them.
bool canClaimUnifiedSwapBestNetReturn({
  required List<UnifiedSwapValuationProof?> valuations,
  required DateTime now,
}) {
  if (valuations.length < 2 || valuations.any((value) => value == null)) {
    return false;
  }
  final proofs = valuations.cast<UnifiedSwapValuationProof>();
  if (proofs.any((proof) => !proof.isFreshAt(now))) return false;
  final currency = proofs.first.currency;
  return proofs.every((proof) => proof.currency == currency);
}

bool _amountsFitLimits(
  Map<String, String> required,
  Map<String, String> limits,
) {
  for (final entry in required.entries) {
    final limit = limits[entry.key];
    if (limit == null || BigInt.parse(entry.value) > BigInt.parse(limit)) {
      return false;
    }
  }
  return true;
}

Map<String, String> _amountMap(Map<String, String> values) {
  final normalized = <String, String>{};
  for (final entry in values.entries) {
    if (entry.key.trim().isEmpty) {
      throw ArgumentError('Amount map keys must be non-empty');
    }
    normalized[entry.key] = _smallestUnitAmount(entry.value);
  }
  return Map.unmodifiable(normalized);
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

bool _isUnsignedDecimal(String value) =>
    RegExp(r'^(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$').hasMatch(value);
