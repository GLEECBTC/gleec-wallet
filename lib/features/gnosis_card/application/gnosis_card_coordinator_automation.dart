part of 'gnosis_card_coordinator.dart';

abstract class _GnosisCardCoordinatorAutomation
    extends _GnosisCardCoordinatorOnboarding {
  _GnosisCardCoordinatorAutomation({
    required super.repository,
    required super.signer,
    required super.externalFlowLauncher,
    required super.paymentGateway,
    super.readiness,
  });

  Future<GnosisCardSnapshot> reconcileAutomaticWork() {
    final active = _automationFlight;
    if (active != null) return active;
    late final Future<GnosisCardSnapshot> flight;
    flight = _reconcileAutomaticWork().whenComplete(() {
      if (identical(_automationFlight, flight)) _automationFlight = null;
    });
    _automationFlight = flight;
    return flight;
  }

  Future<GnosisCardSnapshot> _reconcileAutomaticWork() async {
    final generation = _automationGeneration;
    await _refresh();
    if (generation != _automationGeneration) return _snapshot;
    var migration = _snapshot.safeMigration;
    if (migration.status == GnosisSafeMigrationStatus.failed) {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.migrationFailed,
        message: 'Your card account migration needs support.',
        recovery: GnosisCardRecovery.contactSupport,
      );
    }
    var migrationDelay = const Duration(seconds: 2);
    final migrationStopwatch = Stopwatch()..start();
    while (migration.isActive) {
      if (migrationStopwatch.elapsed >= const Duration(seconds: 90)) {
        return _snapshot;
      }
      await Future<void>.delayed(migrationDelay);
      if (generation != _automationGeneration) return _snapshot;
      await _refresh();
      migration = _snapshot.safeMigration;
      migrationDelay = migrationDelay * 2;
      if (migrationDelay > const Duration(seconds: 10)) {
        migrationDelay = const Duration(seconds: 10);
      }
    }
    if (migration.status == GnosisSafeMigrationStatus.failed) {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.migrationFailed,
        message: 'Your card account migration needs support.',
        recovery: GnosisCardRecovery.contactSupport,
      );
    }
    if (migration.status == GnosisSafeMigrationStatus.completed) {
      final currentSafe = migration.currentSafe;
      if (currentSafe == null ||
          currentSafe.chainId != 100 ||
          !RegExp(r'^0x[a-fA-F0-9]{40}$').hasMatch(currentSafe.address)) {
        throw const GnosisCardFailure(
          code: GnosisCardFailureCode.safeIntegrityFailed,
          message: 'The updated card account could not be verified.',
          recovery: GnosisCardRecovery.contactSupport,
        );
      }
      if (_registeredSafe?.toLowerCase() != currentSafe.address.toLowerCase()) {
        _registeredSafe = null;
        _registeredSafeOwner = null;
      }
      for (var attempt = 0; attempt < 3; attempt += 1) {
        await _refresh();
        if (generation != _automationGeneration) return _snapshot;
        if (_migrationConfigurationIsAuthoritative) break;
        if (attempt < 2) {
          await Future<void>.delayed(Duration(seconds: 2 << attempt));
          if (generation != _automationGeneration) return _snapshot;
        }
      }
      if (!_migrationConfigurationIsAuthoritative) {
        throw const GnosisCardFailure(
          code: GnosisCardFailureCode.serviceUnavailable,
          message: 'The updated card account is still synchronizing.',
          recovery: GnosisCardRecovery.retry,
        );
      }
      await _restoreVerifiedSafe();
    }
    if (_snapshot.progress.nextStage == GnosisOnboardingStage.safeDeployment) {
      await _reconcileSafeDeployment(generation);
    }
    if (generation != _automationGeneration) return _snapshot;
    return _resumeAutomaticCardFulfillment(generation);
  }

  Future<void> _reconcileSafeDeployment(int generation) async {
    final owner = await _ownerAddress();
    if (generation != _automationGeneration) return;
    final existing = await repository.safeDeployment(ownerAddress: owner);
    if (generation != _automationGeneration) return;
    final SafeDeployment deploymentAtStart;
    if (existing == null) {
      deploymentAtStart = await repository.requestSafeDeployment(
        ownerAddress: owner,
      );
    } else {
      deploymentAtStart = existing;
    }
    var deployment = deploymentAtStart;
    if (generation != _automationGeneration) return;
    if (existing == null) {
      await _refresh();
    }
    final stopwatch = Stopwatch()..start();
    var pollDelay = const Duration(seconds: 2);
    while (deployment.status == SafeDeploymentStatus.accepted ||
        deployment.status == SafeDeploymentStatus.processing) {
      if (stopwatch.elapsed >= const Duration(seconds: 90)) {
        await _refresh();
        return;
      }
      await Future<void>.delayed(pollDelay);
      if (generation != _automationGeneration) return;
      deployment = await repository.pollSafeDeployment(ownerAddress: owner);
      await _refresh();
      pollDelay = pollDelay * 2;
      if (pollDelay > const Duration(seconds: 10)) {
        pollDelay = const Duration(seconds: 10);
      }
    }
    if (deployment.status == SafeDeploymentStatus.failed) {
      throw GnosisCardFailure(
        code: GnosisCardFailureCode.deploymentFailed,
        message: deployment.failureReason ?? 'Card account setup failed.',
        recovery: GnosisCardRecovery.contactSupport,
      );
    }
    if (deployment.status == SafeDeploymentStatus.timedOut) {
      return;
    }
    final configuration = await repository.safeConfiguration(
      ownerAddress: owner,
    );
    if (generation != _automationGeneration) return;
    await _validateAndRegister(configuration);
    await _refresh();
  }

  Future<GnosisCardSnapshot> _resumeAutomaticCardFulfillment(
    int generation,
  ) async {
    final stage = _snapshot.progress.nextStage;
    if (stage == GnosisOnboardingStage.virtualCardIssuance) {
      if (generation != _automationGeneration) return _snapshot;
      return issueVirtualCard();
    }
    if (stage == GnosisOnboardingStage.physicalPayment) {
      final order = _snapshot.progress.physicalOrder;
      final hasPayment =
          _snapshot.progress.paymentReceipt != null ||
          order?.transactionHash != null;
      if (order != null &&
          hasPayment &&
          order.status != PhysicalCardOrderStatus.failedTransaction) {
        if (generation != _automationGeneration) return _snapshot;
        await repository.confirmPhysicalCardPayment(orderId: order.id);
        await _refresh();
      }
    }
    if (_snapshot.progress.nextStage ==
        GnosisOnboardingStage.physicalCardCreation) {
      final order = _requirePhysicalOrder();
      if (generation != _automationGeneration) return _snapshot;
      await repository.createPhysicalCard(orderId: order.id);
      await _refresh();
    }
    return _snapshot;
  }
}
