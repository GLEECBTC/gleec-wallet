import 'package:equatable/equatable.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_models.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_ports.dart';

class GnosisCardSnapshot extends Equatable {
  const GnosisCardSnapshot({
    required this.progress,
    this.session,
    this.sourceOfFundsQuestions = const [],
    this.cardProducts = const [],
    this.paymentQuote,
    this.dashboard,
    this.reviewIntent,
  });

  const GnosisCardSnapshot.initial()
    : progress = const GnosisOnboardingProgress.initial(),
      session = null,
      sourceOfFundsQuestions = const [],
      cardProducts = const [],
      paymentQuote = null,
      dashboard = null,
      reviewIntent = null;

  final GnosisOnboardingProgress progress;
  final GnosisCardSession? session;
  final List<SourceOfFundsQuestion> sourceOfFundsQuestions;
  final List<GnosisCardProduct> cardProducts;
  final CardOrderPaymentQuote? paymentQuote;
  final GnosisCardDashboard? dashboard;
  final PreparedSmartAccountIntent? reviewIntent;

  GnosisOnboardingStage get stage => progress.nextStage;
  List<GnosisTerm> get terms => progress.terms;
  GnosisKycStatus get kycStatus => progress.kycStatus;
  PhoneOtpChallenge? get phoneChallenge => progress.phoneChallenge;
  SafeDeployment? get deployment => progress.safeDeployment;
  SafeConfiguration? get safeConfiguration => progress.safeConfiguration;
  CardOrderPaymentReceipt? get paymentReceipt => progress.paymentReceipt;
  CardProvisioningHandle? get provisioningHandle => progress.provisioningHandle;

  GnosisCardSnapshot copyWith({
    GnosisOnboardingProgress? progress,
    GnosisCardSession? session,
    List<SourceOfFundsQuestion>? sourceOfFundsQuestions,
    List<GnosisCardProduct>? cardProducts,
    CardOrderPaymentQuote? paymentQuote,
    GnosisCardDashboard? dashboard,
    PreparedSmartAccountIntent? reviewIntent,
    bool clearSession = false,
    bool clearPaymentQuote = false,
    bool clearDashboard = false,
    bool clearReview = false,
  }) => GnosisCardSnapshot(
    progress: progress ?? this.progress,
    session: clearSession ? null : session ?? this.session,
    sourceOfFundsQuestions:
        sourceOfFundsQuestions ?? this.sourceOfFundsQuestions,
    cardProducts: cardProducts ?? this.cardProducts,
    paymentQuote: clearPaymentQuote ? null : paymentQuote ?? this.paymentQuote,
    dashboard: clearDashboard ? null : dashboard ?? this.dashboard,
    reviewIntent: clearReview ? null : reviewIntent ?? this.reviewIntent,
  );

  @override
  List<Object?> get props => [
    progress,
    session,
    sourceOfFundsQuestions,
    cardProducts,
    paymentQuote,
    dashboard,
    reviewIntent,
  ];
}

/// Coordinates API-owned onboarding with genuine KDF signing.
///
/// The repository is the only component that mutates server-shaped progress.
/// This facade derives the active step after every operation and never deploys
/// or configures a Safe locally.
class GnosisCardCoordinator {
  GnosisCardCoordinator({
    required this.repository,
    required this.signer,
    required this.externalFlowLauncher,
    required this.paymentGateway,
  });

  final GnosisPayRepository repository;
  final SmartAccountSigner signer;

  /// Kept at the composition boundary so callers can use the same injected
  /// launcher for one-shot UI effects. The coordinator only returns flows; it
  /// never opens a browser while handling a BLoC event.
  final ExternalFlowLauncher externalFlowLauncher;
  final CardOrderPaymentGateway paymentGateway;

  GnosisCardSnapshot _snapshot = const GnosisCardSnapshot.initial();
  String? _registeredSafe;
  String? _registeredSafeOwner;

  GnosisCardSnapshot get snapshot => _snapshot;

  Future<GnosisCardSnapshot> initialize() async {
    await _refresh();
    final configuration = _snapshot.progress.safeConfiguration;
    if (configuration?.isValid ?? false) {
      await _validateAndRegister(configuration!);
      await _refresh();
    }
    return _snapshot;
  }

