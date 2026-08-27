import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/ui/custom_tooltip.dart';
import 'package:web_dex/shared/utils/formatters.dart';
import 'package:web_dex/shared/utils/utils.dart';

class KmdRewardInfoHeader extends StatelessWidget {
  const KmdRewardInfoHeader({
    Key? key,
    required this.totalReward,
    required this.isThereReward,
    required this.coinAbbr,
    this.totalRewardUsd,
  }) : super(key: key);

  final double totalReward;
  final double? totalRewardUsd;
  final bool isThereReward;
  final String coinAbbr;

  @override
  Widget build(BuildContext context) {
    final String rewardText = isThereReward
        ? '+ $coinAbbr ${doubleToString(totalReward)}'
        : LocaleKeys.noClaimableRewards.tr();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText(
          rewardText,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: isThereReward ? theme.custom.increaseColor : null,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        if (isThereReward)
          Row(
            children: [
              SelectableText(
                '\$${cutTrailingZeros(formatAmt(totalRewardUsd ?? 0))}',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(color: Colors.grey),
              ),
              const SizedBox(width: 6),
              CustomTooltip(
                maxWidth: 250,
                padding: const EdgeInsets.all(12),
                tooltip: _buildTooltip(context),
                child: const Icon(Icons.info_outline, size: 24),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildTooltip(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12),
        children: [
          TextSpan(text: '${LocaleKeys.kmdRewardSpan1.tr()}('),
          TextSpan(
            text: 'coingecko.com',
            style: const TextStyle(color: Colors.blue),
            recognizer: TapGestureRecognizer()
              ..onTap = () {
                launchURLString('https://www.coingecko.com');
              },
          ),
          const TextSpan(text: ', '),
          TextSpan(
            text: 'openrates.io',
            style: const TextStyle(color: Colors.blue),
            recognizer: TapGestureRecognizer()
              ..onTap = () {
                launchURLString('https://exchangeratesapi.io');
              },
          ),
          const TextSpan(text: ')'),
        ],
      ),
    );
  }
}
