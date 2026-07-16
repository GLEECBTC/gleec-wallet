part of 'gnosis_card_bloc.dart';

extension _GnosisCardBlocOperations on GnosisCardBloc {
  Future<void> _runSnapshotAction(
    Emitter<GnosisCardState> emit, {
    required GnosisCardAction action,
    required Future<GnosisCardSnapshot> Function() operation,
    bool isInitialLoad = false,
  }) async {
    final generation = _walletGeneration;
    emit(
      state.copyWith(
        status: isInitialLoad && state.snapshot == null
            ? GnosisCardLoadStatus.loading
            : state.status,
        busyActions: _addBusyAction(action),
        isPinHandoffCancelled: action == GnosisCardAction.completePhysicalPin
            ? false
            : state.isPinHandoffCancelled,
        clearMessage: true,
        clearFailure: true,
        clearFailedAction: true,
      ),
    );
    try {
      var snapshot = await operation();
      if (emit.isDone || generation != _walletGeneration) return;
      snapshot = await _reconcileIfNeeded(snapshot, emit);
      if (emit.isDone || generation != _walletGeneration) return;
      _emitReadySnapshot(emit, snapshot, completedAction: action);
    } catch (error) {
      if (emit.isDone || generation != _walletGeneration) return;
      final failure = _mapFailure(error);
      if (failure.code == GnosisCardFailureCode.sessionExpired &&
          !_approvalDeclined) {
        try {
          if (_canReplayAfterReauthentication(action)) {
            _pendingReauthenticationRetry = operation;
            _pendingReauthenticationAction = action;
          } else {
            _pendingReauthenticationRetry = null;
            _pendingReauthenticationAction = null;
          }
          final snapshot = await _coordinator.prepareEntry();
          if (snapshot.siweChallenge != null && !emit.isDone) {
            emit(
              state.copyWith(
                status: GnosisCardLoadStatus.ready,
                snapshot: snapshot,
                message: failure.message,
                failure: failure,
                failedAction: action,
                automationPhase: GnosisCardAutomationPhase.awaitingSignature,
                intervention: GnosisCardIntervention.walletApproval,
                busyActions: _removeBusyAction(action),
              ),
            );
            return;
          }
        } catch (_) {
          // Keep the original actionable session-expiry failure.
        }
      }
      _emitFailure(emit, failure, action);
    }
  }

  Future<GnosisCardSnapshot> _reconcileIfNeeded(
    GnosisCardSnapshot snapshot,
    Emitter<GnosisCardState> emit,
  ) async {
    final migrationNeedsWork =
        snapshot.safeMigration.isActive ||
        snapshot.safeMigration.status == GnosisSafeMigrationStatus.failed ||
        (snapshot.safeMigration.status == GnosisSafeMigrationStatus.completed &&
            !snapshot.progress.isSafeReady);
    final needsSafeWork =
        snapshot.progress.nextStage == GnosisOnboardingStage.safeDeployment ||
        migrationNeedsWork;
    final order = snapshot.progress.physicalOrder;
    final canResumePhysicalPayment =
        snapshot.progress.nextStage == GnosisOnboardingStage.physicalPayment &&
        order != null &&
        (snapshot.progress.paymentReceipt != null ||
            order.transactionHash != null) &&
        order.status != PhysicalCardOrderStatus.failedTransaction;
    final needsAutomaticFulfillment =
        snapshot.progress.nextStage ==
            GnosisOnboardingStage.virtualCardIssuance ||
        snapshot.progress.nextStage ==
            GnosisOnboardingStage.physicalCardCreation ||
        canResumePhysicalPayment;
    if (!needsSafeWork && !needsAutomaticFulfillment) return snapshot;
    emit(
      state.copyWith(
        snapshot: snapshot,
        automationPhase: GnosisCardAutomationPhase.preparingCardAccount,
        clearIntervention: true,
      ),
    );
    return _coordinator.reconcileAutomaticWork();
  }

  void _emitReadySnapshot(
    Emitter<GnosisCardState> emit,
    GnosisCardSnapshot snapshot, {
    required GnosisCardAction completedAction,
  }) {
    _dashboardReconnectTimer?.cancel();
    emit(
      state.copyWith(
        status: GnosisCardLoadStatus.ready,
        snapshot: snapshot,
        automationPhase: GnosisCardAutomationPhase.ready,
        busyActions: _removeBusyAction(completedAction),
        lastUpdatedAt: DateTime.now(),
        lastCompletedAction: completedAction,
        clearMessage: true,
        clearFailure: true,
        clearFailedAction: true,
        clearIntervention: true,
      ),
    );
    _scheduleKycRefresh(snapshot);
  }

  void _emitFailure(
    Emitter<GnosisCardState> emit,
    Object error,
    GnosisCardAction action,
  ) {
    final failure = _mapFailure(error);
    final latestSnapshot = coordinator?.snapshot;
    emit(
      state.copyWith(
        status: state.snapshot == null
            ? GnosisCardLoadStatus.failure
            : GnosisCardLoadStatus.ready,
        snapshot: latestSnapshot,
        message: failure.message,
        failure: failure,
        failedAction: action,
        automationPhase: GnosisCardAutomationPhase.paused,
        intervention: switch (failure.recovery) {
          GnosisCardRecovery.contactSupport =>
            GnosisCardIntervention.contactSupport,
          GnosisCardRecovery.retry ||
          GnosisCardRecovery.reauthenticate => GnosisCardIntervention.retry,
          _ => null,
        },
        busyActions: _removeBusyAction(action),
      ),
    );
    if (latestSnapshot != null) {
      _scheduleKycRefresh(latestSnapshot);
      _scheduleDashboardReconnect(latestSnapshot, failure);
    }
  }

