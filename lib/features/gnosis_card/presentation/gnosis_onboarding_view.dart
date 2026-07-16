import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/features/gnosis_card/application/gnosis_card_bloc.dart';
import 'package:web_dex/features/gnosis_card/application/gnosis_card_coordinator.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_models.dart';
import 'package:web_dex/features/gnosis_card/infrastructure/gnosis_card_dependencies.dart';
import 'package:web_dex/features/gnosis_card/presentation/gnosis_onboarding_steps.dart';
import 'package:web_dex/features/gnosis_card/presentation/gnosis_onboarding_widgets.dart';

class GnosisOnboardingView extends StatelessWidget {
  const GnosisOnboardingView({
    required this.state,
    required this.snapshot,
    super.key,
  });

  final GnosisCardState state;
  final GnosisCardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final progress = snapshot.progress;
    final stage = progress.nextStage;
    final error = state.failure == null
        ? null
        : gnosisLocalizedFailureMessage(state.failure!);
    if (state.failure?.recovery == GnosisCardRecovery.reauthenticate) {
      return GnosisOnboardingFrame(
        milestoneIndex: 0,
        child: GnosisDiscoveryStep(
          busy: state.isBusy(GnosisCardAction.signIn),
          error: error,
          onSignIn: () => _add(context, const GnosisSignInRequested()),
        ),
      );
    }
    return GnosisOnboardingFrame(
      milestoneIndex: _milestoneIndex(stage),
      child: switch (stage) {
        GnosisOnboardingStage.signedOut => GnosisDiscoveryStep(
          busy: state.isBusy(GnosisCardAction.signIn),
          error: error,
          onSignIn: () => _add(context, const GnosisSignInRequested()),
        ),
        GnosisOnboardingStage.signupAndTerms => GnosisSignupAndTermsStep(
          terms: progress.terms,
          initialEmail: progress.email,
          busy: state.isBusy(GnosisCardAction.signupAndTerms),
          error: error,
          onOpenTerm: (term) => _add(context, GnosisTermOpenRequested(term)),
          onSubmit: (email, acceptances) => _add(
            context,
            GnosisSignupAndTermsSubmitted(
              email: email,
              acceptances: acceptances,
            ),
          ),
        ),
        GnosisOnboardingStage.kyc => GnosisKycStep(
          status: progress.kycStatus,
          busy: _isAnyBusy(const {
            GnosisCardAction.launchKyc,
            GnosisCardAction.refreshKyc,
            GnosisCardAction.openSupport,
          }),
          error: error,
          onOpen: () => _add(context, const GnosisKycLaunchRequested()),
          onRefresh: () => _add(context, const GnosisKycRefreshRequested()),
          onSupport: () => _add(context, const GnosisSupportOpenRequested()),
        ),
        GnosisOnboardingStage.sourceOfFunds => GnosisSourceOfFundsStep(
          questions: snapshot.sourceOfFundsQuestions,
          busy: state.isBusy(GnosisCardAction.submitSourceOfFunds),
          error: error,
          onSubmit: (answers) =>
              _add(context, GnosisSourceOfFundsSubmitted(answers)),
        ),
        GnosisOnboardingStage.phoneNumber => GnosisPhoneNumberStep(
          initialPhone: progress.phoneNumber,
          busy: state.isBusy(GnosisCardAction.requestPhoneOtp),
          error: error,
          onSubmit: (phone) => _add(context, GnosisPhoneOtpRequested(phone)),
        ),
        GnosisOnboardingStage.phoneOtp => GnosisPhoneOtpStep(
          challenge: progress.phoneChallenge!,
          busy: _isAnyBusy(const {
            GnosisCardAction.verifyPhoneOtp,
            GnosisCardAction.resendPhoneOtp,
            GnosisCardAction.editPhoneNumber,
          }),
          error: error,
          onVerify: (code) => _add(context, GnosisPhoneOtpVerified(code)),
          onResend: () => _add(context, const GnosisPhoneOtpResendRequested()),
          onEdit: () => _add(context, const GnosisPhoneNumberEditRequested()),
        ),
        GnosisOnboardingStage.safeDeployment => GnosisSafeSetupStep(
          progress: progress,
          busy: _isAnyBusy(const {
            GnosisCardAction.deploySafe,
            GnosisCardAction.pollSafe,
            GnosisCardAction.resetSafe,
          }),
          error: error,
          onStart: () => _add(context, const GnosisSafeDeployRequested()),
          onPoll: () => _add(context, const GnosisSafePollRequested()),
          onReset: () => _add(context, const GnosisSafeResetRequested()),
        ),
        GnosisOnboardingStage.cardSelection => GnosisCardSelectionStep(
          products: snapshot.cardProducts,
          busy: state.isBusy(GnosisCardAction.selectCardProduct),
          error: error,
          onSelect: (productId) =>
              _add(context, GnosisCardProductSelected(productId)),
        ),
        GnosisOnboardingStage.virtualCardIssuance => GnosisVirtualIssuanceStep(
          busy: state.isBusy(GnosisCardAction.issueVirtualCard),
          error: error,
          onIssue: () => _add(context, const GnosisVirtualCardIssueRequested()),
        ),
        GnosisOnboardingStage.physicalShipping => GnosisPhysicalShippingStep(
          verifiedCountry: progress.countryCode,
          initialOrder: progress.physicalOrder,
          busy: state.isBusy(GnosisCardAction.submitPhysicalShipping),
          error: error,
          onSubmit: (_, address) =>
              _add(context, GnosisPhysicalShippingSubmitted(address)),
        ),
        GnosisOnboardingStage.physicalOrderReview => GnosisPhysicalReviewStep(
          order: progress.physicalOrder!,
          busy: _isAnyBusy(const {
            GnosisCardAction.confirmPhysicalOrderReview,
            GnosisCardAction.editPhysicalOrder,
            GnosisCardAction.cancelPhysicalOrder,
          }),
          error: error,
          onConfirm: () =>
              _add(context, const GnosisPhysicalOrderReviewConfirmed()),
          onEdit: () => _add(context, const GnosisPhysicalOrderEditRequested()),
          onCancel: () =>
              _add(context, const GnosisPhysicalOrderCancelRequested()),
        ),
        GnosisOnboardingStage.physicalPayment => GnosisPhysicalPaymentStep(
          order: progress.physicalOrder!,
          quote: snapshot.paymentQuote,
          receipt: progress.paymentReceipt,
          busy: _isAnyBusy(const {
            GnosisCardAction.payPhysicalOrder,
            GnosisCardAction.confirmPhysicalPayment,
            GnosisCardAction.cancelPhysicalOrder,
          }),
          error: error,
          onPay: () => _add(context, const GnosisPhysicalPaymentRequested()),
          onConfirm: () =>
              _add(context, const GnosisPhysicalPaymentConfirmed()),
          onCancel: () =>
              _add(context, const GnosisPhysicalOrderCancelRequested()),
        ),
        GnosisOnboardingStage.physicalCardCreation =>
          GnosisPhysicalCreationStep(
            busy: state.isBusy(GnosisCardAction.createPhysicalCard),
            error: error,
            onCreate: () =>
                _add(context, const GnosisPhysicalCardCreateRequested()),
          ),
        GnosisOnboardingStage.physicalPin => GnosisPhysicalPinStep(
          busy: state.isBusy(GnosisCardAction.completePhysicalPin),
          wasHandoffCancelled: state.isPinHandoffCancelled,
          error: error,
          onOpen: () => _openPinProvisioning(context),
        ),
        GnosisOnboardingStage.ready => const SizedBox.shrink(),
      },
    );
  }

  bool _isAnyBusy(Set<GnosisCardAction> actions) => actions.any(state.isBusy);

  void _add(BuildContext context, GnosisCardEvent event) =>
      context.read<GnosisCardBloc>().add(event);

  Future<void> _openPinProvisioning(BuildContext context) async {
    final handle = snapshot.progress.provisioningHandle;
    if (handle == null) {
      _add(context, const GnosisPhysicalPinCancelled());
      return;
    }
    try {
      await context
          .read<GnosisCardDependencies>()
          .secureElement
          .provisionInitialPin(context, handle: handle);
      if (context.mounted) {
        _add(context, const GnosisPhysicalPinCompleted());
      }
    } catch (_) {
      if (context.mounted) {
        _add(context, const GnosisPhysicalPinCancelled());
      }
    }
  }
}

int _milestoneIndex(GnosisOnboardingStage stage) => switch (stage) {
  GnosisOnboardingStage.signedOut || GnosisOnboardingStage.signupAndTerms => 0,
  GnosisOnboardingStage.kyc ||
  GnosisOnboardingStage.sourceOfFunds ||
  GnosisOnboardingStage.phoneNumber ||
  GnosisOnboardingStage.phoneOtp => 1,
  GnosisOnboardingStage.safeDeployment => 2,
  _ => 3,
};
