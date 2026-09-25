import 'package:flutter/material.dart';

/// A full-width, flat action row: title, optional subtitle, trailing chevron.
///
/// The counterpart to [UiPrimaryButton] when a screen needs a second action
/// that must stay obviously available without competing for the eye. Dominance
/// is carried by fill and elevation on the primary button, **not** by shrinking
/// this one - the tap target here is deliberately the full width of its parent
/// and at least [minHeight] tall.
class UiListActionRow extends StatelessWidget {
  const UiListActionRow({
    super.key,
    required this.title,
    this.rowKey,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.backgroundColor,
    this.borderRadius = 18,
    this.minHeight = 56,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  });

  /// Goes on the tappable [InkWell] rather than the outer widget, mirroring
  /// [UiPrimaryButton.buttonKey].
  final Key? rowKey;

  final String title;
  final String? subtitle;
  final Widget? leading;

  /// Defaults to [defaultTrailingIcon].
  final Widget? trailing;

  /// Null disables the row.
  final VoidCallback? onTap;

  /// Null leaves the row transparent, which is the quiet default.
  final Color? backgroundColor;

  final double borderRadius;
  final double minHeight;
  final EdgeInsets padding;

  /// The one chevron this app uses for "opens another screen".
  ///
  /// Referenced as a token rather than re-picked per call site - there were
  /// three different chevrons across three usages before this existed.
  static const IconData defaultTrailingIcon =
      Icons.keyboard_arrow_right_rounded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEnabled = onTap != null;
    final mutedColor = theme.textTheme.bodySmall?.color;

    final titleStyle = theme.textTheme.bodyLarge?.copyWith(
      fontWeight: FontWeight.w600,
      color: isEnabled ? theme.textTheme.bodyLarge?.color : mutedColor,
    );

    return SizedBox(
      width: double.infinity,
      child: Material(
        color: backgroundColor ?? Colors.transparent,
        borderRadius: BorderRadius.circular(borderRadius),
        child: InkWell(
          key: rowKey,
          onTap: onTap,
          borderRadius: BorderRadius.circular(borderRadius),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Padding(
              padding: padding,
              child: Row(
                children: [
                  if (leading != null) ...[
                    leading!,
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: titleStyle),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: mutedColor,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  trailing ??
                      Icon(
                        defaultTrailingIcon,
                        size: 20,
                        color: mutedColor,
                      ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
