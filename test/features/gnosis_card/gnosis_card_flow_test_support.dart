part of 'gnosis_card_flow_test.dart';

Future<GnosisCardSnapshot> _completeAccount(_FlowHarness harness) async {
  var snapshot = await harness.coordinator.initialize();
  expect(snapshot.stage, GnosisOnboardingStage.signedOut);

  snapshot = await harness.coordinator.signIn();
  expect(snapshot.stage, GnosisOnboardingStage.signupAndTerms);
  final acceptances = [
    for (final term in snapshot.terms)
      GnosisTermAcceptance(id: term.id, version: term.version),
  ];
  snapshot = await harness.coordinator.signUpAndAcceptTerms(
    email: 'card.user@example.com',
    acceptances: acceptances,
  );
  expect(snapshot.stage, GnosisOnboardingStage.kyc);
  return snapshot;
}

Future<GnosisExternalFlow> _launchKyc(_FlowHarness harness) async {
  final flow = await harness.coordinator.kycFlow();
  await harness.coordinator.externalFlowLauncher.launch(flow);
  expect(flow.kind, GnosisExternalFlowKind.kyc);
  expect(harness.launcher.launched.last, flow);
  return flow;
}

Future<GnosisCardSnapshot> _completeAccountAndKyc(_FlowHarness harness) async {
  await _completeAccount(harness);
  await _launchKyc(harness);

  final pending = await harness.repository.onboardingProgress();
  expect(pending.kycStatus, GnosisKycStatus.pending);
  var snapshot = await harness.coordinator.refreshKyc();
  expect(snapshot.kycStatus, GnosisKycStatus.processing);
  expect(snapshot.stage, GnosisOnboardingStage.kyc);
  snapshot = await harness.coordinator.refreshKyc();
  expect(snapshot.kycStatus, GnosisKycStatus.approved);
  expect(snapshot.stage, GnosisOnboardingStage.sourceOfFunds);
  return snapshot;
}

Future<GnosisCardSnapshot> _reachPhoneOtp(_FlowHarness harness) async {
  var snapshot = await _completeAccountAndKyc(harness);
  snapshot = await harness.coordinator.submitSourceOfFunds(
    _answersFor(snapshot.sourceOfFundsQuestions),
  );
  expect(snapshot.stage, GnosisOnboardingStage.phoneNumber);
  snapshot = await harness.coordinator.requestPhoneOtp('+4915123456789');
  expect(snapshot.stage, GnosisOnboardingStage.phoneOtp);
  expect(snapshot.phoneChallenge?.demoCode, isNotNull);
  return snapshot;
}

Future<GnosisCardSnapshot> _completeIdentity(_FlowHarness harness) async {
  var snapshot = await _reachPhoneOtp(harness);
  snapshot = await harness.coordinator.verifyPhoneOtp(
    snapshot.phoneChallenge!.demoCode!,
  );
  expect(snapshot.stage, GnosisOnboardingStage.safeDeployment);
  expect(
    snapshot.progress.isMilestoneComplete(GnosisOnboardingMilestone.identity),
    isTrue,
  );
  return snapshot;
}

Future<GnosisCardSnapshot> _completeCardAccount(_FlowHarness harness) async {
  await _completeIdentity(harness);
  var snapshot = await harness.coordinator.deploySafe();
  expect(snapshot.deployment?.status, SafeDeploymentStatus.accepted);
  expect(harness.signer.registeredSafes, isEmpty);

  snapshot = await harness.coordinator.pollSafe();
  expect(snapshot.deployment?.status, SafeDeploymentStatus.processing);
  expect(harness.signer.registeredSafes, isEmpty);

  snapshot = await harness.coordinator.pollSafe();
  expect(snapshot.deployment?.status, SafeDeploymentStatus.ok);
  expect(snapshot.safeConfiguration?.integrity, SafeAccountIntegrity.ok);
  expect(snapshot.stage, GnosisOnboardingStage.cardSelection);
  expect(
    snapshot.progress.isMilestoneComplete(
      GnosisOnboardingMilestone.cardAccount,
    ),
    isTrue,
  );
  expect(harness.signer.registeredSafes, hasLength(1));
  return snapshot;
}

