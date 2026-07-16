import 'dart:async';

import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_models.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_ports.dart';
import 'package:web_dex/features/gnosis_card/infrastructure/gnosis_card_config.dart';

const _fixtureSafe = '0x1111111111111111111111111111111111111111';
const _fixtureDelay = '0x2222222222222222222222222222222222222222';
const _verifiedCountry = 'DE';
const _defaultTerms = [
  GnosisTerm(
    id: 'card-terms',
    title: 'Gnosis Pay Cardholder Terms',
    version: '2026-06',
    documentUrl: 'https://mock.gnosispay.com/legal/cardholder-terms',
    isAccepted: false,
  ),
  GnosisTerm(
    id: 'privacy-notice',
    title: 'Gnosis Pay Privacy Notice',
    version: '2026-05',
    documentUrl: 'https://mock.gnosispay.com/legal/privacy',
    isAccepted: false,
  ),
];

/// In-memory, API-shaped mock. It deliberately excludes every secret card
/// value and persists only for the lifetime of the root dependency graph.
class DeterministicGnosisPayRepository implements GnosisPayRepository {
  DeterministicGnosisPayRepository({
    required this.scenario,
    SmartAccountIntentCodec codec = const SmartAccountIntentCodec(),
  }) : _codec = codec;

  final GnosisCardScenario scenario;
  final SmartAccountIntentCodec _codec;

  bool _isAuthenticated = false;
  bool _isRegistered = false;
  bool _isSourceOfFundsAnswered = false;
  bool _isPhoneValidated = false;
  bool _isPhysicalOrderReviewed = false;
  bool _isPinProvisioned = false;
  String? _stateOwnerAddress;
  String? _email;
  String? _phoneNumber;
  GnosisCardSession? _session;
  GnosisKycStatus _kycStatus = GnosisKycStatus.notStarted;
  PhoneOtpChallenge? _phoneChallenge;
  SafeDeployment? _deployment;
  SafeConfiguration? _safeConfiguration;
  GnosisCardProduct? _selectedProduct;
  PhysicalCardOrder? _physicalOrder;
  CardOrderPaymentReceipt? _paymentReceipt;
  CardProvisioningHandle? _provisioningHandle;
  int _deploymentPolls = 0;
  bool _kycLaunched = false;
  bool _kycResubmissionShown = false;
  bool _kycRecoveryOpened = false;
  bool _offlineFailureConsumed = false;
  bool _expiredSessionConsumed = false;
  bool _invalidOtpConsumed = false;
  bool _deploymentFailureConsumed = false;
  bool _integrityFailureConsumed = false;
  bool _paymentFailureConsumed = false;
  bool _issuanceFailureConsumed = false;

  List<GnosisTerm> _terms = List.of(_defaultTerms);

  final List<GnosisCardProduct> _products = const [
    GnosisCardProduct(
      id: 'virtual-eur',
      kind: GnosisCardKind.virtual,
      title: 'Virtual card',
      description: 'Instant digital card',
      feeMinor: 0,
      currency: 'EUR',
      requiresShipping: false,
      requiresPin: false,
    ),
    GnosisCardProduct(
      id: 'physical-eur',
      kind: GnosisCardKind.physical,
      title: 'Physical card',
      description: 'Physical contactless card',
      feeMinor: 999,
      currency: 'EUR',
      requiresShipping: true,
      requiresPin: true,
    ),
  ];

  late GnosisCardDashboard _dashboard = _initialDashboard();

  @override
  Future<GnosisOnboardingProgress> onboardingProgress() async {
    _requireOnline();
    return _progress;
  }

  @override
  Future<GnosisOnboardingStage> onboardingStage() async =>
      (await onboardingProgress()).nextStage;

  @override
  Future<String> createSiweMessage({required String ownerAddress}) async {
    _requireOnline();
    if (!_isAddress(ownerAddress)) {
      throw _invalidInput('KDF did not return a valid Gnosis owner address.');
    }
    return 'gleec.app wants you to sign in with your Ethereum account:\n'
        '$ownerAddress\n\nAuthorize the card workspace. No transaction is sent.\n\n'
        'URI: https://gleec.app/card\nVersion: 1\nChain ID: 100\n'
        'Nonce: gleec-card-0001\nIssued At: 2026-07-14T00:00:00Z';
  }

