part of 'gnosis_card_models.dart';

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
    required this.operationKey,
    required this.kind,
    required this.status,
    required this.summary,
    required this.executableAt,
  });

  final String id;
  final String operationKey;
  final DelayedOperationKind kind;
  final DelayedOperationStatus status;
  final String summary;
  final DateTime executableAt;

  DelayedOperation copyWith({DelayedOperationStatus? status}) =>
      DelayedOperation(
        id: id,
        operationKey: operationKey,
        kind: kind,
        status: status ?? this.status,
        summary: summary,
        executableAt: executableAt,
      );

  @override
  List<Object?> get props => [
    id,
    operationKey,
    kind,
    status,
    summary,
    executableAt,
  ];
}

class GnosisCardAsset extends Equatable {
  const GnosisCardAsset({
    required this.symbol,
    required this.contractAddress,
    required this.decimals,
    required this.chainId,
  });

  final String symbol;
  final String contractAddress;
  final int decimals;
  final int chainId;

  @override
  List<Object?> get props => [symbol, contractAddress, decimals, chainId];
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
    this.pendingBalanceMinor = 0,
    this.withdrawalAssets = const [],
    this.dailyLimitTarget,
    this.dailyLimitAsset,
    this.physicalOrder,
  });

  final int balanceMinor;
  final int pendingBalanceMinor;
  final String currency;
  final int dailyLimitMinor;
  final List<GnosisPaymentCard> cards;
  final GnosisCardControls controls;
  final List<GnosisCardTransaction> transactions;
  final List<DelayedOperation> operations;
  final List<GnosisCardAsset> withdrawalAssets;
  final String? dailyLimitTarget;
  final GnosisCardAsset? dailyLimitAsset;
  final PhysicalCardOrder? physicalOrder;

  GnosisCardDashboard copyWith({
    int? balanceMinor,
    int? pendingBalanceMinor,
    int? dailyLimitMinor,
    List<GnosisPaymentCard>? cards,
    GnosisCardControls? controls,
    List<DelayedOperation>? operations,
    List<GnosisCardAsset>? withdrawalAssets,
    String? dailyLimitTarget,
    GnosisCardAsset? dailyLimitAsset,
    PhysicalCardOrder? physicalOrder,
  }) => GnosisCardDashboard(
    balanceMinor: balanceMinor ?? this.balanceMinor,
    pendingBalanceMinor: pendingBalanceMinor ?? this.pendingBalanceMinor,
    currency: currency,
    dailyLimitMinor: dailyLimitMinor ?? this.dailyLimitMinor,
    cards: cards ?? this.cards,
    controls: controls ?? this.controls,
    transactions: transactions,
    operations: operations ?? this.operations,
    withdrawalAssets: withdrawalAssets ?? this.withdrawalAssets,
    dailyLimitTarget: dailyLimitTarget ?? this.dailyLimitTarget,
    dailyLimitAsset: dailyLimitAsset ?? this.dailyLimitAsset,
    physicalOrder: physicalOrder ?? this.physicalOrder,
  );

  @override
  List<Object?> get props => [
    balanceMinor,
    pendingBalanceMinor,
    currency,
    dailyLimitMinor,
    cards,
    controls,
    transactions,
    operations,
    withdrawalAssets,
    dailyLimitTarget,
    dailyLimitAsset,
    physicalOrder,
  ];
}

class GnosisIntentReviewMetadata extends Equatable {
  const GnosisIntentReviewMetadata({
    required this.symbol,
    required this.decimals,
    this.feeMinor,
    this.feeCurrency,
  });

  final String symbol;
  final int decimals;
  final int? feeMinor;
  final String? feeCurrency;

  @override
  List<Object?> get props => [symbol, decimals, feeMinor, feeCurrency];
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
