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

part 'gnosis_card_page_privacy_test.dart';
part 'gnosis_card_page_test_support.dart';

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

  testWidgets(
    'automatic entry requests one concise approval and respects Not now',
    (tester) async {
      _setViewSize(tester, const Size(390, 844));
      final launcher = RecordingExternalFlowLauncher();
      final payment = GnosisTestPaymentGateway();
      final coordinator = _coordinator(
        DeterministicGnosisPayRepository(
          scenario: GnosisCardScenario.happyPath,
        ),
        GnosisTestSigner(),
        launcher,
        payment,
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
      );
      addTearDown(bloc.close);

      await tester.pumpWidget(_pageApp(bloc, dependencies));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Securely connect your wallet'), findsOneWidget);
      expect(find.text('Activate GNO'), findsNothing);
      expect(find.text('Sign in with wallet'), findsNothing);
      expect(find.text('Initialize card account'), findsNothing);

      await tester.tap(find.text('Not now'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Securely connect your wallet'), findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Securely connect your wallet'), findsNothing);
    },
  );

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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(bloc.state.snapshot?.kycStatus, GnosisKycStatus.processing);

    await tester.pump(const Duration(seconds: 15));
    await tester.pump(const Duration(milliseconds: 100));
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

  testWidgets('Safe state exposes automatic progress and live semantics', (
    tester,
  ) async {
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
          onRetry: () {},
          onSupport: () {},
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
    expect(find.byKey(const Key('gnosis-safe-primary')), findsNothing);
    expect(find.byKey(const Key('gnosis-safe-reset')), findsNothing);
  });

  testWidgets('card choice and payment expose one explicit authorization', (
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
    expect(find.text('Authorize payment'), findsOneWidget);
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
    expect(find.byKey(const Key('gnosis-payment-submit')), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(confirmationCalls, 0);
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

    await tester.pumpWidget(
      _pageApp(bloc, dependencies, manageLifecycle: false),
    );
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
    for (final size in <Size>[
      const Size(375, 812),
      const Size(768, 1024),
      const Size(1024, 900),
      const Size(1440, 900),
    ]) {
      for (final scale in <double>[1, 1.4, 2]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          _stepApp(
            GnosisOnboardingFrame(
              milestoneIndex: 1,
              child: GnosisPhoneNumberStep(
                busy: false,
                verifiedCallingCode: '+49',
                onSubmit: (_) {},
              ),
            ),
            textScaler: TextScaler.linear(scale),
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
    }
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });

  _registerGnosisCardPrivacyTest();
}
