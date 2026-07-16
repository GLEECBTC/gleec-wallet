part of 'gnosis_card_preview.dart';

GnosisCardState _previewState(GnosisCardPreviewFixture fixture) {
  final snapshot = _previewSnapshot(fixture);
  if (fixture == GnosisCardPreviewFixture.preparing) {
    return GnosisCardState(
      status: GnosisCardLoadStatus.ready,
      snapshot: snapshot,
      busyActions: const {GnosisCardAction.initialize},
      automationPhase: GnosisCardAutomationPhase.preparingWallet,
      isForeground: true,
    );
  }
  if (fixture == GnosisCardPreviewFixture.walletApproval) {
    return GnosisCardState(
      status: GnosisCardLoadStatus.ready,
      snapshot: snapshot,
      automationPhase: GnosisCardAutomationPhase.awaitingSignature,
      intervention: GnosisCardIntervention.walletApproval,
      isForeground: true,
    );
  }
  if (fixture == GnosisCardPreviewFixture.dashboardOffline) {
    return GnosisCardState(
      status: GnosisCardLoadStatus.ready,
      snapshot: snapshot,
      failure: const GnosisCardFailure(
        code: GnosisCardFailureCode.offline,
        message: 'Card services are offline.',
        recovery: GnosisCardRecovery.retry,
      ),
      failedAction: GnosisCardAction.initialize,
      lastUpdatedAt: DateTime(2026, 7, 16, 12),
    );
  }
  if (fixture == GnosisCardPreviewFixture.safeFailure) {
    return GnosisCardState(
      status: GnosisCardLoadStatus.ready,
      snapshot: snapshot,
      message: 'The API could not complete Safe deployment.',
      failure: const GnosisCardFailure(
        code: GnosisCardFailureCode.deploymentFailed,
        message: 'The API could not complete Safe deployment.',
        recovery: GnosisCardRecovery.contactSupport,
      ),
      failedAction: GnosisCardAction.pollSafe,
    );
  }
  if (fixture == GnosisCardPreviewFixture.safeIntegrityFailure) {
    return GnosisCardState(
      status: GnosisCardLoadStatus.ready,
      snapshot: snapshot,
      failure: const GnosisCardFailure(
        code: GnosisCardFailureCode.safeIntegrityFailed,
        message: 'The returned Safe configuration failed integrity checks.',
        recovery: GnosisCardRecovery.contactSupport,
      ),
      failedAction: GnosisCardAction.pollSafe,
    );
  }
  return GnosisCardState(
    status: GnosisCardLoadStatus.ready,
    snapshot: snapshot,
  );
}

GnosisCardSnapshot _previewSnapshot(GnosisCardPreviewFixture fixture) {
  final stage = _stageForFixture(fixture);
  final kycStatus = _kycForFixture(fixture);
  final accountComplete =
      stage != GnosisOnboardingStage.signedOut &&
      stage != GnosisOnboardingStage.signupAndTerms;
  final identityComplete = _identityComplete(stage);
  final safeComplete = _safeComplete(stage);
  final physical = _isPhysicalStage(stage);
  final virtual = stage == GnosisOnboardingStage.virtualCardIssuance;
  final order = _orderFor(stage);
  final receipt = _receiptFor(stage, order);
  final card = _cardFor(stage, fixture);
  final safeStatus = fixture == GnosisCardPreviewFixture.safeAccepted
      ? SafeDeploymentStatus.accepted
      : fixture == GnosisCardPreviewFixture.safeFailure
      ? SafeDeploymentStatus.failed
      : fixture == GnosisCardPreviewFixture.safeTimeout
      ? SafeDeploymentStatus.timedOut
      : fixture == GnosisCardPreviewFixture.safeIntegrityFailure
      ? SafeDeploymentStatus.ok
      : SafeDeploymentStatus.processing;
  final progress = GnosisOnboardingProgress(
    isAuthenticated: stage != GnosisOnboardingStage.signedOut,
    isRegistered:
        stage != GnosisOnboardingStage.signedOut &&
        stage != GnosisOnboardingStage.signupAndTerms,
    email: stage == GnosisOnboardingStage.signedOut ? null : 'alex@example.com',
    countryCode: 'DE',
    phoneCountryCallingCode: '+49',
    verifiedShippingAddress: identityComplete ? _previewAddress : null,
    terms: _previewTerms(accepted: accountComplete),
    kycStatus: kycStatus,
    isSourceOfFundsAnswered:
        identityComplete ||
        stage == GnosisOnboardingStage.phoneNumber ||
        stage == GnosisOnboardingStage.phoneOtp,
    phoneNumber: stage == GnosisOnboardingStage.phoneOtp || identityComplete
        ? '+4915123456789'
        : null,
    isPhoneValidated: identityComplete,
    phoneChallenge: stage == GnosisOnboardingStage.phoneOtp
        ? PhoneOtpChallenge(
            id: 'preview-otp',
            phoneNumber: '+4915123456789',
            expiresAt: DateTime.now().add(const Duration(minutes: 10)),
            resendAvailableAt: DateTime.now().add(const Duration(seconds: 45)),
            attemptsRemaining: 3,
            demoCode: '123456',
          )
        : null,
    safeDeployment: stage == GnosisOnboardingStage.safeDeployment
        ? SafeDeployment(
            requestId: 'preview-deployment',
            ownerAddress: _previewOwner,
            status: safeStatus,
            updatedAt: DateTime(2026, 7, 14, 12),
            failureReason: safeStatus == SafeDeploymentStatus.failed
                ? 'The API could not complete Safe deployment.'
                : null,
          )
        : safeComplete
        ? _previewDeploymentOk
        : null,
    safeConfiguration: fixture == GnosisCardPreviewFixture.safeIntegrityFailure
        ? _previewInvalidSafeConfiguration
        : fixture == GnosisCardPreviewFixture.migration
        ? _previewMigratedSafeConfiguration
        : safeComplete
        ? _previewSafeConfiguration
        : null,
    isSafeRegistered: safeComplete,
    selectedProduct: physical
        ? _physicalProduct
        : virtual
        ? _virtualProduct
        : stage == GnosisOnboardingStage.ready
        ? card?.kind == GnosisCardKind.physical
              ? _physicalProduct
              : _virtualProduct
        : null,
    physicalOrder: order,
    isPhysicalOrderReviewed:
        order != null && stage != GnosisOnboardingStage.physicalOrderReview,
    paymentReceipt: receipt,
    provisioningHandle: stage == GnosisOnboardingStage.physicalPin
        ? const CardProvisioningHandle(
            orderId: 'preview-order',
            cardId: 'preview-physical-card',
            value: 'opaque-preview-capability',
          )
        : null,
    isPinProvisioned: false,
    cards: card == null ? const [] : [card],
  );
  return GnosisCardSnapshot(
    progress: progress,
    sourceOfFundsQuestions: stage == GnosisOnboardingStage.sourceOfFunds
        ? _sourceQuestions
        : const [],
    cardProducts: safeComplete
        ? const [_virtualProduct, _physicalProduct]
        : const [],
    paymentQuote: stage == GnosisOnboardingStage.physicalPayment
        ? _previewQuote
        : null,
    dashboard: stage == GnosisOnboardingStage.ready
        ? _dashboardForFixture(fixture, card!)
        : null,
    siweChallenge: fixture == GnosisCardPreviewFixture.walletApproval
        ? _previewSiweChallenge
        : null,
    safeMigration: fixture == GnosisCardPreviewFixture.migration
        ? _previewMigration
        : const GnosisSafeMigration.none(),
  );
}