  void _scheduleKycRefresh(GnosisCardSnapshot snapshot) {
    _kycRefreshTimer?.cancel();
    if (!state.isForeground ||
        snapshot.progress.nextStage != GnosisOnboardingStage.kyc ||
        !const {
          GnosisKycStatus.pending,
          GnosisKycStatus.processing,
        }.contains(snapshot.kycStatus)) {
      return;
    }
    _kycRefreshTimer = Timer(
      const Duration(seconds: 15),
      () => add(const GnosisKycRefreshRequested()),
    );
  }

  void _scheduleDashboardReconnect(
    GnosisCardSnapshot snapshot,
    GnosisCardFailure failure,
  ) {
    _dashboardReconnectTimer?.cancel();
    if (!state.isForeground ||
        snapshot.dashboard == null ||
        !const {
          GnosisCardFailureCode.offline,
          GnosisCardFailureCode.rateLimited,
          GnosisCardFailureCode.serviceUnavailable,
        }.contains(failure.code)) {
      return;
    }
    _dashboardReconnectTimer = Timer(
      const Duration(seconds: 10),
      () => add(const GnosisCardResumed()),
    );
  }

  bool _canReplayAfterReauthentication(GnosisCardAction action) => const {
    GnosisCardAction.initialize,
    GnosisCardAction.refreshKyc,
    GnosisCardAction.deploySafe,
    GnosisCardAction.pollSafe,
    GnosisCardAction.refreshDelayedOperations,
  }.contains(action);

  Future<void> _runExternalFlowAction(
    Emitter<GnosisCardState> emit, {
    required GnosisCardAction action,
    required Future<GnosisExternalFlow> Function() operation,
  }) async {
    final generation = _walletGeneration;
    emit(
      state.copyWith(
        busyActions: _addBusyAction(action),
        clearMessage: true,
        clearFailure: true,
        clearFailedAction: true,
      ),
    );
    try {
      final flow = await operation();
      if (emit.isDone || generation != _walletGeneration) return;
      _publishExternalFlow(emit, flow, completedAction: action);
    } catch (error) {
      if (emit.isDone || generation != _walletGeneration) return;
      final failure = _mapFailure(error);
      emit(
        state.copyWith(
          status: state.snapshot == null
              ? GnosisCardLoadStatus.failure
              : GnosisCardLoadStatus.ready,
          snapshot: coordinator?.snapshot,
          message: failure.message,
          failure: failure,
          failedAction: action,
          busyActions: _removeBusyAction(action),
        ),
      );
    }
  }

  void _publishExternalFlow(
    Emitter<GnosisCardState> emit,
    GnosisExternalFlow flow, {
    GnosisCardAction? completedAction,
  }) {
    _externalFlowSequence += 1;
    final effect = GnosisExternalFlow(
      id: '${flow.id}-$_externalFlowSequence',
      kind: flow.kind,
      url: flow.url,
    );
    emit(
      state.copyWith(
        status: state.snapshot == null
            ? state.status
            : GnosisCardLoadStatus.ready,
        externalFlow: effect,
        busyActions: completedAction == null
            ? state.busyActions
            : _removeBusyAction(completedAction),
        clearMessage: true,
        clearFailure: true,
        clearFailedAction: true,
      ),
    );
  }

  Set<GnosisCardAction> _addBusyAction(GnosisCardAction action) =>
      Set<GnosisCardAction>.unmodifiable({...state.busyActions, action});

  Set<GnosisCardAction> _removeBusyAction(GnosisCardAction action) =>
      Set<GnosisCardAction>.unmodifiable(
        state.busyActions.where((busyAction) => busyAction != action),
      );

  bool _isRedundantSafeTransition(GnosisSafeTransitionEvent event) {
    final deployment = coordinator?.snapshot.progress.safeDeployment;
    return switch (event) {
      GnosisSafeDeployRequested() => deployment != null,
      GnosisSafePollRequested() => false,
    };
  }

  bool _isRedundantPhysicalTransition(GnosisPhysicalTransitionEvent event) {
    final progress = coordinator?.snapshot.progress;
    if (progress == null) return false;
    final order = progress.physicalOrder;
    return switch (event) {
      GnosisPhysicalShippingSubmitted() =>
        order != null && order.status != PhysicalCardOrderStatus.cancelled,
      GnosisPhysicalOrderReviewConfirmed() => progress.isPhysicalOrderReviewed,
      GnosisPhysicalPaymentRequested() => progress.paymentReceipt != null,
      GnosisPhysicalPaymentConfirmed() =>
        order?.status == PhysicalCardOrderStatus.ready ||
            order?.status == PhysicalCardOrderStatus.cardCreated,
      GnosisPhysicalCardCreateRequested() =>
        progress.provisioningHandle != null ||
            order?.status == PhysicalCardOrderStatus.cardCreated,
      GnosisPhysicalPinCompleted() => progress.isPinProvisioned,
      GnosisPhysicalPinCancelled() => false,
      GnosisPhysicalOrderEditRequested() =>
        order == null || !order.isCancellable,
      GnosisPhysicalOrderCancelRequested() =>
        order == null || !order.isCancellable,
    };
  }

  GnosisCardFailure _mapFailure(Object error) {
    if (error is GnosisCardFailure) return error;
    return const GnosisCardFailure(
      code: GnosisCardFailureCode.unavailable,
      message:
          'Something went wrong. Your completed onboarding steps are preserved.',
      recovery: GnosisCardRecovery.retry,
    );
  }
}
