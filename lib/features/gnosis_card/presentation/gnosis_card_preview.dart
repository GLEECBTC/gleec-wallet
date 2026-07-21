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

part 'gnosis_card_preview_fixtures.dart';
part 'gnosis_card_preview_state.dart';

enum GnosisCardPreviewFixture {
  discovery,
  preparing,
  walletApproval,
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
  dashboardOffline,
  dashboardEmpty,
  dashboardOrdered,
  dashboardShipped,
  dashboardActivatable,
  dashboardFrozen,
  dashboardLost,
  dashboardStolen,
  dashboardVoided,
  migration,
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
  name: 'Automatic preparation · phone · dark',
  group: 'Gnosis Pay onboarding',
  size: Size(390, 844),
  brightness: Brightness.dark,
)
Widget gnosisPreparationPreview() => buildGnosisCardPreview(
  fixture: GnosisCardPreviewFixture.preparing,
  themeMode: ThemeMode.dark,
);

@Preview(
  name: 'Wallet approval · phone',
  group: 'Gnosis Pay onboarding',
  size: Size(390, 844),
)
Widget gnosisWalletApprovalPreview() =>
    buildGnosisCardPreview(fixture: GnosisCardPreviewFixture.walletApproval);

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
  name: 'Payment authorization · desktop dark',
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

@Preview(
  name: 'Saved dashboard · offline · phone',
  group: 'Gnosis Pay cards',
  size: Size(390, 844),
)
Widget gnosisOfflineDashboardPreview() =>
    buildGnosisCardPreview(fixture: GnosisCardPreviewFixture.dashboardOffline);

@Preview(
  name: 'Frozen card · desktop',
  group: 'Gnosis Pay cards · status',
  size: Size(1024, 900),
)
Widget gnosisFrozenCardPreview() =>
    buildGnosisCardPreview(fixture: GnosisCardPreviewFixture.dashboardFrozen);

@Preview(
  name: 'Preparing physical card · tablet',
  group: 'Gnosis Pay cards · status',
  size: Size(768, 1024),
)
Widget gnosisOrderedCardPreview() =>
    buildGnosisCardPreview(fixture: GnosisCardPreviewFixture.dashboardOrdered);

@Preview(
  name: 'Shipped physical card · tablet',
  group: 'Gnosis Pay cards · status',
  size: Size(768, 1024),
)
Widget gnosisShippedCardPreview() =>
    buildGnosisCardPreview(fixture: GnosisCardPreviewFixture.dashboardShipped);

@Preview(
  name: 'Physical card ready to activate · phone',
  group: 'Gnosis Pay cards · status',
  size: Size(390, 844),
)
Widget gnosisActivatableCardPreview() => buildGnosisCardPreview(
  fixture: GnosisCardPreviewFixture.dashboardActivatable,
);

@Preview(
  name: 'Reported lost card · phone',
  group: 'Gnosis Pay cards · status',
  size: Size(390, 844),
)
Widget gnosisLostCardPreview() =>
    buildGnosisCardPreview(fixture: GnosisCardPreviewFixture.dashboardLost);

@Preview(
  name: 'Reported stolen card · phone dark',
  group: 'Gnosis Pay cards · status',
  size: Size(390, 844),
  brightness: Brightness.dark,
)
Widget gnosisStolenCardPreview() => buildGnosisCardPreview(
  fixture: GnosisCardPreviewFixture.dashboardStolen,
  themeMode: ThemeMode.dark,
);

@Preview(
  name: 'Terminal card · large text',
  group: 'Gnosis Pay cards · status',
  size: Size(390, 844),
  textScaleFactor: 2,
)
Widget gnosisVoidedCardPreview() =>
    buildGnosisCardPreview(fixture: GnosisCardPreviewFixture.dashboardVoided);

@Preview(
  name: 'Account migration notice · desktop dark',
  group: 'Gnosis Pay cards',
  size: Size(1440, 900),
  brightness: Brightness.dark,
)
Widget gnosisMigrationPreview() => buildGnosisCardPreview(
  fixture: GnosisCardPreviewFixture.migration,
  themeMode: ThemeMode.dark,
);

@Preview(
  name: 'Empty activity · phone',
  group: 'Gnosis Pay cards',
  size: Size(375, 812),
)
Widget gnosisEmptyActivityPreview() =>
    buildGnosisCardPreview(fixture: GnosisCardPreviewFixture.dashboardEmpty);

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
                child: GnosisCardPage(manageLifecycle: false),
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
