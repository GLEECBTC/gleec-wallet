import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';

/// Presents the shared confirmation gate for destructive Advanced DEX actions.
///
/// Callers must perform the actual BLoC/repository action only when this method
/// returns `true`. Keeping the action outside the dialog avoids changing the
/// existing trading dispatch semantics.
Future<bool> showDexActionConfirmation({
  required BuildContext context,
  required String actionLabel,
  required Key confirmButtonKey,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      final colors = GleecColorTokens.of(dialogContext);
      final geometry = GleecGeometry.of(dialogContext);
      final typography = GleecTypography.of(dialogContext);

      return AlertDialog(
        title: Text(LocaleKeys.confirm.tr()),
        content: Semantics(
          liveRegion: true,
          child: Text(actionLabel, style: typography.bodyMedium),
        ),
        actionsPadding: EdgeInsets.fromLTRB(
          geometry.space24,
          geometry.space8,
          geometry.space24,
          geometry.space24,
        ),
        actions: [
          OutlinedButton(
            key: const Key('dex-destructive-action-dismiss'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(LocaleKeys.cancel.tr()),
          ),
          ElevatedButton(
            key: confirmButtonKey,
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.danger,
              foregroundColor:
                  ThemeData.estimateBrightnessForColor(colors.danger) ==
                      Brightness.dark
                  ? Colors.white
                  : Colors.black,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(actionLabel, textAlign: TextAlign.center),
          ),
        ],
      );
    },
  );

  return confirmed ?? false;
}
