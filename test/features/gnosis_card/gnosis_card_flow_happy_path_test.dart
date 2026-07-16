part of 'gnosis_card_flow_test.dart';

void _registerHappyPathFlowTests() {
  test('derives and resumes the first incomplete step', () async {
    final harness = _FlowHarness(GnosisCardScenario.happyPath);

    var snapshot = await _completeAccountAndKyc(harness);
    expect(snapshot.stage, GnosisOnboardingStage.sourceOfFunds);
    expect(
      snapshot.progress.isMilestoneComplete(GnosisOnboardingMilestone.account),
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

    snapshot = await resumed.verifyPhoneOtp(snapshot.phoneChallenge!.demoCode!);
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
    expect(snapshot.stage, GnosisOnboardingStage.physicalPin);
    expect(snapshot.paymentReceipt?.isSimulated, isTrue);
    expect(
      snapshot.progress.physicalOrder?.status,
      PhysicalCardOrderStatus.cardCreated,
    );
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
      final originalAddress = snapshot.progress.physicalOrder!.shippingAddress;

      snapshot = await editHarness.coordinator.editPhysicalCardOrder();

      expect(snapshot.stage, GnosisOnboardingStage.physicalShipping);
      expect(snapshot.progress.selectedProduct?.kind, GnosisCardKind.physical);
      expect(
        snapshot.progress.physicalOrder?.status,
        PhysicalCardOrderStatus.cancelled,
      );
      expect(snapshot.progress.physicalOrder?.shippingAddress, originalAddress);

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
}
