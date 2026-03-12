import 'package:app_theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

class NftTxnMobileFilterCard extends StatelessWidget {
  final String title;
  final String svgPath;
  final VoidCallback onTap;
  final bool isSelected;
  final Color? accentColor;
  const NftTxnMobileFilterCard({
    super.key,
    required this.title,
    required this.svgPath,
    required this.onTap,
    this.isSelected = false,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).extension<ColorSchemeExtension>()!;
    final textScheme = Theme.of(context).extension<TextThemeExtension>()!;
    final Color inactiveColor = accentColor ?? colorScheme.s70;
    final color = isSelected ? colorScheme.surf : inactiveColor;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        alignment: Alignment.bottomLeft,
        height: 56,
        constraints: const BoxConstraints(maxHeight: 56),
        decoration: BoxDecoration(
          color: isSelected ? colorScheme.primary : colorScheme.surfCont,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: textScheme.bodyS.copyWith(color: color)),
            const SizedBox(width: 8),
            SvgPicture.asset(
              svgPath,
              colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
              width: 24,
              height: 24,
            ),
          ],
        ),
      ),
    );
  }
}
