import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/shared/utils/formatters.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/shared/widgets/copied_text.dart';

class SwapDetailsStep extends StatelessWidget {
  const SwapDetailsStep({
    Key? key,
    required this.event,
    this.isCurrentStep = false,
    this.isProcessedStep = false,
    this.isDisabled = false,
    this.isFailedStep = false,
    this.isLastStep = false,
    this.timeSpent = 0,
    this.txHash,
    this.coin,
  }) : super(key: key);

  final int timeSpent;
  final String event;
  final bool isCurrentStep;
  final bool isProcessedStep;
  final bool isDisabled;
  final bool isFailedStep;
  final bool isLastStep;
  final String? txHash;
  final Coin? coin;

  Color get _circleColor {
    if (isFailedStep) {
      return theme.custom.tradingDetailsTheme.swapStepCircleFailedColor;
    }
    if (isDisabled) {
      return theme.custom.tradingDetailsTheme.swapStepCircleDisabledColor;
    }

    return theme.custom.tradingDetailsTheme.swapStepCircleNormalColor;
  }

  Color get _textColor {
    if (isFailedStep) {
      return theme.custom.tradingDetailsTheme.swapStepTextFailedColor;
    }
    if (isDisabled) {
      return theme.custom.tradingDetailsTheme.swapStepTextDisabledColor;
    }
    if (isCurrentStep) {
      return theme.custom.tradingDetailsTheme.swapStepTextCurrentColor;
    }

    return const Color.fromRGBO(106, 77, 227, 1);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData themeData = Theme.of(context);
    final String? txHash = this.txHash;
    final Coin? coin = this.coin;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.max,
        children: [
          Column(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: _circleColor,
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isProcessedStep || isFailedStep
                          ? Colors.transparent
                          : themeData.colorScheme.surface,
                    ),
                  ),
                ),
              ),
              if (!isLastStep)
                Container(
                  height: 40,
                  width: 1,
                  color: isProcessedStep
                      ? theme.custom.progressBarPassedColor
                      : themeData.textTheme.bodyMedium?.color?.withValues(
                              alpha: 0.3,
                            ) ??
                            Colors.transparent,
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.max,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: AutoScrollText(
                        text: event,
                        style: TextStyle(
                          color: _textColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 4.0),
                      child: _buildAdditionalInfo(context),
                    ),
                  ],
                ),
                if (txHash != null && coin != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: CopiedText(
                          copiedValue: txHash,
                          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                          isTruncated: true,
                          fontSize: 11,
                          iconSize: 14,
                          backgroundColor:
                              theme.custom.specificButtonBackgroundColor,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 6.0, right: 10),
                        child: Material(
                          child: Tooltip(
                            message: LocaleKeys.viewOnExplorer.tr(),
                            child: InkWell(
                              child: const Icon(
                                Icons.open_in_browser,
                                size: 20,
                              ),
                              onTap: () => launchURLString(
                                getTxExplorerUrl(coin, txHash),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdditionalInfo(BuildContext context) {
    if (isFailedStep) {
      return SelectableText(
        LocaleKeys.swapDetailsStepStatusFailed.tr(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: _textColor,
        ),
      );
    }
    if (isCurrentStep) {
      return SelectableText(
        LocaleKeys.swapDetailsStepStatusInProcess.tr(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: _textColor,
        ),
      );
    }
    if (!isDisabled) {
      return SelectableText(
        _getTimeSpent(context),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: theme.custom.tradingDetailsTheme.swapStepTimerColor,
        ),
      );
    }
    return const Text('');
  }

  String _getTimeSpent(BuildContext context) {
    return LocaleKeys.swapDetailsStepStatusTimeSpent.tr(
      args: [
        durationFormat(
          Duration(milliseconds: timeSpent),
          DurationLocalization(
            milliseconds: LocaleKeys.milliseconds.tr(),
            seconds: LocaleKeys.seconds.tr(),
            minutes: LocaleKeys.minutes.tr(),
            hours: LocaleKeys.hours.tr(),
          ),
        ),
      ],
    );
  }
}
