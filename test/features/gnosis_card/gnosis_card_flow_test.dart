import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:web_dex/features/gnosis_card/application/gnosis_card_coordinator.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_models.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_ports.dart';
import 'package:web_dex/features/gnosis_card/infrastructure/deterministic_gnosis_pay_repository.dart';
import 'package:web_dex/features/gnosis_card/infrastructure/gnosis_card_config.dart';

void main() {
  group('mock-first Gnosis card onboarding', () {
    test('derives and resumes the first incomplete step', () async {
      final harness = _FlowHarness(GnosisCardScenario.happyPath);

      var snapshot = await _completeAccountAndKyc(harness);
      expect(snapshot.stage, GnosisOnboardingStage.sourceOfFunds);
      expect(
        snapshot.progress.isMilestoneComplete(
          GnosisOnboardingMilestone.account,
        ),
        isTrue,
      );

      snapshot = await harness.coordinator.submitSourceOfFunds(
        _answersFor(snapshot.sourceOfFundsQuestions),
      );
      expect(snapshot.stage, GnosisOnboardingStage.phoneNumber);
      snapshot = await harness.coordinator.requestPhoneOtp('+49 151 23456789');
      expect(snapshot.stage, GnosisOnboardingStage.phoneOtp);

      final resumed = harness.newCoordinator();
      snapshot = await resumed.initialize();

      expect(snapshot.stage, GnosisOnboardingStage.phoneOtp);
      expect(snapshot.progress.isRegistered, isTrue);
      expect(snapshot.progress.areTermsAccepted, isTrue);
      expect(snapshot.kycStatus, GnosisKycStatus.approved);
      expect(snapshot.progress.isSourceOfFundsAnswered, isTrue);
      expect(snapshot.phoneChallenge?.phoneNumber, '+4915123456789');

      snapshot = await resumed.verifyPhoneOtp(
        snapshot.phoneChallenge!.demoCode!,
      );
      expect(snapshot.stage, GnosisOnboardingStage.safeDeployment);
    });

    test(
      'completes virtual onboarding, delayed intents, and Safe restart',
      () async {
        final harness = _FlowHarness(GnosisCardScenario.happyPath);
        var snapshot = await _completeCardAccount(harness);

        expect(snapshot.stage, GnosisOnboardingStage.cardSelection);
        expect(
          snapshot.cardProducts.map((product) => product.kind),
          containsAll(GnosisCardKind.values),
        );
        expect(harness.signer.registeredSafes, hasLength(1));

        snapshot = await harness.coordinator.selectCardProduct('virtual-eur');
        expect(snapshot.stage, GnosisOnboardingStage.virtualCardIssuance);
        snapshot = await harness.coordinator.issueVirtualCard();

        expect(snapshot.stage, GnosisOnboardingStage.ready);
        expect(snapshot.dashboard?.cards, hasLength(1));
        expect(snapshot.dashboard?.cards.single.kind, GnosisCardKind.virtual);

        snapshot = await harness.coordinator.prepareWithdrawal(
          WithdrawalRequest(
            assetContract: '0x3333333333333333333333333333333333333333',
            assetSymbol: 'USDC',
            recipient: '0x4444444444444444444444444444444444444444',
            amountAtomic: BigInt.from(1000000),
            decimals: 6,
          ),
        );
        expect(snapshot.reviewIntent?.kind, SmartAccountIntentKind.withdrawal);
        snapshot = await harness.coordinator.confirmPreparedIntent();

        snapshot = await harness.coordinator.prepareDailyLimit(
          DailyLimitRequest(
            bouncer: '0x5555555555555555555555555555555555555555',
            amountAtomic: BigInt.from(250000000),
            decimals: 6,
          ),
        );
        expect(snapshot.reviewIntent?.kind, SmartAccountIntentKind.dailyLimit);
        snapshot = await harness.coordinator.confirmPreparedIntent();

        expect(snapshot.dashboard?.operations, hasLength(2));
        expect(harness.signer.typedDataSignatures, 2);
        snapshot = await harness.coordinator.pollDelayedOperations();
        expect(
          snapshot.dashboard?.operations.map((operation) => operation.status),
          everyElement(DelayedOperationStatus.executable),
        );
        snapshot = await harness.coordinator.pollDelayedOperations();
        expect(
          snapshot.dashboard?.operations.map((operation) => operation.status),
          everyElement(DelayedOperationStatus.executed),
        );

        final restarted = harness.newCoordinator();
        snapshot = await restarted.initialize();
        expect(snapshot.stage, GnosisOnboardingStage.ready);
        expect(harness.signer.registeredSafes, hasLength(2));
      },
    );

    test('completes every physical-card onboarding step', () async {
      final harness = _FlowHarness(GnosisCardScenario.happyPath);
      var snapshot = await _completeCardAccount(harness);

      snapshot = await harness.coordinator.selectCardProduct('physical-eur');
      expect(snapshot.stage, GnosisOnboardingStage.physicalShipping);

      snapshot = await harness.coordinator.createPhysicalCardOrder(
        _shippingAddress,
      );
      expect(snapshot.stage, GnosisOnboardingStage.physicalOrderReview);
      expect(
        snapshot.progress.physicalOrder?.status,
        PhysicalCardOrderStatus.pendingTransaction,
      );

      snapshot = await harness.coordinator.confirmPhysicalOrderReview();
      expect(snapshot.stage, GnosisOnboardingStage.physicalPayment);
      expect(snapshot.paymentQuote?.isSimulated, isTrue);
      expect(snapshot.paymentQuote?.amountMinor, 999);

      snapshot = await harness.coordinator.payForPhysicalCard();
      expect(snapshot.stage, GnosisOnboardingStage.physicalPayment);
      expect(snapshot.paymentReceipt?.isSimulated, isTrue);
      expect(
        snapshot.progress.physicalOrder?.status,
        PhysicalCardOrderStatus.pendingTransaction,
      );
      final confirmationRequired = _withPhysicalOrderStatus(
        snapshot.progress,
        PhysicalCardOrderStatus.confirmationRequired,
      );
      expect(confirmationRequired.paymentReceipt, isNotNull);
      expect(
        confirmationRequired.nextStage,
        GnosisOnboardingStage.physicalPayment,
      );

      snapshot = await harness.coordinator.confirmPhysicalCardPayment();
      expect(snapshot.stage, GnosisOnboardingStage.physicalCardCreation);
      expect(
        snapshot.progress.physicalOrder?.status,
        PhysicalCardOrderStatus.ready,
      );

      snapshot = await harness.coordinator.createPhysicalCard();
      expect(snapshot.stage, GnosisOnboardingStage.physicalPin);
      expect(snapshot.provisioningHandle, isNotNull);
      expect(snapshot.provisioningHandle.toString(), contains('<redacted>'));
      expect(
        snapshot.progress.physicalOrder?.status,
        PhysicalCardOrderStatus.cardCreated,
      );

      snapshot = await harness.coordinator.completePinProvisioning();
      expect(snapshot.stage, GnosisOnboardingStage.ready);
      expect(snapshot.provisioningHandle, isNull);
      expect(snapshot.progress.isPinProvisioned, isTrue);
      expect(snapshot.dashboard?.cards.single.kind, GnosisCardKind.physical);
      expect(harness.payment.payments, 1);
    });

    test(
      'edit preserves shipping while cancel exits the physical flow',
      () async {
        final editHarness = _FlowHarness(GnosisCardScenario.happyPath);
        var snapshot = await _createPhysicalOrderForReview(editHarness);
        final originalAddress =
            snapshot.progress.physicalOrder!.shippingAddress;

        snapshot = await editHarness.coordinator.editPhysicalCardOrder();

        expect(snapshot.stage, GnosisOnboardingStage.physicalShipping);
        expect(
          snapshot.progress.selectedProduct?.kind,
          GnosisCardKind.physical,
        );
        expect(
          snapshot.progress.physicalOrder?.status,
          PhysicalCardOrderStatus.cancelled,
        );
        expect(
          snapshot.progress.physicalOrder?.shippingAddress,
          originalAddress,
        );

        final cancelHarness = _FlowHarness(GnosisCardScenario.happyPath);
        await _createPhysicalOrderForReview(cancelHarness);
        snapshot = await cancelHarness.coordinator.cancelPhysicalCardOrder();

        expect(snapshot.stage, GnosisOnboardingStage.cardSelection);
        expect(snapshot.progress.selectedProduct, isNull);
        expect(
          snapshot.progress.physicalOrder?.status,
          PhysicalCardOrderStatus.cancelled,
        );

        final dashboardHarness = _FlowHarness(GnosisCardScenario.happyPath);
        await _completeCardAccount(dashboardHarness);
        await dashboardHarness.coordinator.selectCardProduct('virtual-eur');
        snapshot = await dashboardHarness.coordinator.issueVirtualCard();
        expect(snapshot.stage, GnosisOnboardingStage.ready);
        await dashboardHarness.coordinator.selectCardProduct('physical-eur');
        await dashboardHarness.coordinator.createPhysicalCardOrder(
          _shippingAddress,
        );
        snapshot = await dashboardHarness.coordinator.cancelPhysicalCardOrder();

        expect(snapshot.stage, GnosisOnboardingStage.ready);
        expect(snapshot.progress.selectedProduct, isNull);
        expect(snapshot.dashboard?.cards.single.kind, GnosisCardKind.virtual);
      },
    );

    test(
      'recovers from KYC resubmission by reopening the external flow',
      () async {
        final harness = _FlowHarness(GnosisCardScenario.kycResubmission);
        await _completeAccount(harness);

        await _launchKyc(harness);
        var snapshot = await harness.coordinator.refreshKyc();
        expect(snapshot.stage, GnosisOnboardingStage.kyc);
        expect(snapshot.kycStatus, GnosisKycStatus.resubmissionRequested);

        await _launchKyc(harness);
        snapshot = await harness.coordinator.refreshKyc();
        expect(snapshot.kycStatus, GnosisKycStatus.approved);
        expect(snapshot.stage, GnosisOnboardingStage.sourceOfFunds);
        expect(harness.launcher.launched.map((flow) => flow.kind), [
          GnosisExternalFlowKind.kyc,
          GnosisExternalFlowKind.kyc,
        ]);
      },
    );

    for (final scenario in [
      GnosisCardScenario.kycRejected,
      GnosisCardScenario.kycRequiresAction,
    ]) {
      test('${scenario.name} stays recoverable through support', () async {
        final harness = _FlowHarness(scenario);
        await _completeAccount(harness);
        await _launchKyc(harness);

        final snapshot = await harness.coordinator.refreshKyc();
        final expectedStatus = scenario == GnosisCardScenario.kycRejected
            ? GnosisKycStatus.rejected
            : GnosisKycStatus.requiresAction;
        expect(snapshot.stage, GnosisOnboardingStage.kyc);
        expect(snapshot.kycStatus, expectedStatus);

        final support = await harness.coordinator.supportFlow();
        await harness.launcher.launch(support);
        expect(
          harness.launcher.launched.last.kind,
          GnosisExternalFlowKind.support,
        );
      });
    }

    test('expired authentication requires reauth and then resumes', () async {
      final harness = _FlowHarness(GnosisCardScenario.expiredSession);
      await harness.coordinator.initialize();

      await expectLater(
        harness.coordinator.signIn(),
        throwsA(
          _failure(
            GnosisCardFailureCode.sessionExpired,
            GnosisCardRecovery.reauthenticate,
          ),
        ),
      );
      expect(
        harness.coordinator.snapshot.stage,
        GnosisOnboardingStage.signedOut,
      );

      final snapshot = await harness.coordinator.signIn();
      expect(snapshot.stage, GnosisOnboardingStage.signupAndTerms);
      expect(harness.signer.personalMessageSignatures, 2);
    });

    test(
      'changing the SIWE owner clears prior user-scoped mock state',
      () async {
        final repository = DeterministicGnosisPayRepository(
          scenario: GnosisCardScenario.happyPath,
        );
        await repository.authenticate(
          ownerAddress: '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          signature: '0xowner-a-signature',
        );
        await repository.signUp(email: 'owner.a@example.com');
        await repository.acceptTerms([
          for (final term in await repository.requiredTerms())
            GnosisTermAcceptance(id: term.id, version: term.version),
        ]);
        expect((await repository.onboardingProgress()).isRegistered, isTrue);

        await repository.authenticate(
          ownerAddress: '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          signature: '0xowner-b-signature',
        );
        final progress = await repository.onboardingProgress();

        expect(progress.isAuthenticated, isTrue);
        expect(progress.isRegistered, isFalse);
        expect(progress.email, isNull);
        expect(progress.areTermsAccepted, isFalse);
        expect(progress.safeConfiguration, isNull);
        expect(progress.cards, isEmpty);
        expect(progress.nextStage, GnosisOnboardingStage.signupAndTerms);
      },
    );

    test('invalid phone code preserves the challenge and can retry', () async {
      final harness = _FlowHarness(GnosisCardScenario.invalidOtp);
      var snapshot = await _reachPhoneOtp(harness);
      final demoCode = snapshot.phoneChallenge!.demoCode!;

      await expectLater(
        harness.coordinator.verifyPhoneOtp(demoCode),
        throwsA(
          _failure(
            GnosisCardFailureCode.invalidOtp,
            GnosisCardRecovery.editInput,
          ),
        ),
      );

      snapshot = await harness.coordinator.initialize();
      expect(snapshot.stage, GnosisOnboardingStage.phoneOtp);
      expect(snapshot.phoneChallenge?.attemptsRemaining, 2);
      snapshot = await harness.coordinator.verifyPhoneOtp(demoCode);
      expect(snapshot.stage, GnosisOnboardingStage.safeDeployment);
    });

    test('deployment failure resets before a successful retry', () async {
      final harness = _FlowHarness(GnosisCardScenario.deploymentFailure);
      await _completeIdentity(harness);

      var snapshot = await harness.coordinator.deploySafe();
      expect(snapshot.deployment?.status, SafeDeploymentStatus.accepted);
      snapshot = await harness.coordinator.pollSafe();
      expect(snapshot.deployment?.status, SafeDeploymentStatus.processing);

      await expectLater(
        harness.coordinator.pollSafe(),
        throwsA(
          _failure(
            GnosisCardFailureCode.deploymentFailed,
            GnosisCardRecovery.resetSafe,
          ),
        ),
      );
      expect(
        harness.coordinator.snapshot.deployment?.status,
        SafeDeploymentStatus.failed,
      );
      expect(harness.signer.registeredSafes, isEmpty);

      snapshot = await harness.coordinator.resetSafe();
      expect(snapshot.deployment, isNull);
      await harness.coordinator.deploySafe();
      await harness.coordinator.pollSafe();
      snapshot = await harness.coordinator.pollSafe();
      expect(snapshot.stage, GnosisOnboardingStage.cardSelection);
      expect(harness.signer.registeredSafes, hasLength(1));
    });

    test('integrity failure blocks registration until Safe reset', () async {
      final harness = _FlowHarness(GnosisCardScenario.safeIntegrityFailure);
      await _completeIdentity(harness);
      await harness.coordinator.deploySafe();
      await harness.coordinator.pollSafe();

      await expectLater(
        harness.coordinator.pollSafe(),
        throwsA(
          _failure(
            GnosisCardFailureCode.safeIntegrityFailed,
            GnosisCardRecovery.resetSafe,
          ),
        ),
      );
      expect(
        harness.coordinator.snapshot.safeConfiguration?.integrity,
        SafeAccountIntegrity.safeMisconfigured,
      );
      expect(harness.signer.registeredSafes, isEmpty);

      await expectLater(
        harness.coordinator.pollSafe(),
        throwsA(
          _failure(
            GnosisCardFailureCode.safeIntegrityFailed,
            GnosisCardRecovery.resetSafe,
          ),
        ),
      );
      expect(harness.signer.registeredSafes, isEmpty);

      await harness.coordinator.resetSafe();
      await harness.coordinator.deploySafe();
      await harness.coordinator.pollSafe();
      final snapshot = await harness.coordinator.pollSafe();
      expect(snapshot.safeConfiguration?.integrity, SafeAccountIntegrity.ok);
      expect(snapshot.stage, GnosisOnboardingStage.cardSelection);
      expect(harness.signer.registeredSafes, hasLength(1));
    });

    test('payment failure preserves the physical order for retry', () async {
      final harness = _FlowHarness(GnosisCardScenario.paymentFailure);
      await _completeCardAccount(harness);
      await harness.coordinator.selectCardProduct('physical-eur');
      await harness.coordinator.createPhysicalCardOrder(_shippingAddress);
      await harness.coordinator.confirmPhysicalOrderReview();

      await expectLater(
        harness.coordinator.payForPhysicalCard(),
        throwsA(
          _failure(
            GnosisCardFailureCode.paymentFailed,
            GnosisCardRecovery.retry,
          ),
        ),
      );
      expect(
        harness.coordinator.snapshot.progress.physicalOrder?.status,
        PhysicalCardOrderStatus.pendingTransaction,
      );
      expect(harness.coordinator.snapshot.paymentReceipt, isNull);

      final snapshot = await harness.coordinator.payForPhysicalCard();
      expect(snapshot.paymentReceipt, isNotNull);
      expect(
        snapshot.progress.physicalOrder?.status,
        PhysicalCardOrderStatus.pendingTransaction,
      );
      expect(harness.payment.payments, 2);
    });

    test('issuance failure leaves virtual selection ready to retry', () async {
      final harness = _FlowHarness(GnosisCardScenario.issuanceFailure);
      await _completeCardAccount(harness);
      await harness.coordinator.selectCardProduct('virtual-eur');

      await expectLater(
        harness.coordinator.issueVirtualCard(),
        throwsA(
          _failure(
            GnosisCardFailureCode.issuanceFailed,
            GnosisCardRecovery.retry,
          ),
        ),
      );
      expect(
        harness.coordinator.snapshot.stage,
        GnosisOnboardingStage.virtualCardIssuance,
      );
      expect(harness.coordinator.snapshot.progress.cards, isEmpty);

      final snapshot = await harness.coordinator.issueVirtualCard();
      expect(snapshot.stage, GnosisOnboardingStage.ready);
      expect(snapshot.dashboard?.cards.single.kind, GnosisCardKind.virtual);
    });

    test('offline initialization exposes a typed retryable failure', () async {
      final harness = _FlowHarness(GnosisCardScenario.offline);

      await expectLater(
        harness.coordinator.initialize(),
        throwsA(
          _failure(GnosisCardFailureCode.offline, GnosisCardRecovery.retry),
        ),
      );

      final snapshot = await harness.coordinator.initialize();
      expect(snapshot.stage, GnosisOnboardingStage.signedOut);
    });
  });
}

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

