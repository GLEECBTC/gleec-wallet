import 'package:flutter/material.dart';
import 'package:app_theme/app_theme.dart';
import 'package:web_dex/common/screen.dart';

// Constants for dialog styling
const double _defaultBorderRadius = 18;
const double _defaultMaxWidth = 640;
const BorderRadius _defaultDialogBorderRadius = BorderRadius.all(
  Radius.circular(_defaultBorderRadius),
);

/// A replacement for the deprecated PopupDispatcher that uses Flutter's built-in dialog system.
///
/// This widget provides the same styling and behavior as PopupDispatcher but with
/// better performance and maintainability.
///
/// ## Migration from PopupDispatcher
///
/// **Simple dialog:**
/// ```dart
/// // OLD
/// PopupDispatcher(
///   context: context,
///   width: 320,
///   popupContent: MyWidget(),
/// ).show();
///
/// // NEW
/// AppDialog.show(
///   context: context,
///   width: 320,
///   child: MyWidget(),
/// );
/// ```
///
/// **Dialog with success callback:**
/// ```dart
/// // OLD
/// _popupDispatcher = PopupDispatcher(
///   context: context,
///   popupContent: MyWidget(onSuccess: () => _popupDispatcher?.close()),
/// );
/// _popupDispatcher?.show();
///
/// // NEW
/// AppDialog.showWithCallback(
///   context: context,
///   childBuilder: (closeDialog) => MyWidget(onSuccess: closeDialog),
///   // useRootNavigator defaults to true to prevent navigation corruption
/// );
/// ```
///
/// **Dialog with custom styling:**
/// ```dart
/// // OLD
/// PopupDispatcher(
///   context: context,
///   borderColor: customColor,
///   contentPadding: EdgeInsets.all(20),
///   popupContent: MyWidget(),
/// ).show();
///
/// // NEW
/// AppDialog.show(
///   context: context,
///   borderColor: customColor,
///   contentPadding: EdgeInsets.all(20),
///   child: MyWidget(),
/// );
/// ```
class AppDialog {
  /// Shows a dialog with PopupDispatcher-compatible styling.
  ///
  /// Parameters:
  /// - [context]: The build context to show the dialog in
  /// - [child]: The widget to display inside the dialog
  /// - [width]: The preferred width of the dialog content
  /// - [maxWidth]: The maximum width constraint (defaults to 640)
  /// - [barrierDismissible]: Whether the dialog can be dismissed by tapping outside (defaults to true)
  /// - [borderColor]: The color of the dialog border (defaults to theme.custom.specificButtonBorderColor)
  /// - [insetPadding]: Custom inset padding (uses responsive defaults if null)
  /// - [contentPadding]: Custom content padding (uses responsive defaults if null)
  /// - [useRootNavigator]: Whether to use the root navigator (defaults to false)
  /// - [onDismiss]: Callback called when the dialog is dismissed
  static Future<T?> show<T>({
    required BuildContext context,
    required Widget child,
    double? width,
    double maxWidth = _defaultMaxWidth,
    bool barrierDismissible = true,
    Color? borderColor,
    EdgeInsets? insetPadding,
    EdgeInsets? contentPadding,
    bool useRootNavigator = false,
    VoidCallback? onDismiss,
  }) async {
    // Ensure context is still mounted before showing dialog
    if (!context.mounted) return null;

    // Validate parameters
    assert(maxWidth > 0, 'maxWidth must be positive');
    assert(width == null || width > 0, 'width must be positive if provided');

    final result = await showDialog<T>(
      context: context,
      useRootNavigator: useRootNavigator,
      barrierDismissible: barrierDismissible,
      barrierColor: theme.custom.dialogBarrierColor,
      builder: (BuildContext dialogContext) {
        return PopScope(
          onPopInvokedWithResult: (didPop, result) {
            // Only call onDismiss when dialog is actually dismissed (not programmatically closed)
            if (didPop && onDismiss != null) {
              onDismiss();
            }
          },
          child: SimpleDialog(
            insetPadding:
                insetPadding ??
                EdgeInsets.symmetric(
                  horizontal: isMobile ? 16 : 24,
                  vertical: isMobile ? 40 : 24,
                ),
            shape: RoundedRectangleBorder(
              borderRadius: _defaultDialogBorderRadius,
              side: BorderSide(
                color: borderColor ?? theme.custom.specificButtonBorderColor,
              ),
            ),
            contentPadding:
                contentPadding ??
                EdgeInsets.symmetric(
                  horizontal: isMobile ? 16 : 30,
                  vertical: isMobile ? 26 : 30,
                ),
            children: [
              Container(
                width: width,
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: child,
              ),
            ],
          ),
        );
      },
    );

    return result;
  }

