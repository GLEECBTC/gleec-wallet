import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/features/gnosis_card/application/gnosis_card_bloc.dart';
import 'package:web_dex/features/gnosis_card/application/gnosis_card_coordinator.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_models.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_ports.dart';
import 'package:web_dex/features/gnosis_card/infrastructure/gnosis_card_config.dart';
import 'package:web_dex/features/gnosis_card/infrastructure/gnosis_card_dependencies.dart';
import 'package:web_dex/features/gnosis_card/infrastructure/synthetic_secure_element_gateway.dart';
import 'package:web_dex/features/gnosis_card/presentation/gnosis_card_page.dart';

enum GnosisCardPreviewFixture {
  discovery,
  signupAndTerms,
  kycNotStarted,
  kycDocumentsRequested,
  kycPending,
  kycProcessing,
  kycResubmission,
  kycRejected,
  kycRequiresAction,
  sourceOfFunds,
  phoneNumber,
  phoneOtp,
  safeAccepted,
  safeProcessing,
  safeFailure,
  safeTimeout,
  safeIntegrityFailure,
  cardSelection,
  virtualIssuance,
  physicalShipping,
  physicalReview,
  physicalPayment,
  physicalCreation,
  physicalPin,
  dashboard,
}

@Preview(
  name: 'Discovery · phone · light',
  group: 'Gnosis Pay onboarding',
  size: Size(390, 844),
  brightness: Brightness.light,
)
Widget gnosisDiscoveryPreview() =>
    buildGnosisCardPreview(fixture: GnosisCardPreviewFixture.discovery);

@Preview(
  name: 'Signup and terms · desktop · dark',
  group: 'Gnosis Pay onboarding',
  size: Size(1280, 900),
  brightness: Brightness.dark,
)
Widget gnosisSignupPreview() => buildGnosisCardPreview(
  fixture: GnosisCardPreviewFixture.signupAndTerms,
  themeMode: ThemeMode.dark,
);

@Preview(
  name: 'KYC · not started',
  group: 'Gnosis Pay onboarding · KYC states',
  size: Size(390, 844),
)
Widget gnosisKycNotStartedPreview() =>
    buildGnosisCardPreview(fixture: GnosisCardPreviewFixture.kycNotStarted);

@Preview(
  name: 'KYC · documents requested',
  group: 'Gnosis Pay onboarding · KYC states',
  size: Size(390, 844),
)
Widget gnosisKycDocumentsPreview() => buildGnosisCardPreview(
  fixture: GnosisCardPreviewFixture.kycDocumentsRequested,
);

@Preview(
  name: 'KYC · pending',
  group: 'Gnosis Pay onboarding · KYC states',
  size: Size(390, 844),
)
Widget gnosisKycPendingPreview() =>
    buildGnosisCardPreview(fixture: GnosisCardPreviewFixture.kycPending);

@Preview(
  name: 'KYC · processing',
  group: 'Gnosis Pay onboarding · KYC states',
  size: Size(1280, 900),
  brightness: Brightness.dark,
)
Widget gnosisKycProcessingPreview() => buildGnosisCardPreview(
  fixture: GnosisCardPreviewFixture.kycProcessing,
  themeMode: ThemeMode.dark,
);

@Preview(
  name: 'KYC · resubmission',
  group: 'Gnosis Pay onboarding · KYC states',
  size: Size(390, 844),
)
Widget gnosisKycResubmissionPreview() =>
    buildGnosisCardPreview(fixture: GnosisCardPreviewFixture.kycResubmission);

@Preview(
  name: 'KYC · rejected',
  group: 'Gnosis Pay onboarding · KYC states',
  size: Size(390, 844),
)
Widget gnosisKycRejectedPreview() =>
    buildGnosisCardPreview(fixture: GnosisCardPreviewFixture.kycRejected);

@Preview(
  name: 'KYC · requires action',
  group: 'Gnosis Pay onboarding · KYC states',
  size: Size(1280, 900),
  brightness: Brightness.dark,
)
Widget gnosisKycActionPreview() => buildGnosisCardPreview(
  fixture: GnosisCardPreviewFixture.kycRequiresAction,
  themeMode: ThemeMode.dark,
);

