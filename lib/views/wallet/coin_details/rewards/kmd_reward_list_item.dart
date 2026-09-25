import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/mm2/mm2_api/rpc/kmd_rewards_info/kmd_reward_item.dart';
import 'package:web_dex/shared/ui/custom_tooltip.dart';
import 'package:web_dex/shared/utils/formatters.dart';

class KmdRewardListItem extends StatelessWidget {
  const KmdRewardListItem({Key? key, required this.reward}) : super(key: key);

  final KmdRewardItem reward;

  bool get _isThereReward {
    return reward.reward != null;
  }

  @override
  Widget build(BuildContext context) {
    return isMobile ? _buildMobileItem(context) : _buildDesktopItem(context);
  }

  Widget _buildDesktopItem(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      mainAxisSize: MainAxisSize.max,
      children: [
        Flexible(
          flex: 3,
          child: Align(
            alignment: const Alignment(-1, 0),
            child: SelectableText(
              cutTrailingZeros(formatAmt(double.parse(reward.amount))),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontSize: 14),
            ),
          ),
        ),
        Flexible(
          flex: 3,
          child: Align(
            alignment: const Alignment(-1, 0),
            child: _buildReward(context),
          ),
        ),
        Flexible(
          flex: 3,
          child: Align(
            alignment: const Alignment(-1, 0),
            child: _buildTimeLeft(context),
          ),
        ),
        Flexible(
          flex: 1,
          child: Align(
            alignment: Alignment.centerLeft,
            child: _buildStatus(context),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileItem(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 15.0, horizontal: 15),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(15.0),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.tertiary,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              Icons.arrow_downward,
              size: 15,
              color: theme.custom.increaseColor,
            ),
          ),
          const SizedBox(width: 15),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                LocaleKeys.reward.tr(),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              _buildTimeLeft(context),
            ],
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SelectableText(
                '+KMD '
                '${cutTrailingZeros(formatAmt(double.parse(reward.amount)))}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: theme.custom.increaseColor,
                ),
              ),
              SelectableText(
                '+KMD '
                '${cutTrailingZeros(formatAmt(double.parse(reward.amount)))}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReward(BuildContext context) {
    final String text = _isThereReward
        ? '+ ${cutTrailingZeros(formatAmt(reward.reward!))}'
        : '-';
    final TextStyle? style = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(fontSize: 14);
    return SelectableText(text, style: style);
  }

  Widget _buildStatus(BuildContext context) {
    final RewardItemError? rewardError = reward.error;

    if (rewardError != null) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SelectableText(
            rewardError.short,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontSize: 14),
          ),
          if (rewardError.long.isNotEmpty)
            CustomTooltip(
              maxWidth: 200,
              padding: const EdgeInsets.all(12),
              tooltip: SelectableText(
                rewardError.long,
                style: const TextStyle(fontSize: 13),
              ),
              child: const Icon(Icons.info_outlined, size: 16),
            ),
        ],
      );
    }

    if (_isThereReward) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(0, 0, 20, 0),
        child: Icon(Icons.check_circle, color: Colors.green, size: 14),
      );
    }

    return const SizedBox();
  }

  Widget _buildTimeLeft(BuildContext context) {
    final Duration? timeLeft = reward.timeLeft;
    return timeLeft == null
        ? SelectableText(
            '-',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontSize: 14),
          )
        : SelectableText(
            _formatTimeLeft(timeLeft),
            style: timeLeft.inDays <= 2
                ? Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: 14,
                    color: Colors.orange,
                  )
                : Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontSize: 14),
          );
  }

  String _formatTimeLeft(Duration duration) {
    final int dd = duration.inDays;
    final int hh = duration.inHours;
    final int mm = duration.inMinutes;
    if (dd > 0) {
      return '$dd day(s)';
    }
    if (hh > 0) {
      String minutes = mm.remainder(60).toString();
      if (minutes.length < 2) minutes = '0$minutes';
      return '${hh}h ${minutes}m';
    }
    if (mm > 0) {
      return '${mm}min';
    }
    return '-';
  }
}
