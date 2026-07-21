part of 'gnosis_card_flow_test.dart';

void _registerFlowRecoveryTests() {
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
    expect(harness.coordinator.snapshot.stage, GnosisOnboardingStage.signedOut);

    final snapshot = await harness.coordinator.signIn();
    expect(snapshot.stage, GnosisOnboardingStage.signupAndTerms);
    expect(harness.signer.personalMessageSignatures, 2);
  });

  test('changing the SIWE owner clears prior user-scoped mock state', () async {
    final repository = DeterministicGnosisPayRepository(
      scenario: GnosisCardScenario.happyPath,
    );
    const ownerA = '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    final challengeA = await repository.createSiweChallenge(
      ownerAddress: ownerA,
    );
    await repository.authenticate(
      challenge: challengeA,
      ownerAddress: ownerA,
      signature: '0xowner-a-signature',
    );
    await repository.signUp(email: 'owner.a@example.com');
    await repository.acceptTerms([
      for (final term in await repository.requiredTerms())
        GnosisTermAcceptance(id: term.id, version: term.version),
    ]);
    expect((await repository.onboardingProgress()).isRegistered, isTrue);

    const ownerB = '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    final challengeB = await repository.createSiweChallenge(
      ownerAddress: ownerB,
    );
    await repository.authenticate(
      challenge: challengeB,
      ownerAddress: ownerB,
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
  });

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

  test(
    'deployment failure remains provider-owned and routes to support',
    () async {
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
            GnosisCardRecovery.contactSupport,
          ),
        ),
      );
      expect(
        harness.coordinator.snapshot.deployment?.status,
        SafeDeploymentStatus.failed,
      );
      expect(harness.signer.registeredSafes, isEmpty);

      await expectLater(
        harness.coordinator.pollSafe(),
        throwsA(
          _failure(
            GnosisCardFailureCode.deploymentFailed,
            GnosisCardRecovery.contactSupport,
          ),
        ),
      );
      expect(
        harness.coordinator.snapshot.deployment?.status,
        SafeDeploymentStatus.failed,
      );
      expect(harness.signer.registeredSafes, isEmpty);
    },
  );

  test('integrity failure blocks registration and routes to support', () async {
    final harness = _FlowHarness(GnosisCardScenario.safeIntegrityFailure);
    await _completeIdentity(harness);
    await harness.coordinator.deploySafe();
    await harness.coordinator.pollSafe();

    await expectLater(
      harness.coordinator.pollSafe(),
      throwsA(
        _failure(
          GnosisCardFailureCode.safeIntegrityFailed,
          GnosisCardRecovery.contactSupport,
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
          GnosisCardRecovery.contactSupport,
        ),
      ),
    );
    expect(harness.signer.registeredSafes, isEmpty);

    expect(
      harness.coordinator.snapshot.safeConfiguration?.integrity,
      SafeAccountIntegrity.safeMisconfigured,
    );
    expect(harness.signer.registeredSafes, isEmpty);
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
        _failure(GnosisCardFailureCode.paymentFailed, GnosisCardRecovery.retry),
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
      PhysicalCardOrderStatus.cardCreated,
    );
    expect(snapshot.stage, GnosisOnboardingStage.physicalPin);
    expect(harness.payment.payments, 2);
  });

  test('issuance failure leaves virtual selection ready to retry', () async {
    final harness = _FlowHarness(GnosisCardScenario.issuanceFailure);
    await _completeCardAccount(harness);

    await expectLater(
      harness.coordinator.selectCardProduct('virtual-eur'),
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
}
