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

abstract interface class SmartAccountSigner {
  Future<SmartAccountOwner> owner();
  Future<String> signPersonalMessage(String message);
  Future<void> registerSafe(String safeAddress);
  Future<SmartAccountSignature> signTypedData(
    PreparedSmartAccountIntent intent,
  );
}

abstract interface class GnosisPayRepository {
  Future<GnosisOnboardingStage> onboardingStage();
  Future<String> createSiweMessage({required String ownerAddress});
  Future<GnosisCardSession> authenticate({
    required String ownerAddress,
    required String signature,
  });
  Future<void> acceptTerms();
  Future<void> registerApplicant();
  Future<void> submitPhoneAndSourceOfFunds();
  Future<GnosisKycStatus> pollKyc();
  Future<SafeDeployment?> safeDeployment();
  Future<SafeDeployment> requestSafeDeployment();
  Future<SafeDeployment> pollSafeDeployment(String requestId);
  Future<void> validateSafeIntegrity(SafeDeployment deployment);
  Future<GnosisPaymentCard> issueVirtualCard();
  Future<PhysicalCardOrder> orderPhysicalCard();
  Future<PhysicalCardOrder> payAndShipPhysicalCard(String orderId);
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
  Future<GnosisCardDashboard> updateControls(GnosisCardControls controls);
  Future<PreparedSmartAccountIntent> prepareWithdrawal(
    WithdrawalRequest request,
  );
  Future<PreparedSmartAccountIntent> prepareDailyLimit(
    DailyLimitRequest request,
  );
  Future<DelayedOperation> submitSignedOperation({
    required PreparedSmartAccountIntent intent,
    required SmartAccountSignature signature,
  });
}

/// Owns the sensitive surface. Values never pass through dashboard models.
abstract interface class CardSecureElementGateway {
  Future<void> showCardDetails(BuildContext context, {required String cardId});
  Future<void> showPin(BuildContext context, {required String cardId});
}

class GnosisCardUnavailable implements Exception {
  const GnosisCardUnavailable(this.message);
  final String message;

  @override
  String toString() => message;
}
