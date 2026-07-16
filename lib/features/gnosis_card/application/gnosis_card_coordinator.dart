import 'dart:math';

import 'package:equatable/equatable.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_models.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_ports.dart';

part 'gnosis_card_coordinator_core.dart';
part 'gnosis_card_coordinator_entry.dart';
part 'gnosis_card_coordinator_onboarding.dart';
part 'gnosis_card_coordinator_automation.dart';
part 'gnosis_card_coordinator_dashboard.dart';

class GnosisCardSnapshot extends Equatable {
  const GnosisCardSnapshot({
    required this.progress,
    this.session,
    this.siweChallenge,
    this.safeMigration = const GnosisSafeMigration.none(),
    this.sourceOfFundsQuestions = const [],
    this.cardProducts = const [],
    this.paymentQuote,
    this.dashboard,
    this.reviewIntent,
    this.reviewMetadata,
  });

  const GnosisCardSnapshot.initial()
    : progress = const GnosisOnboardingProgress.initial(),
      session = null,
      siweChallenge = null,
      safeMigration = const GnosisSafeMigration.none(),
      sourceOfFundsQuestions = const [],
      cardProducts = const [],
      paymentQuote = null,
      dashboard = null,
      reviewIntent = null,
      reviewMetadata = null;

  final GnosisOnboardingProgress progress;
  final GnosisCardSession? session;
  final GnosisSiweChallenge? siweChallenge;
  final GnosisSafeMigration safeMigration;
  final List<SourceOfFundsQuestion> sourceOfFundsQuestions;
  final List<GnosisCardProduct> cardProducts;
  final CardOrderPaymentQuote? paymentQuote;
  final GnosisCardDashboard? dashboard;
  final PreparedSmartAccountIntent? reviewIntent;
  final GnosisIntentReviewMetadata? reviewMetadata;

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
    GnosisSiweChallenge? siweChallenge,
    GnosisSafeMigration? safeMigration,
    List<SourceOfFundsQuestion>? sourceOfFundsQuestions,
    List<GnosisCardProduct>? cardProducts,
    CardOrderPaymentQuote? paymentQuote,
    GnosisCardDashboard? dashboard,
    PreparedSmartAccountIntent? reviewIntent,
    GnosisIntentReviewMetadata? reviewMetadata,
    bool clearSession = false,
    bool clearSiweChallenge = false,
    bool clearPaymentQuote = false,
    bool clearDashboard = false,
    bool clearReview = false,
  }) => GnosisCardSnapshot(
    progress: progress ?? this.progress,
    session: clearSession ? null : session ?? this.session,
    siweChallenge: clearSiweChallenge
        ? null
        : siweChallenge ?? this.siweChallenge,
    safeMigration: safeMigration ?? this.safeMigration,
    sourceOfFundsQuestions:
        sourceOfFundsQuestions ?? this.sourceOfFundsQuestions,
    cardProducts: cardProducts ?? this.cardProducts,
    paymentQuote: clearPaymentQuote ? null : paymentQuote ?? this.paymentQuote,
    dashboard: clearDashboard ? null : dashboard ?? this.dashboard,
    reviewIntent: clearReview ? null : reviewIntent ?? this.reviewIntent,
    reviewMetadata: clearReview ? null : reviewMetadata ?? this.reviewMetadata,
  );

  @override
  List<Object?> get props => [
    progress,
    session,
    siweChallenge,
    safeMigration,
    sourceOfFundsQuestions,
    cardProducts,
    paymentQuote,
    dashboard,
    reviewIntent,
    reviewMetadata,
  ];
}

/// Coordinates API-owned onboarding with genuine KDF signing.
///
/// The repository is the only component that mutates server-shaped progress.
/// This facade derives the active step after every operation and never deploys
/// or configures a Safe locally.
class GnosisCardCoordinator extends _GnosisCardCoordinatorDashboard {
  GnosisCardCoordinator({
    required super.repository,
    required super.signer,
    required super.externalFlowLauncher,
    required super.paymentGateway,
    super.readiness,
  });
}
