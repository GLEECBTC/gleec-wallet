import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/common/swap_screen.dart';

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
    this.visible = true,
    super.key,
  });

  final String title;
  final Widget? leading;
  final String? subtitle;

  /// Whether it is drawn. Hidden, it still names the screen for screen
  /// readers and takes the keyboard as the screen arrives.
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final subtitle = this.subtitle;
    final focus = SwapScreen.focusOf(context);
    Widget name = Semantics(
      header: true,
      namesRoute: true,
      label: visible ? null : title,
      // A node with no size is hidden from screen readers.
      child: visible
          ? Text(title, style: SwapText.title(context))
          : const SizedBox(height: 1, width: double.infinity),
    );
    // Where the keyboard lands as the screen arrives; never a Tab stop.
    if (focus != null) {
      name = Focus(focusNode: focus, skipTraversal: true, child: name);
    }
    if (!visible) return name;
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        name,
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

/// A screen's main action, pinned under its scrolling content.
class SwapStickyFooter extends StatelessWidget {
  const SwapStickyFooter({
    required this.child,
    this.inPanel = false,
    super.key,
  });

  final Widget child;

  /// Whether it closes a side panel rather than a whole screen.
  final bool inPanel;

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    final padded = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: child,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: inPanel ? palette.surfaceRaised : palette.canvas,
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: inPanel
          ? padded
          : Align(
              alignment: Alignment.topCenter,
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: SwapGeometry.contentWidth,
                ),
                child: padded,
              ),
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
