import 'package:equatable/equatable.dart';

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

enum GnosisCardStatus { ordered, active, frozen, lost, stolen, voided }

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
  resetSafe,
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

  @override
  List<Object?> get props => [ownerAddress, expiresAt];
}

class GnosisTerm extends Equatable {
  const GnosisTerm({
    required this.id,
    required this.title,
    required this.version,
    required this.documentUrl,
    required this.isAccepted,
  });

  final String id;
  final String title;
  final String version;
  final String documentUrl;
  final bool isAccepted;

  GnosisTerm copyWith({bool? isAccepted}) => GnosisTerm(
    id: id,
    title: title,
    version: version,
    documentUrl: documentUrl,
    isAccepted: isAccepted ?? this.isAccepted,
  );

  @override
  List<Object?> get props => [id, title, version, documentUrl, isAccepted];
}

class GnosisTermAcceptance extends Equatable {
  const GnosisTermAcceptance({required this.id, required this.version});

  final String id;
  final String version;

  @override
  List<Object?> get props => [id, version];
}

class GnosisExternalFlow extends Equatable {
  const GnosisExternalFlow({
    required this.id,
    required this.kind,
    required this.url,
  });

  final String id;
  final GnosisExternalFlowKind kind;
  final String url;

  @override
  List<Object?> get props => [id, kind, url];
}

class SourceOfFundsQuestion extends Equatable {
  const SourceOfFundsQuestion({
    required this.id,
    required this.title,
    required this.answers,
  });

  final String id;
  final String title;
  final List<String> answers;

  @override
  List<Object?> get props => [id, title, answers];
}

class SourceOfFundsAnswer extends Equatable {
  const SourceOfFundsAnswer({
    required this.questionId,
    required this.question,
    required this.answer,
  });

  final String questionId;
  final String question;
  final String answer;

  @override
  List<Object?> get props => [questionId, question, answer];
}

class PhoneOtpChallenge extends Equatable {
  const PhoneOtpChallenge({
    required this.id,
    required this.phoneNumber,
    required this.expiresAt,
    required this.resendAvailableAt,
    required this.attemptsRemaining,
    this.demoCode,
  });

  final String id;
  final String phoneNumber;
  final DateTime expiresAt;
  final DateTime resendAvailableAt;
  final int attemptsRemaining;

  /// Populated only by the explicit deterministic mock adapter.
  final String? demoCode;

  bool get canResend => !DateTime.now().isBefore(resendAvailableAt);

  PhoneOtpChallenge copyWith({
    DateTime? expiresAt,
    DateTime? resendAvailableAt,
    int? attemptsRemaining,
  }) => PhoneOtpChallenge(
    id: id,
    phoneNumber: phoneNumber,
    expiresAt: expiresAt ?? this.expiresAt,
    resendAvailableAt: resendAvailableAt ?? this.resendAvailableAt,
    attemptsRemaining: attemptsRemaining ?? this.attemptsRemaining,
    demoCode: demoCode,
  );

  @override
  List<Object?> get props => [
    id,
    phoneNumber,
    expiresAt,
    resendAvailableAt,
    attemptsRemaining,
    demoCode,
  ];
}

class SafeDeployment extends Equatable {
  const SafeDeployment({
    required this.requestId,
    required this.ownerAddress,
    required this.status,
    required this.updatedAt,
    this.failureReason,
  });

  final String requestId;
  final String ownerAddress;
  final SafeDeploymentStatus status;
  final DateTime updatedAt;
  final String? failureReason;

  SafeDeployment copyWith({
    SafeDeploymentStatus? status,
    DateTime? updatedAt,
    String? failureReason,
    bool clearFailureReason = false,
  }) => SafeDeployment(
    requestId: requestId,
    ownerAddress: ownerAddress,
    status: status ?? this.status,
    updatedAt: updatedAt ?? this.updatedAt,
    failureReason: clearFailureReason
        ? null
        : failureReason ?? this.failureReason,
  );

  @override
  List<Object?> get props => [
    requestId,
    ownerAddress,
    status,
    updatedAt,
    failureReason,
  ];
}

class SafeConfiguration extends Equatable {
  const SafeConfiguration({
    required this.ownerAddress,
    required this.isDeployed,
    required this.integrity,
    required this.safeAddress,
    required this.delayModule,
    required this.tokenSymbol,
    required this.fiatSymbol,
  });

