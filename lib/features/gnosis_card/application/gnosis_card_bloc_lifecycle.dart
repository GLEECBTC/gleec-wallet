part of 'gnosis_card_bloc.dart';

extension _GnosisCardBlocLifecycle on GnosisCardBloc {
  Future<void> _onLifecycle(
    GnosisCardLifecycleEvent event,
    Emitter<GnosisCardState> emit,
  ) async {
    switch (event) {
      case GnosisCardStarted() || GnosisCardEntered():
        await _bootstrap(
          emit,
          markForeground: true,
          resetApprovalDecline: true,
        );
      case GnosisCardResumed():
        await _onResumed(emit);
      case GnosisCardExited():
        _onExited(emit);
    }
  }

  Future<void> _onResumed(Emitter<GnosisCardState> emit) async {
    if (_approvalDeclined) {
      emit(
        state.copyWith(
          isForeground: true,
          automationPhase: GnosisCardAutomationPhase.paused,
        ),
      );
      return;
    }
    if (state.snapshot?.progress.nextStage == GnosisOnboardingStage.kyc) {
      emit(state.copyWith(isForeground: true));
      await _runSnapshotAction(
        emit,
        action: GnosisCardAction.refreshKyc,
        operation: () => _coordinator.refreshKyc(),
      );
      return;
    }
    await _bootstrap(emit, markForeground: true);
  }

  void _onExited(Emitter<GnosisCardState> emit) {
    _kycRefreshTimer?.cancel();
    _dashboardReconnectTimer?.cancel();
    coordinator?.cancelAutomaticWork();
    emit(
      state.copyWith(
        isForeground: false,
        automationPhase: GnosisCardAutomationPhase.paused,
      ),
    );
  }

  void _onWalletIdentityChanged(
    GnosisWalletIdentityChanged event,
    Emitter<GnosisCardState> emit,
  ) {
    if (_walletId == event.walletId) return;
    _walletId = event.walletId;
    _walletGeneration += 1;
    _approvalDeclined = false;
    _pendingReauthenticationRetry = null;
    _pendingReauthenticationAction = null;
    _kycRefreshTimer?.cancel();
    _dashboardReconnectTimer?.cancel();
    coordinator?.resetForWalletChange();
    final wasForeground = state.isForeground;
    emit(
      GnosisCardState(
        status: event.walletId == null
            ? GnosisCardLoadStatus.failure
            : GnosisCardLoadStatus.initial,
        automationPhase: GnosisCardAutomationPhase.paused,
        intervention: event.walletId == null
            ? GnosisCardIntervention.walletUnavailable
            : null,
        failure: event.walletId == null
            ? const GnosisCardFailure(
                code: GnosisCardFailureCode.unavailable,
                message: 'Open a wallet to use Card.',
                recovery: GnosisCardRecovery.retry,
              )
            : null,
        activeWalletGeneration: _walletGeneration,
        isForeground: wasForeground,
      ),
    );
    if (wasForeground && event.walletId != null) {
      add(const GnosisCardEntered());
    }
  }

  void _onSiweApprovalDeclined(
    GnosisSiweApprovalDeclined event,
    Emitter<GnosisCardState> emit,
  ) {
    if (state.snapshot?.siweChallenge?.approvalId != event.approvalId) return;
    _approvalDeclined = true;
    _pendingReauthenticationRetry = null;
    _pendingReauthenticationAction = null;
    final snapshot = coordinator?.declineSignIn();
    emit(
      state.copyWith(
        snapshot: snapshot,
        automationPhase: GnosisCardAutomationPhase.paused,
        clearIntervention: true,
        clearMessage: true,
        clearFailure: true,
        clearFailedAction: true,
      ),
    );
  }

  Future<void> _bootstrap(
    Emitter<GnosisCardState> emit, {
    required bool markForeground,
    bool resetApprovalDecline = false,
  }) async {
    if (config.mode == GnosisCardMode.disabled) {
      emit(
        GnosisCardState(
          status: GnosisCardLoadStatus.disabled,
          message: config.failureReason,
        ),
      );
      return;
    }
    if (resetApprovalDecline) _approvalDeclined = false;
    final generation = _walletGeneration;
    emit(
      state.copyWith(
        status: state.snapshot == null
            ? GnosisCardLoadStatus.loading
            : state.status,
        automationPhase: GnosisCardAutomationPhase.preparingWallet,
        isForeground: markForeground,
        busyActions: _addBusyAction(GnosisCardAction.initialize),
        clearMessage: true,
        clearFailure: true,
        clearFailedAction: true,
        clearIntervention: true,
      ),
    );
    try {
      var snapshot = await _coordinator.prepareEntry();
      if (emit.isDone || generation != _walletGeneration) return;
      if (snapshot.siweChallenge != null) {
        emit(
          state.copyWith(
            status: GnosisCardLoadStatus.ready,
            snapshot: snapshot,
            automationPhase: GnosisCardAutomationPhase.awaitingSignature,
            intervention: GnosisCardIntervention.walletApproval,
            busyActions: _removeBusyAction(GnosisCardAction.initialize),
            activeWalletGeneration: generation,
            isForeground: markForeground,
          ),
        );
        return;
      }
      snapshot = await _reconcileIfNeeded(snapshot, emit);
      if (emit.isDone || generation != _walletGeneration) return;
      _emitReadySnapshot(
        emit,
        snapshot,
        completedAction: GnosisCardAction.initialize,
      );
    } catch (error) {
      if (emit.isDone || generation != _walletGeneration) return;
      _emitFailure(emit, error, GnosisCardAction.initialize);
    }
  }

