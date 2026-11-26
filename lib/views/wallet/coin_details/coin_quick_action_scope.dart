import 'package:flutter/widgets.dart';
import 'package:web_dex/router/state/wallet_state.dart';

/// Hands a coin page's pending quick action to its Send and Receive buttons,
/// which start it through their own checks the first time they are enabled.
class CoinQuickActionScope extends InheritedWidget {
  const CoinQuickActionScope({
    required this.request,
    required super.child,
    super.key,
  });

  final CoinQuickActionRequest? request;

  /// Starts [action] if it is the one pending here, once, after this frame.
  static void startIfPending(
    BuildContext context,
    CoinQuickAction action,
    VoidCallback start,
  ) {
    final scope = context.getInheritedWidgetOfExactType<CoinQuickActionScope>();
    if (scope?.request?.start(action) != true) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) start();
    });
  }

  @override
  bool updateShouldNotify(CoinQuickActionScope oldWidget) =>
      request != oldWidget.request;
}
