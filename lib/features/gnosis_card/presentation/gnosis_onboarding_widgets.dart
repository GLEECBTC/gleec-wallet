import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_models.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';

part 'gnosis_onboarding_milestones.dart';

String gnosisLocalizedFailureMessage(
  GnosisCardFailure failure,
) => switch (failure.code) {
  GnosisCardFailureCode.offline => LocaleKeys.gnosisCard_recovery_offline.tr(),
  GnosisCardFailureCode.rateLimited => 'gnosisCard.recovery.rateLimited'.tr(),
  GnosisCardFailureCode.serviceUnavailable =>
    'gnosisCard.recovery.serviceUnavailable'.tr(),
  GnosisCardFailureCode.walletLocked => 'gnosisCard.recovery.walletLocked'.tr(),
  GnosisCardFailureCode.wrongChain => 'gnosisCard.recovery.wrongChain'.tr(),
  GnosisCardFailureCode.activationFailed =>
    'gnosisCard.recovery.activationFailed'.tr(),
  GnosisCardFailureCode.migrationFailed =>
    'gnosisCard.recovery.migrationFailed'.tr(),
  GnosisCardFailureCode.sessionExpired =>
    LocaleKeys.gnosisCard_recovery_expiredSession.tr(),
  GnosisCardFailureCode.invalidInput =>
    LocaleKeys.gnosisCard_recovery_invalidInput.tr(),
  GnosisCardFailureCode.invalidOtp =>
    LocaleKeys.gnosisCard_phone_codeInvalid.tr(),
  GnosisCardFailureCode.resendCooldown =>
    LocaleKeys.gnosisCard_recovery_resendCooldown.tr(),
  GnosisCardFailureCode.kycResubmissionRequired =>
    LocaleKeys.gnosisCard_kyc_resubmissionRequestedBody.tr(),
  GnosisCardFailureCode.kycRejected =>
    LocaleKeys.gnosisCard_kyc_rejectedBody.tr(),
  GnosisCardFailureCode.kycRequiresAction =>
    LocaleKeys.gnosisCard_kyc_requiresActionBody.tr(),
  GnosisCardFailureCode.deploymentFailed =>
    LocaleKeys.gnosisCard_recovery_deploymentFailure.tr(),
  GnosisCardFailureCode.deploymentTimedOut =>
    LocaleKeys.gnosisCard_safe_timeout.tr(),
  GnosisCardFailureCode.safeIntegrityFailed =>
    LocaleKeys.gnosisCard_safe_invalidIntegrity.tr(),
  GnosisCardFailureCode.paymentFailed =>
    LocaleKeys.gnosisCard_recovery_paymentFailure.tr(),
  GnosisCardFailureCode.issuanceFailed =>
    LocaleKeys.gnosisCard_recovery_issuanceFailure.tr(),
  GnosisCardFailureCode.invalidTransition =>
    LocaleKeys.gnosisCard_recovery_stateChanged.tr(),
  GnosisCardFailureCode.notFound =>
    LocaleKeys.gnosisCard_recovery_notFound.tr(),
  GnosisCardFailureCode.unavailable =>
    LocaleKeys.gnosisCard_recovery_unavailable.tr(),
};

class GnosisOnboardingFrame extends StatelessWidget {
  const GnosisOnboardingFrame({
    required this.milestoneIndex,
    required this.child,
    super.key,
  });

  final int milestoneIndex;
  final Widget child;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final wide = constraints.maxWidth >= 900 && textScale < 1.4;
        final horizontalPadding = constraints.maxWidth < 720 ? 16.0 : 24.0;
        final content = FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 272,
                      child: _MilestoneRail(current: milestoneIndex),
                    ),
                    const SizedBox(width: 32),
                    Expanded(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 760),
                          child: child,
                        ),
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        LocaleKeys.gnosisCard_title.tr(),
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _CompactMilestones(current: milestoneIndex),
                    const SizedBox(height: 20),
                    child,
                  ],
                ),
        );
        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: 24,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: content,
            ),
          ),
        );
      },
    ),
  );
}

