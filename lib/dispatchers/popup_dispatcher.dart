import 'dart:async';

import 'package:app_theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/services/platform_web_api/platform_web_api.dart';

/// **DEPRECATED**: Use `AppDialog` from `package:web_dex/shared/widgets/app_dialog.dart` instead.
///
/// This class is deprecated and will be removed in a future version.
/// It has been replaced by `AppDialog.show()` which provides the same functionality
/// using Flutter's built-in dialog system with better performance and maintainability.
///
/// Migration example:
/// ```dart
/// // OLD (deprecated):
/// PopupDispatcher(
///   context: context,
///   width: 320,
///   popupContent: MyWidget(),
/// ).show();
///
/// // NEW (recommended):
/// AppDialog.show(
///   context: context,
///   width: 320,
///   child: MyWidget(),
/// );
/// ```
@Deprecated(
  'Use AppDialog from package:web_dex/shared/widgets/app_dialog.dart instead. '
  'This class will be removed in a future version.',
)
class PopupDispatcher {
  PopupDispatcher({
    this.context,
    this.popupContent,
    this.width,
    this.insetPadding,
    this.contentPadding,
    this.barrierColor,
    this.borderColor,
    this.maxWidth = 640,
    this.barrierDismissible = true,
    this.onDismiss,
  }) : _platformWebApi = PlatformWebApi();

  final BuildContext? context;
  final Widget? popupContent;
  final double? width;
  final double maxWidth;
  final bool barrierDismissible;
  final EdgeInsets? insetPadding;
  final EdgeInsets? contentPadding;
  final Color? barrierColor;
  final Color? borderColor;
  final VoidCallback? onDismiss;
  final PlatformWebApi _platformWebApi;

  bool _isShown = false;
  bool get isShown => _isShown;

  StreamSubscription<void>? _popStreamSubscription;

  Future<void> show() async {
    if (_currentContext == null) return;

    if (_isShown) close();
    _isShown = true;
    final borderColor = this.borderColor;
    _setupDismissibleLogic();

    await showDialog<void>(
      barrierDismissible: barrierDismissible,
      context: _currentContext!,
      barrierColor: theme.custom.dialogBarrierColor,
      builder: (BuildContext dialogContext) {
        return SimpleDialog(
          insetPadding:
              insetPadding ??
              EdgeInsets.symmetric(
                horizontal: isMobile ? 16 : 24,
                vertical: isMobile ? 40 : 24,
              ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: borderColor != null
                ? BorderSide(color: borderColor)
                : BorderSide.none,
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
              child: popupContent,
            ),
          ],
        );
      },
    );
    _isShown = false;
    _resetBrowserNavigationToDefault();
    if (onDismiss != null) onDismiss!();
  }

  void close() {
    _resetBrowserNavigationToDefault();
    if (_currentContext == null) return;
    if (_isShown) {
      final navigator = Navigator.of(_currentContext!);
      // ignore: discarded_futures
      navigator.maybePop();
    }
  }

  void _setupDismissibleLogic() {
    routingState.isBrowserNavigationBlocked = true;
    if (barrierDismissible) {
      if (kIsWeb) {
        _onPopStateSubscriptionWeb();
      }
    }
  }

  void _onPopStateSubscriptionWeb() {
    _popStreamSubscription = _platformWebApi.onPopState(() {
      final navigator = Navigator.of(_currentContext!, rootNavigator: true);
      if (navigator.canPop()) {
        _resetBrowserNavigationToDefault();
        navigator.pop();
      }
    });
  }

  void _resetBrowserNavigationToDefault() {
    routingState.isBrowserNavigationBlocked = false;
    _popStreamSubscription?.cancel();
  }

  BuildContext? get _currentContext => context ?? scaffoldKey.currentContext;
}
