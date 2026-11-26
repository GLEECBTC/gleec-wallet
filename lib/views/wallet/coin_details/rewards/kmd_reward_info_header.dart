import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/ui/custom_tooltip.dart';
import 'package:web_dex/shared/utils/fiat_format.dart';
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
    final palette = AppPalette.of(context);
    final String rewardText = isThereReward
        ? '+ $coinAbbr ${doubleToString(totalReward)}'
        : LocaleKeys.noClaimableRewards.tr();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText(
          rewardText,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: isThereReward ? palette.success : null,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        if (isThereReward)
          Row(
            children: [
              SelectableText(
                FiatFormat.amount(totalRewardUsd ?? 0),
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(color: palette.textTertiary),
              ),
              const SizedBox(width: 6),
              CustomTooltip(
                maxWidth: 250,
                padding: const EdgeInsets.all(12),
                // The tooltip opens in the app overlay, outside the palette.
                color: palette.surfaceRaised,
                tooltip: _buildTooltip(context),
                child: const Icon(Icons.info_outline, size: 24),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildTooltip(BuildContext context) {
    final palette = AppPalette.of(context);
    return RichText(
      text: TextSpan(
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12),
        children: [
          TextSpan(text: '${LocaleKeys.kmdRewardSpan1.tr()}('),
          TextSpan(
            text: 'coingecko.com',
            style: TextStyle(color: palette.brandHover),
            recognizer: TapGestureRecognizer()
              ..onTap = () {
                launchURLString('https://www.coingecko.com');
              },
          ),
          const TextSpan(text: ', '),
          TextSpan(
            text: 'openrates.io',
            style: TextStyle(color: palette.brandHover),
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
