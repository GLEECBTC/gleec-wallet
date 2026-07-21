import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_capability_policy.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_model_limits.dart';

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
  UnifiedSwapValuationProof({
    required this.currency,
    required this.observedAt,
    required this.validUntil,
    required this.netMinimumReceive,
    this.sourceValue,
  }) {
    UnifiedSwapModelLimits.requireString(
      currency,
      'currency',
      maximumLength: UnifiedSwapModelLimits.discriminatorLength,
    );
    if (!_isUnsignedDecimal(netMinimumReceive) ||
        (sourceValue != null && !_isUnsignedDecimal(sourceValue!)) ||
        validUntil.toUtc().isBefore(observedAt.toUtc()) ||
        validUntil.toUtc().difference(observedAt.toUtc()) >
            const Duration(minutes: 5)) {
      throw ArgumentError('Valuation proof is malformed or unbounded');
    }
  }

  final String currency;
  final DateTime observedAt;
  final DateTime validUntil;
  final String netMinimumReceive;
  final String? sourceValue;

  bool isFreshAt(DateTime now) {
    final utcNow = now.toUtc();
    return currency.trim().isNotEmpty &&
        _isUnsignedDecimal(netMinimumReceive) &&
        (sourceValue == null || _isUnsignedDecimal(sourceValue!)) &&
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
    sourceValue,
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
    List<String> stageAssetPaths = const [],
  }) : stageKinds = List.unmodifiable(stageKinds),
       selectedTools = List.unmodifiable(selectedTools),
       stageAssetPaths = List.unmodifiable(stageAssetPaths) {
    UnifiedSwapModelLimits.requireString(
      topology,
      'topology',
      maximumLength: UnifiedSwapModelLimits.discriminatorLength,
    );
    UnifiedSwapModelLimits.requireString(
      sourceSelectorFingerprint,
      'sourceSelectorFingerprint',
    );
    UnifiedSwapModelLimits.requireString(
      resolvedSourceAddress,
      'resolvedSourceAddress',
      maximumLength: UnifiedSwapModelLimits.addressLength,
    );
    UnifiedSwapModelLimits.requireString(
      recipient,
      'recipient',
      maximumLength: UnifiedSwapModelLimits.addressLength,
    );
    UnifiedSwapModelLimits.requireListLength(
      stageKinds.length,
      'stageKinds',
      maximumLength: UnifiedSwapModelLimits.routeStages,
    );
    UnifiedSwapModelLimits.requireListLength(
      selectedTools.length,
      'selectedTools',
    );
    UnifiedSwapModelLimits.requireListLength(
      stageAssetPaths.length,
      'stageAssetPaths',
      maximumLength: UnifiedSwapModelLimits.routeStages,
    );
    for (final value in [...stageKinds, ...selectedTools, ...stageAssetPaths]) {
      UnifiedSwapModelLimits.requireString(value, 'routeStructureValue');
    }
    if (!source.hasBoundedIdentity || !destination.hasBoundedIdentity) {
      throw ArgumentError('Route structure asset identity exceeds bounds');
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
  final List<String> stageAssetPaths;

  @override
  List<Object?> get props => [
    topology,
    source.ticker,
    source.chainFamily,
    source.chainId,
    source.kind,
    source.decimals,
    source.contractIdentity,
    source.rawChainFamilyDiscriminator,
    source.rawKindDiscriminator,
    destination.ticker,
    destination.chainFamily,
    destination.chainId,
    destination.kind,
    destination.decimals,
    destination.contractIdentity,
    destination.rawChainFamilyDiscriminator,
    destination.rawKindDiscriminator,
    sourceSelectorFingerprint,
    _addressIdentity(source, resolvedSourceAddress),
    _addressIdentity(destination, recipient),
    stageKinds,
    selectedTools,
    stageAssetPaths,
  ];
}

enum UnifiedSwapPreparedApprovalState {
  notApplicable,
  sufficientAllowance,
  exactApprovalRequired,
}

/// Canonical, provider-neutral approval authority for one prepared stage.
///
/// Stage identity and the exact token/spender identify who may spend what.
/// The remaining fields identify the action the wallet has to take. Allowance
/// balance itself is intentionally excluded: only the resulting sufficient or
/// exact-approval-required state changes the customer's authority.
@immutable
class UnifiedSwapPreparedApprovalAuthority extends Equatable {
  UnifiedSwapPreparedApprovalAuthority({
    required this.stageIndex,
    required this.state,
    this.token,
    this.spender,
    String? requiredAmount,
    this.resetRequired = false,
  }) : requiredAmount = requiredAmount == null
           ? null
           : _smallestUnitAmount(requiredAmount) {
    if (stageIndex < 0 || stageIndex >= UnifiedSwapModelLimits.routeStages) {
      throw ArgumentError.value(
        stageIndex,
        'stageIndex',
        'Must not be negative',
      );
    }
    switch (state) {
      case UnifiedSwapPreparedApprovalState.notApplicable:
        if (token != null ||
            spender != null ||
            this.requiredAmount != null ||
            resetRequired) {
          throw ArgumentError(
            'A not-applicable approval cannot carry spend authority',
          );
        }
      case UnifiedSwapPreparedApprovalState.sufficientAllowance:
      case UnifiedSwapPreparedApprovalState.exactApprovalRequired:
        if (token == null ||
            !token!.isValidEvmV1 ||
            token!.kind != UnifiedSwapAssetKind.token ||
            spender == null ||
            this.requiredAmount == null ||
            !_isCanonicalEvmAddress(spender!)) {
          throw ArgumentError(
            'Prepared approval authority must be exact and canonical',
          );
        }
        if (state == UnifiedSwapPreparedApprovalState.sufficientAllowance &&
            resetRequired) {
          throw ArgumentError(
            'Sufficient allowance cannot require an approval reset',
          );
        }
    }
  }

  final int stageIndex;
  final UnifiedSwapPreparedApprovalState state;
  final UnifiedSwapAssetIdentity? token;
  final String? spender;
  final String? requiredAmount;
  final bool resetRequired;

  bool hasSameAuthorityIdentity(UnifiedSwapPreparedApprovalAuthority other) =>
      stageIndex == other.stageIndex &&
      _sameOptionalAssetIdentity(token, other.token) &&
      spender == other.spender;

  @override
  List<Object?> get props => [
    stageIndex,
    state,
    ..._optionalAssetIdentityProps(token),
    spender,
    requiredAmount,
    resetRequired,
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
    List<String> warnings = const [],
    List<UnifiedSwapPreparedApprovalAuthority> preparedApprovals = const [],
  }) : expectedReceive = _smallestUnitAmount(expectedReceive),
       minimumReceive = _smallestUnitAmount(minimumReceive),
       requiredNonNetworkFees = _amountMap(requiredNonNetworkFees),
       consentedNonNetworkFeeLimits = _amountMap(consentedNonNetworkFeeLimits),
       requiredNetworkFees = _amountMap(requiredNetworkFees),
       consentedNetworkFeeCaps = _amountMap(consentedNetworkFeeCaps),
       warnings = List.unmodifiable(warnings),
       preparedApprovals = List.unmodifiable(preparedApprovals) {
    UnifiedSwapModelLimits.requireListLength(warnings.length, 'warnings');
    UnifiedSwapModelLimits.requireListLength(
      preparedApprovals.length,
      'preparedApprovals',
      maximumLength: UnifiedSwapModelLimits.routeStages,
    );
    if (BigInt.parse(this.minimumReceive) >
        BigInt.parse(this.expectedReceive)) {
      throw ArgumentError('minimumReceive must not exceed expectedReceive');
    }
    if (this.warnings.any(
          (warning) => !UnifiedSwapModelLimits.isCanonicalString(warning),
        ) ||
        this.warnings.toSet().length != this.warnings.length) {
      throw ArgumentError('Refresh warnings must be unique and non-empty');
    }
    var previousStageIndex = -1;
    for (final approval in this.preparedApprovals) {
      if (approval.stageIndex <= previousStageIndex) {
        throw ArgumentError(
          'Prepared approvals must have unique, increasing stage indexes',
        );
      }
      previousStageIndex = approval.stageIndex;
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
  final List<String> warnings;
  final List<UnifiedSwapPreparedApprovalAuthority> preparedApprovals;

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
    warnings,
    preparedApprovals,
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
  if (!_samePreparedApprovalIdentities(
    consented.preparedApprovals,
    replacement.preparedApprovals,
  )) {
    return UnifiedSwapRefreshDecision.freshQuoteRequired;
  }
  if (!listEquals(consented.preparedApprovals, replacement.preparedApprovals)) {
    return UnifiedSwapRefreshDecision.explicitConsentRequired;
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
  final noNewWarnings = replacement.warnings.every(consented.warnings.contains);

  if (degradationBps <=
          BigInt.from(unifiedSwapQuietRefreshMaximumDegradationBps) &&
      minimumStillSatisfied &&
      feesStillCapped &&
      noNewWarnings) {
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

bool _samePreparedApprovalIdentities(
  List<UnifiedSwapPreparedApprovalAuthority> left,
  List<UnifiedSwapPreparedApprovalAuthority> right,
) =>
    left.length == right.length &&
    left.indexed.every(
      (entry) => entry.$2.hasSameAuthorityIdentity(right[entry.$1]),
    );

String _addressIdentity(UnifiedSwapAssetIdentity asset, String address) {
  if (asset.isValidEvmV1 && _isEvmAddress(address)) {
    return address.toLowerCase();
  }
  return address;
}

bool _sameOptionalAssetIdentity(
  UnifiedSwapAssetIdentity? left,
  UnifiedSwapAssetIdentity? right,
) => left == null ? right == null : right != null && left.sameIdentity(right);

List<Object?> _optionalAssetIdentityProps(UnifiedSwapAssetIdentity? asset) =>
    asset == null
    ? const [null]
    : [
        asset.ticker,
        asset.chainFamily,
        asset.chainId,
        asset.kind,
        asset.decimals,
        asset.contractIdentity,
        asset.rawChainFamilyDiscriminator,
        asset.rawKindDiscriminator,
      ];

bool _isCanonicalEvmAddress(String value) =>
    _isEvmAddress(value) && value == value.toLowerCase();

bool _isEvmAddress(String value) =>
    RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(value);

Map<String, String> _amountMap(Map<String, String> values) {
  UnifiedSwapModelLimits.requireListLength(values.length, 'amountMap');
  final normalized = <String, String>{};
  for (final entry in values.entries) {
    UnifiedSwapModelLimits.requireString(entry.key, 'amountMapKey');
    normalized[entry.key] = _smallestUnitAmount(entry.value);
  }
  return Map.unmodifiable(normalized);
}

String _smallestUnitAmount(String value) {
  if (value.length > UnifiedSwapModelLimits.amountDigits ||
      !RegExp(r'^(?:0|[1-9][0-9]*)$').hasMatch(value)) {
    throw ArgumentError.value(
      value,
      'amount',
      'Must be a non-negative integer in smallest units',
    );
  }
  return value;
}

bool _isUnsignedDecimal(String value) =>
    value.length <= UnifiedSwapModelLimits.amountDigits &&
    RegExp(r'^(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$').hasMatch(value);