class GnosisStepCard extends StatelessWidget {
  const GnosisStepCard({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: Padding(padding: const EdgeInsets.all(24), child: child),
  );
}

class GnosisStepHeader extends StatelessWidget {
  const GnosisStepHeader({
    required this.icon,
    required this.title,
    required this.body,
    super.key,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 40, color: theme.colorScheme.primary),
        const SizedBox(height: 20),
        Semantics(
          header: true,
          child: Text(title, style: theme.textTheme.headlineSmall),
        ),
        const SizedBox(height: 12),
        Text(
          body,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: _gnosisReadableText(context),
          ),
        ),
      ],
    );
  }
}

class GnosisStatusBanner extends StatelessWidget {
  const GnosisStatusBanner({
    required this.title,
    required this.message,
    this.icon = Icons.info_outline,
    this.isError = false,
    this.isLiveRegion = false,
    super.key,
  });

  final String title;
  final String message;
  final IconData icon;
  final bool isError;
  final bool isLiveRegion;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = isError
        ? dark
              ? const Color(0xFF421525)
              : const Color(0xFFFFE5EE)
        : dark
        ? const Color(0xFF302640)
        : const Color(0xFFF1E9FF);
    final foreground = isError
        ? dark
              ? const Color(0xFFFFD9E4)
              : const Color(0xFF7A1238)
        : dark
        ? const Color(0xFFF7F1FF)
        : const Color(0xFF321A4D);
    return Semantics(
      liveRegion: isLiveRegion,
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: foreground),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: foreground),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GnosisServerErrorBanner extends StatelessWidget {
  const GnosisServerErrorBanner({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) => GnosisStatusBanner(
    title: LocaleKeys.gnosisCard_failureTitle.tr(),
    message: message,
    icon: Icons.error_outline,
    isError: true,
    isLiveRegion: true,
  );
}

class GnosisProgressIndicator extends StatelessWidget {
  const GnosisProgressIndicator({this.label, super.key});

  final String? label;

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: label ?? LocaleKeys.gnosisCard_loading.tr(),
      liveRegion: true,
      child: Center(
        child: ExcludeSemantics(
          child: reducedMotion
              ? const Icon(Icons.hourglass_top_outlined, size: 32)
              : const CircularProgressIndicator(),
        ),
      ),
    );
  }
}

class GnosisExternalHandoffCard extends StatelessWidget {
  const GnosisExternalHandoffCard({
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onOpen,
    this.icon = Icons.open_in_new,
    super.key,
  });

  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback? onOpen;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      border: Border.all(color: _gnosisBorderColor(context)),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(body),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton.icon(
            onPressed: onOpen,
            icon: const Icon(Icons.open_in_new),
            label: Text(actionLabel),
          ),
        ),
      ],
    ),
  );
}

class GnosisResponsiveActions extends StatelessWidget {
  const GnosisResponsiveActions({
    required this.primary,
    this.secondary,
    super.key,
  });

  final Widget primary;
  final Widget? secondary;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final stack =
          constraints.maxWidth < 520 ||
          MediaQuery.textScalerOf(context).scale(1) >= 1.4;
      if (stack) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            primary,
            if (secondary != null) ...[const SizedBox(height: 12), secondary!],
          ],
        );
      }
      return Row(
        children: [
          if (secondary != null) ...[
            Expanded(child: secondary!),
            const SizedBox(width: 12),
          ],
          Expanded(child: primary),
        ],
      );
    },
  );
}

const _milestoneKeys = [
  LocaleKeys.gnosisCard_milestones_account,
  LocaleKeys.gnosisCard_milestones_identity,
  LocaleKeys.gnosisCard_milestones_cardAccount,
  LocaleKeys.gnosisCard_milestones_card,
];
