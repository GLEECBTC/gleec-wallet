import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/features/gnosis_card/application/gnosis_card_coordinator.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_models.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_ports.dart';
import 'package:web_dex/features/gnosis_card/infrastructure/gnosis_card_config.dart';

part 'gnosis_card_bloc_core.dart';
part 'gnosis_card_bloc_lifecycle.dart';
part 'gnosis_card_bloc_handlers.dart';
part 'gnosis_card_bloc_operations.dart';

sealed class GnosisCardEvent extends Equatable {
  const GnosisCardEvent();

  @override
  List<Object?> get props => const [];
}

sealed class GnosisCardLifecycleEvent extends GnosisCardEvent {
  const GnosisCardLifecycleEvent();
}

final class GnosisCardStarted extends GnosisCardLifecycleEvent {
  const GnosisCardStarted();
}

final class GnosisCardEntered extends GnosisCardLifecycleEvent {
  const GnosisCardEntered();
}

final class GnosisCardResumed extends GnosisCardLifecycleEvent {
  const GnosisCardResumed();
}

final class GnosisCardExited extends GnosisCardLifecycleEvent {
  const GnosisCardExited();
}

final class GnosisWalletIdentityChanged extends GnosisCardEvent {
  const GnosisWalletIdentityChanged(this.walletId);

  final String? walletId;

  @override
  List<Object?> get props => [walletId];
}

sealed class GnosisCardSubmissionEvent extends GnosisCardEvent {
  const GnosisCardSubmissionEvent();
}

final class GnosisSignInRequested extends GnosisCardSubmissionEvent {
  const GnosisSignInRequested();
}

final class GnosisSiweApprovalRequested extends GnosisCardSubmissionEvent {
  const GnosisSiweApprovalRequested(this.approvalId);

  final String approvalId;

  @override
  List<Object?> get props => [approvalId];
}

final class GnosisSiweApprovalDeclined extends GnosisCardEvent {
  const GnosisSiweApprovalDeclined(this.approvalId);

  final String approvalId;

  @override
  List<Object?> get props => [approvalId];
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
  const GnosisCardControlsChanged(this.cardId, this.controls);

  final String cardId;
  final GnosisCardControls controls;

  @override
  List<Object?> get props => [cardId, controls];
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

final class GnosisMigrationNoticeDismissed extends GnosisCardEvent {
  const GnosisMigrationNoticeDismissed(this.migrationId);

  final String migrationId;

  @override
  List<Object?> get props => [migrationId];
}

final class GnosisMigrationNoticeStatusRequested extends GnosisCardEvent {
  const GnosisMigrationNoticeStatusRequested(this.migrationId);

  final String migrationId;

  @override
  List<Object?> get props => [migrationId];
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
    this.automationPhase = GnosisCardAutomationPhase.idle,
    this.intervention,
    this.activeWalletGeneration = 0,
    this.lastUpdatedAt,
    this.isForeground = false,
    this.lastCompletedAction,
    this.dismissedMigrationId,
    this.checkedMigrationId,
  });

  const GnosisCardState.initial()
    : status = GnosisCardLoadStatus.initial,
      snapshot = null,
      message = null,
      failure = null,
      failedAction = null,
      externalFlow = null,
      isPinHandoffCancelled = false,
      busyActions = const <GnosisCardAction>{},
      automationPhase = GnosisCardAutomationPhase.idle,
      intervention = null,
      activeWalletGeneration = 0,
      lastUpdatedAt = null,
      isForeground = false,
      lastCompletedAction = null,
      dismissedMigrationId = null,
      checkedMigrationId = null;

  final GnosisCardLoadStatus status;
  final GnosisCardSnapshot? snapshot;
  final String? message;
  final GnosisCardFailure? failure;
  final GnosisCardAction? failedAction;
  final GnosisExternalFlow? externalFlow;
  final bool isPinHandoffCancelled;
  final Set<GnosisCardAction> busyActions;
  final GnosisCardAutomationPhase automationPhase;
  final GnosisCardIntervention? intervention;
  final int activeWalletGeneration;
  final DateTime? lastUpdatedAt;
  final bool isForeground;
  final GnosisCardAction? lastCompletedAction;
  final String? dismissedMigrationId;
  final String? checkedMigrationId;

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
    GnosisCardAutomationPhase? automationPhase,
    GnosisCardIntervention? intervention,
    int? activeWalletGeneration,
    DateTime? lastUpdatedAt,
    bool? isForeground,
    GnosisCardAction? lastCompletedAction,
    String? dismissedMigrationId,
    String? checkedMigrationId,
    bool clearMessage = false,
    bool clearFailure = false,
    bool clearFailedAction = false,
    bool clearExternalFlow = false,
    bool clearIntervention = false,
    bool clearLastCompletedAction = false,
    bool clearDismissedMigrationId = false,
    bool clearCheckedMigrationId = false,
  }) => GnosisCardState(
    status: status ?? this.status,
    snapshot: snapshot ?? this.snapshot,
    message: clearMessage ? null : message ?? this.message,
    failure: clearFailure ? null : failure ?? this.failure,
    failedAction: clearFailedAction ? null : failedAction ?? this.failedAction,
    externalFlow: clearExternalFlow ? null : externalFlow ?? this.externalFlow,
    isPinHandoffCancelled: isPinHandoffCancelled ?? this.isPinHandoffCancelled,
    busyActions: busyActions ?? this.busyActions,
    automationPhase: automationPhase ?? this.automationPhase,
    intervention: clearIntervention ? null : intervention ?? this.intervention,
    activeWalletGeneration:
        activeWalletGeneration ?? this.activeWalletGeneration,
    lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
    isForeground: isForeground ?? this.isForeground,
    lastCompletedAction: clearLastCompletedAction
        ? null
        : lastCompletedAction ?? this.lastCompletedAction,
    dismissedMigrationId: clearDismissedMigrationId
        ? null
        : dismissedMigrationId ?? this.dismissedMigrationId,
    checkedMigrationId: clearCheckedMigrationId
        ? null
        : checkedMigrationId ?? this.checkedMigrationId,
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
    automationPhase,
    intervention,
    activeWalletGeneration,
    lastUpdatedAt,
    isForeground,
    lastCompletedAction,
    dismissedMigrationId,
    checkedMigrationId,
  ];
}