Future<GnosisCardSnapshot> _createPhysicalOrderForReview(
  _FlowHarness harness,
) async {
  await _completeCardAccount(harness);
  await harness.coordinator.selectCardProduct('physical-eur');
  final snapshot = await harness.coordinator.createPhysicalCardOrder(
    _shippingAddress,
  );
  expect(snapshot.stage, GnosisOnboardingStage.physicalOrderReview);
  return snapshot;
}

List<SourceOfFundsAnswer> _answersFor(List<SourceOfFundsQuestion> questions) =>
    [
      for (final question in questions)
        SourceOfFundsAnswer(
          questionId: question.id,
          question: question.title,
          answer: question.answers.first,
        ),
    ];

Matcher _failure(GnosisCardFailureCode code, GnosisCardRecovery recovery) =>
    isA<GnosisCardFailure>()
        .having((failure) => failure.code, 'code', code)
        .having((failure) => failure.recovery, 'recovery', recovery);

const _shippingAddress = ShippingAddress(
  recipientName: 'Test Cardholder',
  address1: '1 Mock Street',
  city: 'Berlin',
  postalCode: '10115',
  country: 'DE',
);

class _FlowHarness {
  factory _FlowHarness(GnosisCardScenario scenario) {
    final repository = DeterministicGnosisPayRepository(scenario: scenario);
    final signer = _TestSigner();
    final launcher = _TestExternalFlowLauncher();
    final payment = _TestPaymentGateway();
    return _FlowHarness._(
      repository: repository,
      signer: signer,
      launcher: launcher,
      payment: payment,
    );
  }

  _FlowHarness._({
    required this.repository,
    required this.signer,
    required this.launcher,
    required this.payment,
  }) : coordinator = GnosisCardCoordinator(
         repository: repository,
         signer: signer,
         externalFlowLauncher: launcher,
         paymentGateway: payment,
       );

  final DeterministicGnosisPayRepository repository;
  final _TestSigner signer;
  final _TestExternalFlowLauncher launcher;
  final _TestPaymentGateway payment;
  final GnosisCardCoordinator coordinator;

  GnosisCardCoordinator newCoordinator() => GnosisCardCoordinator(
    repository: repository,
    signer: signer,
    externalFlowLauncher: launcher,
    paymentGateway: payment,
  );
}

class _TestSigner implements SmartAccountSigner {
  final List<String> registeredSafes = [];
  int personalMessageSignatures = 0;
  int typedDataSignatures = 0;

  @override
  Future<SmartAccountOwner> owner() async => const SmartAccountOwner(
    address: '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    coin: 'GNO',
  );

  @override
  Future<void> registerSafe(
    String safeAddress, {
    required SmartAccountOwner expectedOwner,
  }) async {
    registeredSafes.add(safeAddress);
  }

  @override
  Future<String> signPersonalMessage(
    String message, {
    required SmartAccountOwner expectedOwner,
  }) async {
    personalMessageSignatures += 1;
    return 'test-eip191-${message.hashCode}';
  }

  @override
  Future<SmartAccountSignature> signTypedData(
    PreparedSmartAccountIntent intent, {
    required SmartAccountOwner expectedOwner,
  }) async {
    typedDataSignatures += 1;
    return const SmartAccountSignature(
      signature: 'test-eip712-signature',
      typedDataHash:
          '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      ownerAddress: '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
  }
}

class _TestExternalFlowLauncher implements ExternalFlowLauncher {
  final List<GnosisExternalFlow> launched = [];

  @override
  Future<void> launch(GnosisExternalFlow flow) async {
    launched.add(flow);
  }
}

class _TestPaymentGateway implements CardOrderPaymentGateway {
  int payments = 0;
  final Map<String, CardOrderPaymentReceipt> _receipts = {};

  @override
  Future<CardOrderPaymentReceipt?> findPayment({
    required CardOrderPaymentQuote quote,
    required String idempotencyKey,
  }) async => _receipts[idempotencyKey];

  @override
  Future<CardOrderPaymentReceipt> pay(
    CardOrderPaymentQuote quote, {
    required String idempotencyKey,
  }) async {
    final existing = _receipts[idempotencyKey];
    if (existing != null) return existing;
    payments += 1;
    final receipt = CardOrderPaymentReceipt(
      orderId: quote.orderId,
      transactionHash:
          '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      amountMinor: quote.amountMinor,
      currency: quote.currency,
      paidAt: DateTime.utc(2026, 7, 10, 12),
      isSimulated: true,
    );
    _receipts[idempotencyKey] = receipt;
    return receipt;
  }
}
