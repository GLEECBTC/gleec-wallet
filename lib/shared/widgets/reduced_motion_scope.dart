import 'package:flutter/widgets.dart';
import 'package:web_dex/services/reduced_motion/reduced_motion_signal.dart';

/// Makes `MediaQuery.disableAnimations` true whenever the user has asked for
/// less motion, on every platform.
///
/// Flutter 3.41 sets that flag only on Android and Linux. iOS reports Reduce
/// Motion as `AccessibilityFeatures.reduceMotion`, which no framework code
/// reads, and web, macOS and Windows report nothing, so [ReducedMotionSignal]
/// asks them. Every `MediaQuery.disableAnimationsOf` below this scope then
/// sees the user's choice.
class ReducedMotionScope extends StatefulWidget {
  const ReducedMotionScope({required this.child, this.signal, super.key});

  final Widget child;

  /// Replaces the platform's own signal, for tests.
  final ReducedMotionSignal? signal;

  @override
  State<ReducedMotionScope> createState() => _ReducedMotionScopeState();
}

class _ReducedMotionScopeState extends State<ReducedMotionScope>
    with WidgetsBindingObserver {
  late final ReducedMotionSignal _signal =
      widget.signal ?? ReducedMotionSignal();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _signal.addListener(_changed);
  }

  // iOS's flag is not part of `MediaQueryData`, so nothing else rebuilds
  // this scope when it changes.
  @override
  void didChangeAccessibilityFeatures() => _changed();

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _signal.removeListener(_changed);
    if (widget.signal == null) _signal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = MediaQuery.of(context);
    final reduce =
        data.disableAnimations ||
        View.of(
          context,
        ).platformDispatcher.accessibilityFeatures.reduceMotion ||
        _signal.value;
    // Always a MediaQuery, so flipping the setting never remounts the app.
    return MediaQuery(
      data: data.copyWith(disableAnimations: reduce),
      child: widget.child,
    );
  }
}
