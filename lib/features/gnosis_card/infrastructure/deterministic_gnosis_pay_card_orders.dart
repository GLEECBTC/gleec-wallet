part of 'deterministic_gnosis_pay_repository.dart';

mixin _DeterministicGnosisPayCardOrders
    on _DeterministicGnosisPayRepositoryState, _DeterministicGnosisPaySupport {
  Future<List<GnosisCardProduct>> cardProducts() async {
    _requireSession();
    _requireSafeReady();
    return List.unmodifiable(_products);
  }

  Future<void> selectCardProduct({required String productId}) async {
    _requireSession();
    _requireSafeReady();
    final product = _products
        .where((value) => value.id == productId)
        .firstOrNull;
    if (product == null) {
      throw _invalidInput('The selected card is unavailable.');
    }
    _selectedProduct = product;
    if (product.kind == GnosisCardKind.physical) {
      _physicalOrder = null;
      _isPhysicalOrderReviewed = false;
      _paymentReceipt = null;
      _provisioningHandle = null;
      _isPinProvisioned = false;
    }
  }

  Future<void> clearCardProductSelection() async {
    _selectedProduct = null;
  }

  Future<GnosisPaymentCard> issueVirtualCard({
    required String productId,
  }) async {
    _requireSession();
    _requireSelectedProduct(productId, GnosisCardKind.virtual);
    if (scenario == GnosisCardScenario.issuanceFailure &&
        !_issuanceFailureConsumed) {
      _issuanceFailureConsumed = true;
      throw _issuanceFailure();
    }
    final existing = _dashboard.cards
        .where((card) => card.kind == GnosisCardKind.virtual)
        .firstOrNull;
    if (existing != null) return existing;
    final card = GnosisPaymentCard(
      id: 'card-virtual-0001',
      kind: GnosisCardKind.virtual,
      status: _scenarioCardStatusFor(GnosisCardKind.virtual),
      lastFour: '4242',
      label: 'Everyday card',
      isActivatable: false,
    );
    _dashboard = _dashboard.copyWith(cards: [..._dashboard.cards, card]);
    try {
      await _refreshAfterIssuance();
    } catch (_) {
      rethrow;
    }
    return card;
  }

  Future<PhysicalCardOrder> createPhysicalCardOrder({
    required String productId,
    required ShippingAddress shippingAddress,
  }) async {
    _requireSession();
    _requireSelectedProduct(productId, GnosisCardKind.physical);
    if (shippingAddress.country.toUpperCase() != _verifiedCountry) {
      throw _invalidInput(
        'Physical cards can only be shipped to the verified country.',
      );
    }
    if ([
      shippingAddress.recipientName,
      shippingAddress.address1,
      shippingAddress.city,
      shippingAddress.postalCode,
    ].any((value) => value.trim().isEmpty)) {
      throw _invalidInput('Complete the required shipping address fields.');
    }
    final current = _physicalOrder;
    if (current != null &&
        current.status != PhysicalCardOrderStatus.cancelled) {
      return current;
    }
    _isPhysicalOrderReviewed = false;
    _paymentReceipt = null;
    _provisioningHandle = null;
    _isPinProvisioned = false;
    return _physicalOrder = PhysicalCardOrder(
      id: 'order-physical-0001',
      createdAt: DateTime.now().toUtc(),
      status: PhysicalCardOrderStatus.pendingTransaction,
      totalAmountMinor: 999,
      totalDiscountMinor: 0,
      currency: 'EUR',
      embossedName: shippingAddress.recipientName,
      shippingAddress: shippingAddress,
    );
  }

  Future<void> markPhysicalCardOrderReviewed({required String orderId}) async {
    _requireSession();
    final order = _requireOrder(orderId);
    if (order.status != PhysicalCardOrderStatus.pendingTransaction) {
      throw _invalidTransition('This order can no longer be reviewed.');
    }
    _isPhysicalOrderReviewed = true;
  }

  Future<CardOrderPaymentQuote> physicalCardPaymentQuote({
    required String orderId,
  }) async {
    _requireSession();
    final order = _requireOrder(orderId);
    if (!_isPhysicalOrderReviewed) {
      throw _invalidTransition('Review the physical-card order first.');
    }
    return CardOrderPaymentQuote(
      orderId: order.id,
      amountMinor: order.feeMinor,
      currency: order.currency,
      assetSymbol: 'EURe',
      assetContract: _fixtureEure,
      recipient: '0x4444444444444444444444444444444444444444',
      isSimulated: true,
    );
  }

  Future<PhysicalCardOrder> attachPhysicalCardPayment({
    required String orderId,
    required CardOrderPaymentReceipt receipt,
  }) async {
    _requireSession();
    final order = _requireOrder(orderId);
    if (scenario == GnosisCardScenario.paymentFailure &&
        !_paymentFailureConsumed) {
      _paymentFailureConsumed = true;
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.paymentFailed,
        message: 'The simulated payment failed. Your order is preserved.',
        recovery: GnosisCardRecovery.retry,
      );
    }
    if (!receipt.isSimulated ||
        receipt.orderId != order.id ||
        receipt.amountMinor != order.feeMinor ||
        receipt.currency != order.currency) {
      throw _invalidInput('The synthetic payment receipt is invalid.');
    }
    _paymentReceipt = receipt;
    return _physicalOrder = order.copyWith(
      transactionHash: receipt.transactionHash,
    );
  }

  Future<PhysicalCardOrder> confirmPhysicalCardPayment({
    required String orderId,
  }) async {
    _requireSession();
    final order = _requireOrder(orderId);
    if (_paymentReceipt == null ||
        !const {
          PhysicalCardOrderStatus.pendingTransaction,
          PhysicalCardOrderStatus.transactionComplete,
          PhysicalCardOrderStatus.confirmationRequired,
        }.contains(order.status)) {
      throw _invalidTransition(
        'Attach the simulated payment before confirming it.',
      );
    }
    return _physicalOrder = order.copyWith(
      status: PhysicalCardOrderStatus.ready,
    );
  }

  Future<CardProvisioningHandle> createPhysicalCard({
    required String orderId,
  }) async {
    _requireSession();
    final order = _requireOrder(orderId);
    if (order.status != PhysicalCardOrderStatus.ready) {
      throw _invalidTransition('Confirm payment before creating the card.');
    }
    if (scenario == GnosisCardScenario.issuanceFailure &&
        !_issuanceFailureConsumed) {
      _issuanceFailureConsumed = true;
      throw _issuanceFailure();
    }
    final card = GnosisPaymentCard(
      id: 'card-physical-0001',
      kind: GnosisCardKind.physical,
      status: _scenarioCardStatusFor(GnosisCardKind.physical),
      lastFour: '8810',
      label: 'Physical card',
      isActivatable: scenario == GnosisCardScenario.cardActivatable,
    );
    if (!_dashboard.cards.any((value) => value.id == card.id)) {
      _dashboard = _dashboard.copyWith(cards: [..._dashboard.cards, card]);
    }
    _physicalOrder = order.copyWith(
      status: PhysicalCardOrderStatus.cardCreated,
    );
    return _provisioningHandle = const CardProvisioningHandle(
      orderId: 'order-physical-0001',
      cardId: 'card-physical-0001',
      value: 'opaque-pse-session-0001',
    );
  }

  Future<void> completePhysicalCardPin({
    required String orderId,
    required String cardId,
  }) async {
    _requireSession();
    final handle = _provisioningHandle;
    if (handle == null ||
        handle.orderId != orderId ||
        handle.cardId != cardId) {
      throw _invalidTransition('The secure PIN setup session is unavailable.');
    }
    _isPinProvisioned = true;
    _provisioningHandle = null;
  }

  Future<PhysicalCardOrder> cancelPhysicalCardOrder({
    required String orderId,
  }) async {
    _requireSession();
    final order = _requireOrder(orderId);
    if (!order.isCancellable) {
      throw _invalidTransition('This physical-card order cannot be cancelled.');
    }
    return _physicalOrder = order.copyWith(
      status: PhysicalCardOrderStatus.cancelled,
    );
  }
}
