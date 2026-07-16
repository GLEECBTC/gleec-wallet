import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/features/gnosis_card/application/gnosis_card_bloc.dart';
import 'package:web_dex/features/gnosis_card/application/gnosis_card_coordinator.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_models.dart';
import 'package:web_dex/features/gnosis_card/infrastructure/deterministic_gnosis_pay_repository.dart';
import 'package:web_dex/features/gnosis_card/infrastructure/gnosis_card_config.dart';

import 'gnosis_card_test_helpers.dart';

const _mockConfig = GnosisCardConfig(
  mode: GnosisCardMode.mock,
  scenario: GnosisCardScenario.happyPath,
  failureReason: null,
);

void main() {
  blocTest<GnosisCardBloc, GnosisCardState>(
    'fails closed when card mode is disabled',
    build: () => GnosisCardBloc(
      config: const GnosisCardConfig(
        mode: GnosisCardMode.disabled,
        scenario: GnosisCardScenario.happyPath,
        failureReason: 'Disabled for test',
      ),
      coordinator: null,
    ),
    act: (bloc) => bloc.add(const GnosisCardStarted()),
    expect: () => const [
      GnosisCardState(
        status: GnosisCardLoadStatus.disabled,
        message: 'Disabled for test',
      ),
    ],
  );

  test(
    'drops duplicate submissions and exposes action-scoped busy state',
    () async {
      final signer = GnosisTestSigner()
        ..personalSignatureGate = Completer<void>();
      final coordinator = _coordinator(
        DeterministicGnosisPayRepository(
          scenario: GnosisCardScenario.happyPath,
        ),
        signer,
      );
      final initialSnapshot = await coordinator.initialize();
      final bloc = GnosisCardBloc(
        config: _mockConfig,
        coordinator: coordinator,
        initialState: GnosisCardState(
          status: GnosisCardLoadStatus.ready,
          snapshot: initialSnapshot,
        ),
      );
      addTearDown(bloc.close);

      final busyState = bloc.stream.firstWhere(
        (state) => state.isBusy(GnosisCardAction.signIn),
      );
      bloc
        ..add(const GnosisSignInRequested())
        ..add(const GnosisSignInRequested());

      final busy = await busyState;
      await signer.personalSignatureStarted.future;
      expect(busy.status, GnosisCardLoadStatus.ready);
      expect(busy.snapshot, same(initialSnapshot));
      expect(signer.personalSignatureCalls, 1);

      final completed = bloc.stream.firstWhere(
        (state) =>
            state.snapshot?.stage == GnosisOnboardingStage.signupAndTerms &&
            !state.isBusy(GnosisCardAction.signIn),
      );
      signer.personalSignatureGate!.complete();
      await completed;
      expect(signer.personalSignatureCalls, 1);
    },
  );

  test('retains the active snapshot for expired-session recovery', () async {
    final coordinator = _coordinator(
      DeterministicGnosisPayRepository(
        scenario: GnosisCardScenario.expiredSession,
      ),
      GnosisTestSigner(),
    );
    final initialSnapshot = await coordinator.initialize();
    final bloc = GnosisCardBloc(
      config: _mockConfig,
      coordinator: coordinator,
      initialState: GnosisCardState(
        status: GnosisCardLoadStatus.ready,
        snapshot: initialSnapshot,
      ),
    );
    addTearDown(bloc.close);

    final failed = bloc.stream.firstWhere(
      (state) => state.failure?.code == GnosisCardFailureCode.sessionExpired,
    );
    bloc.add(const GnosisSignInRequested());

    final state = await failed;
    expect(state.status, GnosisCardLoadStatus.ready);
    expect(state.snapshot?.stage, GnosisOnboardingStage.signedOut);
    expect(state.failedAction, GnosisCardAction.signIn);
    expect(state.failure?.recovery, GnosisCardRecovery.reauthenticate);
    expect(state.busyActions, isEmpty);
  });

  test(
    'publishes unique external effects and safely handles launch failure',
    () async {
      const snapshot = GnosisCardSnapshot.initial();
      final bloc = GnosisCardBloc(
        config: _mockConfig,
        coordinator: null,
        initialState: const GnosisCardState(
          status: GnosisCardLoadStatus.ready,
          snapshot: snapshot,
        ),
      );
      addTearDown(bloc.close);
      const term = GnosisTerm(
        id: 'terms',
        title: 'Card agreement',
        version: '2026-07',
        documentUrl: 'https://example.test/card-agreement',
        isAccepted: false,
      );

      final firstEffect = bloc.stream.firstWhere(
        (state) => state.externalFlow != null,
      );
      bloc.add(const GnosisTermOpenRequested(term));
      final first = (await firstEffect).externalFlow!;
      expect(first.kind, GnosisExternalFlowKind.terms);

      final cleared = bloc.stream.firstWhere(
        (state) => state.externalFlow == null,
      );
      bloc.add(GnosisExternalFlowHandled(first.id));
      await cleared;

      final secondEffect = bloc.stream.firstWhere(
        (state) => state.externalFlow != null,
      );
      bloc.add(const GnosisTermOpenRequested(term));
      final second = (await secondEffect).externalFlow!;
      expect(second.id, isNot(first.id));

      final launchFailure = bloc.stream.firstWhere(
        (state) => state.failure?.code == GnosisCardFailureCode.unavailable,
      );
      bloc.add(GnosisExternalFlowLaunchFailed(second.id));
      final failed = await launchFailure;
      expect(failed.snapshot, same(snapshot));
      expect(failed.externalFlow, isNull);
      expect(failed.failure?.isRecoverable, isTrue);
      expect(failed.failedAction, GnosisCardAction.signupAndTerms);
    },
  );

  test('serializes and deduplicates physical-order submissions', () async {
    final repository = _CountingRepository();
    final coordinator = _coordinator(repository, GnosisTestSigner());
    await _advanceToPhysicalShipping(coordinator);
    final bloc = GnosisCardBloc(
      config: _mockConfig,
      coordinator: coordinator,
      initialState: GnosisCardState(
        status: GnosisCardLoadStatus.ready,
        snapshot: coordinator.snapshot,
      ),
    );
    addTearDown(bloc.close);
    const address = ShippingAddress(
      recipientName: 'Test Cardholder',
      address1: '12 Test Street',
      city: 'Berlin',
      postalCode: '10115',
      country: 'DE',
    );

    final reviewed = bloc.stream.firstWhere(
      (state) =>
          state.snapshot?.stage == GnosisOnboardingStage.physicalOrderReview,
    );
    bloc
      ..add(const GnosisPhysicalShippingSubmitted(address))
      ..add(const GnosisPhysicalShippingSubmitted(address));

    final state = await reviewed;
    expect(state.failure, isNull);
    expect(repository.createPhysicalOrderCalls, 1);
    expect(state.snapshot?.progress.physicalOrder, isNotNull);
  });
}

