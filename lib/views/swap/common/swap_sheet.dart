import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';

/// Width below which a sheet covers the whole screen.
const double _fullScreenBelow = 768;

/// Opens [builder] as the swap surface's sheet: full screen on a phone, a
/// panel sliding in from the right on anything wider.
///
/// One presentation for pickers, options and evidence keeps focus handling
/// and dismissal identical everywhere: Escape, the close button and a tap on
/// the scrim all pop with null.
Future<T?> showSwapSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  required String label,
}) {
  final width = MediaQuery.sizeOf(context).width;
  final fullScreen = width < _fullScreenBelow;
  final reduceMotion = MediaQuery.disableAnimationsOf(context);
  final palette = SwapPalette.of(context);
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: label,
    barrierColor: fullScreen
        ? Colors.transparent
        : Colors.black.withValues(alpha: 0.45),
    transitionDuration: reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 220),
    pageBuilder: (dialogContext, _, _) {
      final content = Material(
        color: fullScreen ? palette.canvas : palette.surfaceRaised,
        child: SafeArea(child: Builder(builder: builder)),
      );
      if (fullScreen) return content;
      return Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: width < SwapGeometry.panelWidth
                ? width
                : SwapGeometry.panelWidth,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: palette.border)),
              boxShadow: [
                BoxShadow(
                  color: palette.shadow,
                  blurRadius: 48,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: SizedBox(height: double.infinity, child: content),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: fullScreen ? const Offset(0, 0.06) : const Offset(0.12, 0),
          end: Offset.zero,
        ).animate(curved),
        child: FadeTransition(opacity: curved, child: child),
      );
    },
  );
}

/// The layout inside a swap sheet: a heading row with a close action, a
/// scrolling body and an optional pinned footer.
class SwapSheetScaffold extends StatelessWidget {
  const SwapSheetScaffold({
    required this.title,
    required this.body,
    this.subtitle,
    this.footer,
    this.onClose,
    this.scrollable = true,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget body;
  final Widget? footer;
  final VoidCallback? onClose;

  /// Whether the body scrolls itself. Lists that scroll lazily pass false.
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    final subtitle = this.subtitle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(title, style: SwapText.heading(context)),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(subtitle, style: SwapText.small(context)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SwapIconButton(
                icon: Icons.close_rounded,
                label: LocaleKeys.close.tr(),
                onPressed: onClose ?? () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ),
        Expanded(
          child: scrollable
              ? SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                  child: body,
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: body,
                ),
        ),
        if (footer != null)
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: palette.border)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
              child: footer,
            ),
          ),
      ],
    );
  }
}
