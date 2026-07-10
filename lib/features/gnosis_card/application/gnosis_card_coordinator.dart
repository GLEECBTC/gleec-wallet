import 'package:equatable/equatable.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_models.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_ports.dart';

class GnosisCardSnapshot extends Equatable {
  const GnosisCardSnapshot({
    required this.stage,
    this.session,
    this.kycStatus,
    this.deployment,
    this.dashboard,
    this.reviewIntent,
  });

  final GnosisOnboardingStage stage;
  final GnosisCardSession? session;
  final GnosisKycStatus? kycStatus;
  final SafeDeployment? deployment;
  final GnosisCardDashboard? dashboard;
  final PreparedSmartAccountIntent? reviewIntent;

  GnosisCardSnapshot copyWith({
    GnosisOnboardingStage? stage,
    GnosisCardSession? session,
    GnosisKycStatus? kycStatus,
    SafeDeployment? deployment,
    GnosisCardDashboard? dashboard,
    PreparedSmartAccountIntent? reviewIntent,
    bool clearReview = false,
  }) => GnosisCardSnapshot(
    stage: stage ?? this.stage,
    session: session ?? this.session,
    kycStatus: kycStatus ?? this.kycStatus,
    deployment: deployment ?? this.deployment,
    dashboard: dashboard ?? this.dashboard,
    reviewIntent: clearReview ? null : reviewIntent ?? this.reviewIntent,
  );

  @override
  List<Object?> get props => [
    stage,
    session,
    kycStatus,
    deployment,
    dashboard,
    reviewIntent,
  ];
}

/// Facade over repository plus signer workflows. Gnosis API deployment stays
/// in the repository; this class only polls, verifies, then registers in KDF.
class GnosisCardCoordinator {
  GnosisCardCoordinator({required this.repository, required this.signer});

  final GnosisPayRepository repository;
  final SmartAccountSigner signer;

  GnosisCardSnapshot _snapshot = const GnosisCardSnapshot(
    stage: GnosisOnboardingStage.signedOut,
  );

  Future<GnosisCardSnapshot> initialize() async {
    final stage = await repository.onboardingStage();
    _snapshot = GnosisCardSnapshot(stage: stage);
    if (stage == GnosisOnboardingStage.ready) {
      final deployment = await repository.safeDeployment();
      if (deployment?.safeAddress == null) {
        throw const GnosisCardUnavailable(
          'The deployed Safe could not be restored after restart.',
        );
      }
      await repository.validateSafeIntegrity(deployment!);
      await signer.registerSafe(deployment.safeAddress!);
      _snapshot = _snapshot.copyWith(
        stage: GnosisOnboardingStage.ready,
        deployment: deployment,
        dashboard: await repository.dashboard(),
      );
    }
    return _snapshot;
  }

