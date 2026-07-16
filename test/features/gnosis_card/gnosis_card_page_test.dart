import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/features/gnosis_card/application/gnosis_card_bloc.dart';
import 'package:web_dex/features/gnosis_card/application/gnosis_card_coordinator.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_models.dart';
import 'package:web_dex/features/gnosis_card/infrastructure/deterministic_gnosis_pay_repository.dart';
import 'package:web_dex/features/gnosis_card/infrastructure/gnosis_card_config.dart';
import 'package:web_dex/features/gnosis_card/infrastructure/gnosis_card_dependencies.dart';
import 'package:web_dex/features/gnosis_card/infrastructure/synthetic_secure_element_gateway.dart';
import 'package:web_dex/features/gnosis_card/presentation/gnosis_card_page.dart';
import 'package:web_dex/features/gnosis_card/presentation/gnosis_card_preview.dart';
import 'package:web_dex/features/gnosis_card/presentation/gnosis_onboarding_steps.dart';
import 'package:web_dex/features/gnosis_card/presentation/gnosis_onboarding_widgets.dart';
import 'package:web_dex/shared/screenshot/screenshot_sensitivity.dart';

import 'gnosis_card_test_helpers.dart';

const _mockConfig = GnosisCardConfig(
  mode: GnosisCardMode.mock,
  scenario: GnosisCardScenario.happyPath,
  failureReason: null,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(EasyLocalization.ensureInitialized);

  for (final size in <Size>[const Size(390, 844), const Size(1280, 900)]) {
    testWidgets('disabled card remains usable at ${size.width}px', (
      tester,
    ) async {
      _setViewSize(tester, size);
      const config = GnosisCardConfig(
        mode: GnosisCardMode.disabled,
        scenario: GnosisCardScenario.happyPath,
        failureReason: 'Cards are disabled in this build.',
      );
      final dependencies = GnosisCardDependencies.forAdapters(
        config: config,
        secureElement: GnosisTestSecureElementGateway(),
      );
      final bloc = GnosisCardBloc(
        config: config,
        coordinator: null,
        initialState: const GnosisCardState(
          status: GnosisCardLoadStatus.disabled,
          message: 'Cards are disabled in this build.',
        ),
      );
      addTearDown(bloc.close);

      await tester.pumpWidget(_pageApp(bloc, dependencies));
      await tester.pump();

      expect(find.text('Cards are unavailable'), findsOneWidget);
      expect(find.text('This feature is disabled.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('signup validates email, accepts terms, and launches documents', (
    tester,
  ) async {
    _setViewSize(tester, const Size(390, 844));
    final launcher = RecordingExternalFlowLauncher();
    final payment = GnosisTestPaymentGateway();
    final coordinator = _coordinator(
      DeterministicGnosisPayRepository(scenario: GnosisCardScenario.happyPath),
      GnosisTestSigner(),
      launcher,
      payment,
    );
    await coordinator.initialize();
    final snapshot = await coordinator.signIn();
    final dependencies = GnosisCardDependencies.forAdapters(
      config: _mockConfig,
      secureElement: GnosisTestSecureElementGateway(),
      externalFlowLauncher: launcher,
      paymentGateway: payment,
      coordinator: coordinator,
    );
    final bloc = GnosisCardBloc(
      config: _mockConfig,
      coordinator: coordinator,
      initialState: GnosisCardState(
        status: GnosisCardLoadStatus.ready,
        snapshot: snapshot,
      ),
    );
    addTearDown(bloc.close);

    await tester.pumpWidget(_pageApp(bloc, dependencies));
    await tester.pump();

    final uncheckedTerm = find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.checked == false,
    );
    expect(uncheckedTerm, findsNWidgets(snapshot.terms.length));

    final openDocument = find.text('Open document').first;
    await tester.ensureVisible(openDocument);
    await tester.tap(openDocument);
    await tester.pump();
    await tester.pump();
    expect(launcher.flows.single.kind, GnosisExternalFlowKind.terms);
    expect(bloc.state.externalFlow, isNull);

    await tester.enterText(
      find.byKey(const Key('gnosis-signup-email')),
      'cardholder@example.test',
    );
    for (final term in snapshot.terms) {
      final title = find.text(term.title);
      await tester.ensureVisible(title);
      await tester.tap(title);
      await tester.pump();
    }
    final submit = find.byKey(const Key('gnosis-signup-submit'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(bloc.state.snapshot?.stage, GnosisOnboardingStage.kyc);
    expect(bloc.state.failure, isNull);
  });

  testWidgets('KYC launches externally and refreshes when the app resumes', (
    tester,
  ) async {
    _setViewSize(tester, const Size(390, 844));
    final launcher = RecordingExternalFlowLauncher();
    final payment = GnosisTestPaymentGateway();
    final coordinator = _coordinator(
      DeterministicGnosisPayRepository(scenario: GnosisCardScenario.happyPath),
      GnosisTestSigner(),
      launcher,
      payment,
    );
    await coordinator.initialize();
    var snapshot = await coordinator.signIn();
    snapshot = await coordinator.signUpAndAcceptTerms(
      email: 'cardholder@example.test',
      acceptances: [
        for (final term in snapshot.terms)
          GnosisTermAcceptance(id: term.id, version: term.version),
      ],
    );
    final dependencies = GnosisCardDependencies.forAdapters(
      config: _mockConfig,
      secureElement: GnosisTestSecureElementGateway(),
      externalFlowLauncher: launcher,
      paymentGateway: payment,
      coordinator: coordinator,
    );
    final bloc = GnosisCardBloc(
      config: _mockConfig,
      coordinator: coordinator,
      initialState: GnosisCardState(
        status: GnosisCardLoadStatus.ready,
        snapshot: snapshot,
      ),
    );
    addTearDown(bloc.close);

    await tester.pumpWidget(_pageApp(bloc, dependencies));
    await tester.pump();
    await tester.tap(find.byKey(const Key('gnosis-kyc-open')));
    await tester.pumpAndSettle();
    expect(launcher.flows.single.kind, GnosisExternalFlowKind.kyc);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(bloc.state.snapshot?.kycStatus, GnosisKycStatus.processing);

    await tester.tap(find.byKey(const Key('gnosis-kyc-refresh')));
    await tester.pumpAndSettle();
    expect(bloc.state.snapshot?.stage, GnosisOnboardingStage.sourceOfFunds);
  });

  testWidgets('OTP is one accessible field with resend and edit actions', (
    tester,
  ) async {
    _setViewSize(tester, const Size(390, 844));
    String? verifiedCode;
    var resendCalls = 0;
    var editCalls = 0;
    final challenge = PhoneOtpChallenge(
      id: 'challenge',
      phoneNumber: '+4915123456789',
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      resendAvailableAt: DateTime.now().subtract(const Duration(seconds: 1)),
      attemptsRemaining: 3,
    );

    await tester.pumpWidget(
      _stepApp(
        GnosisPhoneOtpStep(
          challenge: challenge,
          busy: false,
          onVerify: (value) => verifiedCode = value,
          onResend: () => resendCalls += 1,
          onEdit: () => editCalls += 1,
        ),
      ),
    );
    await tester.pump();

    final otpField = find.byKey(const Key('gnosis-phone-otp'));
    expect(otpField, findsOneWidget);
    expect(find.byType(EditableText), findsOneWidget);
    await tester.enterText(otpField, '12ab3456');
    await tester.tap(find.byKey(const Key('gnosis-phone-verify')));
    await tester.pump();
    expect(verifiedCode, '123456');

    await tester.tap(find.byKey(const Key('gnosis-phone-resend')));
    await tester.tap(find.text('Edit phone number'));
    expect(resendCalls, 1);
    expect(editCalls, 1);
  });

  testWidgets('Safe state exposes polling, reset, and live status semantics', (
    tester,
  ) async {
    var polls = 0;
    var resets = 0;
    final progress = _safeProgress(
      deployment: SafeDeployment(
        requestId: 'deployment',
        ownerAddress: _owner,
        status: SafeDeploymentStatus.accepted,
        updatedAt: DateTime.utc(2026, 7, 14, 12),
      ),
    );

    await tester.pumpWidget(
      _stepApp(
        GnosisSafeSetupStep(
          progress: progress,
          busy: false,
          onStart: () {},
          onPoll: () => polls += 1,
          onReset: () => resets += 1,
        ),
      ),
    );
    await tester.pump();

    expect(progress.nextStage, GnosisOnboardingStage.safeDeployment);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.liveRegion == true,
      ),
      findsWidgets,
    );
    await tester.tap(find.byKey(const Key('gnosis-safe-primary')));
    await tester.tap(find.byKey(const Key('gnosis-safe-reset')));
    expect(polls, 1);
    expect(resets, 1);
  });

  testWidgets('card choices and simulated payment expose explicit actions', (
    tester,
  ) async {
    String? selectedProduct;
    var paymentCalls = 0;
    var confirmationCalls = 0;
    await tester.pumpWidget(
      _stepApp(
        GnosisCardSelectionStep(
          products: const [_virtualProduct, _physicalProduct],
          busy: false,
          onSelect: (value) => selectedProduct = value,
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Physical card').first);
    expect(selectedProduct, _physicalProduct.id);

    final order = _physicalOrder(PhysicalCardOrderStatus.pendingTransaction);
    await tester.pumpWidget(
      _stepApp(
        GnosisPhysicalPaymentStep(
          order: order,
          quote: _paymentQuote,
          busy: false,
          onPay: () => paymentCalls += 1,
          onConfirm: () => confirmationCalls += 1,
          onCancel: () {},
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Demo payment only'), findsOneWidget);
    await tester.tap(find.byKey(const Key('gnosis-payment-submit')));
    expect(paymentCalls, 1);

    await tester.pumpWidget(
      _stepApp(
        GnosisPhysicalPaymentStep(
          order: order,
          quote: _paymentQuote,
          receipt: _paymentReceipt,
          busy: false,
          onPay: () => paymentCalls += 1,
          onConfirm: () => confirmationCalls += 1,
          onCancel: () {},
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('gnosis-payment-submit')));
    expect(confirmationCalls, 1);
  });

  testWidgets('cancelled secure handoff preserves state and can be resumed', (
    tester,
  ) async {
    _setViewSize(tester, const Size(390, 844));
    final secure = GnosisTestSecureElementGateway(cancelProvisioning: true);
    final progress = _physicalProgress(
      orderStatus: PhysicalCardOrderStatus.cardCreated,
      receipt: _paymentReceipt,
      provisioningHandle: const CardProvisioningHandle(
        orderId: 'physical-order',
        cardId: 'physical-card',
        value: 'opaque-test-capability',
      ),
      cards: const [
        GnosisPaymentCard(
          id: 'physical-card',
          kind: GnosisCardKind.physical,
          status: GnosisCardStatus.ordered,
          lastFour: '0000',
          label: 'Test physical card',
        ),
      ],
    );
    final snapshot = GnosisCardSnapshot(progress: progress);
    final bloc = GnosisCardBloc(
      config: _mockConfig,
      coordinator: null,
      initialState: GnosisCardState(
        status: GnosisCardLoadStatus.ready,
        snapshot: snapshot,
      ),
    );
    addTearDown(bloc.close);
    final dependencies = GnosisCardDependencies.forAdapters(
      config: _mockConfig,
      secureElement: secure,
      externalFlowLauncher: RecordingExternalFlowLauncher(),
      paymentGateway: GnosisTestPaymentGateway(),
    );

    await tester.pumpWidget(_pageApp(bloc, dependencies));
    await tester.pump();
    await tester.tap(find.byKey(const Key('gnosis-pin-open')));
    await tester.pump();
    await tester.pump();

    expect(secure.provisioningCalls, 1);
    expect(bloc.state.snapshot, same(snapshot));
    expect(bloc.state.failure, isNull);
    expect(bloc.state.isPinHandoffCancelled, isTrue);
    expect(find.text('Resume PIN setup'), findsOneWidget);

    await tester.tap(find.byKey(const Key('gnosis-pin-open')));
    await tester.pump();
    expect(secure.provisioningCalls, 2);
  });

  testWidgets('onboarding adapts to width, large text, and keyboard focus', (
    tester,
  ) async {
    for (final size in <Size>[const Size(390, 844), const Size(1280, 900)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        _stepApp(
          GnosisOnboardingFrame(
            milestoneIndex: 1,
            child: GnosisPhoneNumberStep(busy: false, onSubmit: (_) {}),
          ),
          textScaler: const TextScaler.linear(2),
          disableAnimations: true,
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);

      expect(FocusManager.instance.primaryFocus, isNotNull);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.header == true,
        ),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
    }
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });

  testWidgets('secure detail placeholder remains screenshot-sensitive', (
    tester,
  ) async {
    _setViewSize(tester, const Size(1280, 900));
    final sensitivity = ScreenshotSensitivityController();
    addTearDown(sensitivity.dispose);
    final bloc = GnosisCardBloc(
      config: _mockConfig,
      coordinator: null,
      initialState: GnosisCardState(
        status: GnosisCardLoadStatus.ready,
        snapshot: gnosisCardPreviewSnapshot(),
      ),
    );
    addTearDown(bloc.close);
    final dependencies = GnosisCardDependencies.forAdapters(
      config: _mockConfig,
      secureElement: const SyntheticSecureElementGateway(),
    );

    await tester.pumpWidget(
      _pageApp(bloc, dependencies, sensitivity: sensitivity),
    );
    await tester.pump();
    await tester.tap(find.text('Details'));
    await tester.pump();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(sensitivity.isSensitive, isTrue);
    expect(
      find.text(
        'This opens securely outside Gleec Wallet. Return here when you are finished.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(sensitivity.isSensitive, isFalse);
  });
}

GnosisCardCoordinator _coordinator(
  DeterministicGnosisPayRepository repository,
  GnosisTestSigner signer,
  RecordingExternalFlowLauncher launcher,
  GnosisTestPaymentGateway payment,
) => GnosisCardCoordinator(
  repository: repository,
  signer: signer,
  externalFlowLauncher: launcher,
  paymentGateway: payment,
);

Widget _pageApp(
  GnosisCardBloc bloc,
  GnosisCardDependencies dependencies, {
  ScreenshotSensitivityController? sensitivity,
}) {
  Widget child = _localizedApp(
    RepositoryProvider.value(
      value: dependencies,
      child: BlocProvider.value(
        value: bloc,
        child: const Scaffold(body: GnosisCardPage()),
      ),
    ),
  );
  if (sensitivity != null) {
    child = ScreenshotSensitivity(controller: sensitivity, child: child);
  }
  return child;
}

Widget _stepApp(
  Widget child, {
  TextScaler textScaler = TextScaler.noScaling,
  bool disableAnimations = false,
}) => _localizedApp(
  Scaffold(body: child),
  textScaler: textScaler,
  disableAnimations: disableAnimations,
);

Widget _localizedApp(
  Widget home, {
  TextScaler textScaler = TextScaler.noScaling,
  bool disableAnimations = false,
}) => EasyLocalization(
  supportedLocales: const [Locale('en')],
  fallbackLocale: const Locale('en'),
  useOnlyLangCode: true,
  path: '$assetsPath/translations',
  child: Builder(
    builder: (context) => MaterialApp(
      locale: context.locale,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      theme: theme.global.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: textScaler,
          disableAnimations: disableAnimations,
        ),
        child: child!,
      ),
      home: home,
    ),
  ),
);

void _setViewSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

GnosisOnboardingProgress _safeProgress({SafeDeployment? deployment}) =>
    GnosisOnboardingProgress(
      isAuthenticated: true,
      isRegistered: true,
      email: 'cardholder@example.test',
      countryCode: 'DE',
      terms: _acceptedTerms,
      kycStatus: GnosisKycStatus.approved,
      isSourceOfFundsAnswered: true,
      phoneNumber: '+4915123456789',
      isPhoneValidated: true,
      phoneChallenge: null,
      safeDeployment: deployment,
      safeConfiguration: null,
      isSafeRegistered: false,
      selectedProduct: null,
      physicalOrder: null,
      isPhysicalOrderReviewed: false,
      paymentReceipt: null,
      provisioningHandle: null,
      isPinProvisioned: false,
      cards: const [],
    );

GnosisOnboardingProgress _physicalProgress({
  required PhysicalCardOrderStatus orderStatus,
  CardOrderPaymentReceipt? receipt,
  CardProvisioningHandle? provisioningHandle,
  List<GnosisPaymentCard> cards = const [],
}) => GnosisOnboardingProgress(
  isAuthenticated: true,
  isRegistered: true,
  email: 'cardholder@example.test',
  countryCode: 'DE',
  terms: _acceptedTerms,
  kycStatus: GnosisKycStatus.approved,
  isSourceOfFundsAnswered: true,
  phoneNumber: '+4915123456789',
  isPhoneValidated: true,
  phoneChallenge: null,
  safeDeployment: _safeDeployment,
  safeConfiguration: _safeConfiguration,
  isSafeRegistered: true,
  selectedProduct: _physicalProduct,
  physicalOrder: _physicalOrder(orderStatus),
  isPhysicalOrderReviewed: true,
  paymentReceipt: receipt,
  provisioningHandle: provisioningHandle,
  isPinProvisioned: false,
  cards: cards,
);

PhysicalCardOrder _physicalOrder(PhysicalCardOrderStatus status) =>
    PhysicalCardOrder(
      id: 'physical-order',
      createdAt: DateTime.utc(2026, 7, 14, 12),
      status: status,
      totalAmountMinor: 999,
      totalDiscountMinor: 0,
      currency: 'EUR',
      embossedName: 'Test Cardholder',
      shippingAddress: const ShippingAddress(
        recipientName: 'Test Cardholder',
        address1: '12 Test Street',
        city: 'Berlin',
        postalCode: '10115',
        country: 'DE',
      ),
      transactionHash: '0xtest-synthetic-receipt',
    );

const _owner = '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

const _acceptedTerms = [
  GnosisTerm(
    id: 'terms',
    title: 'Card agreement',
    version: '2026-07',
    documentUrl: 'https://example.test/card-agreement',
    isAccepted: true,
  ),
];

const _virtualProduct = GnosisCardProduct(
  id: 'virtual',
  kind: GnosisCardKind.virtual,
  title: 'Virtual card',
  description: 'Test virtual product',
  feeMinor: 0,
  currency: 'EUR',
  requiresShipping: false,
  requiresPin: false,
);

const _physicalProduct = GnosisCardProduct(
  id: 'physical',
  kind: GnosisCardKind.physical,
  title: 'Physical card',
  description: 'Test physical product',
  feeMinor: 999,
  currency: 'EUR',
  requiresShipping: true,
  requiresPin: true,
);

final _safeDeployment = SafeDeployment(
  requestId: 'deployment',
  ownerAddress: _owner,
  status: SafeDeploymentStatus.ok,
  updatedAt: DateTime.utc(2026, 7, 14, 12),
);

const _safeConfiguration = SafeConfiguration(
  ownerAddress: _owner,
  isDeployed: true,
  integrity: SafeAccountIntegrity.ok,
  safeAddress: '0x1111111111111111111111111111111111111111',
  delayModule: '0x2222222222222222222222222222222222222222',
  tokenSymbol: 'EURe',
  fiatSymbol: 'EUR',
);

const _paymentQuote = CardOrderPaymentQuote(
  orderId: 'physical-order',
  amountMinor: 999,
  currency: 'EUR',
  assetSymbol: 'EURe',
  assetContract: '0x3333333333333333333333333333333333333333',
  recipient: '0x4444444444444444444444444444444444444444',
  isSimulated: true,
);

final _paymentReceipt = CardOrderPaymentReceipt(
  orderId: 'physical-order',
  transactionHash: '0xtest-synthetic-receipt',
  amountMinor: 999,
  currency: 'EUR',
  paidAt: DateTime.utc(2026, 7, 14, 12),
  isSimulated: true,
);
