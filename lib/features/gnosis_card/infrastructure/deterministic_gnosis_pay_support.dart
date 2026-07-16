part of 'deterministic_gnosis_pay_repository.dart';

mixin _DeterministicGnosisPaySupport on _DeterministicGnosisPayRepositoryState {
  GnosisOnboardingProgress get _progress => GnosisOnboardingProgress(
    isAuthenticated: _isAuthenticated,
    isRegistered: _isRegistered,
    email: _email,
    countryCode: _verifiedCountry,
    phoneCountryCallingCode: '+49',
    terms: List.unmodifiable(_terms),
    kycStatus: _kycStatus,
    isSourceOfFundsAnswered: _isSourceOfFundsAnswered,
    phoneNumber: _phoneNumber,
    isPhoneValidated: _isPhoneValidated,
    phoneChallenge: _phoneChallenge,
    safeDeployment: _deployment,
    safeConfiguration: _safeConfiguration,
    isSafeRegistered: false,
    selectedProduct: _selectedProduct,
    physicalOrder: _physicalOrder,
    isPhysicalOrderReviewed: _isPhysicalOrderReviewed,
    paymentReceipt: _paymentReceipt,
    provisioningHandle: _provisioningHandle,
    isPinProvisioned: _isPinProvisioned,
    cards: List.unmodifiable(_dashboard.cards),
    verifiedShippingAddress: _kycStatus == GnosisKycStatus.approved
        ? const ShippingAddress(
            recipientName: 'Alex Morgan',
            address1: '12 Lindenstrasse',
            city: 'Berlin',
            postalCode: '10115',
            country: _verifiedCountry,
          )
        : null,
  );

  bool get _isKycResubmissionScenario =>
      scenario == GnosisCardScenario.kycResubmission ||
      scenario.name == 'kycExpired';

  bool get _isMigrationScenario =>
      scenario == GnosisCardScenario.migrationPending ||
      scenario == GnosisCardScenario.migrationFailed;

  GnosisCardStatus _scenarioCardStatusFor(GnosisCardKind kind) {
    if (kind == GnosisCardKind.virtual) {
      return switch (scenario) {
        GnosisCardScenario.cardFrozen => GnosisCardStatus.frozen,
        GnosisCardScenario.cardLost => GnosisCardStatus.lost,
        GnosisCardScenario.cardStolen => GnosisCardStatus.stolen,
        GnosisCardScenario.cardVoided => GnosisCardStatus.voided,
        _ => GnosisCardStatus.active,
      };
    }
    return switch (scenario) {
      GnosisCardScenario.cardShipped ||
      GnosisCardScenario.cardActivatable => GnosisCardStatus.shipped,
      GnosisCardScenario.cardActive => GnosisCardStatus.active,
      GnosisCardScenario.cardFrozen => GnosisCardStatus.frozen,
      GnosisCardScenario.cardLost => GnosisCardStatus.lost,
      GnosisCardScenario.cardStolen => GnosisCardStatus.stolen,
      GnosisCardScenario.cardVoided => GnosisCardStatus.voided,
      _ => GnosisCardStatus.ordered,
    };
  }

  String get _activeSafeAddress => _isMigrationScenario
      ? _migrationPolls >= 3
            ? _fixtureMigratedSafe
            : _fixturePreviousSafe
      : _fixtureSafe;

  void _seedMigrationUser(String ownerAddress) {
    _isRegistered = true;
    _email = 'cardholder@example.com';
    _terms = [for (final term in _terms) term.copyWith(isAccepted: true)];
    _kycStatus = GnosisKycStatus.approved;
    _isSourceOfFundsAnswered = true;
    _phoneNumber = '+4915112345678';
    _isPhoneValidated = true;
    _deployment = SafeDeployment(
      requestId: 'existing-safe-deployment',
      ownerAddress: ownerAddress,
      status: SafeDeploymentStatus.ok,
      updatedAt: DateTime.now().toUtc(),
    );
    _safeConfiguration = SafeConfiguration(
      ownerAddress: ownerAddress,
      isDeployed: true,
      integrity: SafeAccountIntegrity.ok,
      safeAddress: _fixturePreviousSafe,
      delayModule: _fixtureDelay,
      tokenSymbol: 'EURe',
      fiatSymbol: 'EUR',
    );
  }

  PhoneOtpChallenge _newPhoneChallenge(String phoneNumber) {
    final now = DateTime.now();
    return PhoneOtpChallenge(
      id: 'phone-otp-0001',
      phoneNumber: phoneNumber,
      expiresAt: now.add(const Duration(minutes: 10)),
      resendAvailableAt: now.add(const Duration(seconds: 60)),
      attemptsRemaining: 3,
      demoCode: '123456',
    );
  }

  void _requireOnline() {
    final shouldFailOffline =
        scenario == GnosisCardScenario.offline ||
        (scenario == GnosisCardScenario.offlineDashboard &&
            _dashboard.cards.isNotEmpty);
    if (shouldFailOffline && !_offlineFailureConsumed) {
      _offlineFailureConsumed = true;
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.offline,
        message: 'Card services are offline. Check your connection and retry.',
        recovery: GnosisCardRecovery.retry,
      );
    }
    if ((scenario == GnosisCardScenario.rateLimited ||
            scenario == GnosisCardScenario.serviceFailure) &&
        !_transientServiceFailureConsumed) {
      _transientServiceFailureConsumed = true;
      throw GnosisCardFailure(
        code: scenario == GnosisCardScenario.rateLimited
            ? GnosisCardFailureCode.rateLimited
            : GnosisCardFailureCode.serviceUnavailable,
        message: 'Card services are temporarily busy. Please try again.',
        recovery: GnosisCardRecovery.retry,
      );
    }
  }

  Future<void> _refreshAfterIssuance() async {
    _requireOnline();
  }

  void _resetUserState() {
    _isAuthenticated = false;
    _isRegistered = false;
    _isSourceOfFundsAnswered = false;
    _isPhoneValidated = false;
    _isPhysicalOrderReviewed = false;
    _isPinProvisioned = false;
    _email = null;
    _phoneNumber = null;
    _session = null;
    _kycStatus = GnosisKycStatus.notStarted;
    _phoneChallenge = null;
    _deployment = null;
    _safeConfiguration = null;
    _selectedProduct = null;
    _physicalOrder = null;
    _paymentReceipt = null;
    _provisioningHandle = null;
    _deploymentPolls = 0;
    _migrationPolls = 0;
    _submittedOperations.clear();
    _kycLaunched = false;
    _kycResubmissionShown = false;
    _kycRecoveryOpened = false;
    _terms = List.of(_defaultTerms);
    _dashboard = _initialDashboard(
      emptyActivity: scenario == GnosisCardScenario.emptyActivity,
    );
  }

  void _requireSession() {
    _requireOnline();
    if (!_isAuthenticated || _session == null || _session!.isExpired) {
      _session = null;
      _isAuthenticated = false;
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.sessionExpired,
        message: 'Your card session expired. Sign in again to continue.',
        recovery: GnosisCardRecovery.reauthenticate,
      );
    }
  }

  void _requireAccount() {
    if (!_isRegistered || !_terms.every((term) => term.isAccepted)) {
      throw _invalidTransition('Complete signup and agreements first.');
    }
  }

  void _requireKycApproved() {
    if (_kycStatus != GnosisKycStatus.approved) {
      throw _invalidTransition('Identity verification is not approved.');
    }
  }

  void _requireIdentityPrerequisites() {
    _requireKycApproved();
    if (!_isSourceOfFundsAnswered) {
      throw _invalidTransition('Complete source-of-funds questions first.');
    }
  }

  void _requireSafePrerequisites() {
    _requireIdentityPrerequisites();
    if (!_isPhoneValidated) {
      throw _invalidTransition('Verify the phone number first.');
    }
  }

  void _requireSafeReady() {
    if (!(_safeConfiguration?.isValid ?? false)) {
      throw _invalidTransition('The verified Safe is not ready.');
    }
  }

  void _validateOwner(String ownerAddress) {
    if (_session?.ownerAddress.toLowerCase() != ownerAddress.toLowerCase()) {
      throw _invalidInput('The Safe owner does not match the card session.');
    }
  }

  void _requireSelectedProduct(String productId, GnosisCardKind kind) {
    final product = _selectedProduct;
    if (product == null || product.id != productId || product.kind != kind) {
      throw _invalidTransition('Select the matching card product first.');
    }
  }

  PhysicalCardOrder _requireOrder(String orderId) {
    final order = _physicalOrder;
    if (order == null || order.id != orderId) {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.notFound,
        message: 'The physical-card order was not found.',
        recovery: GnosisCardRecovery.retry,
      );
    }
    return order;
  }

  GnosisCardDashboard _updateCard(String cardId, GnosisCardStatus status) {
    final index = _dashboard.cards.indexWhere((card) => card.id == cardId);
    if (index < 0) {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.notFound,
        message: 'The card was not found.',
        recovery: GnosisCardRecovery.retry,
      );
    }
    final cards = [..._dashboard.cards];
    cards[index] = cards[index].copyWith(status: status);
    _dashboard = _dashboard.copyWith(cards: cards);
    return _dashboard;
  }

  GnosisPaymentCard _card(String cardId) {
    final card = _dashboard.cards
        .where((value) => value.id == cardId)
        .firstOrNull;
    if (card == null) {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.notFound,
        message: 'The card was not found.',
        recovery: GnosisCardRecovery.retry,
      );
    }
    return card;
  }

  String _nextIntentSalt() {
    _intentSequence += 1;
    return '0x${_word(BigInt.from(_intentSequence))}';
  }
}

