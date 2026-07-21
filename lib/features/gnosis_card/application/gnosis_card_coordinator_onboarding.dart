part of 'gnosis_card_coordinator.dart';

abstract class _GnosisCardCoordinatorOnboarding
    extends _GnosisCardCoordinatorEntry {
  _GnosisCardCoordinatorOnboarding({
    required super.repository,
    required super.signer,
    required super.externalFlowLauncher,
    required super.paymentGateway,
    super.readiness,
  });

  void resetForWalletChange() {
    _walletGeneration += 1;
    readiness.invalidate();
    repository.invalidateSession();
    cancelAutomaticWork();
    _entryFlight = null;
    _approvalFlight = null;
    _snapshot = const GnosisCardSnapshot.initial();
    _registeredSafe = null;
    _registeredSafeOwner = null;
  }

  void cancelAutomaticWork() {
    _automationGeneration += 1;
    _automationFlight = null;
  }

  Future<GnosisCardSnapshot> signUpAndAcceptTerms({
    required String email,
    required List<GnosisTermAcceptance> acceptances,
  }) async {
    final walletGeneration = _walletGeneration;
    if (!_snapshot.progress.isRegistered || _snapshot.progress.email != email) {
      await repository.signUp(email: email);
      if (walletGeneration != _walletGeneration) return _snapshot;
    }
    await repository.acceptTerms(acceptances);
    if (walletGeneration != _walletGeneration) return _snapshot;
    return _refresh();
  }

  Future<GnosisExternalFlow> kycFlow() => repository.kycIntegration();

  Future<GnosisExternalFlow> supportFlow() => repository.supportFlow();

  Future<GnosisCardSnapshot> refreshKyc() async {
    final walletGeneration = _walletGeneration;
    await repository.pollKyc();
    if (walletGeneration != _walletGeneration) return _snapshot;
    return _refresh();
  }

  Future<GnosisCardSnapshot> submitSourceOfFunds(
    List<SourceOfFundsAnswer> answers,
  ) async {
    final walletGeneration = _walletGeneration;
    await repository.submitSourceOfFunds(answers);
    if (walletGeneration != _walletGeneration) return _snapshot;
    return _refresh();
  }

  Future<GnosisCardSnapshot> requestPhoneOtp(String phoneNumber) async {
    final walletGeneration = _walletGeneration;
    await repository.requestPhoneOtp(phoneNumber: phoneNumber);
    if (walletGeneration != _walletGeneration) return _snapshot;
    return _refresh();
  }

  Future<GnosisCardSnapshot> resendPhoneOtp() async {
    final walletGeneration = _walletGeneration;
    await repository.resendPhoneOtp();
    if (walletGeneration != _walletGeneration) return _snapshot;
    return _refresh();
  }

  Future<GnosisCardSnapshot> verifyPhoneOtp(String code) async {
    final walletGeneration = _walletGeneration;
    try {
      await repository.verifyPhoneOtp(code: code);
      if (walletGeneration != _walletGeneration) return _snapshot;
      return _refresh();
    } catch (_) {
      try {
        await _refresh();
      } catch (_) {
        // Preserve the verification failure.
      }
      rethrow;
    }
  }

  Future<GnosisCardSnapshot> editPhoneNumber() async {
    final walletGeneration = _walletGeneration;
    await repository.clearPhoneOtp();
    if (walletGeneration != _walletGeneration) return _snapshot;
    return _refresh();
  }

  Future<GnosisCardSnapshot> deploySafe() async {
    final walletGeneration = _walletGeneration;
    _requireNoActiveMigration();
    final owner = await _ownerAddress();
    if (walletGeneration != _walletGeneration) return _snapshot;
    await repository.requestSafeDeployment(ownerAddress: owner);
    if (walletGeneration != _walletGeneration) return _snapshot;
    return _refresh();
  }

  Future<GnosisCardSnapshot> pollSafe() async {
    final walletGeneration = _walletGeneration;
    _requireNoActiveMigration();
    final owner = await _ownerAddress();
    if (walletGeneration != _walletGeneration) return _snapshot;
    final deployment = await repository.pollSafeDeployment(ownerAddress: owner);
    if (walletGeneration != _walletGeneration) return _snapshot;
    await _refresh();
    if (walletGeneration != _walletGeneration) return _snapshot;
    if (deployment.status == SafeDeploymentStatus.failed) {
      throw GnosisCardFailure(
        code: GnosisCardFailureCode.deploymentFailed,
        message: deployment.failureReason ?? 'Safe deployment failed.',
        recovery: GnosisCardRecovery.contactSupport,
      );
    }
    if (deployment.status == SafeDeploymentStatus.timedOut) {
      return _snapshot;
    }
    if (deployment.status != SafeDeploymentStatus.ok) return _snapshot;

    final configuration = await repository.safeConfiguration(
      ownerAddress: owner,
    );
    if (walletGeneration != _walletGeneration) return _snapshot;
    await _refresh();
    if (walletGeneration != _walletGeneration) return _snapshot;
    await _validateAndRegister(configuration);
    return _refresh();
  }

  Future<GnosisCardSnapshot> selectCardProduct(String productId) async {
    final walletGeneration = _walletGeneration;
    _requireNoActiveMigration();
    await repository.selectCardProduct(productId: productId);
    if (walletGeneration != _walletGeneration) return _snapshot;
    await _refresh(clearPaymentQuote: true);
    if (walletGeneration != _walletGeneration) return _snapshot;
    if (_snapshot.progress.selectedProduct?.kind == GnosisCardKind.virtual) {
      return issueVirtualCard();
    }
    return _snapshot;
  }

  Future<GnosisCardSnapshot> issueVirtualCard() async {
    final walletGeneration = _walletGeneration;
    _requireNoActiveMigration();
    await _refresh();
    if (walletGeneration != _walletGeneration) return _snapshot;
    if (_snapshot.progress.cards.any(
      (card) => card.kind == GnosisCardKind.virtual,
    )) {
      return _snapshot;
    }
    final product = _requireSelectedProduct(GnosisCardKind.virtual);
    try {
      await repository.issueVirtualCard(productId: product.id);
      if (walletGeneration != _walletGeneration) return _snapshot;
      return _refresh();
    } catch (_) {
      try {
        final reconciled = await _refresh();
        if (reconciled.progress.cards.any(
          (card) => card.kind == GnosisCardKind.virtual,
        )) {
          return reconciled;
        }
      } catch (_) {
        // Preserve the issuance or connectivity failure.
      }
      rethrow;
    }
  }

  Future<GnosisCardSnapshot> createPhysicalCardOrder(
    ShippingAddress address,
  ) async {
    final walletGeneration = _walletGeneration;
    _requireNoActiveMigration();
    final product = _requireSelectedProduct(GnosisCardKind.physical);
    await repository.createPhysicalCardOrder(
      productId: product.id,
      shippingAddress: address,
    );
    if (walletGeneration != _walletGeneration) return _snapshot;
    return _refresh(clearPaymentQuote: true);
  }

  Future<GnosisCardSnapshot> confirmPhysicalOrderReview() async {
    final walletGeneration = _walletGeneration;
    _requireNoActiveMigration();
    final order = _requirePhysicalOrder();
    await repository.markPhysicalCardOrderReviewed(orderId: order.id);
    if (walletGeneration != _walletGeneration) return _snapshot;
    final quote = await repository.physicalCardPaymentQuote(orderId: order.id);
    if (walletGeneration != _walletGeneration) return _snapshot;
    return _refresh(paymentQuote: quote);
  }

  Future<GnosisCardSnapshot> payForPhysicalCard() async {
    _requireNoActiveMigration();
    final walletGeneration = _walletGeneration;
    await _refresh();
    if (walletGeneration != _walletGeneration) return _snapshot;
    var order = _requirePhysicalOrder();
    final quote =
        _snapshot.paymentQuote ??
        await repository.physicalCardPaymentQuote(orderId: order.id);
    if (walletGeneration != _walletGeneration) return _snapshot;
    final hasAttachedPayment =
        _snapshot.progress.paymentReceipt != null ||
        order.transactionHash != null;
    try {
      if (!hasAttachedPayment) {
        final paymentKey =
            'gnosis-card-payment:${order.id}:'
            '${order.createdAt.toUtc().toIso8601String()}:'
            '${quote.amountMinor}:${quote.currency}';
        final receipt =
            await paymentGateway.findPayment(
              quote: quote,
              idempotencyKey: paymentKey,
            ) ??
            await paymentGateway.pay(quote, idempotencyKey: paymentKey);
        if (walletGeneration != _walletGeneration) return _snapshot;
        if (!receipt.isSimulated || receipt.orderId != order.id) {
          throw const GnosisCardFailure(
            code: GnosisCardFailureCode.paymentFailed,
            message: 'The payment receipt did not match this order.',
            recovery: GnosisCardRecovery.retry,
          );
        }
        await repository.attachPhysicalCardPayment(
          orderId: order.id,
          receipt: receipt,
        );
        if (walletGeneration != _walletGeneration) return _snapshot;
        await _refresh(paymentQuote: quote);
        if (walletGeneration != _walletGeneration) return _snapshot;
        order = _requirePhysicalOrder();
      }
      if (order.status != PhysicalCardOrderStatus.ready) {
        await repository.confirmPhysicalCardPayment(orderId: order.id);
        if (walletGeneration != _walletGeneration) return _snapshot;
        await _refresh(paymentQuote: quote);
        if (walletGeneration != _walletGeneration) return _snapshot;
        order = _requirePhysicalOrder();
      }
      if (order.status == PhysicalCardOrderStatus.ready) {
        await repository.createPhysicalCard(orderId: order.id);
        if (walletGeneration != _walletGeneration) return _snapshot;
      }
      return _refresh(paymentQuote: quote);
    } catch (_) {
      try {
        final reconciled = await _refresh(paymentQuote: quote);
        final reconciledOrder = reconciled.progress.physicalOrder;
        if (reconciled.progress.cards.any(
              (card) => card.kind == GnosisCardKind.physical,
            ) ||
            reconciled.progress.provisioningHandle != null ||
            reconciledOrder?.status == PhysicalCardOrderStatus.cardCreated) {
          return reconciled;
        }
      } catch (_) {
        // Preserve the original operation failure.
      }
      rethrow;
    }
  }

  Future<GnosisCardSnapshot> confirmPhysicalCardPayment() async {
    final walletGeneration = _walletGeneration;
    _requireNoActiveMigration();
    final order = _requirePhysicalOrder();
    await repository.confirmPhysicalCardPayment(orderId: order.id);
    if (walletGeneration != _walletGeneration) return _snapshot;
    return _refresh();
  }

  Future<GnosisCardSnapshot> createPhysicalCard() async {
    final walletGeneration = _walletGeneration;
    _requireNoActiveMigration();
    await _refresh();
    if (walletGeneration != _walletGeneration) return _snapshot;
    if (_snapshot.progress.provisioningHandle != null ||
        _snapshot.progress.cards.any(
          (card) => card.kind == GnosisCardKind.physical,
        )) {
      return _snapshot;
    }
    final order = _requirePhysicalOrder();
    await repository.createPhysicalCard(orderId: order.id);
    if (walletGeneration != _walletGeneration) return _snapshot;
    return _refresh();
  }

  Future<GnosisCardSnapshot> completePinProvisioning() async {
    final walletGeneration = _walletGeneration;
    _requireNoActiveMigration();
    final handle = _snapshot.progress.provisioningHandle;
    if (handle == null) {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.invalidTransition,
        message: 'The secure PIN setup session is unavailable.',
        recovery: GnosisCardRecovery.retry,
      );
    }
    await repository.completePhysicalCardPin(
      orderId: handle.orderId,
      cardId: handle.cardId,
    );
    if (walletGeneration != _walletGeneration) return _snapshot;
    return _refresh();
  }

  Future<GnosisCardSnapshot> cancelPhysicalCardOrder() async {
    _requireNoActiveMigration();
    final walletGeneration = _walletGeneration;
    final order = _requirePhysicalOrder();
    if (!order.isCancellable) {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.invalidTransition,
        message: 'This physical-card order can no longer be cancelled.',
        recovery: GnosisCardRecovery.none,
        isRecoverable: false,
      );
    }
    await repository.cancelPhysicalCardOrder(orderId: order.id);
    if (walletGeneration != _walletGeneration) return _snapshot;
    await repository.clearCardProductSelection();
    if (walletGeneration != _walletGeneration) return _snapshot;
    return _refresh(clearPaymentQuote: true);
  }

  Future<GnosisCardSnapshot> editPhysicalCardOrder() async {
    final walletGeneration = _walletGeneration;
    _requireNoActiveMigration();
    final order = _requirePhysicalOrder();
    if (!order.isCancellable) {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.invalidTransition,
        message: 'This physical-card order can no longer be edited.',
        recovery: GnosisCardRecovery.none,
        isRecoverable: false,
      );
    }
    await repository.cancelPhysicalCardOrder(orderId: order.id);
    if (walletGeneration != _walletGeneration) return _snapshot;
    return _refresh(clearPaymentQuote: true);
  }
}