GnosisOnboardingStage _stageForFixture(
  GnosisCardPreviewFixture fixture,
) => switch (fixture) {
  GnosisCardPreviewFixture.discovery ||
  GnosisCardPreviewFixture.preparing ||
  GnosisCardPreviewFixture.walletApproval => GnosisOnboardingStage.signedOut,
  GnosisCardPreviewFixture.signupAndTerms =>
    GnosisOnboardingStage.signupAndTerms,
  GnosisCardPreviewFixture.kycNotStarted ||
  GnosisCardPreviewFixture.kycDocumentsRequested ||
  GnosisCardPreviewFixture.kycPending ||
  GnosisCardPreviewFixture.kycProcessing ||
  GnosisCardPreviewFixture.kycResubmission ||
  GnosisCardPreviewFixture.kycRejected ||
  GnosisCardPreviewFixture.kycRequiresAction => GnosisOnboardingStage.kyc,
  GnosisCardPreviewFixture.sourceOfFunds => GnosisOnboardingStage.sourceOfFunds,
  GnosisCardPreviewFixture.phoneNumber => GnosisOnboardingStage.phoneNumber,
  GnosisCardPreviewFixture.phoneOtp => GnosisOnboardingStage.phoneOtp,
  GnosisCardPreviewFixture.safeAccepted ||
  GnosisCardPreviewFixture.safeProcessing ||
  GnosisCardPreviewFixture.safeFailure ||
  GnosisCardPreviewFixture.safeTimeout ||
  GnosisCardPreviewFixture.safeIntegrityFailure =>
    GnosisOnboardingStage.safeDeployment,
  GnosisCardPreviewFixture.cardSelection => GnosisOnboardingStage.cardSelection,
  GnosisCardPreviewFixture.virtualIssuance =>
    GnosisOnboardingStage.virtualCardIssuance,
  GnosisCardPreviewFixture.physicalShipping =>
    GnosisOnboardingStage.physicalShipping,
  GnosisCardPreviewFixture.physicalReview =>
    GnosisOnboardingStage.physicalOrderReview,
  GnosisCardPreviewFixture.physicalPayment =>
    GnosisOnboardingStage.physicalPayment,
  GnosisCardPreviewFixture.physicalCreation =>
    GnosisOnboardingStage.physicalCardCreation,
  GnosisCardPreviewFixture.physicalPin => GnosisOnboardingStage.physicalPin,
  GnosisCardPreviewFixture.dashboard ||
  GnosisCardPreviewFixture.dashboardOffline ||
  GnosisCardPreviewFixture.dashboardEmpty ||
  GnosisCardPreviewFixture.dashboardOrdered ||
  GnosisCardPreviewFixture.dashboardShipped ||
  GnosisCardPreviewFixture.dashboardActivatable ||
  GnosisCardPreviewFixture.dashboardFrozen ||
  GnosisCardPreviewFixture.dashboardLost ||
  GnosisCardPreviewFixture.dashboardStolen ||
  GnosisCardPreviewFixture.dashboardVoided ||
  GnosisCardPreviewFixture.migration => GnosisOnboardingStage.ready,
};
