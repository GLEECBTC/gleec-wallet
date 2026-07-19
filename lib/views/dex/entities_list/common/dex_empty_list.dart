import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';

class DexEmptyList extends StatelessWidget {
  const DexEmptyList();

  @override
  Widget build(BuildContext context) {
    final colors = GleecColorTokens.of(context);
    final typography = GleecTypography.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 70, 12, 70),
        alignment: Alignment.topCenter,
        child: Text(
          LocaleKeys.listIsEmpty.tr(),
          textAlign: TextAlign.center,
          style: typography.bodyMedium.copyWith(color: colors.textSecondary),
        ),
      ),
    );
  }
}
