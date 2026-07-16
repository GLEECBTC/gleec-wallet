part of 'gnosis_card_bloc.dart';

extension _GnosisCardBlocHandlers on GnosisCardBloc {
  void _onTermOpenRequested(
    GnosisTermOpenRequested event,
    Emitter<GnosisCardState> emit,
  ) {
    if (state.externalFlow != null) return;
    _publishExternalFlow(
      emit,
      GnosisExternalFlow(
        id: 'term-${event.term.id}',
        kind: GnosisExternalFlowKind.terms,
        url: event.term.documentUrl,
      ),
    );
  }

  Future<void> _onKycRefreshRequested(
    GnosisKycRefreshRequested event,
    Emitter<GnosisCardState> emit,
  ) async {
    if (!state.isForeground) return;
    await _runSnapshotAction(
      emit,
      action: GnosisCardAction.refreshKyc,
      operation: () => _coordinator.refreshKyc(),
    );
  }

  Future<void> _onSafeTransition(
    GnosisSafeTransitionEvent event,
    Emitter<GnosisCardState> emit,
  ) async {
    if (_isRedundantSafeTransition(event)) return;
    switch (event) {
      case GnosisSafeDeployRequested():
        await _runSnapshotAction(
          emit,
          action: GnosisCardAction.deploySafe,
          operation: () => _coordinator.deploySafe(),
        );
      case GnosisSafePollRequested():
        await _runSnapshotAction(
          emit,
          action: GnosisCardAction.pollSafe,
          operation: () => _coordinator.pollSafe(),
        );
    }
  }

  Future<void> _onPhysicalTransition(
    GnosisPhysicalTransitionEvent event,
    Emitter<GnosisCardState> emit,
  ) async {
    if (_isRedundantPhysicalTransition(event)) return;
    switch (event) {
      case GnosisPhysicalShippingSubmitted():
        await _runSnapshotAction(
          emit,
          action: GnosisCardAction.submitPhysicalShipping,
          operation: () => _coordinator.createPhysicalCardOrder(event.address),
        );
      case GnosisPhysicalOrderReviewConfirmed():
        await _runSnapshotAction(
          emit,
          action: GnosisCardAction.confirmPhysicalOrderReview,
          operation: () => _coordinator.confirmPhysicalOrderReview(),
        );
      case GnosisPhysicalPaymentRequested():
        await _runSnapshotAction(
          emit,
          action: GnosisCardAction.payPhysicalOrder,
          operation: () => _coordinator.payForPhysicalCard(),
        );
      case GnosisPhysicalPaymentConfirmed():
        await _runSnapshotAction(
          emit,
          action: GnosisCardAction.confirmPhysicalPayment,
          operation: () => _coordinator.confirmPhysicalCardPayment(),
        );
      case GnosisPhysicalCardCreateRequested():
        await _runSnapshotAction(
          emit,
          action: GnosisCardAction.createPhysicalCard,
          operation: () => _coordinator.createPhysicalCard(),
        );
      case GnosisPhysicalPinCompleted():
        await _runSnapshotAction(
          emit,
          action: GnosisCardAction.completePhysicalPin,
          operation: () => _coordinator.completePinProvisioning(),
        );
      case GnosisPhysicalPinCancelled():
        emit(
          state.copyWith(
            isPinHandoffCancelled: true,
            clearMessage: true,
            clearFailure: true,
            clearFailedAction: true,
          ),
        );
      case GnosisPhysicalOrderEditRequested():
        await _runSnapshotAction(
          emit,
          action: GnosisCardAction.editPhysicalOrder,
          operation: () => _coordinator.editPhysicalCardOrder(),
        );
      case GnosisPhysicalOrderCancelRequested():
        await _runSnapshotAction(
          emit,
          action: GnosisCardAction.cancelPhysicalOrder,
          operation: () => _coordinator.cancelPhysicalCardOrder(),
        );
    }
  }

  void _onExternalFlowHandled(
    GnosisExternalFlowHandled event,
    Emitter<GnosisCardState> emit,
  ) {
    if (state.externalFlow?.id != event.effectId) return;
    emit(state.copyWith(clearExternalFlow: true));
  }

  void _onExternalFlowLaunchFailed(
    GnosisExternalFlowLaunchFailed event,
    Emitter<GnosisCardState> emit,
  ) {
    final flow = state.externalFlow;
    if (flow == null || flow.id != event.effectId) return;
    final action = switch (flow.kind) {
      GnosisExternalFlowKind.terms => GnosisCardAction.signupAndTerms,
      GnosisExternalFlowKind.kyc => GnosisCardAction.launchKyc,
      GnosisExternalFlowKind.support => GnosisCardAction.openSupport,
    };
    final recovery = flow.kind == GnosisExternalFlowKind.kyc
        ? GnosisCardRecovery.reopenKyc
        : GnosisCardRecovery.retry;
    const message = 'The external onboarding page could not be opened.';
    emit(
      state.copyWith(
        status: state.snapshot == null
            ? GnosisCardLoadStatus.failure
            : GnosisCardLoadStatus.ready,
        failure: GnosisCardFailure(
          code: GnosisCardFailureCode.unavailable,
          message: message,
          recovery: recovery,
        ),
        failedAction: action,
        message: message,
        clearExternalFlow: true,
      ),
    );
  }

