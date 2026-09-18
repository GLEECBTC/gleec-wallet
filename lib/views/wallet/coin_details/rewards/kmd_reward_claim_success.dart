import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/common/app_assets.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/views/common/page_header/page_header.dart';
import 'package:web_dex/views/common/pages/page_layout.dart';

class KmdRewardClaimSuccess extends StatelessWidget {
  const KmdRewardClaimSuccess({
    Key? key,
    required this.reward,
    required this.formattedUsd,
    required this.onBackButtonPressed,
  }) : super(key: key);

  final String reward;
  final String formattedUsd;
  final VoidCallback onBackButtonPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData themeData = Theme.of(context);

    return PageLayout(
      header: PageHeader(
        backText: LocaleKeys.back.tr(),
        onBackButtonPressed: onBackButtonPressed,
        title: LocaleKeys.successClaim.tr(),
      ),
      content: getContent(themeData),
    );
  }

  Widget getContent(ThemeData themeData) {
    return Center(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 30.0),
          const DexSvgImage(path: Assets.assetTick),
          const SizedBox(height: 40.0),
          Text(
            LocaleKeys.youClaimed.tr(),
            style: TextStyle(
              color: themeData.textTheme.bodyMedium?.color?.withValues(
                alpha: 0.4,
              ),
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 5.0),
          SelectableText(
            reward,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 25),
          ),
          const SizedBox(height: 5.0),
          SelectableText(
            '\$$formattedUsd',
            style: TextStyle(
              color: themeData.textTheme.bodyMedium?.color?.withValues(
                alpha: 0.7,
              ),
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 60.0),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: UiPrimaryButton(
              onPressed: onBackButtonPressed,
              text: LocaleKeys.done.tr(),
            ),
          ),
        ],
      ),
    );
  }
}
