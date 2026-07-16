import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/features/gnosis_card/application/gnosis_card_coordinator.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_models.dart';
import 'package:web_dex/features/gnosis_card/infrastructure/gnosis_card_config.dart';

sealed class GnosisCardEvent extends Equatable {
  const GnosisCardEvent();

  @override
  List<Object?> get props => const [];
}

final class GnosisCardStarted extends GnosisCardEvent {
  const GnosisCardStarted();
}

sealed class GnosisCardSubmissionEvent extends GnosisCardEvent {
  const GnosisCardSubmissionEvent();
}

final class GnosisSignInRequested extends GnosisCardSubmissionEvent {
  const GnosisSignInRequested();
}

final class GnosisSignupAndTermsSubmitted extends GnosisCardSubmissionEvent {
  GnosisSignupAndTermsSubmitted({
    required this.email,
    required List<GnosisTermAcceptance> acceptances,
  }) : acceptances = List.unmodifiable(acceptances);

  final String email;
  final List<GnosisTermAcceptance> acceptances;

  @override
  List<Object?> get props => [email, acceptances];
}

final class GnosisKycLaunchRequested extends GnosisCardSubmissionEvent {
  const GnosisKycLaunchRequested();
}

final class GnosisSupportOpenRequested extends GnosisCardSubmissionEvent {
  const GnosisSupportOpenRequested();
}

final class GnosisSourceOfFundsSubmitted extends GnosisCardSubmissionEvent {
  GnosisSourceOfFundsSubmitted(List<SourceOfFundsAnswer> answers)
    : answers = List.unmodifiable(answers);

  final List<SourceOfFundsAnswer> answers;

  @override
  List<Object?> get props => [answers];
}

final class GnosisPhoneOtpRequested extends GnosisCardSubmissionEvent {
  const GnosisPhoneOtpRequested(this.phoneNumber);

  final String phoneNumber;

  @override
  List<Object?> get props => [phoneNumber];
}

final class GnosisPhoneOtpVerified extends GnosisCardSubmissionEvent {
  const GnosisPhoneOtpVerified(this.code);

  final String code;

  @override
  List<Object?> get props => [code];
}

final class GnosisPhoneNumberEditRequested extends GnosisCardSubmissionEvent {
  const GnosisPhoneNumberEditRequested();
}

final class GnosisPhoneOtpResendRequested extends GnosisCardSubmissionEvent {
  const GnosisPhoneOtpResendRequested();
}

final class GnosisCardProductSelected extends GnosisCardSubmissionEvent {
  const GnosisCardProductSelected(this.productId);

  final String productId;

  @override
  List<Object?> get props => [productId];
}

final class GnosisVirtualCardIssueRequested extends GnosisCardSubmissionEvent {
  const GnosisVirtualCardIssueRequested();
}

final class GnosisTermOpenRequested extends GnosisCardEvent {
  const GnosisTermOpenRequested(this.term);

  final GnosisTerm term;

  @override
  List<Object?> get props => [term];
}

final class GnosisKycRefreshRequested extends GnosisCardEvent {
  const GnosisKycRefreshRequested();
}

sealed class GnosisSafeTransitionEvent extends GnosisCardEvent {
  const GnosisSafeTransitionEvent();
}

final class GnosisSafeDeployRequested extends GnosisSafeTransitionEvent {
  const GnosisSafeDeployRequested();
}

final class GnosisSafePollRequested extends GnosisSafeTransitionEvent {
  const GnosisSafePollRequested();
}

final class GnosisSafeResetRequested extends GnosisSafeTransitionEvent {
  const GnosisSafeResetRequested();
}

sealed class GnosisPhysicalTransitionEvent extends GnosisCardEvent {
  const GnosisPhysicalTransitionEvent();
}

final class GnosisPhysicalShippingSubmitted
    extends GnosisPhysicalTransitionEvent {
  const GnosisPhysicalShippingSubmitted(this.address);

  final ShippingAddress address;

  @override
  List<Object?> get props => [address];
}

final class GnosisPhysicalOrderReviewConfirmed
    extends GnosisPhysicalTransitionEvent {
  const GnosisPhysicalOrderReviewConfirmed();
}

final class GnosisPhysicalPaymentRequested
    extends GnosisPhysicalTransitionEvent {
  const GnosisPhysicalPaymentRequested();
}

final class GnosisPhysicalPaymentConfirmed
    extends GnosisPhysicalTransitionEvent {
  const GnosisPhysicalPaymentConfirmed();
}

final class GnosisPhysicalCardCreateRequested
    extends GnosisPhysicalTransitionEvent {
  const GnosisPhysicalCardCreateRequested();
}

final class GnosisPhysicalPinCompleted extends GnosisPhysicalTransitionEvent {
  const GnosisPhysicalPinCompleted();
}

final class GnosisPhysicalPinCancelled extends GnosisPhysicalTransitionEvent {
  const GnosisPhysicalPinCancelled();
}

final class GnosisPhysicalOrderEditRequested
    extends GnosisPhysicalTransitionEvent {
  const GnosisPhysicalOrderEditRequested();
}