  final String ownerAddress;
  final bool isDeployed;
  final SafeAccountIntegrity integrity;
  final String? safeAddress;
  final String? delayModule;
  final String? tokenSymbol;
  final String? fiatSymbol;

  bool get isValid =>
      isDeployed &&
      integrity.isValid &&
      safeAddress != null &&
      delayModule != null;

  @override
  List<Object?> get props => [
    ownerAddress,
    isDeployed,
    integrity,
    safeAddress,
    delayModule,
    tokenSymbol,
    fiatSymbol,
  ];
}

class GnosisCardProduct extends Equatable {
  const GnosisCardProduct({
    required this.id,
    required this.kind,
    required this.title,
    required this.description,
    required this.feeMinor,
    required this.currency,
    required this.requiresShipping,
    required this.requiresPin,
  });

  final String id;
  final GnosisCardKind kind;
  final String title;
  final String description;
  final int feeMinor;
  final String currency;
  final bool requiresShipping;
  final bool requiresPin;

  @override
  List<Object?> get props => [
    id,
    kind,
    title,
    description,
    feeMinor,
    currency,
    requiresShipping,
    requiresPin,
  ];
}

class ShippingAddress extends Equatable {
  const ShippingAddress({
    required this.recipientName,
    required this.address1,
    required this.city,
    required this.postalCode,
    required this.country,
    this.address2,
    this.state,
  });

  final String recipientName;
  final String address1;
  final String? address2;
  final String city;
  final String? state;
  final String postalCode;
  final String country;

  @override
  List<Object?> get props => [
    recipientName,
    address1,
    address2,
    city,
    state,
    postalCode,
    country,
  ];
}

class CardOrderPaymentQuote extends Equatable {
  const CardOrderPaymentQuote({
    required this.orderId,
    required this.amountMinor,
    required this.currency,
    required this.assetSymbol,
    required this.assetContract,
    required this.recipient,
    required this.isSimulated,
  });

  final String orderId;
  final int amountMinor;
  final String currency;
  final String assetSymbol;
  final String assetContract;
  final String recipient;
  final bool isSimulated;

  @override
  List<Object?> get props => [
    orderId,
    amountMinor,
    currency,
    assetSymbol,
    assetContract,
    recipient,
    isSimulated,
  ];
}

class CardOrderPaymentReceipt extends Equatable {
  const CardOrderPaymentReceipt({
    required this.orderId,
    required this.transactionHash,
    required this.amountMinor,
    required this.currency,
    required this.paidAt,
    required this.isSimulated,
  });

  final String orderId;
  final String transactionHash;
  final int amountMinor;
  final String currency;
  final DateTime paidAt;
  final bool isSimulated;

  @override
  List<Object?> get props => [
    orderId,
    transactionHash,
    amountMinor,
    currency,
    paidAt,
    isSimulated,
  ];
}

/// Opaque PSE capability. It contains no PAN, CVV, or PIN.
class CardProvisioningHandle extends Equatable {
  const CardProvisioningHandle({
    required this.orderId,
    required this.cardId,
    required this.value,
  });

  final String orderId;
  final String cardId;
  final String value;

  @override
  List<Object?> get props => [orderId, cardId, value];

  @override
  String toString() => 'CardProvisioningHandle(<redacted>)';
}

class GnosisPaymentCard extends Equatable {
  const GnosisPaymentCard({
    required this.id,
    required this.kind,
    required this.status,
    required this.lastFour,
    required this.label,
  });

  final String id;
  final GnosisCardKind kind;
  final GnosisCardStatus status;
  final String lastFour;
  final String label;

  GnosisPaymentCard copyWith({GnosisCardStatus? status}) => GnosisPaymentCard(
    id: id,
    kind: kind,
    status: status ?? this.status,
    lastFour: lastFour,
    label: label,
  );

  @override
  List<Object?> get props => [id, kind, status, lastFour, label];
}

class PhysicalCardOrder extends Equatable {
  const PhysicalCardOrder({
    required this.id,
    required this.createdAt,
    required this.status,
    required this.totalAmountMinor,
    required this.totalDiscountMinor,
    required this.currency,
    required this.embossedName,
    required this.shippingAddress,
    this.transactionHash,
    this.trackingHint,
  });