GnosisOnboardingProgress _withPhysicalOrderStatus(
  GnosisOnboardingProgress progress,
  PhysicalCardOrderStatus status,
) => GnosisOnboardingProgress(
  isAuthenticated: progress.isAuthenticated,
  isRegistered: progress.isRegistered,
  email: progress.email,
  countryCode: progress.countryCode,
  terms: progress.terms,
  kycStatus: progress.kycStatus,
  isSourceOfFundsAnswered: progress.isSourceOfFundsAnswered,
  phoneNumber: progress.phoneNumber,
  isPhoneValidated: progress.isPhoneValidated,
  phoneChallenge: progress.phoneChallenge,
  safeDeployment: progress.safeDeployment,
  safeConfiguration: progress.safeConfiguration,
  isSafeRegistered: progress.isSafeRegistered,
  selectedProduct: progress.selectedProduct,
  physicalOrder: progress.physicalOrder!.copyWith(status: status),
  isPhysicalOrderReviewed: progress.isPhysicalOrderReviewed,
  paymentReceipt: progress.paymentReceipt,
  provisioningHandle: progress.provisioningHandle,
  isPinProvisioned: progress.isPinProvisioned,
  cards: progress.cards,
);

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
  Future<void> registerSafe(String safeAddress) async {
    registeredSafes.add(safeAddress);
  }

  @override
  Future<String> signPersonalMessage(String message) async {
    personalMessageSignatures += 1;
    return 'test-eip191-signature';
  }

  @override
  Future<SmartAccountSignature> signTypedData(
    PreparedSmartAccountIntent intent,
  ) async {
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

  @override
  Future<CardOrderPaymentReceipt> pay(CardOrderPaymentQuote quote) async {
    payments += 1;
    return CardOrderPaymentReceipt(
      orderId: quote.orderId,
      transactionHash:
          '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      amountMinor: quote.amountMinor,
      currency: quote.currency,
      paidAt: DateTime.utc(2026, 7, 10, 12),
      isSimulated: true,
    );
  }
}
