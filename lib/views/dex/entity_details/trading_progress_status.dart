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
    this.isSuccessful = false,
  }) : super(key: key);

  final int progress;
  final bool isFailed;

  /// The swap's terminal outcome; the progress estimate cannot establish it.
  final bool isSuccessful;

  @override
  Widget build(BuildContext context) {
    const double circleSize = 220.0;
    if (isFailed) {
      return const _FailedSwapStatus(
        key: Key('swap-status-failed'),
        circleSize: circleSize,
      );
    }
    if (isSuccessful) {
      return const _CompletedSwapStatus(key: Key('swap-status-success'));
    }
    return _InProgressSwapStatus(
      progress: progress.clamp(0, 99),
      circleSize: circleSize,
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 30, 10, 40),
        child: Container(
          width: circleSize,
          height: circleSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: theme.custom.tradingDetailsTheme.swapFailedStatusColors,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(30),
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).colorScheme.surface,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      LocaleKeys.swapProgressStatusFailed.tr(),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InProgressSwapStatus extends StatefulWidget {
  const _InProgressSwapStatus({
    Key? key,
    required this.progress,
    required this.circleSize,
  }) : super(key: key);
  final int progress;
  final double circleSize;

  @override
  State<_InProgressSwapStatus> createState() => _InProgressSwapStatusState();
}

class _InProgressSwapStatusState extends State<_InProgressSwapStatus>
    with TickerProviderStateMixin {
  late AnimationController _colorAnimationController;
  late Animation _colorAnimation;

  @override
  void initState() {
    _colorAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );
    _colorAnimationController.repeat(reverse: true);
    _colorAnimation =
        Tween(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeIn))
            .animate(_colorAnimationController)
          ..addListener(() {
            setState(() {});
          });
    super.initState();
  }

  @override
  void dispose() {
    _colorAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 30, 10, 40),
        child: Container(
          width: widget.circleSize,
          height: widget.circleSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              stops: [
                _colorAnimation.value - 0.7,
                _colorAnimation.value,
                _colorAnimation.value + 0.4,
                _colorAnimation.value + 0.7,
              ],
              colors: theme.custom.tradingDetailsTheme.swapStatusColors,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(30),
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).colorScheme.surface,
              ),
              child: Center(
                child: Text(
                  '${widget.progress.toString()} %',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