  /// Shows a dialog with a specific content widget that can close itself.
  ///
  /// This is a convenience method for dialogs that need to close automatically
  /// when a success action occurs. The child widget receives a `closeDialog`
  /// callback that it can call to close the dialog safely.
  ///
  /// It defaults to using the root navigator to prevent navigation stack
  /// corruption after login or similar flows.
  static Future<T?> showWithCallback<T>({
    required BuildContext context,
    required Widget Function(VoidCallback closeDialog) childBuilder,
    double? width,
    double maxWidth = _defaultMaxWidth,
    bool barrierDismissible = true,
    Color? borderColor,
    EdgeInsets? insetPadding,
    EdgeInsets? contentPadding,
    bool useRootNavigator = true,
    VoidCallback? onDismiss,
  }) async {
    // Ensure context is still mounted before showing dialog
    if (!context.mounted) return null;

    // Validate parameters
    assert(maxWidth > 0, 'maxWidth must be positive');
    assert(width == null || width > 0, 'width must be positive if provided');

    // Guard against multiple close attempts which may happen during
    // rapid navigation state changes (e.g. login success + route change).
    // Held per dialog, so a rebuild of its content does not reset it.
    bool didRequestClose = false;
    return show<T>(
      context: context,
      width: width,
      maxWidth: maxWidth,
      barrierDismissible: barrierDismissible,
      borderColor: borderColor,
      insetPadding: insetPadding,
      contentPadding: contentPadding,
      useRootNavigator: useRootNavigator,
      onDismiss: onDismiss,
      child: Builder(
        builder: (context) {
          try {
            return childBuilder(() {
              if (didRequestClose || !context.mounted) return;
              didRequestClose = true;

              // Pop the dialog using the same navigator that was used to show it.
              final navigator = Navigator.of(
                context,
                rootNavigator: useRootNavigator,
              );
              // maybePop acts on the top route. Below another dialog it would
              // close that one instead, and while that one is closing it
              // drops this request, leaving this dialog open.
              final route = ModalRoute.of(context);
              if (route != null && route.isActive && !route.isCurrent) {
                navigator.removeRoute(route);
                return;
              }
              // Use maybePop to avoid "Bad state: No element" when there is
              // nothing left to pop on the target navigator.
              // ignore: discarded_futures
              navigator.maybePop();
            });
          } catch (e) {
            // If childBuilder throws an error, show a fallback widget
            return Center(
              child: Text(
                'Error building dialog content: $e',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            );
          }
        },
      ),
    );
  }

  /// Safely closes a dialog using the correct navigator context.
  ///
  /// This method ensures the dialog is closed using the appropriate navigator,
  /// preventing navigation stack corruption. Use this when you need to close
  /// a dialog programmatically from outside the dialog widget.
  ///
  /// [useRootNavigator] should match the value used when showing the dialog.
  /// - Use `false` for dialogs shown with `AppDialog.show()` (default)
  /// - Use `true` for dialogs shown with `AppDialog.showWithCallback()` (default)
  static void close(BuildContext context, {bool useRootNavigator = false}) {
    if (context.mounted) {
      final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
      // ignore: discarded_futures
      navigator.maybePop();
    }
  }
}
