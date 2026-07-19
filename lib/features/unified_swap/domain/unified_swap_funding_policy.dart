import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_capability_policy.dart';

enum UnifiedSwapFundingDenial {
  invalidSourceIdentity,
  sourceBalanceIdentityMismatch,
  staleSourceBalance,
  invalidGasAssetIdentity,
  missingGasBalance,
  gasBalanceIdentityMismatch,
  staleGasBalance,
  invalidSourceAmount,
  invalidGasReserve,
  insufficientSourceBalance,
  insufficientGasBalance,
}

@immutable
class UnifiedSwapBalanceSnapshot extends Equatable {
  UnifiedSwapBalanceSnapshot({
    required this.asset,
    required String amount,
    required this.observedAt,
    required this.validUntil,
  }) : amount = _smallestUnitAmount(amount);

  final UnifiedSwapAssetIdentity asset;
  final String amount;
  final DateTime observedAt;
  final DateTime validUntil;

  bool isFreshAt(DateTime now) {
    final utcNow = now.toUtc();
    final observed = observedAt.toUtc();
    final valid = validUntil.toUtc();
    return !observed.isAfter(utcNow) &&
        valid.isAfter(utcNow) &&
        !valid.isBefore(observed);
  }

  @override
  List<Object?> get props => [
    asset,
    amount,
    observedAt.toUtc(),
    validUntil.toUtc(),
  ];
}

@immutable
class UnifiedSwapMaximumAmount extends Equatable {
  const UnifiedSwapMaximumAmount._({
    required this.amount,
    required this.denial,
  });

  const UnifiedSwapMaximumAmount.available(String amount)
    : this._(amount: amount, denial: null);

  const UnifiedSwapMaximumAmount.unavailable(
    UnifiedSwapFundingDenial denial, {
    String amount = '0',
  }) : this._(amount: amount, denial: denial);

  final String amount;
  final UnifiedSwapFundingDenial? denial;

  bool get isAvailable => denial == null;

  @override
  List<Object?> get props => [amount, denial];
}

@immutable
class UnifiedSwapFundingDecision extends Equatable {
  const UnifiedSwapFundingDecision._({
    required this.maximumSourceAmount,
    required this.denial,
  });

  const UnifiedSwapFundingDecision.allowed({
    required String maximumSourceAmount,
  }) : this._(maximumSourceAmount: maximumSourceAmount, denial: null);

  const UnifiedSwapFundingDecision.denied({
    required String maximumSourceAmount,
    required UnifiedSwapFundingDenial denial,
  }) : this._(maximumSourceAmount: maximumSourceAmount, denial: denial);

  final String maximumSourceAmount;
  final UnifiedSwapFundingDenial? denial;

  bool get isAllowed => denial == null;

  @override
  List<Object?> get props => [maximumSourceAmount, denial];
}

/// Computes the largest exact source amount that leaves the required native
/// gas reserve. Native sources spend balance and gas from one holding; tokens
/// retain their full token balance only when a fresh native balance can fund
/// the complete reserve.
UnifiedSwapMaximumAmount unifiedSwapMaximumSourceAmount({
  required UnifiedSwapAssetIdentity source,
  required UnifiedSwapBalanceSnapshot sourceBalance,
  required UnifiedSwapAssetIdentity nativeGasAsset,
  required UnifiedSwapBalanceSnapshot? nativeGasBalance,
  required String gasReserve,
  required DateTime now,
}) {
  final prepared = _prepareFunding(
    source: source,
    sourceBalance: sourceBalance,
    nativeGasAsset: nativeGasAsset,
    nativeGasBalance: nativeGasBalance,
    gasReserve: gasReserve,
    now: now,
  );
  if (prepared.denial != null) {
    return UnifiedSwapMaximumAmount.unavailable(prepared.denial!);
  }

  if (source.kind == UnifiedSwapAssetKind.native) {
    final maximum = prepared.sourceBalance! - prepared.gasReserve!;
    if (maximum <= BigInt.zero) {
      return const UnifiedSwapMaximumAmount.unavailable(
        UnifiedSwapFundingDenial.insufficientSourceBalance,
      );
    }
    return UnifiedSwapMaximumAmount.available(maximum.toString());
  }

  if (prepared.gasBalance! < prepared.gasReserve!) {
    return const UnifiedSwapMaximumAmount.unavailable(
      UnifiedSwapFundingDenial.insufficientGasBalance,
    );
  }
  if (prepared.sourceBalance == BigInt.zero) {
    return const UnifiedSwapMaximumAmount.unavailable(
      UnifiedSwapFundingDenial.insufficientSourceBalance,
    );
  }
  return UnifiedSwapMaximumAmount.available(prepared.sourceBalance!.toString());
}

