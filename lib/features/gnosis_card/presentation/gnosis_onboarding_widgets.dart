import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_models.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';

String gnosisLocalizedFailureMessage(GnosisCardFailure failure) =>
    switch (failure.code) {
      GnosisCardFailureCode.offline =>
        LocaleKeys.gnosisCard_recovery_offline.tr(),
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
        Text(body, style: theme.textTheme.bodyLarge),
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
    final scheme = Theme.of(context).colorScheme;
    final background = isError
        ? scheme.errorContainer
        : scheme.secondaryContainer;
    final foreground = isError
        ? scheme.onErrorContainer
        : scheme.onSecondaryContainer;
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
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
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

class _MilestoneRail extends StatelessWidget {
  const _MilestoneRail({required this.current});

  final int current;

  @override
  Widget build(BuildContext context) => Semantics(
    label: LocaleKeys.gnosisCard_milestones_label.tr(),
    explicitChildNodes: true,
    child: Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              LocaleKeys.gnosisCard_title.tr(),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 24),
            for (var index = 0; index < _milestoneKeys.length; index += 1)
              _MilestoneTile(
                label: _milestoneKeys[index].tr(),
                index: index,
                current: current,
              ),
          ],
        ),
      ),
    ),
  );
}

class _CompactMilestones extends StatelessWidget {
  const _CompactMilestones({required this.current});

  final int current;

  @override
  Widget build(BuildContext context) => Semantics(
    label: LocaleKeys.gnosisCard_milestones_label.tr(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (var index = 0; index < _milestoneKeys.length; index += 1) ...[
              Expanded(
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: index <= current
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              if (index < _milestoneKeys.length - 1) const SizedBox(width: 6),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _milestoneKeys[current.clamp(0, _milestoneKeys.length - 1)].tr(),
          style: Theme.of(context).textTheme.labelLarge,
        ),
      ],
    ),
  );
}

class _MilestoneTile extends StatelessWidget {
  const _MilestoneTile({
    required this.label,
    required this.index,
    required this.current,
  });

  final String label;
  final int index;
  final int current;

  @override
  Widget build(BuildContext context) {
    final complete = index < current;
    final active = index == current;
    final status = complete
        ? LocaleKeys.gnosisCard_milestones_complete.tr()
        : active
        ? LocaleKeys.gnosisCard_milestones_current.tr()
        : LocaleKeys.gnosisCard_milestones_upcoming.tr();
    final color = active || complete
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.outline;
    return Semantics(
      label: '$label, $status',
      selected: active,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            CircleAvatar(
              radius: 15,
              backgroundColor: active || complete
                  ? color
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              foregroundColor: active || complete
                  ? Theme.of(context).colorScheme.onPrimary
                  : color,
              child: complete
                  ? const Icon(Icons.check, size: 18)
                  : Icon(
                      active
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 18,
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: color,
                  fontWeight: active ? FontWeight.w700 : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