  final String id;
  final DateTime createdAt;
  final PhysicalCardOrderStatus status;
  final int totalAmountMinor;
  final int totalDiscountMinor;
  final String currency;
  final String embossedName;
  final ShippingAddress shippingAddress;
  final String? transactionHash;
  final String? trackingHint;

  bool get isFree => totalAmountMinor == totalDiscountMinor;

  bool get isCancellable => switch (status) {
    PhysicalCardOrderStatus.pendingTransaction ||
    PhysicalCardOrderStatus.transactionComplete ||
    PhysicalCardOrderStatus.confirmationRequired ||
    PhysicalCardOrderStatus.failedTransaction => true,
    _ => false,
  };

  /// Compatibility alias for dashboard consumers that display one fee.
  int get feeMinor => totalAmountMinor - totalDiscountMinor;

  PhysicalCardOrder copyWith({
    PhysicalCardOrderStatus? status,
    String? transactionHash,
    String? trackingHint,
    bool clearTransactionHash = false,
  }) => PhysicalCardOrder(
    id: id,
    createdAt: createdAt,
    status: status ?? this.status,
    totalAmountMinor: totalAmountMinor,
    totalDiscountMinor: totalDiscountMinor,
    currency: currency,
    embossedName: embossedName,
    shippingAddress: shippingAddress,
    transactionHash: clearTransactionHash
        ? null
        : transactionHash ?? this.transactionHash,
    trackingHint: trackingHint ?? this.trackingHint,
  );

  @override
  List<Object?> get props => [
    id,
    createdAt,
    status,
    totalAmountMinor,
    totalDiscountMinor,
    currency,
    embossedName,
    shippingAddress,
    transactionHash,
    trackingHint,
  ];
}

class GnosisOnboardingProgress extends Equatable {
  const GnosisOnboardingProgress({
    required this.isAuthenticated,
    required this.isRegistered,
    required this.email,
    required this.countryCode,
    required this.terms,
    required this.kycStatus,
    required this.isSourceOfFundsAnswered,
    required this.phoneNumber,
    required this.isPhoneValidated,
    required this.phoneChallenge,
    required this.safeDeployment,
    required this.safeConfiguration,
    required this.isSafeRegistered,
    required this.selectedProduct,
    required this.physicalOrder,
    required this.isPhysicalOrderReviewed,
    required this.paymentReceipt,
    required this.provisioningHandle,
    required this.isPinProvisioned,
    required this.cards,
  });

  const GnosisOnboardingProgress.initial({
    this.countryCode = 'DE',
    this.terms = const [],
  }) : isAuthenticated = false,
       isRegistered = false,
       email = null,
       kycStatus = GnosisKycStatus.notStarted,
       isSourceOfFundsAnswered = false,
       phoneNumber = null,
       isPhoneValidated = false,
       phoneChallenge = null,
       safeDeployment = null,
       safeConfiguration = null,
       isSafeRegistered = false,
       selectedProduct = null,
       physicalOrder = null,
       isPhysicalOrderReviewed = false,
       paymentReceipt = null,
       provisioningHandle = null,
       isPinProvisioned = false,
       cards = const [];

  final bool isAuthenticated;
  final bool isRegistered;
  final String? email;
  final String countryCode;
  final List<GnosisTerm> terms;
  final GnosisKycStatus kycStatus;
  final bool isSourceOfFundsAnswered;
  final String? phoneNumber;
  final bool isPhoneValidated;
  final PhoneOtpChallenge? phoneChallenge;
  final SafeDeployment? safeDeployment;
  final SafeConfiguration? safeConfiguration;
  final bool isSafeRegistered;
  final GnosisCardProduct? selectedProduct;
  final PhysicalCardOrder? physicalOrder;
  final bool isPhysicalOrderReviewed;
  final CardOrderPaymentReceipt? paymentReceipt;
  final CardProvisioningHandle? provisioningHandle;
  final bool isPinProvisioned;
  final List<GnosisPaymentCard> cards;

  bool get areTermsAccepted =>
      terms.isNotEmpty && terms.every((term) => term.isAccepted);

  bool get isSafeReady =>
      (safeConfiguration?.isValid ?? false) && isSafeRegistered;

