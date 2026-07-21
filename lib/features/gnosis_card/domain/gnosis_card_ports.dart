import 'package:flutter/widgets.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_models.dart';

class SmartAccountOwner {
  const SmartAccountOwner({
    required this.address,
    required this.coin,
    this.derivationPath,
  });

  final String address;
  final String coin;
  final String? derivationPath;
}

class SmartAccountSignature {
  const SmartAccountSignature({
    required this.signature,
    required this.typedDataHash,
    required this.ownerAddress,
  });

  final String signature;
  final String typedDataHash;
  final String ownerAddress;
}

abstract interface class GnosisWalletReadiness {
  Future<SmartAccountOwner> ensureReady();
  void invalidate();
}

abstract interface class GnosisWalletIdentitySource {
  Future<String?> currentWalletId();
  Stream<String?> watchWalletId();
}

abstract interface class GnosisMigrationNoticeStore {
  Future<bool> isDismissed({
    required String walletIdentity,
    required String migrationId,
  });

  Future<void> dismiss({
    required String walletIdentity,
    required String migrationId,
  });
}

abstract interface class SmartAccountSigner {
  Future<SmartAccountOwner> owner();
  Future<String> signPersonalMessage(
    String message, {
    required SmartAccountOwner expectedOwner,
  });
  Future<void> registerSafe(
    String safeAddress, {
    required SmartAccountOwner expectedOwner,
  });
  Future<SmartAccountSignature> signTypedData(
    PreparedSmartAccountIntent intent, {
    required SmartAccountOwner expectedOwner,
  });
}

abstract interface class GnosisPayRepository {
  Future<GnosisOnboardingProgress> onboardingProgress();

  /// Compatibility view; implementations must derive this from progress.
  Future<GnosisOnboardingStage> onboardingStage();

  Future<GnosisSiweChallenge> createSiweChallenge({
    required String ownerAddress,
  });

  /// Temporary compatibility surface for older harness callers.
  @Deprecated('Use createSiweChallenge')
  Future<String> createSiweMessage({required String ownerAddress});

  Future<GnosisCardSession> authenticate({
    required GnosisSiweChallenge challenge,
    required String ownerAddress,
    required String signature,
  });

  /// Restores an existing provider session only when it belongs to [ownerAddress].
  Future<GnosisCardSession?> currentSession({required String ownerAddress});

  /// Clears local credentials and outstanding approvals after the wallet
  /// identity changes without discarding server-derived onboarding progress.
  void invalidateSession();

  Future<List<GnosisTerm>> requiredTerms();
  Future<void> signUp({required String email});
  Future<void> acceptTerms(List<GnosisTermAcceptance> acceptances);

  Future<GnosisExternalFlow> kycIntegration();
  Future<GnosisKycStatus> pollKyc();
  Future<GnosisExternalFlow> supportFlow();

  Future<List<SourceOfFundsQuestion>> sourceOfFundsQuestions();
  Future<void> submitSourceOfFunds(List<SourceOfFundsAnswer> answers);

  Future<PhoneOtpChallenge> requestPhoneOtp({required String phoneNumber});
  Future<PhoneOtpChallenge> resendPhoneOtp();
  Future<void> verifyPhoneOtp({required String code});
  Future<void> clearPhoneOtp();

  Future<SafeDeployment?> safeDeployment({required String ownerAddress});
  Future<SafeDeployment> requestSafeDeployment({required String ownerAddress});
  Future<SafeDeployment> pollSafeDeployment({required String ownerAddress});
  Future<SafeConfiguration> safeConfiguration({required String ownerAddress});
  Future<void> validateSafeIntegrity(SafeConfiguration configuration);

  Future<List<GnosisCardProduct>> cardProducts();
  Future<void> selectCardProduct({required String productId});
  Future<void> clearCardProductSelection();
  Future<GnosisPaymentCard> issueVirtualCard({required String productId});

  Future<PhysicalCardOrder> createPhysicalCardOrder({
    required String productId,
    required ShippingAddress shippingAddress,
  });
  Future<void> markPhysicalCardOrderReviewed({required String orderId});
  Future<CardOrderPaymentQuote> physicalCardPaymentQuote({
    required String orderId,
  });
  Future<PhysicalCardOrder> attachPhysicalCardPayment({
    required String orderId,
    required CardOrderPaymentReceipt receipt,
  });
  Future<PhysicalCardOrder> confirmPhysicalCardPayment({
    required String orderId,
  });
  Future<CardProvisioningHandle> createPhysicalCard({required String orderId});
  Future<void> completePhysicalCardPin({
    required String orderId,
    required String cardId,
  });
  Future<PhysicalCardOrder> cancelPhysicalCardOrder({required String orderId});

  Future<GnosisCardDashboard> dashboard();
  Future<GnosisCardDashboard> pollDelayedOperations();
  Future<GnosisCardDashboard> setFrozen({
    required String cardId,
    required bool frozen,
  });
  Future<GnosisCardDashboard> setCardStatus({
    required String cardId,
    required GnosisCardStatus status,
  });
  Future<GnosisCardDashboard> updateControls({
    required String cardId,
    required GnosisCardControls controls,
  });
  Future<PreparedSmartAccountIntent> prepareWithdrawal(
    WithdrawalRequest request,
  );
  Future<PreparedSmartAccountIntent> prepareDailyLimit(
    DailyLimitRequest request,
  );
  Future<DelayedOperation> submitSignedOperation({
    required PreparedSmartAccountIntent intent,
    required SmartAccountSignature signature,
    required String idempotencyKey,
  });
}

abstract interface class GnosisSafeMigrationRepository {
  Future<GnosisSafeMigration> safeMigration();
}

abstract interface class ExternalFlowLauncher {
  Future<void> launch(GnosisExternalFlow flow);
}

abstract interface class CardOrderPaymentGateway {
  Future<CardOrderPaymentReceipt?> findPayment({
    required CardOrderPaymentQuote quote,
    required String idempotencyKey,
  });

  Future<CardOrderPaymentReceipt> pay(
    CardOrderPaymentQuote quote, {
    required String idempotencyKey,
  });
}

/// Owns the sensitive surface. Secret values never pass through domain state.
abstract interface class CardSecureElementGateway {
  Future<void> showCardDetails(BuildContext context, {required String cardId});
  Future<void> showPin(BuildContext context, {required String cardId});
  Future<void> provisionInitialPin(
    BuildContext context, {
    required CardProvisioningHandle handle,
  });
}
