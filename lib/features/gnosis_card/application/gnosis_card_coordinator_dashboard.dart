part of 'gnosis_card_coordinator.dart';

abstract class _GnosisCardCoordinatorDashboard
    extends _GnosisCardCoordinatorAutomation {
  _GnosisCardCoordinatorDashboard({
    required super.repository,
    required super.signer,
    required super.externalFlowLauncher,
    required super.paymentGateway,
    super.readiness,
  });

  Future<GnosisCardSnapshot> setFrozen(String cardId, bool frozen) async {
    _requireNoActiveMigration();
    return _updateDashboard(
      () => repository.setFrozen(cardId: cardId, frozen: frozen),
      isReconciled: (dashboard) => dashboard.cards.any(
        (card) =>
            card.id == cardId &&
            card.status ==
                (frozen ? GnosisCardStatus.frozen : GnosisCardStatus.active),
      ),
    );
  }

  Future<GnosisCardSnapshot> setCardStatus(
    String cardId,
    GnosisCardStatus status,
  ) async {
    _requireNoActiveMigration();
    return _updateDashboard(
      () => repository.setCardStatus(cardId: cardId, status: status),
      isReconciled: (dashboard) => dashboard.cards.any(
        (card) => card.id == cardId && card.status == status,
      ),
    );
  }

  Future<GnosisCardSnapshot> updateControls({
    required String cardId,
    required GnosisCardControls controls,
  }) async {
    _requireNoActiveMigration();
    return _updateDashboard(
      () => repository.updateControls(cardId: cardId, controls: controls),
      isReconciled: (dashboard) => dashboard.cards.any(
        (card) => card.id == cardId && card.controls == controls,
      ),
    );
  }

  Future<GnosisCardSnapshot> pollDelayedOperations() async =>
      _updateDashboard(repository.pollDelayedOperations);

  Future<GnosisCardSnapshot> prepareWithdrawal(
    WithdrawalRequest request,
  ) async {
    _requireNoActiveMigration();
    final walletGeneration = _walletGeneration;
    final review = await repository.prepareWithdrawal(request);
    if (walletGeneration != _walletGeneration) return _snapshot;
    return _snapshot = _snapshot.copyWith(
      reviewIntent: review,
      reviewMetadata: GnosisIntentReviewMetadata(
        symbol: request.assetSymbol,
        decimals: request.decimals,
        feeMinor: 0,
        feeCurrency: request.assetSymbol,
      ),
    );
  }

  Future<GnosisCardSnapshot> prepareDailyLimit(
    DailyLimitRequest request,
  ) async {
    _requireNoActiveMigration();
    final walletGeneration = _walletGeneration;
    final review = await repository.prepareDailyLimit(request);
    if (walletGeneration != _walletGeneration) return _snapshot;
    return _snapshot = _snapshot.copyWith(
      reviewIntent: review,
      reviewMetadata: GnosisIntentReviewMetadata(
        symbol:
            _snapshot.dashboard?.dailyLimitAsset?.symbol ??
            _snapshot.progress.safeConfiguration?.tokenSymbol ??
            _snapshot.dashboard?.currency ??
            '',
        decimals: request.decimals,
        feeMinor: 0,
        feeCurrency:
            _snapshot.dashboard?.dailyLimitAsset?.symbol ??
            _snapshot.dashboard?.currency ??
            'EUR',
      ),
    );
  }

  Future<GnosisCardSnapshot> confirmPreparedIntent() async {
    _requireNoActiveMigration();
    final walletGeneration = _walletGeneration;
    final intent = _snapshot.reviewIntent;
    if (intent == null) {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.invalidTransition,
        message: 'There is no reviewed intent to sign.',
        recovery: GnosisCardRecovery.retry,
      );
    }
    final operationKey = intent.payloadDigest;
    final currentDashboard = await repository.dashboard();
    if (walletGeneration != _walletGeneration) return _snapshot;
    if (currentDashboard.operations.any(
      (operation) => operation.operationKey == operationKey,
    )) {
      return _snapshot = _snapshot.copyWith(
        dashboard: currentDashboard,
        clearReview: true,
      );
    }
    final session = _snapshot.session;
    final configuration = _snapshot.progress.safeConfiguration;
    if (session == null ||
        !session.isUsableFor(session.ownerAddress) ||
        configuration == null ||
        !configuration.isValid ||
        configuration.safeAddress?.toLowerCase() !=
            intent.safeAddress.toLowerCase() ||
        configuration.delayModule?.toLowerCase() !=
            intent.delayModule.toLowerCase() ||
        intent.chainId != BigInt.from(100)) {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.safeIntegrityFailed,
        message: 'The reviewed card-account action is no longer current.',
        recovery: GnosisCardRecovery.retry,
      );
    }
    final expectedOwner = await _validateAndRegister(configuration);
    if (walletGeneration != _walletGeneration) return _snapshot;
    final signature = await signer.signTypedData(
      intent,
      expectedOwner: expectedOwner,
    );
    if (walletGeneration != _walletGeneration) return _snapshot;
    if (signature.ownerAddress.toLowerCase() !=
            session.ownerAddress.toLowerCase() ||
        signature.ownerAddress.toLowerCase() !=
            configuration.ownerAddress.toLowerCase()) {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.sessionExpired,
        message: 'The active wallet changed before signing.',
        recovery: GnosisCardRecovery.reauthenticate,
      );
    }
    late final GnosisCardDashboard dashboard;
    try {
      await repository.submitSignedOperation(
        intent: intent,
        signature: signature,
        idempotencyKey: operationKey,
      );
      dashboard = await repository.dashboard();
    } catch (_) {
      try {
        final reconciled = await repository.dashboard();
        if (reconciled.operations.any(
          (operation) => operation.operationKey == operationKey,
        )) {
          if (walletGeneration != _walletGeneration) return _snapshot;
          return _snapshot = _snapshot.copyWith(
            dashboard: reconciled,
            clearReview: true,
          );
        }
      } catch (_) {
        // Preserve the original submission or connectivity failure.
      }
      rethrow;
    }
    if (walletGeneration != _walletGeneration) return _snapshot;
    return _snapshot = _snapshot.copyWith(
      dashboard: dashboard,
      clearReview: true,
    );
  }

  GnosisCardSnapshot cancelPreparedIntent() =>
      _snapshot = _snapshot.copyWith(clearReview: true);
}