/// Validates a requested exact source amount against the same inputs used by
/// Max. No decimal conversion or fiat estimate participates in funding.
UnifiedSwapFundingDecision unifiedSwapFundingDecision({
  required UnifiedSwapAssetIdentity source,
  required String sourceAmount,
  required UnifiedSwapBalanceSnapshot sourceBalance,
  required UnifiedSwapAssetIdentity nativeGasAsset,
  required UnifiedSwapBalanceSnapshot? nativeGasBalance,
  required String gasReserve,
  required DateTime now,
}) {
  final requested = _trySmallestUnitAmount(sourceAmount);
  if (requested == null || requested <= BigInt.zero) {
    return const UnifiedSwapFundingDecision.denied(
      maximumSourceAmount: '0',
      denial: UnifiedSwapFundingDenial.invalidSourceAmount,
    );
  }
  final prepared = _prepareFunding(
    source: source,
    sourceBalance: sourceBalance,
    nativeGasAsset: nativeGasAsset,
    nativeGasBalance: nativeGasBalance,
    gasReserve: gasReserve,
    now: now,
  );
  if (prepared.denial != null) {
    return UnifiedSwapFundingDecision.denied(
      maximumSourceAmount: '0',
      denial: prepared.denial!,
    );
  }

  if (source.kind == UnifiedSwapAssetKind.native) {
    final maximum = prepared.sourceBalance! > prepared.gasReserve!
        ? prepared.sourceBalance! - prepared.gasReserve!
        : BigInt.zero;
    if (requested > maximum) {
      return UnifiedSwapFundingDecision.denied(
        maximumSourceAmount: maximum.toString(),
        denial: UnifiedSwapFundingDenial.insufficientSourceBalance,
      );
    }
    return UnifiedSwapFundingDecision.allowed(
      maximumSourceAmount: maximum.toString(),
    );
  }

  final maximum = prepared.sourceBalance!;
  if (requested > maximum) {
    return UnifiedSwapFundingDecision.denied(
      maximumSourceAmount: maximum.toString(),
      denial: UnifiedSwapFundingDenial.insufficientSourceBalance,
    );
  }
  if (prepared.gasBalance! < prepared.gasReserve!) {
    return UnifiedSwapFundingDecision.denied(
      maximumSourceAmount: maximum.toString(),
      denial: UnifiedSwapFundingDenial.insufficientGasBalance,
    );
  }
  return UnifiedSwapFundingDecision.allowed(
    maximumSourceAmount: maximum.toString(),
  );
}

class _PreparedFunding {
  const _PreparedFunding({
    this.sourceBalance,
    this.gasBalance,
    this.gasReserve,
    this.denial,
  });

  final BigInt? sourceBalance;
  final BigInt? gasBalance;
  final BigInt? gasReserve;
  final UnifiedSwapFundingDenial? denial;
}

_PreparedFunding _prepareFunding({
  required UnifiedSwapAssetIdentity source,
  required UnifiedSwapBalanceSnapshot sourceBalance,
  required UnifiedSwapAssetIdentity nativeGasAsset,
  required UnifiedSwapBalanceSnapshot? nativeGasBalance,
  required String gasReserve,
  required DateTime now,
}) {
  if (!source.isValidEvmV1) {
    return const _PreparedFunding(
      denial: UnifiedSwapFundingDenial.invalidSourceIdentity,
    );
  }
  if (!sourceBalance.asset.sameIdentity(source)) {
    return const _PreparedFunding(
      denial: UnifiedSwapFundingDenial.sourceBalanceIdentityMismatch,
    );
  }
  if (!sourceBalance.isFreshAt(now)) {
    return const _PreparedFunding(
      denial: UnifiedSwapFundingDenial.staleSourceBalance,
    );
  }
  final reserve = _trySmallestUnitAmount(gasReserve);
  if (reserve == null) {
    return const _PreparedFunding(
      denial: UnifiedSwapFundingDenial.invalidGasReserve,
    );
  }
  final validGasIdentity =
      nativeGasAsset.isValidEvmV1 &&
      nativeGasAsset.kind == UnifiedSwapAssetKind.native &&
      nativeGasAsset.chainFamily == source.chainFamily &&
      nativeGasAsset.chainId == source.chainId;
  if (!validGasIdentity ||
      (source.kind == UnifiedSwapAssetKind.native &&
          !source.sameIdentity(nativeGasAsset))) {
    return const _PreparedFunding(
      denial: UnifiedSwapFundingDenial.invalidGasAssetIdentity,
    );
  }

  final exactSourceBalance = BigInt.parse(sourceBalance.amount);
  if (source.kind == UnifiedSwapAssetKind.native) {
    return _PreparedFunding(
      sourceBalance: exactSourceBalance,
      gasBalance: exactSourceBalance,
      gasReserve: reserve,
    );
  }
  if (nativeGasBalance == null) {
    return const _PreparedFunding(
      denial: UnifiedSwapFundingDenial.missingGasBalance,
    );
  }
  if (!nativeGasBalance.asset.sameIdentity(nativeGasAsset)) {
    return const _PreparedFunding(
      denial: UnifiedSwapFundingDenial.gasBalanceIdentityMismatch,
    );
  }
  if (!nativeGasBalance.isFreshAt(now)) {
    return const _PreparedFunding(
      denial: UnifiedSwapFundingDenial.staleGasBalance,
    );
  }
  return _PreparedFunding(
    sourceBalance: exactSourceBalance,
    gasBalance: BigInt.parse(nativeGasBalance.amount),
    gasReserve: reserve,
  );
}

String _smallestUnitAmount(String value) {
  final parsed = _trySmallestUnitAmount(value);
  if (parsed == null) {
    throw ArgumentError.value(
      value,
      'amount',
      'must be a canonical unsigned integer',
    );
  }
  return parsed.toString();
}

BigInt? _trySmallestUnitAmount(String value) {
  if (!RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(value)) return null;
  return BigInt.tryParse(value);
}
