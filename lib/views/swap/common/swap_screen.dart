import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One screen of the swap surface, as the keyboard and screen readers meet
/// it.
///
/// Screen readers hear it arrive as a new screen, named by its
/// `SwapPageHeading`. When it replaces the screen that held keyboard focus,
/// focus moves to its heading, so Tab, the arrow keys and Escape carry on
/// from here rather than from the top of the app. Focus held anywhere else,
/// such as on the tab that switched to it, stays put. [onEscape], when given,
/// is what Escape does anywhere on the screen.
class SwapScreen extends StatefulWidget {
  const SwapScreen({required this.child, this.onEscape, super.key});

  final Widget child;
  final VoidCallback? onEscape;

  /// The focus node the heading of the enclosing screen takes, if any.
  static FocusNode? focusOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SwapScreenScope>()?.focusNode;

  @override
  State<SwapScreen> createState() => _SwapScreenState();
}

class _SwapScreenState extends State<SwapScreen> {
  final FocusNode _heading = FocusNode(debugLabel: 'SwapScreen heading');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _arrive());
  }

  void _arrive() {
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
    if (swapFocusLost()) _heading.requestFocus();
  }

  @override
  void dispose() {
    _heading.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onEscape = widget.onEscape;
    Widget child = _SwapScreenScope(focusNode: _heading, child: widget.child);
    if (onEscape != null) {
      child = CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): onEscape},
        child: child,
      );
    }
    return Semantics(
      container: true,
      scopesRoute: true,
      explicitChildNodes: true,
      child: child,
    );
  }
}

/// Whether keyboard focus went with the screen that held it. Until the frame
/// after a screen changes settles, focus lost that way reads as nothing, or
/// as a scope.
bool swapFocusLost() {
  final focus = FocusManager.instance.primaryFocus;
  return focus == null || focus is FocusScopeNode;
}

class _SwapScreenScope extends InheritedWidget {
  const _SwapScreenScope({required this.focusNode, required super.child});

  final FocusNode focusNode;

  @override
  bool updateShouldNotify(_SwapScreenScope oldWidget) =>
      focusNode != oldWidget.focusNode;
}