  GnosisOnboardingProgress withSafeRegistration(bool value) =>
      GnosisOnboardingProgress(
        isAuthenticated: isAuthenticated,
        isRegistered: isRegistered,
        email: email,
        countryCode: countryCode,
        terms: terms,
        kycStatus: kycStatus,
        isSourceOfFundsAnswered: isSourceOfFundsAnswered,
        phoneNumber: phoneNumber,
        isPhoneValidated: isPhoneValidated,
        phoneChallenge: phoneChallenge,
        safeDeployment: safeDeployment,
        safeConfiguration: safeConfiguration,
        isSafeRegistered: value,
        selectedProduct: selectedProduct,
        physicalOrder: physicalOrder,
        isPhysicalOrderReviewed: isPhysicalOrderReviewed,
        paymentReceipt: paymentReceipt,
        provisioningHandle: provisioningHandle,
        isPinProvisioned: isPinProvisioned,
        cards: cards,
      );

  GnosisOnboardingStage get nextStage {
    if (!isAuthenticated) return GnosisOnboardingStage.signedOut;
    if (!isRegistered || !areTermsAccepted) {
      return GnosisOnboardingStage.signupAndTerms;
    }
    if (kycStatus != GnosisKycStatus.approved) {
      return GnosisOnboardingStage.kyc;
    }
    if (!isSourceOfFundsAnswered) {
      return GnosisOnboardingStage.sourceOfFunds;
    }
    if (!isPhoneValidated) {
      return phoneChallenge == null
          ? GnosisOnboardingStage.phoneNumber
          : GnosisOnboardingStage.phoneOtp;
    }
    if (!isSafeReady) return GnosisOnboardingStage.safeDeployment;
    final physicalFlowInProgress =
        selectedProduct?.kind == GnosisCardKind.physical && !isPinProvisioned;
    if (cards.isNotEmpty &&
        !physicalFlowInProgress &&
        (physicalOrder == null ||
            physicalOrder?.status == PhysicalCardOrderStatus.cancelled ||
            isPinProvisioned)) {
      return GnosisOnboardingStage.ready;
    }
    final product = selectedProduct;
    if (product == null) return GnosisOnboardingStage.cardSelection;
    if (product.kind == GnosisCardKind.virtual) {
      return GnosisOnboardingStage.virtualCardIssuance;
    }
    final order = physicalOrder;
    if (order == null || order.status == PhysicalCardOrderStatus.cancelled) {
      return GnosisOnboardingStage.physicalShipping;
    }
    if (!isPhysicalOrderReviewed &&
        order.status == PhysicalCardOrderStatus.pendingTransaction &&
        paymentReceipt == null &&
        order.transactionHash == null) {
      return GnosisOnboardingStage.physicalOrderReview;
    }
    if (order.status == PhysicalCardOrderStatus.pendingTransaction ||
        order.status == PhysicalCardOrderStatus.transactionComplete ||
        order.status == PhysicalCardOrderStatus.confirmationRequired ||
        order.status == PhysicalCardOrderStatus.failedTransaction) {
      return GnosisOnboardingStage.physicalPayment;
    }
    if (order.status == PhysicalCardOrderStatus.ready &&
        provisioningHandle == null) {
      return GnosisOnboardingStage.physicalCardCreation;
    }
    if (!isPinProvisioned) return GnosisOnboardingStage.physicalPin;
    return GnosisOnboardingStage.ready;
  }

  bool isMilestoneComplete(GnosisOnboardingMilestone milestone) =>
      switch (milestone) {
        GnosisOnboardingMilestone.account =>
          isAuthenticated && isRegistered && areTermsAccepted,
        GnosisOnboardingMilestone.identity =>
          kycStatus == GnosisKycStatus.approved &&
              isSourceOfFundsAnswered &&
              isPhoneValidated,
        GnosisOnboardingMilestone.cardAccount => isSafeReady,
        GnosisOnboardingMilestone.card =>
          cards.isNotEmpty &&
              (cards.every((card) => card.kind != GnosisCardKind.physical) ||
                  isPinProvisioned),
      };

