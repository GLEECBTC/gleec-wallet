part of 'gnosis_card_models.dart';

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
    this.isActivatable = false,
    this.controls = const GnosisCardControls(
      contactless: true,
      online: true,
      atm: false,
    ),
  });

  final String id;
  final GnosisCardKind kind;
  final GnosisCardStatus status;
  final String lastFour;
  final String label;
  final bool isActivatable;
  final GnosisCardControls controls;

  GnosisPaymentCard copyWith({
    GnosisCardStatus? status,
    bool? isActivatable,
    GnosisCardControls? controls,
  }) => GnosisPaymentCard(
    id: id,
    kind: kind,
    status: status ?? this.status,
    lastFour: lastFour,
    label: label,
    isActivatable: isActivatable ?? this.isActivatable,
    controls: controls ?? this.controls,
  );

  @override
  List<Object?> get props => [
    id,
    kind,
    status,
    lastFour,
    label,
    isActivatable,
    controls,
  ];
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
