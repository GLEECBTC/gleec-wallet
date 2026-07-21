import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:equatable/equatable.dart';

part 'gnosis_card_identity_models.dart';
part 'gnosis_card_order_models.dart';
part 'gnosis_card_onboarding_models.dart';
part 'gnosis_card_dashboard_models.dart';

enum GnosisCardMode { disabled, mock, live }

/// A presentation destination derived from [GnosisOnboardingProgress].
///
/// It is deliberately not persisted or advanced ordinally. A refreshed API
/// progress response can therefore skip any already-completed destination.
enum GnosisOnboardingStage {
  signedOut,
  signupAndTerms,
  kyc,
  sourceOfFunds,
  phoneNumber,
  phoneOtp,
  safeDeployment,
  cardSelection,
  virtualCardIssuance,
  physicalShipping,
  physicalOrderReview,
  physicalPayment,
  physicalCardCreation,
  physicalPin,
  ready,
}

enum GnosisOnboardingMilestone { account, identity, cardAccount, card }

/// User-facing phases for automatic card preparation.
enum GnosisCardAutomationPhase {
  idle,
  preparingWallet,
  awaitingSignature,
  authenticating,
  checkingAccount,
  preparingCardAccount,
  ready,
  paused,
}

enum GnosisCardIntervention {
  walletApproval,
  walletUnavailable,
  retry,
  contactSupport,
}

/// Values returned by the Gnosis Pay user endpoint.
enum GnosisKycStatus {
  notStarted,
  documentsRequested,
  pending,
  processing,
  approved,
  resubmissionRequested,
  rejected,
  requiresAction,
}

enum SafeDeploymentStatus { accepted, processing, ok, failed, timedOut }

enum GnosisSafeMigrationStatus { pending, inProgress, completed, failed }

/// Mirrors Account Kit's `AccountIntegrityStatus` numeric values.
enum SafeAccountIntegrity {
  ok(0),
  safeNotDeployed(1),
  safeMisconfigured(2),
  rolesNotDeployed(3),
  rolesMisconfigured(4),
  delayNotDeployed(5),
  delayMisconfigured(6),
  delayQueueNotEmpty(7),
  unexpectedError(8);

  const SafeAccountIntegrity(this.code);

  final int code;

  bool get isValid => this == ok || this == delayQueueNotEmpty;
}

enum GnosisCardKind { virtual, physical }

enum GnosisCardStatus { ordered, shipped, active, frozen, lost, stolen, voided }

/// API-shaped physical card order states.
enum PhysicalCardOrderStatus {
  pendingTransaction,
  transactionComplete,
  confirmationRequired,
  ready,
  cardCreated,
  failedTransaction,
  cancelled,
}

enum GnosisExternalFlowKind { terms, kyc, support }

enum DelayedOperationKind { withdrawal, dailyLimit }

enum DelayedOperationStatus {
  queued,
  coolingDown,
  executable,
  executed,
  failed,
}

enum GnosisCardFailureCode {
  offline,
  rateLimited,
  serviceUnavailable,
  walletLocked,
  wrongChain,
  activationFailed,
  migrationFailed,
  sessionExpired,
  invalidInput,
  invalidOtp,
  resendCooldown,
  kycResubmissionRequired,
  kycRejected,
  kycRequiresAction,
  deploymentFailed,
  deploymentTimedOut,
  safeIntegrityFailed,
  paymentFailed,
  issuanceFailed,
  invalidTransition,
  notFound,
  unavailable,
}

enum GnosisCardRecovery {
  retry,
  reauthenticate,
  editInput,
  reopenKyc,
  cancelOrder,
  contactSupport,
  none,
}

class GnosisCardFailure extends Equatable implements Exception {
  const GnosisCardFailure({
    required this.code,
    required this.message,
    required this.recovery,
    this.isRecoverable = true,
  });

  final GnosisCardFailureCode code;
  final String message;
  final GnosisCardRecovery recovery;
  final bool isRecoverable;

  @override
  List<Object?> get props => [code, message, recovery, isRecoverable];

  @override
  String toString() => message;
}

/// Backwards-compatible generic boundary failure.
class GnosisCardUnavailable extends GnosisCardFailure {
  const GnosisCardUnavailable(String message)
    : super(
        code: GnosisCardFailureCode.unavailable,
        message: message,
        recovery: GnosisCardRecovery.retry,
      );
}

class GnosisCardSession extends Equatable {
  const GnosisCardSession({
    required this.ownerAddress,
    required this.expiresAt,
  });

  final String ownerAddress;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  bool isUsableFor(
    String ownerAddress, {
    Duration expirySkew = const Duration(seconds: 60),
  }) =>
      this.ownerAddress.toLowerCase() == ownerAddress.toLowerCase() &&
      DateTime.now().add(expirySkew).isBefore(expiresAt);

  @override
  List<Object?> get props => [ownerAddress, expiresAt];
}

/// Exact EIP-4361 challenge returned by the provider boundary.
class GnosisSiweChallenge extends Equatable {
  const GnosisSiweChallenge({
    required this.message,
    required this.ownerAddress,
    required this.domain,
    required this.uri,
    required this.nonce,
    required this.chainId,
    required this.issuedAt,
    required this.expiresAt,
  });

  final String message;
  final String ownerAddress;
  final String domain;
  final Uri uri;
  final String nonce;
  final int chainId;
  final DateTime issuedAt;
  final DateTime expiresAt;

  bool get isExpired => !DateTime.now().isBefore(expiresAt);
  String get approvalId => sha256.convert(utf8.encode(message)).toString();

  @override
  bool get stringify => false;

  @override
  List<Object?> get props => [
    approvalId,
    ownerAddress,
    domain,
    uri,
    nonce,
    chainId,
    issuedAt,
    expiresAt,
  ];
}
