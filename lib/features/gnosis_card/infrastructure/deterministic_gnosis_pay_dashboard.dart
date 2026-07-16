part of 'deterministic_gnosis_pay_repository.dart';

mixin _DeterministicGnosisPayDashboard
    on _DeterministicGnosisPayRepositoryState, _DeterministicGnosisPaySupport {
  Future<GnosisCardDashboard> dashboard() async {
    _requireSession();
    if (_dashboard.cards.isEmpty) {
      throw _invalidTransition('No card has been issued yet.');
    }
    return _dashboard = _dashboard.copyWith(physicalOrder: _physicalOrder);
  }

  Future<GnosisCardDashboard> pollDelayedOperations() async {
    await dashboard();
    _dashboard = _dashboard.copyWith(
      operations: [
        for (final operation in _dashboard.operations)
          operation.copyWith(
            status: switch (operation.status) {
              DelayedOperationStatus.coolingDown =>
                DelayedOperationStatus.executable,
              DelayedOperationStatus.executable =>
                DelayedOperationStatus.executed,
              _ => operation.status,
            },
          ),
      ],
    );
    return _dashboard;
  }

  Future<GnosisCardDashboard> setFrozen({
    required String cardId,
    required bool frozen,
  }) async {
    await dashboard();
    final current = _card(cardId);
    final expected = frozen ? GnosisCardStatus.active : GnosisCardStatus.frozen;
    if (current.status != expected) {
      throw _invalidTransition(
        frozen
            ? 'Only an active card can be frozen.'
            : 'Only a frozen card can be unfrozen.',
      );
    }
    return _updateCard(
      cardId,
      frozen ? GnosisCardStatus.frozen : GnosisCardStatus.active,
    );
  }

  Future<GnosisCardDashboard> setCardStatus({
    required String cardId,
    required GnosisCardStatus status,
  }) async {
    await dashboard();
    final current = _card(cardId);
    if (status == GnosisCardStatus.active && !current.isActivatable) {
      throw _invalidTransition('This physical card is not ready to activate.');
    }
    if (!_allowedStatusTransitions[current.status]!.contains(status)) {
      throw _invalidTransition('This card status can no longer be changed.');
    }
    return _updateCard(cardId, status);
  }

  Future<GnosisCardDashboard> updateControls({
    required String cardId,
    required GnosisCardControls controls,
  }) async {
    await dashboard();
    final current = _card(cardId);
    if (!const {
      GnosisCardStatus.active,
      GnosisCardStatus.frozen,
    }.contains(current.status)) {
      throw _invalidTransition('Controls are unavailable for this card.');
    }
    final cards = [
      for (final card in _dashboard.cards)
        if (card.id == cardId) card.copyWith(controls: controls) else card,
    ];
    _dashboard = _dashboard.copyWith(cards: cards);
    return _dashboard;
  }

  Future<PreparedSmartAccountIntent> prepareWithdrawal(
    WithdrawalRequest request,
  ) async {
    await dashboard();
    final isNative = request.assetContract == _zeroAddress;
    final inner = isNative
        ? ''
        : 'a9059cbb${_addressWord(request.recipient)}'
              '${_word(request.amountAtomic)}';
    final target = isNative ? request.recipient : request.assetContract;
    return _codec.prepare(
      _moduleTypedData(
        _outer(
          target: target,
          value: isNative ? request.amountAtomic : BigInt.zero,
          inner: inner,
        ),
        salt: _nextIntentSalt(),
      ),
      safeAddress: _activeSafeAddress,
      expectedChainId: BigInt.from(100),
      expectedDelayModule: _fixtureDelay,
      requested: SmartAccountRequestedAction.withdrawal(
        assetContract: request.assetContract,
        recipient: request.recipient,
        amount: request.amountAtomic,
      ),
    );
  }

  Future<PreparedSmartAccountIntent> prepareDailyLimit(
    DailyLimitRequest request,
  ) async {
    await dashboard();
    final inner =
        'a8ec43ee$_allowanceKey'
        '${_word(request.amountAtomic)}${_word(request.amountAtomic)}'
        '${_word(request.amountAtomic)}${_word(BigInt.from(request.periodSeconds))}'
        '${_word(BigInt.zero)}';
    return _codec.prepare(
      _moduleTypedData(
        _outer(target: request.bouncer, inner: inner),
        salt: _nextIntentSalt(),
      ),
      safeAddress: _activeSafeAddress,
      expectedChainId: BigInt.from(100),
      expectedDelayModule: _fixtureDelay,
      requested: SmartAccountRequestedAction.dailyLimit(
        bouncer: request.bouncer,
        amount: request.amountAtomic,
        periodSeconds: request.periodSeconds,
      ),
    );
  }

  Future<DelayedOperation> submitSignedOperation({
    required PreparedSmartAccountIntent intent,
    required SmartAccountSignature signature,
    required String idempotencyKey,
  }) async {
    await dashboard();
    if (idempotencyKey != intent.payloadDigest) {
      throw _invalidInput(
        'The signed operation key does not match its review.',
      );
    }
    final existing = _submittedOperations[idempotencyKey];
    if (existing != null) return existing;
    if (signature.signature.isEmpty ||
        !signature.typedDataHash.startsWith('0x') ||
        signature.ownerAddress.toLowerCase() !=
            _session!.ownerAddress.toLowerCase() ||
        intent.safeAddress.toLowerCase() != _activeSafeAddress.toLowerCase() ||
        intent.chainId != BigInt.from(100) ||
        intent.delayModule.toLowerCase() != _fixtureDelay.toLowerCase()) {
      throw _invalidInput('KDF returned an invalid signature response.');
    }
    final operation = DelayedOperation(
      id: 'operation-${_dashboard.operations.length + 1}',
      operationKey: idempotencyKey,
      kind: intent.kind == SmartAccountIntentKind.withdrawal
          ? DelayedOperationKind.withdrawal
          : DelayedOperationKind.dailyLimit,
      status: DelayedOperationStatus.coolingDown,
      summary: intent.kind == SmartAccountIntentKind.withdrawal
          ? 'Withdrawal of ${intent.amount}'
          : 'Daily limit of ${intent.amount}',
      executableAt: DateTime.now().add(const Duration(minutes: 5)),
    );
    _dashboard = _dashboard.copyWith(
      operations: [operation, ..._dashboard.operations],
    );
    _submittedOperations[idempotencyKey] = operation;
    return operation;
  }
}
