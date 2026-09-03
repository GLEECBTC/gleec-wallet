import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';

class NftFailure extends StatelessWidget {
  const NftFailure({
    super.key,
    required this.title,
    required this.subtitle,
    required this.message,
    required this.onTryAgain,
    this.additionSubtitle,
    this.isSpinnerShown = false,
  });

  final String title;
  final String subtitle;
  final String? additionSubtitle;
  final String message;
  final VoidCallback onTryAgain;
  final bool isSpinnerShown;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).extension<ColorSchemeExtension>()!;
    final textTheme = Theme.of(context).extension<TextThemeExtension>()!;

    final additionSubtitle = this.additionSubtitle;
    final scrollController = ScrollController();
    return DexScrollbar(
      scrollController: scrollController,
      child: SingleChildScrollView(
        controller: scrollController,
        child: SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 15),
              DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: colorScheme.error, width: 6),
                ),
                child: Icon(
                  Icons.close_rounded,
                  size: 66,
                  color: colorScheme.error,
                ),
              ),
              const SizedBox(height: 15),
              Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(color: colorScheme.error),
              ),
              const SizedBox(height: 12),
              Text(
                subtitle,
                style: textTheme.bodyS,
                textAlign: TextAlign.center,
              ),
              if (additionSubtitle != null)
                Text(
                  additionSubtitle,
                  style: textTheme.bodyS,
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: 12),
              Container(
                  constraints: const BoxConstraints(maxWidth: 324),
                  decoration: BoxDecoration(
                      color: theme.custom.subCardBackgroundColor,
                      borderRadius: BorderRadius.circular(18)),
                  child: SelectableText(
                    message,
                    textAlign: TextAlign.center,
                    style: textTheme.bodyS.copyWith(color: colorScheme.s70),
                  )),
              const SizedBox(height: 24),
              UiPrimaryButton(
                text: LocaleKeys.retryButtonText.tr(),
                width: 324,
                prefix: isSpinnerShown
                    ? UiSpinner(color: colorScheme.primary)
                    : null,
                onPressed: isSpinnerShown ? null : onTryAgain,
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