GnosisCardCoordinator _coordinator(
  DeterministicGnosisPayRepository repository,
  GnosisTestSigner signer,
) => GnosisCardCoordinator(
  repository: repository,
  signer: signer,
  externalFlowLauncher: RecordingExternalFlowLauncher(),
  paymentGateway: GnosisTestPaymentGateway(),
);

Future<void> _advanceToPhysicalShipping(
  GnosisCardCoordinator coordinator,
) async {
  await coordinator.initialize();
  var snapshot = await coordinator.signIn();
  await coordinator.signUpAndAcceptTerms(
    email: 'cardholder@example.test',
    acceptances: [
      for (final term in snapshot.terms)
        GnosisTermAcceptance(id: term.id, version: term.version),
    ],
  );
  await coordinator.kycFlow();
  await coordinator.refreshKyc();
  snapshot = await coordinator.refreshKyc();
  await coordinator.submitSourceOfFunds([
    for (final question in snapshot.sourceOfFundsQuestions)
      SourceOfFundsAnswer(
        questionId: question.id,
        question: question.title,
        answer: question.answers.first,
      ),
  ]);
  await coordinator.requestPhoneOtp('+4915123456789');
  await coordinator.verifyPhoneOtp('123456');
  await coordinator.deploySafe();
  await coordinator.pollSafe();
  snapshot = await coordinator.pollSafe();
  final physical = snapshot.cardProducts.firstWhere(
    (product) => product.kind == GnosisCardKind.physical,
  );
  await coordinator.selectCardProduct(physical.id);
}

class _CountingRepository extends DeterministicGnosisPayRepository {
  _CountingRepository() : super(scenario: GnosisCardScenario.happyPath);

  int createPhysicalOrderCalls = 0;

  @override
  Future<PhysicalCardOrder> createPhysicalCardOrder({
    required String productId,
    required ShippingAddress shippingAddress,
  }) {
    createPhysicalOrderCalls += 1;
    return super.createPhysicalCardOrder(
      productId: productId,
      shippingAddress: shippingAddress,
    );
  }
}