final class GnosisPhysicalOrderCancelRequested
    extends GnosisPhysicalTransitionEvent {
  const GnosisPhysicalOrderCancelRequested();
}

final class GnosisExternalFlowHandled extends GnosisCardEvent {
  const GnosisExternalFlowHandled(this.effectId);

  final String effectId;

  @override
  List<Object?> get props => [effectId];
}

final class GnosisExternalFlowLaunchFailed extends GnosisCardEvent {
  const GnosisExternalFlowLaunchFailed(this.effectId);

  final String effectId;

  @override
  List<Object?> get props => [effectId];
}

final class GnosisCardFreezeChanged extends GnosisCardEvent {
  const GnosisCardFreezeChanged(this.cardId, {required this.frozen});

  final String cardId;
  final bool frozen;

  @override
  List<Object?> get props => [cardId, frozen];
}

final class GnosisCardStatusChanged extends GnosisCardEvent {
  const GnosisCardStatusChanged(this.cardId, this.status);

  final String cardId;
  final GnosisCardStatus status;

  @override
  List<Object?> get props => [cardId, status];
}

final class GnosisCardControlsChanged extends GnosisCardEvent {
  const GnosisCardControlsChanged(this.controls);

  final GnosisCardControls controls;

  @override
  List<Object?> get props => [controls];
}

final class GnosisWithdrawalReviewRequested extends GnosisCardEvent {
  const GnosisWithdrawalReviewRequested(this.request);

  final WithdrawalRequest request;

  @override
  List<Object?> get props => [request];
}

final class GnosisDailyLimitReviewRequested extends GnosisCardEvent {
  const GnosisDailyLimitReviewRequested(this.request);

  final DailyLimitRequest request;

  @override
  List<Object?> get props => [request];
}

final class GnosisPreparedIntentConfirmed extends GnosisCardEvent {
  const GnosisPreparedIntentConfirmed();
}

final class GnosisPreparedIntentCancelled extends GnosisCardEvent {
  const GnosisPreparedIntentCancelled();
}

final class GnosisDelayedOperationsRefreshRequested extends GnosisCardEvent {
  const GnosisDelayedOperationsRefreshRequested();
}

enum GnosisCardLoadStatus { initial, loading, ready, failure, disabled }

enum GnosisCardAction {
  initialize,
  signIn,
  signupAndTerms,
  launchKyc,
  refreshKyc,
  openSupport,
  submitSourceOfFunds,
  requestPhoneOtp,
  verifyPhoneOtp,
  editPhoneNumber,
  resendPhoneOtp,
  deploySafe,
  pollSafe,
  resetSafe,
  selectCardProduct,
  issueVirtualCard,
  submitPhysicalShipping,
  confirmPhysicalOrderReview,
  payPhysicalOrder,
  confirmPhysicalPayment,
  createPhysicalCard,
  completePhysicalPin,
  editPhysicalOrder,
  cancelPhysicalOrder,
  setCardFrozen,
  setCardStatus,
  updateCardControls,
  prepareWithdrawal,
  prepareDailyLimit,
  confirmPreparedIntent,
  cancelPreparedIntent,
  refreshDelayedOperations,
}

class GnosisCardState extends Equatable {
  const GnosisCardState({
    required this.status,
    this.snapshot,
    this.message,
    this.failure,
    this.failedAction,
    this.externalFlow,
    this.isPinHandoffCancelled = false,
    this.busyActions = const <GnosisCardAction>{},
  });

  const GnosisCardState.initial()
    : status = GnosisCardLoadStatus.initial,
      snapshot = null,
      message = null,
      failure = null,
      failedAction = null,
      externalFlow = null,
      isPinHandoffCancelled = false,
      busyActions = const <GnosisCardAction>{};

  final GnosisCardLoadStatus status;
  final GnosisCardSnapshot? snapshot;
  final String? message;
  final GnosisCardFailure? failure;
  final GnosisCardAction? failedAction;
  final GnosisExternalFlow? externalFlow;
  final bool isPinHandoffCancelled;
  final Set<GnosisCardAction> busyActions;

  bool isBusy(GnosisCardAction action) => busyActions.contains(action);

  GnosisCardState copyWith({
    GnosisCardLoadStatus? status,
    GnosisCardSnapshot? snapshot,
    String? message,
    GnosisCardFailure? failure,
    GnosisCardAction? failedAction,
    GnosisExternalFlow? externalFlow,
    bool? isPinHandoffCancelled,
    Set<GnosisCardAction>? busyActions,
    bool clearMessage = false,
    bool clearFailure = false,
    bool clearFailedAction = false,
    bool clearExternalFlow = false,
  }) => GnosisCardState(
    status: status ?? this.status,
    snapshot: snapshot ?? this.snapshot,
    message: clearMessage ? null : message ?? this.message,
    failure: clearFailure ? null : failure ?? this.failure,
    failedAction: clearFailedAction ? null : failedAction ?? this.failedAction,
    externalFlow: clearExternalFlow ? null : externalFlow ?? this.externalFlow,
    isPinHandoffCancelled: isPinHandoffCancelled ?? this.isPinHandoffCancelled,
    busyActions: busyActions ?? this.busyActions,
  );