  Future<GnosisCardSnapshot> signIn() async {
    final owner = await signer.owner();
    final message = await repository.createSiweMessage(
      ownerAddress: owner.address,
    );
    final signature = await signer.signPersonalMessage(message);
    final session = await repository.authenticate(
      ownerAddress: owner.address,
      signature: signature,
    );
    if (session.isExpired) {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.sessionExpired,
        message: 'The card session expired. Sign in again to continue.',
        recovery: GnosisCardRecovery.reauthenticate,
      );
    }
    final previousOwner = _snapshot.session?.ownerAddress;
    if (previousOwner != null &&
        previousOwner.toLowerCase() != session.ownerAddress.toLowerCase()) {
      _registeredSafe = null;
      _registeredSafeOwner = null;
    }
    await repository.requiredTerms();
    await _refresh(session: session);
    final configuration = _snapshot.progress.safeConfiguration;
    if (configuration?.isValid ?? false) {
      await _validateAndRegister(configuration!);
      await _refresh(session: session);
    }
    return _snapshot;
  }

  Future<GnosisCardSnapshot> signUpAndAcceptTerms({
    required String email,
    required List<GnosisTermAcceptance> acceptances,
  }) async {
    if (!_snapshot.progress.isRegistered || _snapshot.progress.email != email) {
      await repository.signUp(email: email);
    }
    await repository.acceptTerms(acceptances);
    return _refresh();
  }

  Future<GnosisExternalFlow> kycFlow() => repository.kycIntegration();

  Future<GnosisExternalFlow> supportFlow() => repository.supportFlow();

  Future<GnosisCardSnapshot> refreshKyc() async {
    await repository.pollKyc();
    return _refresh();
  }

  Future<GnosisCardSnapshot> submitSourceOfFunds(
    List<SourceOfFundsAnswer> answers,
  ) async {
    await repository.submitSourceOfFunds(answers);
    return _refresh();
  }

  Future<GnosisCardSnapshot> requestPhoneOtp(String phoneNumber) async {
    await repository.requestPhoneOtp(phoneNumber: phoneNumber);
    return _refresh();
  }

  Future<GnosisCardSnapshot> resendPhoneOtp() async {
    await repository.resendPhoneOtp();
    return _refresh();
  }

  Future<GnosisCardSnapshot> verifyPhoneOtp(String code) async {
    await repository.verifyPhoneOtp(code: code);
    return _refresh();
  }

  Future<GnosisCardSnapshot> editPhoneNumber() async {
    await repository.clearPhoneOtp();
    return _refresh();
  }

  Future<GnosisCardSnapshot> deploySafe() async {
    final owner = await _ownerAddress();
    await repository.requestSafeDeployment(ownerAddress: owner);
    return _refresh();
  }

  Future<GnosisCardSnapshot> pollSafe() async {
    final owner = await _ownerAddress();
    final deployment = await repository.pollSafeDeployment(ownerAddress: owner);
    await _refresh();
    if (deployment.status == SafeDeploymentStatus.failed) {
      throw GnosisCardFailure(
        code: GnosisCardFailureCode.deploymentFailed,
        message: deployment.failureReason ?? 'Safe deployment failed.',
        recovery: GnosisCardRecovery.resetSafe,
      );
    }
    if (deployment.status == SafeDeploymentStatus.timedOut) {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.deploymentTimedOut,
        message: 'Safe deployment is taking longer than expected.',
        recovery: GnosisCardRecovery.resetSafe,
      );
    }
    if (deployment.status != SafeDeploymentStatus.ok) return _snapshot;

    final configuration = await repository.safeConfiguration(
      ownerAddress: owner,
    );
    await _refresh();
    await _validateAndRegister(configuration);
    return _refresh();
  }

  Future<GnosisCardSnapshot> resetSafe() async {
    final owner = await _ownerAddress();
    await repository.resetSafe(ownerAddress: owner);
    _registeredSafe = null;
    _registeredSafeOwner = null;
    return _refresh(clearPaymentQuote: true);
  }

  Future<GnosisCardSnapshot> selectCardProduct(String productId) async {
    await repository.selectCardProduct(productId: productId);
    return _refresh(clearPaymentQuote: true);
  }

  Future<GnosisCardSnapshot> issueVirtualCard() async {
    final product = _requireSelectedProduct(GnosisCardKind.virtual);
    await repository.issueVirtualCard(productId: product.id);
    return _refresh();
  }

  Future<GnosisCardSnapshot> createPhysicalCardOrder(
    ShippingAddress address,
  ) async {
    final product = _requireSelectedProduct(GnosisCardKind.physical);
    await repository.createPhysicalCardOrder(
      productId: product.id,
      shippingAddress: address,
    );
    return _refresh(clearPaymentQuote: true);
  }

  Future<GnosisCardSnapshot> confirmPhysicalOrderReview() async {
    final order = _requirePhysicalOrder();
    await repository.markPhysicalCardOrderReviewed(orderId: order.id);
    final quote = await repository.physicalCardPaymentQuote(orderId: order.id);
    return _refresh(paymentQuote: quote);
  }

  Future<GnosisCardSnapshot> payForPhysicalCard() async {
    final order = _requirePhysicalOrder();
    final quote =
        _snapshot.paymentQuote ??
        await repository.physicalCardPaymentQuote(orderId: order.id);
    final receipt = await paymentGateway.pay(quote);
    if (!receipt.isSimulated || receipt.orderId != order.id) {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.paymentFailed,
        message: 'The simulated payment receipt did not match this order.',
        recovery: GnosisCardRecovery.retry,
      );
    }
    await repository.attachPhysicalCardPayment(
      orderId: order.id,
      receipt: receipt,
    );
    return _refresh(paymentQuote: quote);
  }

  Future<GnosisCardSnapshot> confirmPhysicalCardPayment() async {
    final order = _requirePhysicalOrder();
    await repository.confirmPhysicalCardPayment(orderId: order.id);
    return _refresh();
  }

  Future<GnosisCardSnapshot> createPhysicalCard() async {
    final order = _requirePhysicalOrder();
    await repository.createPhysicalCard(orderId: order.id);
    return _refresh();
  }

  Future<GnosisCardSnapshot> completePinProvisioning() async {
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
    return _refresh();
  }

  Future<GnosisCardSnapshot> cancelPhysicalCardOrder() async {
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
    await repository.clearCardProductSelection();
    return _refresh(clearPaymentQuote: true);
  }

  Future<GnosisCardSnapshot> editPhysicalCardOrder() async {
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
    return _refresh(clearPaymentQuote: true);
  }

  Future<GnosisCardSnapshot> setFrozen(String cardId, bool frozen) async =>
      _snapshot = _snapshot.copyWith(
        dashboard: await repository.setFrozen(cardId: cardId, frozen: frozen),
      );

  Future<GnosisCardSnapshot> setCardStatus(
    String cardId,
    GnosisCardStatus status,
  ) async => _snapshot = _snapshot.copyWith(
    dashboard: await repository.setCardStatus(cardId: cardId, status: status),
  );

  Future<GnosisCardSnapshot> updateControls(
    GnosisCardControls controls,
  ) async => _snapshot = _snapshot.copyWith(
    dashboard: await repository.updateControls(controls),
  );

  Future<GnosisCardSnapshot> pollDelayedOperations() async => _snapshot =
      _snapshot.copyWith(dashboard: await repository.pollDelayedOperations());

  Future<GnosisCardSnapshot> prepareWithdrawal(
    WithdrawalRequest request,
  ) async => _snapshot = _snapshot.copyWith(
    reviewIntent: await repository.prepareWithdrawal(request),
  );

  Future<GnosisCardSnapshot> prepareDailyLimit(
    DailyLimitRequest request,
  ) async => _snapshot = _snapshot.copyWith(
    reviewIntent: await repository.prepareDailyLimit(request),
  );

  Future<GnosisCardSnapshot> confirmPreparedIntent() async {
    final intent = _snapshot.reviewIntent;
    if (intent == null) {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.invalidTransition,
        message: 'There is no reviewed intent to sign.',
        recovery: GnosisCardRecovery.retry,
      );
    }
    final signature = await signer.signTypedData(intent);
    await repository.submitSignedOperation(
      intent: intent,
      signature: signature,
    );
    return _snapshot = _snapshot.copyWith(
      dashboard: await repository.dashboard(),
      clearReview: true,
    );
  }

  GnosisCardSnapshot cancelPreparedIntent() =>
      _snapshot = _snapshot.copyWith(clearReview: true);

  Future<GnosisCardSnapshot> _refresh({
    GnosisCardSession? session,
    CardOrderPaymentQuote? paymentQuote,
    bool clearPaymentQuote = false,
  }) async {
    var progress = await repository.onboardingProgress();
    final configuration = progress.safeConfiguration;
    final configuredSafe = configuration?.safeAddress;
    final effectiveSession = session ?? _snapshot.session;
    final sessionMatchesConfiguration =
        effectiveSession == null ||
        effectiveSession.ownerAddress.toLowerCase() ==
            configuration?.ownerAddress.toLowerCase();
    progress = progress.withSafeRegistration(
      configuredSafe != null &&
          _registeredSafe?.toLowerCase() == configuredSafe.toLowerCase() &&
          _registeredSafeOwner?.toLowerCase() ==
              configuration?.ownerAddress.toLowerCase() &&
          sessionMatchesConfiguration,
    );
    var sourceQuestions = _snapshot.sourceOfFundsQuestions;
    var products = _snapshot.cardProducts;
    var dashboard = _snapshot.dashboard;

    if (progress.nextStage == GnosisOnboardingStage.sourceOfFunds &&
        sourceQuestions.isEmpty) {
      sourceQuestions = await repository.sourceOfFundsQuestions();
    }
    if (progress.isSafeReady && products.isEmpty) {
      products = await repository.cardProducts();
    }
    if (progress.cards.isNotEmpty) {
      dashboard = await repository.dashboard();
    }

    _snapshot = _snapshot.copyWith(
      progress: progress,
      session: session,
      sourceOfFundsQuestions: sourceQuestions,
      cardProducts: products,
      paymentQuote: paymentQuote,
      dashboard: dashboard,
      clearPaymentQuote: clearPaymentQuote,
      clearDashboard: progress.cards.isEmpty,
    );
    return _snapshot;
  }

  Future<void> _validateAndRegister(SafeConfiguration configuration) async {
    await repository.validateSafeIntegrity(configuration);
    final safeAddress = configuration.safeAddress;
    if (safeAddress == null) {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.safeIntegrityFailed,
        message: 'The verified Safe address is missing.',
        recovery: GnosisCardRecovery.resetSafe,
      );
    }
    final owner = await signer.owner();
    if (owner.address.toLowerCase() !=
        configuration.ownerAddress.toLowerCase()) {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.sessionExpired,
        message: 'The active KDF owner changed. Sign in again to continue.',
        recovery: GnosisCardRecovery.reauthenticate,
      );
    }
    await signer.registerSafe(safeAddress);
    _registeredSafe = safeAddress;
    _registeredSafeOwner = owner.address;
  }

  Future<String> _ownerAddress() async {
    final session = _snapshot.session;
    if (session != null) {
      if (session.isExpired) {
        throw const GnosisCardFailure(
          code: GnosisCardFailureCode.sessionExpired,
          message: 'The card session expired. Sign in again to continue.',
          recovery: GnosisCardRecovery.reauthenticate,
        );
      }
      return session.ownerAddress;
    }
    return (await signer.owner()).address;
  }

  GnosisCardProduct _requireSelectedProduct(GnosisCardKind kind) {
    final product = _snapshot.progress.selectedProduct;
    if (product == null || product.kind != kind) {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.invalidTransition,
        message: 'Select the matching card product before continuing.',
        recovery: GnosisCardRecovery.retry,
      );
    }
    return product;
  }

  PhysicalCardOrder _requirePhysicalOrder() {
    final order = _snapshot.progress.physicalOrder;
    if (order == null) {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.invalidTransition,
        message: 'There is no physical-card order to update.',
        recovery: GnosisCardRecovery.retry,
      );
    }
    return order;
  }
}
