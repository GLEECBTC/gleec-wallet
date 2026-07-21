import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:web_dex/features/unified_swap/domain/route_execution_models.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_capability_policy.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_quote_models.dart';

/// Revalidates a prepared Review at the last reversible boundary before init.
///
/// Implementations must never initialize a route. A quiet result carries a
/// freshly prepared, one-shot authority which the execution repository may
/// consume exactly once; every other result is non-executing.
abstract interface class RouteExecutionAcceptanceCoordinator {
  Future<RouteExecutionAcceptanceResult> revalidate(
    RouteExecutionReview consentedReview,
  );
}

/// Optional lifecycle companion for coordinators that retain refresh-only
/// authority alongside an execution repository's one-shot consent.
///
/// The BLoC invokes this only once init has succeeded or its outcome is
/// uncertain. Deterministic pre-init failures deliberately leave the review
/// available for another attempt.
abstract interface class RouteExecutionAcceptanceLifecycle {
  void retireConsumedReview(RouteExecutionReview review);
}

/// Two-phase replacement boundary used by the BLoC to validate a proposed
/// Review before any registered or verified execution authority is replaced.
abstract interface class RouteExecutionAcceptanceTransactionCoordinator {
  RouteExecutionReview commitReplacement({
    required String transactionId,
    required RouteExecutionReview expectedReview,
    required RouteExecutionReview proposedReview,
  });

  void abandonReplacement(String transactionId);
}

sealed class RouteExecutionAcceptanceResult extends Equatable {
  const RouteExecutionAcceptanceResult();

  @override
  List<Object?> get props => const [];
}

/// The final prepared economics remain within the customer's prior consent.
@immutable
final class RouteExecutionAcceptanceQuiet
    extends RouteExecutionAcceptanceResult {
  const RouteExecutionAcceptanceQuiet(this.review, {this.transactionId = ''});

  final RouteExecutionReview review;
  final String transactionId;

  @override
  List<Object?> get props => [review, transactionId];
}

/// Route structure is unchanged, but the final economics require new consent.
@immutable
final class RouteExecutionAcceptanceMaterialChange
    extends RouteExecutionAcceptanceResult {
  const RouteExecutionAcceptanceMaterialChange({
    required this.consentedReview,
    required this.replacementReview,
    this.transactionId = '',
  });

  final RouteExecutionReview consentedReview;
  final RouteExecutionReview replacementReview;
  final String transactionId;

  @override
  List<Object?> get props => [
    consentedReview,
    replacementReview,
    transactionId,
  ];
}

/// No unique equivalent route remains. The fresh evaluation is display-only
/// until the customer chooses and reviews one of its candidates.
@immutable
final class RouteExecutionAcceptanceFreshQuote
    extends RouteExecutionAcceptanceResult {
  const RouteExecutionAcceptanceFreshQuote({
    required this.intent,
    required this.evaluation,
  });

  final UnifiedSwapIntent intent;
  final UnifiedSwapQuoteEvaluation evaluation;

  @override
  List<Object?> get props => [intent, evaluation];
}

/// Latest terms could not be established. The original Review remains
/// unconsumed so the customer may retry while it is still valid.
@immutable
final class RouteExecutionAcceptanceUnavailable
    extends RouteExecutionAcceptanceResult {
  const RouteExecutionAcceptanceUnavailable(this.failure);

  final RouteExecutionFailure failure;

  @override
  List<Object?> get props => [failure];
}

/// Validates the invariants that a refreshed Review is not allowed to alter.
///
/// V1 source authority is EVM-only. EVM addresses are compared using their
/// exact 20-byte hexadecimal representation and normalized only after both
/// values pass that grammar. Non-EVM recipient identities remain exact and
/// case-sensitive.
bool isValidRouteExecutionReplacement({
  required RouteExecutionReview consented,
  required RouteExecutionReview replacement,
  required DateTime now,
}) =>
    replacement.walletId == consented.walletId &&
    replacement.routeExecutionId == consented.routeExecutionId &&
    replacement.isExecutable &&
    !replacement.isExpiredAt(now) &&
    replacement.source.sameIdentity(consented.source) &&
    replacement.destination.sameIdentity(consented.destination) &&
    replacement.sourceAmount == consented.sourceAmount &&
    replacement.sourceSelectorKind == consented.sourceSelectorKind &&
    consented.source.isValidEvmV1 &&
    replacement.source.isValidEvmV1 &&
    _sameExactEvmAddress(
      replacement.resolvedSourceAddress,
      consented.resolvedSourceAddress,
    ) &&
    _sameRecipient(
      consented.destination,
      replacement.recipient,
      consented.recipient,
    ) &&
    replacement.externalRecipientConfirmed ==
        consented.externalRecipientConfirmed &&
    replacement.steps.length == consented.steps.length &&
    replacement.steps.indexed.every((entry) {
      final oldStep = consented.steps[entry.$1];
      final newStep = entry.$2;
      return newStep.sequence == oldStep.sequence &&
          newStep.kind == oldStep.kind &&
          newStep.source.sameIdentity(oldStep.source) &&
          newStep.destination.sameIdentity(oldStep.destination);
    });

bool _sameRecipient(UnifiedSwapAssetIdentity asset, String left, String right) {
  if (asset.chainFamily == UnifiedSwapChainFamily.evm) {
    return asset.isValidEvmV1 && _sameExactEvmAddress(left, right);
  }
  return left == right;
}

bool _sameExactEvmAddress(String left, String right) =>
    _isExactEvmAddress(left) &&
    _isExactEvmAddress(right) &&
    left.toLowerCase() == right.toLowerCase();

bool _isExactEvmAddress(String value) =>
    RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(value);