GnosisCardFailure _invalidInput(String message) => GnosisCardFailure(
  code: GnosisCardFailureCode.invalidInput,
  message: message,
  recovery: GnosisCardRecovery.editInput,
);

GnosisCardFailure _invalidTransition(String message) => GnosisCardFailure(
  code: GnosisCardFailureCode.invalidTransition,
  message: message,
  recovery: GnosisCardRecovery.retry,
);

GnosisCardFailure _invalidOtp() => const GnosisCardFailure(
  code: GnosisCardFailureCode.invalidOtp,
  message: 'That phone verification code is invalid.',
  recovery: GnosisCardRecovery.editInput,
);

GnosisCardFailure _issuanceFailure() => const GnosisCardFailure(
  code: GnosisCardFailureCode.issuanceFailed,
  message: 'The card could not be created. Retry issuance.',
  recovery: GnosisCardRecovery.retry,
);

bool _isAddress(String value) => RegExp(r'^0x[a-fA-F0-9]{40}$').hasMatch(value);

const _allowedStatusTransitions = <GnosisCardStatus, Set<GnosisCardStatus>>{
  GnosisCardStatus.ordered: {GnosisCardStatus.active},
  GnosisCardStatus.shipped: {GnosisCardStatus.active},
  GnosisCardStatus.active: {
    GnosisCardStatus.lost,
    GnosisCardStatus.stolen,
    GnosisCardStatus.voided,
  },
  GnosisCardStatus.frozen: {
    GnosisCardStatus.lost,
    GnosisCardStatus.stolen,
    GnosisCardStatus.voided,
  },
  GnosisCardStatus.lost: {},
  GnosisCardStatus.stolen: {},
  GnosisCardStatus.voided: {},
};

