import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';

/// Centres swap content in the readable column.
class SwapColumn extends StatelessWidget {
  const SwapColumn({
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(16, 20, 16, 32),
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: SwapGeometry.contentWidth),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// A rounded, bordered surface.
class SwapSurface extends StatelessWidget {
  const SwapSurface({
    required this.child,
    this.color,
    this.borderColor,
    this.radius = 16,
    this.padding = const EdgeInsets.all(14),
    this.dashed = false,
    super.key,
  });

  final Widget child;
  final Color? color;
  final Color? borderColor;
  final double radius;
  final EdgeInsetsGeometry padding;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? palette.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? palette.border),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// A page heading with an optional leading back or close action.
class SwapPageHeading extends StatelessWidget {
  const SwapPageHeading({
    required this.title,
    this.leading,
    this.subtitle,
    super.key,
  });

  final String title;
  final Widget? leading;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final subtitle = this.subtitle;
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: SwapText.title(context)),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle, style: SwapText.small(context)),
        ],
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: leading == null
          ? heading
          : Row(
              children: [
                leading!,
                const SizedBox(width: 12),
                Expanded(child: heading),
              ],
            ),
    );
  }
}

/// Announces [message] to assistive technology, where the platform supports
/// announcements.
void swapAnnounce(BuildContext context, String message) {
  if (!MediaQuery.supportsAnnounceOf(context)) return;
  SemanticsService.sendAnnouncement(
    View.of(context),
    message,
    Directionality.of(context),
  );
}
