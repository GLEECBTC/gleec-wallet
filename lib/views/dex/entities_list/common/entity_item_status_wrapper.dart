import 'package:app_theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

class EntityItemStatusWrapper extends StatelessWidget {
  const EntityItemStatusWrapper({
    Key? key,
    required this.text,
    required this.icon,
    required this.width,
    required this.backgroundColor,
    required this.textColor,
  }) : super(key: key);

  final String text;
  final double width;
  final Widget icon;
  final Color backgroundColor;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    assert(icon is Icon || icon is SvgPicture);
    final geometry = GleecGeometry.of(context);
    final typography = GleecTypography.of(context);

    return Container(
      padding: const EdgeInsets.all(8),
      constraints: BoxConstraints(
        minWidth: width,
        maxWidth: width,
        minHeight: geometry.minimumTapTarget,
      ),
      decoration: BoxDecoration(
        borderRadius: geometry.borderRadius12,
        color: backgroundColor,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 6.0),
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: typography.bodySmall.copyWith(color: textColor),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