GnosisCardDashboard _initialDashboard({bool emptyActivity = false}) =>
    GnosisCardDashboard(
      balanceMinor: 184250,
      pendingBalanceMinor: 1230,
      currency: 'EUR',
      dailyLimitMinor: 150000,
      withdrawalAssets: const [
        GnosisCardAsset(
          symbol: 'USDC',
          contractAddress: _fixtureUsdc,
          decimals: 6,
          chainId: 100,
        ),
      ],
      dailyLimitTarget: _fixtureDailyLimitTarget,
      dailyLimitAsset: const GnosisCardAsset(
        symbol: 'EURe',
        contractAddress: _fixtureEure,
        decimals: 6,
        chainId: 100,
      ),
      cards: const [],
      controls: const GnosisCardControls(
        contactless: true,
        online: true,
        atm: false,
      ),
      transactions: emptyActivity
          ? const []
          : [
              GnosisCardTransaction(
                id: 'tx-1',
                merchant: 'City Market',
                amountMinor: -4235,
                currency: 'EUR',
                occurredAt: DateTime(2026, 7, 9, 17, 42),
                isDeclined: false,
              ),
              GnosisCardTransaction(
                id: 'tx-2',
                merchant: 'Rail Europe',
                amountMinor: -7890,
                currency: 'EUR',
                occurredAt: DateTime(2026, 7, 8, 9, 15),
                isDeclined: false,
              ),
            ],
      operations: const [],
    );

Map<String, dynamic> _moduleTypedData(String data, {required String salt}) => {
  'primaryType': 'ModuleTx',
  'domain': {'chainId': 100, 'verifyingContract': _fixtureDelay},
  'types': {
    'ModuleTx': [
      {'name': 'data', 'type': 'bytes'},
      {'name': 'salt', 'type': 'bytes32'},
    ],
  },
  'message': {'data': data, 'salt': salt},
};

String _outer({required String target, required String inner, BigInt? value}) {
  final byteLength = inner.length ~/ 2;
  final padding = _repeat('00', (32 - (byteLength % 32)) % 32);
  return '0x468721a7${_addressWord(target)}${_word(value ?? BigInt.zero)}'
      '${_word(BigInt.from(128))}${_word(BigInt.zero)}'
      '${_word(BigInt.from(byteLength))}$inner$padding';
}

String _addressWord(String address) => address.substring(2).padLeft(64, '0');
String _word(BigInt value) => value.toRadixString(16).padLeft(64, '0');
String _repeat(String value, int count) => List.filled(count, value).join();

const _zeroAddress = '0x0000000000000000000000000000000000000000';
const _allowanceKey =
    'fe687fc128d1915040376d20ccb1bf40d838ddd82bf9b0ba3da683cc2a251623';

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
