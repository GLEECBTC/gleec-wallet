import 'package:equatable/equatable.dart';

enum GnosisCardMode { disabled, mock, live }

enum GnosisOnboardingStage {
  signedOut,
  terms,
  registration,
  phoneAndSourceOfFunds,
  kycPending,
  safeDeployment,
  cardIssuance,
  ready,
}

enum GnosisKycStatus { notStarted, pending, approved, rejected, expired }

enum SafeDeploymentStatus { accepted, processing, ok, failed }

enum GnosisCardKind { virtual, physical }

enum GnosisCardStatus { ordered, active, frozen, lost, stolen, voided }

enum PhysicalCardOrderStatus { quoted, paid, printing, shipped, delivered }

enum DelayedOperationKind { withdrawal, dailyLimit }

enum DelayedOperationStatus {
  queued,
  coolingDown,
  executable,
  executed,
  failed,
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

class SafeDeployment extends Equatable {
  const SafeDeployment({
    required this.requestId,
    required this.status,
    this.safeAddress,
    this.delayModule,
    this.failureReason,
  });

  final String requestId;
  final SafeDeploymentStatus status;
  final String? safeAddress;
  final String? delayModule;
  final String? failureReason;

  SafeDeployment copyWith({
    SafeDeploymentStatus? status,
    String? safeAddress,
    String? delayModule,
    String? failureReason,
  }) => SafeDeployment(
    requestId: requestId,
    status: status ?? this.status,
    safeAddress: safeAddress ?? this.safeAddress,
    delayModule: delayModule ?? this.delayModule,
    failureReason: failureReason ?? this.failureReason,
  );

  @override
  List<Object?> get props => [
    requestId,
    status,
    safeAddress,
    delayModule,
    failureReason,
  ];
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
    required this.status,
    required this.feeMinor,
    required this.currency,
    this.trackingHint,
  });

  final String id;
  final PhysicalCardOrderStatus status;
  final int feeMinor;
  final String currency;
  final String? trackingHint;

  @override
  List<Object?> get props => [id, status, feeMinor, currency, trackingHint];
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