@Preview(
  name: 'KYC approved → source of funds · desktop',
  group: 'Gnosis Pay onboarding',
  size: Size(1280, 900),
)
Widget gnosisSourcePreview() =>
    buildGnosisCardPreview(fixture: GnosisCardPreviewFixture.sourceOfFunds);

@Preview(
  name: 'Phone entry · large text',
  group: 'Gnosis Pay onboarding',
  size: Size(390, 844),
  textScaleFactor: 2,
)
Widget gnosisPhonePreview() =>
    buildGnosisCardPreview(fixture: GnosisCardPreviewFixture.phoneNumber);

@Preview(
  name: 'Phone OTP · phone',
  group: 'Gnosis Pay onboarding',
  size: Size(390, 844),
)
Widget gnosisOtpPreview() =>
    buildGnosisCardPreview(fixture: GnosisCardPreviewFixture.phoneOtp);

@Preview(
  name: 'Safe accepted · phone',
  group: 'Gnosis Pay onboarding · Safe states',
  size: Size(390, 844),
)
Widget gnosisSafeAcceptedPreview() =>
    buildGnosisCardPreview(fixture: GnosisCardPreviewFixture.safeAccepted);

@Preview(
  name: 'Safe processing · desktop dark',
  group: 'Gnosis Pay onboarding · Safe states',
  size: Size(1280, 900),
  brightness: Brightness.dark,
)
Widget gnosisSafeProcessingPreview() => buildGnosisCardPreview(
  fixture: GnosisCardPreviewFixture.safeProcessing,
  themeMode: ThemeMode.dark,
);

@Preview(
  name: 'Safe failure · phone',
  group: 'Gnosis Pay onboarding · Safe states',
  size: Size(390, 844),
)
Widget gnosisSafeFailurePreview() =>
    buildGnosisCardPreview(fixture: GnosisCardPreviewFixture.safeFailure);

@Preview(
  name: 'Safe timeout · phone',
  group: 'Gnosis Pay onboarding · Safe states',
  size: Size(390, 844),
)
Widget gnosisSafeTimeoutPreview() =>
    buildGnosisCardPreview(fixture: GnosisCardPreviewFixture.safeTimeout);

@Preview(
  name: 'Safe integrity blocked · desktop dark',
  group: 'Gnosis Pay onboarding · Safe states',
  size: Size(1280, 900),
  brightness: Brightness.dark,
)
Widget gnosisSafeIntegrityPreview() => buildGnosisCardPreview(
  fixture: GnosisCardPreviewFixture.safeIntegrityFailure,
  themeMode: ThemeMode.dark,
);

@Preview(
  name: 'Card choice · desktop dark',
  group: 'Gnosis Pay onboarding',
  size: Size(1280, 900),
  brightness: Brightness.dark,
)
Widget gnosisCardChoicePreview() => buildGnosisCardPreview(
  fixture: GnosisCardPreviewFixture.cardSelection,
  themeMode: ThemeMode.dark,
);

@Preview(
  name: 'Virtual issuance · phone',
  group: 'Gnosis Pay onboarding',
  size: Size(390, 844),
)
Widget gnosisVirtualPreview() =>
    buildGnosisCardPreview(fixture: GnosisCardPreviewFixture.virtualIssuance);

@Preview(
  name: 'Physical shipping · desktop',
  group: 'Gnosis Pay onboarding · Physical card',
  size: Size(1280, 900),
)
Widget gnosisShippingPreview() =>
    buildGnosisCardPreview(fixture: GnosisCardPreviewFixture.physicalShipping);

@Preview(
  name: 'Physical review · phone',
  group: 'Gnosis Pay onboarding · Physical card',
  size: Size(390, 844),
)
Widget gnosisOrderReviewPreview() =>
    buildGnosisCardPreview(fixture: GnosisCardPreviewFixture.physicalReview);

@Preview(
  name: 'Simulated payment · desktop dark',
  group: 'Gnosis Pay onboarding · Physical card',
  size: Size(1280, 900),
  brightness: Brightness.dark,
)
Widget gnosisPaymentPreview() => buildGnosisCardPreview(
  fixture: GnosisCardPreviewFixture.physicalPayment,
  themeMode: ThemeMode.dark,
);

