part of 'gnosis_card_models.dart';

class GnosisOnboardingProgress extends Equatable {
  const GnosisOnboardingProgress({
    required this.isAuthenticated,
    required this.isRegistered,
    required this.email,
    required this.countryCode,
    required this.phoneCountryCallingCode,
    required this.terms,
    required this.kycStatus,
    required this.isSourceOfFundsAnswered,
    required this.phoneNumber,
    required this.isPhoneValidated,
    required this.phoneChallenge,
    required this.safeDeployment,
    required this.safeConfiguration,
    required this.isSafeRegistered,
    required this.selectedProduct,
    required this.physicalOrder,
    required this.isPhysicalOrderReviewed,
    required this.paymentReceipt,
    required this.provisioningHandle,
    required this.isPinProvisioned,
    required this.cards,
    this.verifiedShippingAddress,
  });

  const GnosisOnboardingProgress.initial({
    this.countryCode = 'DE',
    this.phoneCountryCallingCode = '+49',
    this.terms = const [],
  }) : isAuthenticated = false,
       isRegistered = false,
       email = null,
       kycStatus = GnosisKycStatus.notStarted,
       isSourceOfFundsAnswered = false,
       phoneNumber = null,
       isPhoneValidated = false,
       phoneChallenge = null,
       safeDeployment = null,
       safeConfiguration = null,
       isSafeRegistered = false,
       selectedProduct = null,
       physicalOrder = null,
       isPhysicalOrderReviewed = false,
       paymentReceipt = null,
       provisioningHandle = null,
       isPinProvisioned = false,
       cards = const [],
       verifiedShippingAddress = null;

  final bool isAuthenticated;
  final bool isRegistered;
  final String? email;
  final String countryCode;
  final String phoneCountryCallingCode;
  final List<GnosisTerm> terms;
  final GnosisKycStatus kycStatus;
  final bool isSourceOfFundsAnswered;
  final String? phoneNumber;
  final bool isPhoneValidated;
  final PhoneOtpChallenge? phoneChallenge;
  final SafeDeployment? safeDeployment;
  final SafeConfiguration? safeConfiguration;
  final bool isSafeRegistered;
  final GnosisCardProduct? selectedProduct;
  final PhysicalCardOrder? physicalOrder;
  final bool isPhysicalOrderReviewed;
  final CardOrderPaymentReceipt? paymentReceipt;
  final CardProvisioningHandle? provisioningHandle;
  final bool isPinProvisioned;
  final List<GnosisPaymentCard> cards;
  final ShippingAddress? verifiedShippingAddress;

  bool get areTermsAccepted =>
      terms.isNotEmpty && terms.every((term) => term.isAccepted);

  bool get isSafeReady =>
      (safeConfiguration?.isValid ?? false) && isSafeRegistered;

  GnosisOnboardingProgress withSafeRegistration(bool value) =>
      GnosisOnboardingProgress(
        isAuthenticated: isAuthenticated,
        isRegistered: isRegistered,
        email: email,
        countryCode: countryCode,
        phoneCountryCallingCode: phoneCountryCallingCode,
        terms: terms,
        kycStatus: kycStatus,
        isSourceOfFundsAnswered: isSourceOfFundsAnswered,
        phoneNumber: phoneNumber,
        isPhoneValidated: isPhoneValidated,
        phoneChallenge: phoneChallenge,
        safeDeployment: safeDeployment,
        safeConfiguration: safeConfiguration,
        isSafeRegistered: value,
        selectedProduct: selectedProduct,
        physicalOrder: physicalOrder,
        isPhysicalOrderReviewed: isPhysicalOrderReviewed,
        paymentReceipt: paymentReceipt,
        provisioningHandle: provisioningHandle,
        isPinProvisioned: isPinProvisioned,
        cards: cards,
        verifiedShippingAddress: verifiedShippingAddress,
      );

  GnosisOnboardingStage get nextStage {
    if (!isAuthenticated) return GnosisOnboardingStage.signedOut;
    if (!isRegistered || !areTermsAccepted) {
      return GnosisOnboardingStage.signupAndTerms;
    }
    if (kycStatus != GnosisKycStatus.approved) {
      return GnosisOnboardingStage.kyc;
    }
    if (!isSourceOfFundsAnswered) {
      return GnosisOnboardingStage.sourceOfFunds;
    }
    if (!isPhoneValidated) {
      return phoneChallenge == null
          ? GnosisOnboardingStage.phoneNumber
          : GnosisOnboardingStage.phoneOtp;
    }
    if (!isSafeReady) return GnosisOnboardingStage.safeDeployment;
    final physicalFlowInProgress =
        selectedProduct?.kind == GnosisCardKind.physical && !isPinProvisioned;
    if (cards.isNotEmpty &&
        !physicalFlowInProgress &&
        (physicalOrder == null ||
            physicalOrder?.status == PhysicalCardOrderStatus.cancelled ||
            isPinProvisioned)) {
      return GnosisOnboardingStage.ready;
    }
    final product = selectedProduct;
    if (product == null) return GnosisOnboardingStage.cardSelection;
    if (product.kind == GnosisCardKind.virtual) {
      return GnosisOnboardingStage.virtualCardIssuance;
    }
    final order = physicalOrder;
    if (order == null || order.status == PhysicalCardOrderStatus.cancelled) {
      return GnosisOnboardingStage.physicalShipping;
    }
    if (!isPhysicalOrderReviewed &&
        order.status == PhysicalCardOrderStatus.pendingTransaction &&
        paymentReceipt == null &&
        order.transactionHash == null) {
      return GnosisOnboardingStage.physicalOrderReview;
    }
    if (order.status == PhysicalCardOrderStatus.pendingTransaction ||
        order.status == PhysicalCardOrderStatus.transactionComplete ||
        order.status == PhysicalCardOrderStatus.confirmationRequired ||
        order.status == PhysicalCardOrderStatus.failedTransaction) {
      return GnosisOnboardingStage.physicalPayment;
    }
    if (order.status == PhysicalCardOrderStatus.ready &&
        provisioningHandle == null) {
      return GnosisOnboardingStage.physicalCardCreation;
    }
    if (!isPinProvisioned) return GnosisOnboardingStage.physicalPin;
    return GnosisOnboardingStage.ready;
  }

  bool isMilestoneComplete(GnosisOnboardingMilestone milestone) =>
      switch (milestone) {
        GnosisOnboardingMilestone.account =>
          isAuthenticated && isRegistered && areTermsAccepted,
        GnosisOnboardingMilestone.identity =>
          kycStatus == GnosisKycStatus.approved &&
              isSourceOfFundsAnswered &&
              isPhoneValidated,
        GnosisOnboardingMilestone.cardAccount => isSafeReady,
        GnosisOnboardingMilestone.card =>
          cards.isNotEmpty &&
              (cards.every((card) => card.kind != GnosisCardKind.physical) ||
                  isPinProvisioned),
      };

  @override
  List<Object?> get props => [
    isAuthenticated,
    isRegistered,
    email,
    countryCode,
    phoneCountryCallingCode,
    terms,
    kycStatus,
    isSourceOfFundsAnswered,
    phoneNumber,
    isPhoneValidated,
    phoneChallenge,
    safeDeployment,
    safeConfiguration,
    isSafeRegistered,
    selectedProduct,
    physicalOrder,
    isPhysicalOrderReviewed,
    paymentReceipt,
    provisioningHandle,
    isPinProvisioned,
    cards,
    verifiedShippingAddress,
  ];
}