  @override
  Future<GnosisCardSession> authenticate({
    required String ownerAddress,
    required String signature,
  }) async {
    _requireOnline();
    if (signature.trim().isEmpty) {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.unavailable,
        message: 'KDF returned an empty SIWE signature.',
        recovery: GnosisCardRecovery.retry,
      );
    }
    final normalizedOwner = ownerAddress.toLowerCase();
    if (_stateOwnerAddress != null && _stateOwnerAddress != normalizedOwner) {
      _resetUserState();
    }
    _stateOwnerAddress = normalizedOwner;
    final expiresImmediately =
        scenario == GnosisCardScenario.expiredSession &&
        !_expiredSessionConsumed;
    if (expiresImmediately) {
      _expiredSessionConsumed = true;
    }
    _session = GnosisCardSession(
      ownerAddress: ownerAddress,
      expiresAt: expiresImmediately
          ? DateTime.now().subtract(const Duration(minutes: 1))
          : DateTime.now().add(const Duration(hours: 1)),
    );
    _isAuthenticated = !expiresImmediately;
    return _session!;
  }

  @override
  Future<List<GnosisTerm>> requiredTerms() async {
    _requireSession();
    return List.unmodifiable(_terms);
  }

  @override
  Future<void> signUp({required String email}) async {
    _requireSession();
    final normalized = email.trim().toLowerCase();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(normalized)) {
      throw _invalidInput('Enter a valid email address.');
    }
    _email = normalized;
    _isRegistered = true;
  }

  @override
  Future<void> acceptTerms(List<GnosisTermAcceptance> acceptances) async {
    _requireSession();
    if (!_isRegistered) {
      throw _invalidTransition(
        'Create the card account before accepting terms.',
      );
    }
    final accepted = {for (final value in acceptances) value.id: value.version};
    if (_terms.any((term) => accepted[term.id] != term.version)) {
      throw _invalidInput('Accept every current agreement to continue.');
    }
    _terms = [for (final term in _terms) term.copyWith(isAccepted: true)];
  }

  @override
  Future<GnosisExternalFlow> kycIntegration() async {
    _requireSession();
    _requireAccount();
    _kycLaunched = true;
    if (_kycStatus == GnosisKycStatus.notStarted ||
        _kycStatus == GnosisKycStatus.documentsRequested) {
      _kycStatus = GnosisKycStatus.pending;
    } else if (_kycStatus == GnosisKycStatus.resubmissionRequested) {
      _kycRecoveryOpened = true;
      _kycStatus = GnosisKycStatus.pending;
    }
    return const GnosisExternalFlow(
      id: 'kyc-mock-flow',
      kind: GnosisExternalFlowKind.kyc,
      url: 'https://mock.gnosispay.com/kyc/gleec-applicant',
    );
  }

  @override
  Future<GnosisKycStatus> pollKyc() async {
    _requireSession();
    _requireAccount();
    if (!_kycLaunched) return _kycStatus;
    if (scenario == GnosisCardScenario.kycRejected) {
      return _kycStatus = GnosisKycStatus.rejected;
    }
    if (scenario == GnosisCardScenario.kycRequiresAction) {
      return _kycStatus = GnosisKycStatus.requiresAction;
    }
    if (_isKycResubmissionScenario && !_kycResubmissionShown) {
      _kycResubmissionShown = true;
      return _kycStatus = GnosisKycStatus.resubmissionRequested;
    }
    if (_isKycResubmissionScenario && !_kycRecoveryOpened) {
      return _kycStatus;
    }
    if (_kycStatus == GnosisKycStatus.pending && !_isKycResubmissionScenario) {
      return _kycStatus = GnosisKycStatus.processing;
    }
    return _kycStatus = GnosisKycStatus.approved;
  }

  @override
  Future<GnosisExternalFlow> supportFlow() async {
    _requireOnline();
    return const GnosisExternalFlow(
      id: 'support-mock-flow',
      kind: GnosisExternalFlowKind.support,
      url: 'https://mock.gnosispay.com/support',
    );
  }

  @override
  Future<List<SourceOfFundsQuestion>> sourceOfFundsQuestions() async {
    _requireSession();
    _requireKycApproved();
    return const [
      SourceOfFundsQuestion(
        id: 'primary-source',
        title: 'What is the primary source of funds for this card?',
        answers: ['Salary', 'Savings', 'Investments', 'Business income'],
      ),
      SourceOfFundsQuestion(
        id: 'expected-use',
        title: 'How do you expect to use the card?',
        answers: [
          'Everyday spending',
          'Travel',
          'Online purchases',
          'Business',
        ],
      ),
    ];
  }

  @override
  Future<void> submitSourceOfFunds(List<SourceOfFundsAnswer> answers) async {
    _requireSession();
    final questions = await sourceOfFundsQuestions();
    final byId = {for (final answer in answers) answer.questionId: answer};
    for (final question in questions) {
      final answer = byId[question.id];
      if (answer == null || !question.answers.contains(answer.answer)) {
        throw _invalidInput('Answer every source-of-funds question.');
      }
    }
    _isSourceOfFundsAnswered = true;
  }

  @override
  Future<PhoneOtpChallenge> requestPhoneOtp({
    required String phoneNumber,
  }) async {
    _requireSession();
    _requireIdentityPrerequisites();
    final normalized = phoneNumber.replaceAll(RegExp(r'[\s\-()]'), '');
    if (!RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(normalized)) {
      throw _invalidInput('Enter a valid E.164 phone number.');
    }
    _phoneNumber = normalized;
    return _phoneChallenge = _newPhoneChallenge(normalized);
  }

  @override
  Future<PhoneOtpChallenge> resendPhoneOtp() async {
    _requireSession();
    final challenge = _phoneChallenge;
    if (challenge == null || _phoneNumber == null) {
      throw _invalidTransition('Request a phone code before resending it.');
    }
    if (!challenge.canResend) {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.resendCooldown,
        message: 'Wait for the resend cooldown before requesting another code.',
        recovery: GnosisCardRecovery.retry,
      );
    }
    return _phoneChallenge = _newPhoneChallenge(_phoneNumber!);
  }

  @override
  Future<void> verifyPhoneOtp({required String code}) async {
    _requireSession();
    final challenge = _phoneChallenge;
    if (challenge == null) {
      throw _invalidTransition('Request a phone code before verifying it.');
    }
    if (scenario == GnosisCardScenario.invalidOtp && !_invalidOtpConsumed) {
      _invalidOtpConsumed = true;
      _phoneChallenge = challenge.copyWith(
        attemptsRemaining: challenge.attemptsRemaining - 1,
      );
      throw _invalidOtp();
    }
    if (code != challenge.demoCode) {
      _phoneChallenge = challenge.copyWith(
        attemptsRemaining: challenge.attemptsRemaining - 1,
      );
      throw _invalidOtp();
    }
    _isPhoneValidated = true;
    _phoneChallenge = null;
  }

  @override
  Future<void> clearPhoneOtp() async {
    _requireSession();
    _phoneChallenge = null;
    _phoneNumber = null;
    _isPhoneValidated = false;
  }

  @override
  Future<SafeDeployment?> safeDeployment({required String ownerAddress}) async {
    _requireSession();
    _validateOwner(ownerAddress);
    return _deployment;
  }

  @override
  Future<SafeDeployment> requestSafeDeployment({
    required String ownerAddress,
  }) async {
    _requireSession();
    _requireSafePrerequisites();
    _validateOwner(ownerAddress);
    final current = _deployment;
    if (current != null &&
        current.status != SafeDeploymentStatus.failed &&
        current.status != SafeDeploymentStatus.timedOut) {
      return current;
    }
    if (current?.status == SafeDeploymentStatus.failed ||
        current?.status == SafeDeploymentStatus.timedOut) {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.deploymentFailed,
        message: 'Reset the failed Safe deployment before retrying.',
        recovery: GnosisCardRecovery.resetSafe,
      );
    }
    _deploymentPolls = 0;
    return _deployment = SafeDeployment(
      requestId: 'deploy-gleec-0001',
      ownerAddress: ownerAddress,
      status: SafeDeploymentStatus.accepted,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<SafeDeployment> pollSafeDeployment({
    required String ownerAddress,
  }) async {
    _requireSession();
    _validateOwner(ownerAddress);
    final current = _deployment;
    if (current == null) {
      throw _invalidTransition('Start Safe deployment before checking it.');
    }
    if (current.status == SafeDeploymentStatus.failed ||
        current.status == SafeDeploymentStatus.timedOut ||
        current.status == SafeDeploymentStatus.ok) {
      return current;
    }
    _deploymentPolls += 1;
    if (_deploymentPolls == 1) {
      return _deployment = current.copyWith(
        status: SafeDeploymentStatus.processing,
        updatedAt: DateTime.now().toUtc(),
        clearFailureReason: true,
      );
    }
    if (scenario == GnosisCardScenario.deploymentFailure &&
        !_deploymentFailureConsumed) {
      _deploymentFailureConsumed = true;
      return _deployment = current.copyWith(
        status: SafeDeploymentStatus.failed,
        updatedAt: DateTime.now().toUtc(),
        failureReason: 'The API could not complete Safe deployment.',
      );
    }
    return _deployment = current.copyWith(
      status: SafeDeploymentStatus.ok,
      updatedAt: DateTime.now().toUtc(),
      clearFailureReason: true,
    );
  }

  @override
  Future<SafeConfiguration> safeConfiguration({
    required String ownerAddress,
  }) async {
    _requireSession();
    _validateOwner(ownerAddress);
    if (_deployment?.status != SafeDeploymentStatus.ok) {
      throw _invalidTransition('The Safe is not deployed yet.');
    }
    final current = _safeConfiguration;
    if (current != null &&
        current.ownerAddress.toLowerCase() == ownerAddress.toLowerCase()) {
      return current;
    }
    final integrity =
        scenario == GnosisCardScenario.safeIntegrityFailure &&
            !_integrityFailureConsumed
        ? SafeAccountIntegrity.safeMisconfigured
        : SafeAccountIntegrity.ok;
    if (integrity == SafeAccountIntegrity.safeMisconfigured) {
      _integrityFailureConsumed = true;
    }
    return _safeConfiguration = SafeConfiguration(
      ownerAddress: ownerAddress,
      isDeployed: true,
      integrity: integrity,
      safeAddress: _fixtureSafe,
      delayModule: _fixtureDelay,
      tokenSymbol: 'EURe',
      fiatSymbol: 'EUR',
    );
  }

  @override
  Future<void> validateSafeIntegrity(SafeConfiguration configuration) async {
    _requireSession();
    if (!configuration.isValid ||
        configuration.safeAddress != _fixtureSafe ||
        configuration.delayModule != _fixtureDelay ||
        configuration.ownerAddress != _session!.ownerAddress) {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.safeIntegrityFailed,
        message: 'The returned Safe configuration failed integrity checks.',
        recovery: GnosisCardRecovery.resetSafe,
      );
    }
  }

  @override
  Future<void> resetSafe({required String ownerAddress}) async {
    _requireSession();
    _validateOwner(ownerAddress);
    _deployment = null;
    _safeConfiguration = null;
    _deploymentPolls = 0;
  }

  @override
  Future<List<GnosisCardProduct>> cardProducts() async {
    _requireSession();
    _requireSafeReady();
    return List.unmodifiable(_products);
  }

  @override
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

  @override
  Future<void> clearCardProductSelection() async {
    _selectedProduct = null;
  }

  @override
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
    const card = GnosisPaymentCard(
      id: 'card-virtual-0001',
      kind: GnosisCardKind.virtual,
      status: GnosisCardStatus.active,
      lastFour: '4242',
      label: 'Everyday card',
    );
    _dashboard = _dashboard.copyWith(cards: [..._dashboard.cards, card]);
    return card;
  }

  @override
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

  @override
  Future<void> markPhysicalCardOrderReviewed({required String orderId}) async {
    _requireSession();
    final order = _requireOrder(orderId);
    if (order.status != PhysicalCardOrderStatus.pendingTransaction) {
      throw _invalidTransition('This order can no longer be reviewed.');
    }
    _isPhysicalOrderReviewed = true;
  }

  @override
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
      assetContract: '0x3333333333333333333333333333333333333333',
      recipient: '0x4444444444444444444444444444444444444444',
      isSimulated: true,
    );
  }

  @override
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

  @override
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

  @override
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
    const card = GnosisPaymentCard(
      id: 'card-physical-0001',
      kind: GnosisCardKind.physical,
      status: GnosisCardStatus.ordered,
      lastFour: '8810',
      label: 'Physical card',
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

  @override
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

  @override
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

  @override
  Future<GnosisCardDashboard> dashboard() async {
    _requireSession();
    if (_dashboard.cards.isEmpty) {
      throw _invalidTransition('No card has been issued yet.');
    }
    return _dashboard = _dashboard.copyWith(physicalOrder: _physicalOrder);
  }

  @override
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

  @override
  Future<GnosisCardDashboard> setFrozen({
    required String cardId,
    required bool frozen,
  }) async {
    await dashboard();
    return _updateCard(
      cardId,
      frozen ? GnosisCardStatus.frozen : GnosisCardStatus.active,
    );
  }

  @override
  Future<GnosisCardDashboard> setCardStatus({
    required String cardId,
    required GnosisCardStatus status,
  }) async {
    await dashboard();
    return _updateCard(cardId, status);
  }

  @override
  Future<GnosisCardDashboard> updateControls(
    GnosisCardControls controls,
  ) async {
    await dashboard();
    _dashboard = _dashboard.copyWith(controls: controls);
    return _dashboard;
  }

  @override
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
      ),
      safeAddress: _fixtureSafe,
      expectedChainId: BigInt.from(100),
      expectedDelayModule: _fixtureDelay,
      requested: SmartAccountRequestedAction.withdrawal(
        assetContract: request.assetContract,
        recipient: request.recipient,
        amount: request.amountAtomic,
      ),
    );
  }

  @override
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
      _moduleTypedData(_outer(target: request.bouncer, inner: inner)),
      safeAddress: _fixtureSafe,
      expectedChainId: BigInt.from(100),
      expectedDelayModule: _fixtureDelay,
      requested: SmartAccountRequestedAction.dailyLimit(
        bouncer: request.bouncer,
        amount: request.amountAtomic,
        periodSeconds: request.periodSeconds,
      ),
    );
  }

  @override
  Future<DelayedOperation> submitSignedOperation({
    required PreparedSmartAccountIntent intent,
    required SmartAccountSignature signature,
  }) async {
    await dashboard();
    if (signature.signature.isEmpty ||
        !signature.typedDataHash.startsWith('0x')) {
      throw _invalidInput('KDF returned an invalid signature response.');
    }
    final operation = DelayedOperation(
      id: 'operation-${_dashboard.operations.length + 1}',
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
    return operation;
  }

  GnosisOnboardingProgress get _progress => GnosisOnboardingProgress(
    isAuthenticated: _isAuthenticated,
    isRegistered: _isRegistered,
    email: _email,
    countryCode: _verifiedCountry,
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
  );

  bool get _isKycResubmissionScenario =>
      scenario == GnosisCardScenario.kycResubmission ||
      scenario.name == 'kycExpired';

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
    if (scenario == GnosisCardScenario.offline && !_offlineFailureConsumed) {
      _offlineFailureConsumed = true;
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.offline,
        message: 'Card services are offline. Check your connection and retry.',
        recovery: GnosisCardRecovery.retry,
      );
    }
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
    _kycLaunched = false;
    _kycResubmissionShown = false;
    _kycRecoveryOpened = false;
    _terms = List.of(_defaultTerms);
    _dashboard = _initialDashboard();
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

GnosisCardDashboard _initialDashboard() => GnosisCardDashboard(
  balanceMinor: 184250,
  currency: 'EUR',
  dailyLimitMinor: 150000,
  cards: const [],
  controls: const GnosisCardControls(
    contactless: true,
    online: true,
    atm: false,
  ),
  transactions: [
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

Map<String, dynamic> _moduleTypedData(String data) => {
  'primaryType': 'ModuleTx',
  'domain': {'chainId': 100, 'verifyingContract': _fixtureDelay},
  'types': {
    'ModuleTx': [
      {'name': 'data', 'type': 'bytes'},
      {'name': 'salt', 'type': 'bytes32'},
    ],
  },
  'message': {'data': data, 'salt': '0x${_repeat('11', 32)}'},
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
