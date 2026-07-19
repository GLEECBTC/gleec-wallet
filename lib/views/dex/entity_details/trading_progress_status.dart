import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';

class SwapProgressStatus extends StatelessWidget {
  const SwapProgressStatus({
    Key? key,
    required this.progress,
    this.isFailed = false,
  }) : super(key: key);

  final int progress;
  final bool isFailed;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final circleSize = constraints.maxWidth.clamp(160.0, 220.0).toDouble();
        if (progress == 100) {
          return const _CompletedSwapStatus(key: Key('swap-status-success'));
        }
        return isFailed
            ? _FailedSwapStatus(circleSize: circleSize)
            : _InProgressSwapStatus(progress: progress, circleSize: circleSize);
      },
    );
  }
}

class _CompletedSwapStatus extends StatelessWidget {
  const _CompletedSwapStatus({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 24, 0, 30),
        child: SvgPicture.asset(
          '$assetsPath/ui_icons/success_swap.svg',
          colorFilter: ColorFilter.mode(
            Theme.of(context).colorScheme.primary,
            BlendMode.srcIn,
          ),
          width: 66,
          height: 66,
        ),
      ),
    );
  }
}

class _FailedSwapStatus extends StatelessWidget {
  const _FailedSwapStatus({Key? key, required this.circleSize})
    : super(key: key);
  final double circleSize;

  @override
  Widget build(BuildContext context) {
    final colors = GleecColorTokens.of(context);
    final geometry = GleecGeometry.of(context);
    final typography = GleecTypography.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 30, 10, 40),
        child: Container(
          width: circleSize,
          height: circleSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.dangerContainer,
            border: Border.all(color: colors.danger, width: 2),
          ),
          padding: EdgeInsets.all(geometry.space24),
          child: Center(
            child: Text(
              LocaleKeys.swapProgressStatusFailed.tr(),
              textAlign: TextAlign.center,
              style: typography.sectionTitle.copyWith(color: colors.danger),
            ),
          ),
        ),
      ),
    );
  }
}

class _InProgressSwapStatus extends StatelessWidget {
  const _InProgressSwapStatus({
    required this.progress,
    required this.circleSize,
  });

  final int progress;
  final double circleSize;

  @override
  Widget build(BuildContext context) {
    final colors = GleecColorTokens.of(context);
    final motion = GleecMotion.of(context);
    final typography = GleecTypography.of(context);
    final normalizedProgress = (progress / 100).clamp(0.0, 1.0).toDouble();

    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 30, 10, 40),
        child: SizedBox.square(
          dimension: circleSize,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: normalizedProgress),
            duration: motion.resolve(context, motion.deliberate),
            curve: motion.standardCurve,
            builder: (context, value, child) {
              return Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: value,
                    strokeWidth: 12,
                    color: colors.brand,
                    backgroundColor: colors.surfaceHighest,
                  ),
                  Center(child: child),
                ],
              );
            },
            child: Text(
              '$progress %',
              style: typography.tabularAmount.copyWith(color: colors.brand),
            ),
          ),
        ),
      ),
    );
  }
}