@Preview(
  name: 'Physical issuance · phone',
  group: 'Gnosis Pay onboarding · Physical card',
  size: Size(390, 844),
)
Widget gnosisPhysicalCreationPreview() =>
    buildGnosisCardPreview(fixture: GnosisCardPreviewFixture.physicalCreation);

@Preview(
  name: 'PSE PIN handoff · phone',
  group: 'Gnosis Pay onboarding · Physical card',
  size: Size(390, 844),
)
Widget gnosisPinPreview() =>
    buildGnosisCardPreview(fixture: GnosisCardPreviewFixture.physicalPin);

@Preview(
  name: 'Card dashboard · desktop · dark',
  group: 'Gnosis Pay cards',
  size: Size(1280, 900),
  brightness: Brightness.dark,
)
Widget gnosisCardDashboardPreview() => buildGnosisCardPreview(
  fixture: GnosisCardPreviewFixture.dashboard,
  themeMode: ThemeMode.dark,
);

Widget buildGnosisCardPreview({
  GnosisCardPreviewFixture fixture = GnosisCardPreviewFixture.dashboard,
  ThemeMode themeMode = ThemeMode.system,
}) {
  const config = GnosisCardConfig(
    mode: GnosisCardMode.mock,
    scenario: GnosisCardScenario.happyPath,
    failureReason: null,
  );
  final dependencies = GnosisCardDependencies.forAdapters(
    config: config,
    secureElement: const SyntheticSecureElementGateway(),
    externalFlowLauncher: const _PreviewExternalFlowLauncher(),
  );
  final state = _previewState(fixture);
  return EasyLocalization(
    supportedLocales: const [Locale('en')],
    fallbackLocale: const Locale('en'),
    useOnlyLangCode: true,
    path: '$assetsPath/translations',
    child: Builder(
      builder: (context) => RepositoryProvider.value(
        value: dependencies,
        child: BlocProvider(
          create: (_) => GnosisCardBloc(
            config: config,
            coordinator: null,
            initialState: state,
          ),
          child: MaterialApp(
            locale: context.locale,
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            theme: theme.global.light,
            darkTheme: theme.global.dark,
            themeMode: themeMode,
            home: const Scaffold(
              body: RepaintBoundary(
                key: Key('gnosis-card-preview'),
                child: GnosisCardPage(),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

GnosisCardSnapshot gnosisCardPreviewSnapshot() =>
    _previewSnapshot(GnosisCardPreviewFixture.dashboard);

GnosisCardState _previewState(GnosisCardPreviewFixture fixture) {
  final snapshot = _previewSnapshot(fixture);
  if (fixture == GnosisCardPreviewFixture.safeFailure) {
    return GnosisCardState(
      status: GnosisCardLoadStatus.ready,
      snapshot: snapshot,
      message: 'The API could not complete Safe deployment.',
      failure: const GnosisCardFailure(
        code: GnosisCardFailureCode.deploymentFailed,
        message: 'The API could not complete Safe deployment.',
        recovery: GnosisCardRecovery.resetSafe,
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
        recovery: GnosisCardRecovery.resetSafe,
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
  final card = _cardFor(stage);
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
        : safeComplete
        ? _previewSafeConfiguration
        : null,
    isSafeRegistered: safeComplete,
    selectedProduct: physical
        ? _physicalProduct
        : virtual
        ? _virtualProduct
        : fixture == GnosisCardPreviewFixture.dashboard
        ? _virtualProduct
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
    dashboard: fixture == GnosisCardPreviewFixture.dashboard
        ? _previewDashboard
        : null,
  );
}

GnosisOnboardingStage _stageForFixture(
  GnosisCardPreviewFixture fixture,
) => switch (fixture) {
  GnosisCardPreviewFixture.discovery => GnosisOnboardingStage.signedOut,
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
  GnosisCardPreviewFixture.dashboard => GnosisOnboardingStage.ready,
};

GnosisKycStatus _kycForFixture(GnosisCardPreviewFixture fixture) =>
    switch (fixture) {
      GnosisCardPreviewFixture.kycNotStarted => GnosisKycStatus.notStarted,
      GnosisCardPreviewFixture.kycDocumentsRequested =>
        GnosisKycStatus.documentsRequested,
      GnosisCardPreviewFixture.kycPending => GnosisKycStatus.pending,
      GnosisCardPreviewFixture.kycProcessing => GnosisKycStatus.processing,
      GnosisCardPreviewFixture.kycResubmission =>
        GnosisKycStatus.resubmissionRequested,
      GnosisCardPreviewFixture.kycRejected => GnosisKycStatus.rejected,
      GnosisCardPreviewFixture.kycRequiresAction =>
        GnosisKycStatus.requiresAction,
      _ =>
        _stageForFixture(fixture) == GnosisOnboardingStage.kyc
            ? GnosisKycStatus.notStarted
            : GnosisKycStatus.approved,
    };

bool _identityComplete(GnosisOnboardingStage stage) => switch (stage) {
  GnosisOnboardingStage.safeDeployment ||
  GnosisOnboardingStage.cardSelection ||
  GnosisOnboardingStage.virtualCardIssuance ||
  GnosisOnboardingStage.physicalShipping ||
  GnosisOnboardingStage.physicalOrderReview ||
  GnosisOnboardingStage.physicalPayment ||
  GnosisOnboardingStage.physicalCardCreation ||
  GnosisOnboardingStage.physicalPin ||
  GnosisOnboardingStage.ready => true,
  _ => false,
};

bool _safeComplete(GnosisOnboardingStage stage) => switch (stage) {
  GnosisOnboardingStage.cardSelection ||
  GnosisOnboardingStage.virtualCardIssuance ||
  GnosisOnboardingStage.physicalShipping ||
  GnosisOnboardingStage.physicalOrderReview ||
  GnosisOnboardingStage.physicalPayment ||
  GnosisOnboardingStage.physicalCardCreation ||
  GnosisOnboardingStage.physicalPin ||
  GnosisOnboardingStage.ready => true,
  _ => false,
};

bool _isPhysicalStage(GnosisOnboardingStage stage) => switch (stage) {
  GnosisOnboardingStage.physicalShipping ||
  GnosisOnboardingStage.physicalOrderReview ||
  GnosisOnboardingStage.physicalPayment ||
  GnosisOnboardingStage.physicalCardCreation ||
  GnosisOnboardingStage.physicalPin => true,
  _ => false,
};

PhysicalCardOrder? _orderFor(GnosisOnboardingStage stage) {
  final status = switch (stage) {
    GnosisOnboardingStage.physicalOrderReview ||
    GnosisOnboardingStage.physicalPayment =>
      PhysicalCardOrderStatus.pendingTransaction,
    GnosisOnboardingStage.physicalCardCreation => PhysicalCardOrderStatus.ready,
    GnosisOnboardingStage.physicalPin => PhysicalCardOrderStatus.cardCreated,
    _ => null,
  };
  if (status == null) return null;
  return PhysicalCardOrder(
    id: 'preview-order',
    createdAt: DateTime(2026, 7, 14, 12),
    status: status,
    totalAmountMinor: 999,
    totalDiscountMinor: 0,
    currency: 'EUR',
    embossedName: 'Alex Morgan',
    shippingAddress: const ShippingAddress(
      recipientName: 'Alex Morgan',
      address1: '12 Example Strasse',
      city: 'Berlin',
      postalCode: '10115',
      country: 'DE',
    ),
  );
}

CardOrderPaymentReceipt? _receiptFor(
  GnosisOnboardingStage stage,
  PhysicalCardOrder? order,
) => switch (stage) {
  GnosisOnboardingStage.physicalCardCreation ||
  GnosisOnboardingStage.physicalPin => CardOrderPaymentReceipt(
    orderId: order!.id,
    transactionHash: '0xpreview-synthetic-receipt',
    amountMinor: 999,
    currency: 'EUR',
    paidAt: DateTime(2026, 7, 14, 12, 5),
    isSimulated: true,
  ),
  _ => null,
};

GnosisPaymentCard? _cardFor(GnosisOnboardingStage stage) => switch (stage) {
  GnosisOnboardingStage.physicalPin => const GnosisPaymentCard(
    id: 'preview-physical-card',
    kind: GnosisCardKind.physical,
    status: GnosisCardStatus.ordered,
    lastFour: '8810',
    label: 'Physical card',
  ),
  GnosisOnboardingStage.ready => const GnosisPaymentCard(
    id: 'preview-virtual-card',
    kind: GnosisCardKind.virtual,
    status: GnosisCardStatus.active,
    lastFour: '4242',
    label: 'Everyday card',
  ),
  _ => null,
};

List<GnosisTerm> _previewTerms({required bool accepted}) => [
  GnosisTerm(
    id: 'preview-terms',
    title: 'Gnosis Pay Cardholder Terms',
    version: '2026-06',
    documentUrl: 'https://mock.gnosispay.com/legal/cardholder-terms',
    isAccepted: accepted,
  ),
  GnosisTerm(
    id: 'preview-privacy',
    title: 'Gnosis Pay Privacy Notice',
    version: '2026-05',
    documentUrl: 'https://mock.gnosispay.com/legal/privacy',
    isAccepted: accepted,
  ),
];

const _sourceQuestions = [
  SourceOfFundsQuestion(
    id: 'preview-source',
    title: 'What is the primary source of funds for this card?',
    answers: ['Salary', 'Savings', 'Investments', 'Business income'],
  ),
];

const _virtualProduct = GnosisCardProduct(
  id: 'virtual-eur',
  kind: GnosisCardKind.virtual,
  title: 'Virtual card',
  description: 'Instant digital card',
  feeMinor: 0,
  currency: 'EUR',
  requiresShipping: false,
  requiresPin: false,
);

const _physicalProduct = GnosisCardProduct(
  id: 'physical-eur',
  kind: GnosisCardKind.physical,
  title: 'Physical card',
  description: 'Physical contactless card',
  feeMinor: 999,
  currency: 'EUR',
  requiresShipping: true,
  requiresPin: true,
);

const _previewOwner = '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

final _previewDeploymentOk = SafeDeployment(
  requestId: 'preview-deployment',
  ownerAddress: _previewOwner,
  status: SafeDeploymentStatus.ok,
  updatedAt: DateTime(2026, 7, 14, 12),
);

const _previewSafeConfiguration = SafeConfiguration(
  ownerAddress: _previewOwner,
  isDeployed: true,
  integrity: SafeAccountIntegrity.delayQueueNotEmpty,
  safeAddress: '0x1111111111111111111111111111111111111111',
  delayModule: '0x2222222222222222222222222222222222222222',
  tokenSymbol: 'EURe',
  fiatSymbol: 'EUR',
);

const _previewInvalidSafeConfiguration = SafeConfiguration(
  ownerAddress: _previewOwner,
  isDeployed: true,
  integrity: SafeAccountIntegrity.safeMisconfigured,
  safeAddress: '0x1111111111111111111111111111111111111111',
  delayModule: '0x2222222222222222222222222222222222222222',
  tokenSymbol: 'EURe',
  fiatSymbol: 'EUR',
);

const _previewQuote = CardOrderPaymentQuote(
  orderId: 'preview-order',
  amountMinor: 999,
  currency: 'EUR',
  assetSymbol: 'EURe',
  assetContract: '0x3333333333333333333333333333333333333333',
  recipient: '0x4444444444444444444444444444444444444444',
  isSimulated: true,
);

final _previewDashboard = GnosisCardDashboard(
  balanceMinor: 184250,
  currency: 'EUR',
  dailyLimitMinor: 150000,
  cards: const [
    GnosisPaymentCard(
      id: 'preview-virtual-card',
      kind: GnosisCardKind.virtual,
      status: GnosisCardStatus.active,
      lastFour: '4242',
      label: 'Everyday card',
    ),
  ],
  controls: const GnosisCardControls(
    contactless: true,
    online: true,
    atm: false,
  ),
  transactions: [
    GnosisCardTransaction(
      id: 'preview-tx',
      merchant: 'City Market',
      amountMinor: -4235,
      currency: 'EUR',
      occurredAt: DateTime(2026, 7, 9, 17, 42),
      isDeclined: false,
    ),
  ],
  operations: const [],
);

class _PreviewExternalFlowLauncher implements ExternalFlowLauncher {
  const _PreviewExternalFlowLauncher();

  @override
  Future<void> launch(GnosisExternalFlow flow) async {}
}