  Future<void> _onSubmission(
    GnosisCardSubmissionEvent event,
    Emitter<GnosisCardState> emit,
  ) async {
    switch (event) {
      case GnosisSignInRequested():
        await _bootstrap(
          emit,
          markForeground: true,
          resetApprovalDecline: true,
        );
      case GnosisSiweApprovalRequested():
        await _approveSiwe(event.approvalId, emit);
      case GnosisSignupAndTermsSubmitted():
        await _runSnapshotAction(
          emit,
          action: GnosisCardAction.signupAndTerms,
          operation: () => _coordinator.signUpAndAcceptTerms(
            email: event.email,
            acceptances: event.acceptances,
          ),
        );
      case GnosisKycLaunchRequested():
        if (state.externalFlow != null) return;
        await _runExternalFlowAction(
          emit,
          action: GnosisCardAction.launchKyc,
          operation: () => _coordinator.kycFlow(),
        );
      case GnosisSupportOpenRequested():
        if (state.externalFlow != null) return;
        await _runExternalFlowAction(
          emit,
          action: GnosisCardAction.openSupport,
          operation: () => _coordinator.supportFlow(),
        );
      case GnosisSourceOfFundsSubmitted():
        await _runSnapshotAction(
          emit,
          action: GnosisCardAction.submitSourceOfFunds,
          operation: () => _coordinator.submitSourceOfFunds(event.answers),
        );
      case GnosisPhoneOtpRequested():
        await _runSnapshotAction(
          emit,
          action: GnosisCardAction.requestPhoneOtp,
          operation: () => _coordinator.requestPhoneOtp(event.phoneNumber),
        );
      case GnosisPhoneOtpVerified():
        await _runSnapshotAction(
          emit,
          action: GnosisCardAction.verifyPhoneOtp,
          operation: () => _coordinator.verifyPhoneOtp(event.code),
        );
      case GnosisPhoneNumberEditRequested():
        await _runSnapshotAction(
          emit,
          action: GnosisCardAction.editPhoneNumber,
          operation: () => _coordinator.editPhoneNumber(),
        );
      case GnosisPhoneOtpResendRequested():
        await _runSnapshotAction(
          emit,
          action: GnosisCardAction.resendPhoneOtp,
          operation: () => _coordinator.resendPhoneOtp(),
        );
      case GnosisCardProductSelected():
        await _runSnapshotAction(
          emit,
          action: GnosisCardAction.selectCardProduct,
          operation: () => _coordinator.selectCardProduct(event.productId),
        );
      case GnosisVirtualCardIssueRequested():
        await _runSnapshotAction(
          emit,
          action: GnosisCardAction.issueVirtualCard,
          operation: () => _coordinator.issueVirtualCard(),
        );
    }
  }

  Future<void> _approveSiwe(
    String approvalId,
    Emitter<GnosisCardState> emit,
  ) async {
    if (state.snapshot?.siweChallenge == null ||
        state.isBusy(GnosisCardAction.signIn)) {
      return;
    }
    _approvalDeclined = false;
    final generation = _walletGeneration;
    emit(
      state.copyWith(
        automationPhase: GnosisCardAutomationPhase.authenticating,
        busyActions: _addBusyAction(GnosisCardAction.signIn),
        clearMessage: true,
        clearFailure: true,
        clearFailedAction: true,
        clearIntervention: true,
      ),
    );
    try {
      var snapshot = await _coordinator.approveSignIn(approvalId: approvalId);
      if (emit.isDone || generation != _walletGeneration) return;
      snapshot = await _reconcileIfNeeded(snapshot, emit);
      if (emit.isDone || generation != _walletGeneration) return;
      final retry = _pendingReauthenticationRetry;
      final retryAction = _pendingReauthenticationAction;
      _pendingReauthenticationRetry = null;
      _pendingReauthenticationAction = null;
      if (retry != null && retryAction != null) {
        snapshot = await retry();
        if (emit.isDone || generation != _walletGeneration) return;
        snapshot = await _reconcileIfNeeded(snapshot, emit);
        if (emit.isDone || generation != _walletGeneration) return;
      }
      _emitReadySnapshot(
        emit,
        snapshot,
        completedAction: retryAction ?? GnosisCardAction.signIn,
      );
    } catch (error) {
      if (emit.isDone || generation != _walletGeneration) return;
      _emitFailure(emit, error, GnosisCardAction.signIn);
    }
  }
}