  Future<void> _onCardFreezeChanged(
    GnosisCardFreezeChanged event,
    Emitter<GnosisCardState> emit,
  ) => _runSnapshotAction(
    emit,
    action: GnosisCardAction.setCardFrozen,
    operation: () => _coordinator.setFrozen(event.cardId, event.frozen),
  );

  Future<void> _onCardStatusChanged(
    GnosisCardStatusChanged event,
    Emitter<GnosisCardState> emit,
  ) => _runSnapshotAction(
    emit,
    action: GnosisCardAction.setCardStatus,
    operation: () => _coordinator.setCardStatus(event.cardId, event.status),
  );

  Future<void> _onCardControlsChanged(
    GnosisCardControlsChanged event,
    Emitter<GnosisCardState> emit,
  ) => _runSnapshotAction(
    emit,
    action: GnosisCardAction.updateCardControls,
    operation: () => _coordinator.updateControls(
      cardId: event.cardId,
      controls: event.controls,
    ),
  );

  Future<void> _onWithdrawalReviewRequested(
    GnosisWithdrawalReviewRequested event,
    Emitter<GnosisCardState> emit,
  ) => _runSnapshotAction(
    emit,
    action: GnosisCardAction.prepareWithdrawal,
    operation: () => _coordinator.prepareWithdrawal(event.request),
  );

  Future<void> _onDailyLimitReviewRequested(
    GnosisDailyLimitReviewRequested event,
    Emitter<GnosisCardState> emit,
  ) => _runSnapshotAction(
    emit,
    action: GnosisCardAction.prepareDailyLimit,
    operation: () => _coordinator.prepareDailyLimit(event.request),
  );

  Future<void> _onPreparedIntentConfirmed(
    GnosisPreparedIntentConfirmed event,
    Emitter<GnosisCardState> emit,
  ) => _runSnapshotAction(
    emit,
    action: GnosisCardAction.confirmPreparedIntent,
    operation: () => _coordinator.confirmPreparedIntent(),
  );

  Future<void> _onPreparedIntentCancelled(
    GnosisPreparedIntentCancelled event,
    Emitter<GnosisCardState> emit,
  ) => _runSnapshotAction(
    emit,
    action: GnosisCardAction.cancelPreparedIntent,
    operation: () async => _coordinator.cancelPreparedIntent(),
  );

  Future<void> _onDelayedOperationsRefreshRequested(
    GnosisDelayedOperationsRefreshRequested event,
    Emitter<GnosisCardState> emit,
  ) => _runSnapshotAction(
    emit,
    action: GnosisCardAction.refreshDelayedOperations,
    operation: () => _coordinator.pollDelayedOperations(),
  );

  Future<void> _onMigrationNoticeStatusRequested(
    GnosisMigrationNoticeStatusRequested event,
    Emitter<GnosisCardState> emit,
  ) async {
    if (state.snapshot?.safeMigration.migrationId != event.migrationId) return;
    final walletIdentity = state.snapshot?.session?.ownerAddress ?? _walletId;
    var dismissed = false;
    if (walletIdentity != null && migrationNoticeStore != null) {
      try {
        dismissed = await migrationNoticeStore!.isDismissed(
          walletIdentity: walletIdentity,
          migrationId: event.migrationId,
        );
      } catch (_) {
        // A storage failure must not block the card dashboard.
      }
    }
    if (emit.isDone ||
        state.snapshot?.safeMigration.migrationId != event.migrationId) {
      return;
    }
    emit(
      state.copyWith(
        checkedMigrationId: event.migrationId,
        dismissedMigrationId: dismissed ? event.migrationId : null,
        clearDismissedMigrationId: !dismissed,
      ),
    );
  }

  Future<void> _onMigrationNoticeDismissed(
    GnosisMigrationNoticeDismissed event,
    Emitter<GnosisCardState> emit,
  ) async {
    if (state.snapshot?.safeMigration.migrationId != event.migrationId) return;
    final walletIdentity = state.snapshot?.session?.ownerAddress ?? _walletId;
    emit(
      state.copyWith(
        checkedMigrationId: event.migrationId,
        dismissedMigrationId: event.migrationId,
      ),
    );
    if (walletIdentity == null || migrationNoticeStore == null) return;
    try {
      await migrationNoticeStore!.dismiss(
        walletIdentity: walletIdentity,
        migrationId: event.migrationId,
      );
    } catch (_) {
      // The current-session dismissal remains valid if persistence fails.
    }
  }
}