  @override
  List<Object?> get props => [
    isAuthenticated,
    isRegistered,
    email,
    countryCode,
    terms,
    kycStatus,
    isSourceOfFundsAnswered,
    phoneNumber,
    isPhoneValidated,
    phoneChallenge,
    safeDeployment,
    safeConfiguration,
    isSafeRegistered,
    selectedProduct,
    physicalOrder,
    isPhysicalOrderReviewed,
    paymentReceipt,
    provisioningHandle,
    isPinProvisioned,
    cards,
  ];
}

class GnosisCardControls extends Equatable {
  const GnosisCardControls({
    required this.contactless,
    required this.online,
    required this.atm,
  });

  final bool contactless;
  final bool online;
  final bool atm;

  GnosisCardControls copyWith({bool? contactless, bool? online, bool? atm}) =>
      GnosisCardControls(
        contactless: contactless ?? this.contactless,
        online: online ?? this.online,
        atm: atm ?? this.atm,
      );

  @override
  List<Object?> get props => [contactless, online, atm];
}

class GnosisCardTransaction extends Equatable {
  const GnosisCardTransaction({
    required this.id,
    required this.merchant,
    required this.amountMinor,
    required this.currency,
    required this.occurredAt,
    required this.isDeclined,
  });

  final String id;
  final String merchant;
  final int amountMinor;
  final String currency;
  final DateTime occurredAt;
  final bool isDeclined;

  @override
  List<Object?> get props => [
    id,
    merchant,
    amountMinor,
    currency,
    occurredAt,
    isDeclined,
  ];
}

class DelayedOperation extends Equatable {
  const DelayedOperation({
    required this.id,
    required this.kind,
    required this.status,
    required this.summary,
    required this.executableAt,
  });

  final String id;
  final DelayedOperationKind kind;
  final DelayedOperationStatus status;
  final String summary;
  final DateTime executableAt;

  DelayedOperation copyWith({DelayedOperationStatus? status}) =>
      DelayedOperation(
        id: id,
        kind: kind,
        status: status ?? this.status,
        summary: summary,
        executableAt: executableAt,
      );

  @override
  List<Object?> get props => [id, kind, status, summary, executableAt];
}

class GnosisCardDashboard extends Equatable {
  const GnosisCardDashboard({
    required this.balanceMinor,
    required this.currency,
    required this.dailyLimitMinor,
    required this.cards,
    required this.controls,
    required this.transactions,
    required this.operations,
    this.physicalOrder,
  });

  final int balanceMinor;
  final String currency;
  final int dailyLimitMinor;
  final List<GnosisPaymentCard> cards;
  final GnosisCardControls controls;
  final List<GnosisCardTransaction> transactions;
  final List<DelayedOperation> operations;
  final PhysicalCardOrder? physicalOrder;

  GnosisCardDashboard copyWith({
    int? dailyLimitMinor,
    List<GnosisPaymentCard>? cards,
    GnosisCardControls? controls,
    List<DelayedOperation>? operations,
    PhysicalCardOrder? physicalOrder,
  }) => GnosisCardDashboard(
    balanceMinor: balanceMinor,
    currency: currency,
    dailyLimitMinor: dailyLimitMinor ?? this.dailyLimitMinor,
    cards: cards ?? this.cards,
    controls: controls ?? this.controls,
    transactions: transactions,
    operations: operations ?? this.operations,
    physicalOrder: physicalOrder ?? this.physicalOrder,
  );

  @override
  List<Object?> get props => [
    balanceMinor,
    currency,
    dailyLimitMinor,
    cards,
    controls,
    transactions,
    operations,
    physicalOrder,
  ];
}

class WithdrawalRequest extends Equatable {
  const WithdrawalRequest({
    required this.assetContract,
    required this.assetSymbol,
    required this.recipient,
    required this.amountAtomic,
    required this.decimals,
  });

  final String assetContract;
  final String assetSymbol;
  final String recipient;
  final BigInt amountAtomic;
  final int decimals;

  @override
  List<Object?> get props => [
    assetContract,
    assetSymbol,
    recipient,
    amountAtomic,
    decimals,
  ];
}

class DailyLimitRequest extends Equatable {
  const DailyLimitRequest({
    required this.bouncer,
    required this.amountAtomic,
    required this.decimals,
    this.periodSeconds = 86400,
  });

  final String bouncer;
  final BigInt amountAtomic;
  final int decimals;
  final int periodSeconds;

  @override
  List<Object?> get props => [bouncer, amountAtomic, decimals, periodSeconds];
}
