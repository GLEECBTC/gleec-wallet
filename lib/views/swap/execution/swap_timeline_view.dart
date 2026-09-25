import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/views/swap/common/swap_copy.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';

/// How a swap completes, step by step, with where it has got to.
class SwapTimelineView extends StatelessWidget {
  const SwapTimelineView({required this.steps, super.key});

  final List<SwapTimelineStep> steps;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: LocaleKeys.swapProgressTitle.tr(),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          children: [
            for (var i = 0; i < steps.length; i++)
              _StepRow(step: steps[i], last: i == steps.length - 1),
          ],
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step, required this.last});

  final SwapTimelineStep step;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    final (background, border, foreground, icon) = switch (step.status) {
      SwapStepStatus.done => (
        palette.successBg,
        palette.success,
        palette.success,
        Icons.check_rounded,
      ),
      SwapStepStatus.current => (
        palette.selected,
        palette.brand,
        palette.brandHover,
        Icons.more_horiz_rounded,
      ),
      SwapStepStatus.error => (
        palette.dangerBg,
        palette.danger,
        palette.danger,
        Icons.priority_high_rounded,
      ),
      SwapStepStatus.cancelled => (
        palette.surfaceHigh,
        palette.textTertiary,
        palette.textTertiary,
        Icons.close_rounded,
      ),
      SwapStepStatus.notStarted => (
        palette.surfaceHigh,
        palette.controlBorder,
        palette.textTertiary,
        Icons.circle_outlined,
      ),
    };
    final statusLabel = switch (step.status) {
      SwapStepStatus.done => LocaleKeys.swapStepCompleted,
      SwapStepStatus.current => LocaleKeys.swapStepCurrent,
      SwapStepStatus.error => LocaleKeys.swapStepError,
      SwapStepStatus.cancelled => LocaleKeys.swapStepCancelled,
      SwapStepStatus.notStarted => LocaleKeys.swapStepNotStarted,
    }.tr(args: [step.title]);
    final emphasised =
        step.status == SwapStepStatus.current ||
        step.status == SwapStepStatus.error;

    return Semantics(
      label: '$statusLabel. ${step.detail}',
      excludeSemantics: true,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 32,
              child: Column(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: background,
                      shape: BoxShape.circle,
                      border: Border.all(color: border, width: 2),
                    ),
                    child: Icon(
                      icon,
                      size: step.status == SwapStepStatus.notStarted ? 10 : 16,
                      color: foreground,
                    ),
                  ),
                  if (!last)
                    Expanded(
                      child: Container(
                        width: 2,
                        color: step.status == SwapStepStatus.done
                            ? palette.success
                            : palette.border,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 70),
                child: Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        step.title,
                        style: SwapText.strong(context).copyWith(
                          color: step.status == SwapStepStatus.notStarted
                              ? palette.textSecondary
                              : palette.text,
                          fontWeight: emphasised
                              ? FontWeight.w800
                              : FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(step.detail, style: SwapText.small(context)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
