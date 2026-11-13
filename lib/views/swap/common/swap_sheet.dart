import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';

/// Width below which a sheet covers the whole screen.
const double _fullScreenBelow = 768;

/// The widest a sheet shown as a dialog gets.
const double _dialogWidth = 440;

/// Opens [builder] as the swap surface's sheet: full screen on a phone, a
/// panel sliding in from the right on anything wider.
///
/// One presentation for pickers, options and evidence keeps focus handling
/// and dismissal identical everywhere: Escape, the close button and a tap on
/// the scrim all pop with null. A snack bar raised inside a sheet, such as a
/// copy confirmation, shows on the sheet rather than on the page beneath.
///
/// With [fitContent], a short choice that should not take the whole screen
/// is only as tall as its content instead: a bottom sheet on a phone, which
/// can also be swiped away, and a dialog in the middle of a wider window. A
/// window too short for a dialog keeps the panel. A snack bar raised inside
/// either shows on the page beneath, so they suit a choice that raises none.
Future<T?> showSwapSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  required String label,
  bool fitContent = false,
}) {
  final size = MediaQuery.sizeOf(context);
  final width = size.width;
  final fullScreen = width < _fullScreenBelow;
  final reduceMotion = MediaQuery.disableAnimationsOf(context);
  final palette = SwapPalette.of(context);
  if (fitContent && !fullScreen && size.height >= SwapGeometry.shortHeight) {
    return _showSwapDialog<T>(context: context, builder: builder, label: label);
  }
  if (fullScreen && fitContent) {
    return showModalBottomSheet<T>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: palette.surfaceRaised,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      barrierLabel: label,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      sheetAnimationStyle: reduceMotion
          ? const AnimationStyle(
              duration: Duration.zero,
              reverseDuration: Duration.zero,
            )
          : null,
      builder: (sheetContext) => _FitsContent(
        handle: true,
        child: SafeArea(top: false, child: Builder(builder: builder)),
      ),
    );
  }
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
      final content = ScaffoldMessenger(
        child: Scaffold(
          backgroundColor: fullScreen ? palette.canvas : palette.surfaceRaised,
          // A sheet makes its own room for the keyboard: resizing here would
          // unpin the asset picker's search mid-typing and drop its focus.
          resizeToAvoidBottomInset: false,
          body: Actions(
            // Scaffold binds Escape to its drawer and, having none, drops it;
            // pass it on so Escape still closes the sheet.
            actions: {
              DismissIntent: CallbackAction<DismissIntent>(
                onInvoke: (intent) =>
                    Actions.maybeInvoke(dialogContext, intent),
              ),
            },
            child: SafeArea(child: Builder(builder: builder)),
          ),
        ),
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

/// Opens [builder] in a dialog in the middle of the window, as tall as its
/// content.
Future<T?> _showSwapDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  required String label,
}) {
  final reduceMotion = MediaQuery.disableAnimationsOf(context);
  final palette = SwapPalette.of(context);
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: label,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 180),
    // Dialog stays above the keyboard and hides it from its content, so a
    // sheet that makes its own room for the keyboard adds none here.
    pageBuilder: (_, _, _) => SafeArea(
      child: Dialog(
        backgroundColor: palette.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        shadowColor: palette.shadow,
        elevation: 24,
        insetPadding: const EdgeInsets.all(24),
        insetAnimationDuration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 100),
        constraints: const BoxConstraints(
          minWidth: 280,
          maxWidth: _dialogWidth,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: palette.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: _FitsContent(handle: false, child: Builder(builder: builder)),
      ),
    ),
    transitionBuilder: (context, animation, _, child) {
      final curved = animation.drive(CurveTween(curve: Curves.easeOutCubic));
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: curved.drive(Tween<double>(begin: 0.96, end: 1)),
          child: child,
        ),
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
    final text = this.subtitle;
    final subtitle = text == null
        ? null
        : Text(text, style: SwapText.small(context));
    // A scrolling body carries the subtitle, so large text cannot push the
    // pinned heading and footer past the screen.
    final pinnedSubtitle = scrollable ? null : subtitle;
    // In a sheet as tall as its content the body takes only the height it
    // needs, and under a drag handle the heading needs no room above it.
    final fitted = context.getInheritedWidgetOfExactType<_FitsContent>();
    final fits = fitted != null;
    final underHandle = fitted?.handle ?? false;
    final body = scrollable
        ? SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            child: subtitle == null
                ? this.body
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [subtitle, const SizedBox(height: 12), this.body],
                  ),
          )
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: this.body,
          );
    return Column(
      mainAxisSize: fits ? MainAxisSize.min : MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            underHandle ? 0 : 18,
            18,
            subtitle != null && scrollable ? 4 : 12,
          ),
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
                    if (pinnedSubtitle != null) ...[
                      const SizedBox(height: 4),
                      pinnedSubtitle,
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
        if (fits) Flexible(child: body) else Expanded(child: body),
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

/// Marks a sheet that is as tall as its content.
class _FitsContent extends InheritedWidget {
  const _FitsContent({required this.handle, required super.child});

  /// Whether a drag handle sits above it, as on a bottom sheet.
  final bool handle;

  @override
  bool updateShouldNotify(_FitsContent oldWidget) => handle != oldWidget.handle;
}