  @override
  List<Object?> get props => [
    status,
    snapshot,
    message,
    failure,
    failedAction,
    externalFlow,
    isPinHandoffCancelled,
    busyActions,
  ];
}

class GnosisCardBloc extends Bloc<GnosisCardEvent, GnosisCardState> {
  GnosisCardBloc({
    required this.config,
    required this.coordinator,
    GnosisCardState initialState = const GnosisCardState.initial(),
  }) : super(initialState) {
    on<GnosisCardStarted>(_onStarted, transformer: restartable());
    on<GnosisCardSubmissionEvent>(_onSubmission, transformer: droppable());
    on<GnosisTermOpenRequested>(_onTermOpenRequested);
    on<GnosisKycRefreshRequested>(
      _onKycRefreshRequested,
      transformer: restartable(),
    );
    on<GnosisSafeTransitionEvent>(_onSafeTransition, transformer: sequential());
    on<GnosisPhysicalTransitionEvent>(
      _onPhysicalTransition,
      transformer: sequential(),
    );
    on<GnosisExternalFlowHandled>(_onExternalFlowHandled);
    on<GnosisExternalFlowLaunchFailed>(_onExternalFlowLaunchFailed);
    on<GnosisCardFreezeChanged>(_onCardFreezeChanged, transformer: droppable());
    on<GnosisCardStatusChanged>(_onCardStatusChanged, transformer: droppable());
    on<GnosisCardControlsChanged>(
      _onCardControlsChanged,
      transformer: droppable(),
    );
    on<GnosisWithdrawalReviewRequested>(
      _onWithdrawalReviewRequested,
      transformer: droppable(),
    );
    on<GnosisDailyLimitReviewRequested>(
      _onDailyLimitReviewRequested,
      transformer: droppable(),
    );
    on<GnosisPreparedIntentConfirmed>(
      _onPreparedIntentConfirmed,
      transformer: droppable(),
    );
    on<GnosisPreparedIntentCancelled>(_onPreparedIntentCancelled);
    on<GnosisDelayedOperationsRefreshRequested>(
      _onDelayedOperationsRefreshRequested,
      transformer: restartable(),
    );
  }

  final GnosisCardConfig config;
  final GnosisCardCoordinator? coordinator;

  var _externalFlowSequence = 0;

  GnosisCardCoordinator get _coordinator {
    final value = coordinator;
    if (value == null) {
      throw const GnosisCardUnavailable(
        'Gnosis card dependencies are unavailable.',
      );
    }
    return value;
  }

  Future<void> _onStarted(
    GnosisCardStarted event,
    Emitter<GnosisCardState> emit,
  ) async {
    if (config.mode == GnosisCardMode.disabled) {
      emit(
        GnosisCardState(
          status: GnosisCardLoadStatus.disabled,
          message: config.failureReason,
        ),
      );
      return;
    }
    await _runSnapshotAction(
      emit,
      action: GnosisCardAction.initialize,
      operation: () => _coordinator.initialize(),
      isInitialLoad: true,
    );
  }

  Future<void> _onSubmission(
    GnosisCardSubmissionEvent event,
    Emitter<GnosisCardState> emit,
  ) async {
    switch (event) {
      case GnosisSignInRequested():
        await _runSnapshotAction(
          emit,
          action: GnosisCardAction.signIn,
          operation: () => _coordinator.signIn(),
        );
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
  ) => _runSnapshotAction(
    emit,
    action: GnosisCardAction.refreshKyc,
    operation: () => _coordinator.refreshKyc(),
  );

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
      case GnosisSafeResetRequested():
        await _runSnapshotAction(
          emit,
          action: GnosisCardAction.resetSafe,
          operation: () => _coordinator.resetSafe(),
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
    operation: () => _coordinator.updateControls(event.controls),
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

  Future<void> _runSnapshotAction(
    Emitter<GnosisCardState> emit, {
    required GnosisCardAction action,
    required Future<GnosisCardSnapshot> Function() operation,
    bool isInitialLoad = false,
  }) async {
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
      final snapshot = await operation();
      if (emit.isDone) return;
      emit(
        state.copyWith(
          status: GnosisCardLoadStatus.ready,
          snapshot: snapshot,
          busyActions: _removeBusyAction(action),
          clearMessage: true,
          clearFailure: true,
          clearFailedAction: true,
        ),
      );
    } catch (error) {
      if (emit.isDone) return;
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

  Future<void> _runExternalFlowAction(
    Emitter<GnosisCardState> emit, {
    required GnosisCardAction action,
    required Future<GnosisExternalFlow> Function() operation,
  }) async {
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
      if (emit.isDone) return;
      _publishExternalFlow(emit, flow, completedAction: action);
    } catch (error) {
      if (emit.isDone) return;
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
      GnosisSafeResetRequested() => deployment == null,
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