  Future<GnosisCardSnapshot> advance() async {
    switch (_snapshot.stage) {
      case GnosisOnboardingStage.signedOut:
        final identity = await signer.owner();
        final message = await repository.createSiweMessage(
          ownerAddress: identity.address,
        );
        final signature = await signer.signPersonalMessage(message);
        final session = await repository.authenticate(
          ownerAddress: identity.address,
          signature: signature,
        );
        if (session.isExpired) {
          throw const GnosisCardUnavailable(
            'The card session expired. Sign in again to continue.',
          );
        }
        _snapshot = _snapshot.copyWith(
          stage: GnosisOnboardingStage.terms,
          session: session,
        );
        return _snapshot;
      case GnosisOnboardingStage.terms:
        await repository.acceptTerms();
        _snapshot = _snapshot.copyWith(
          stage: GnosisOnboardingStage.registration,
        );
        return _snapshot;
      case GnosisOnboardingStage.registration:
        await repository.registerApplicant();
        _snapshot = _snapshot.copyWith(
          stage: GnosisOnboardingStage.phoneAndSourceOfFunds,
        );
        return _snapshot;
      case GnosisOnboardingStage.phoneAndSourceOfFunds:
        await repository.submitPhoneAndSourceOfFunds();
        _snapshot = _snapshot.copyWith(
          stage: GnosisOnboardingStage.kycPending,
          kycStatus: GnosisKycStatus.pending,
        );
        return _snapshot;
      case GnosisOnboardingStage.kycPending:
        final status = await repository.pollKyc();
        if (status != GnosisKycStatus.approved) {
          throw GnosisCardUnavailable(
            status == GnosisKycStatus.expired
                ? 'Identity verification expired. Restart KYC to continue.'
                : 'Identity verification is not approved yet.',
          );
        }
        _snapshot = _snapshot.copyWith(
          stage: GnosisOnboardingStage.safeDeployment,
          kycStatus: status,
        );
        return _snapshot;
      case GnosisOnboardingStage.safeDeployment:
        SafeDeployment deployment =
            _snapshot.deployment ?? await repository.requestSafeDeployment();
        for (var poll = 0; poll < 4; poll += 1) {
          if (deployment.status == SafeDeploymentStatus.ok ||
              deployment.status == SafeDeploymentStatus.failed) {
            break;
          }
          deployment = await repository.pollSafeDeployment(
            deployment.requestId,
          );
          _snapshot = _snapshot.copyWith(deployment: deployment);
        }
        if (deployment.status != SafeDeploymentStatus.ok ||
            deployment.safeAddress == null) {
          throw GnosisCardUnavailable(
            deployment.failureReason ?? 'Safe deployment did not complete.',
          );
        }
        await repository.validateSafeIntegrity(deployment);
        await signer.registerSafe(deployment.safeAddress!);
        _snapshot = _snapshot.copyWith(
          stage: GnosisOnboardingStage.cardIssuance,
          deployment: deployment,
        );
        return _snapshot;
      case GnosisOnboardingStage.cardIssuance:
        await repository.issueVirtualCard();
        _snapshot = _snapshot.copyWith(
          stage: GnosisOnboardingStage.ready,
          dashboard: await repository.dashboard(),
        );
        return _snapshot;
      case GnosisOnboardingStage.ready:
        _snapshot = _snapshot.copyWith(dashboard: await repository.dashboard());
        return _snapshot;
    }
  }

  Future<GnosisCardSnapshot> orderPhysicalCard() async {
    final order = await repository.orderPhysicalCard();
    await repository.payAndShipPhysicalCard(order.id);
    return _snapshot = _snapshot.copyWith(
      dashboard: await repository.dashboard(),
    );
  }

  Future<GnosisCardSnapshot> setFrozen(String cardId, bool frozen) async =>
      _snapshot = _snapshot.copyWith(
        dashboard: await repository.setFrozen(cardId: cardId, frozen: frozen),
      );

  Future<GnosisCardSnapshot> setCardStatus(
    String cardId,
    GnosisCardStatus status,
  ) async => _snapshot = _snapshot.copyWith(
    dashboard: await repository.setCardStatus(cardId: cardId, status: status),
  );

  Future<GnosisCardSnapshot> updateControls(
    GnosisCardControls controls,
  ) async => _snapshot = _snapshot.copyWith(
    dashboard: await repository.updateControls(controls),
  );

  Future<GnosisCardSnapshot> pollDelayedOperations() async => _snapshot =
      _snapshot.copyWith(dashboard: await repository.pollDelayedOperations());

  Future<GnosisCardSnapshot> prepareWithdrawal(
    WithdrawalRequest request,
  ) async => _snapshot = _snapshot.copyWith(
    reviewIntent: await repository.prepareWithdrawal(request),
  );

  Future<GnosisCardSnapshot> prepareDailyLimit(
    DailyLimitRequest request,
  ) async => _snapshot = _snapshot.copyWith(
    reviewIntent: await repository.prepareDailyLimit(request),
  );

  Future<GnosisCardSnapshot> confirmPreparedIntent() async {
    final intent = _snapshot.reviewIntent;
    if (intent == null) {
      throw const GnosisCardUnavailable('There is no reviewed intent to sign.');
    }
    final signature = await signer.signTypedData(intent);
    await repository.submitSignedOperation(
      intent: intent,
      signature: signature,
    );
    return _snapshot = _snapshot.copyWith(
      dashboard: await repository.dashboard(),
      clearReview: true,
    );
  }

  GnosisCardSnapshot cancelPreparedIntent() =>
      _snapshot = _snapshot.copyWith(clearReview: true);
}
