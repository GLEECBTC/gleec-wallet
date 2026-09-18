import 'package:flutter/widgets.dart';

/// Controller that tracks whether the current UI subtree is considered
/// screenshot-sensitive.
class ScreenshotSensitivityController extends ChangeNotifier {
  int _depth = 0;
  int _entryRevision = 0;
  bool _disposed = false;
  final ChangeNotifier _captureChanges = ChangeNotifier();

  bool get isSensitive => _depth > 0;
  bool get isDisposed => _disposed;

  /// Synchronous paint-only notifications. Unlike widget rebuild notifications,
  /// these must take effect before a newly sensitive subtree can be captured.
  Listenable get captureChanges => _captureChanges;

  void enter() {
    if (_disposed) return;
    _depth += 1;
    _entryRevision += 1;
    _captureChanges.notifyListeners();
    _safeNotifyListeners();
  }

  void exit() {
    if (_disposed) return;
    if (_depth > 0) {
      _depth -= 1;
      _safeNotifyListeners();
    }
  }

  /// Safely notify listeners, avoiding calls during widget tree locked phases
  /// and calling build during a build or dismount.
  void _safeNotifyListeners() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed && hasListeners) {
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _captureChanges.notifyListeners();
    _captureChanges.dispose();
    super.dispose();
  }
}

/// A capture stays unsafe after any sensitive entry, even after navigation or
/// logout clears the screen. A missing/replaced/disposed controller fails closed.
final class ScreenshotCapturePolicy {
  ScreenshotCapturePolicy.capture(ScreenshotSensitivityController? controller)
    : _controller = controller,
      _entryRevision = controller?._entryRevision,
      _initiallySafe =
          controller != null &&
          !controller._disposed &&
          !controller.isSensitive;

  final ScreenshotSensitivityController? _controller;
  final int? _entryRevision;
  final bool _initiallySafe;

  bool canIncludeScreenshot(ScreenshotSensitivityController? current) =>
      _initiallySafe &&
      current != null &&
      identical(current, _controller) &&
      !current._disposed &&
      !current.isSensitive &&
      current._entryRevision == _entryRevision;
}

/// Inherited notifier providing access to the ScreenshotSensitivityController.
class ScreenshotSensitivity
    extends InheritedNotifier<ScreenshotSensitivityController> {
  const ScreenshotSensitivity({
    super.key,
    required ScreenshotSensitivityController controller,
    required super.child,
  }) : super(notifier: controller);

  static ScreenshotSensitivityController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<ScreenshotSensitivity>()
        ?.notifier;
  }

  static ScreenshotSensitivityController of(BuildContext context) {
    final controller = maybeOf(context);
    assert(
      controller != null,
      'ScreenshotSensitivity not found in widget tree',
    );
    return controller!;
  }
}

/// Widget that marks its subtree as screenshot-sensitive while mounted.
class ScreenshotSensitive extends StatefulWidget {
  const ScreenshotSensitive({super.key, required this.child});

  final Widget child;

  @override
  State<ScreenshotSensitive> createState() => _ScreenshotSensitiveState();
}

class _ScreenshotSensitiveState extends State<ScreenshotSensitive> {
  ScreenshotSensitivityController? _controller;
  bool _hasCalledEnter = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = ScreenshotSensitivity.maybeOf(context);
    if (!identical(controller, _controller)) {
      // Exit the old controller if we were using it
      if (_hasCalledEnter) {
        _controller?.exit();
      }
      _controller = controller;
      _hasCalledEnter = false;
      // Enter the new controller - this is safe now due to deferred notification
      _controller?.enter();
      _hasCalledEnter = true;
    }
  }

  @override
  void dispose() {
    // Exit the controller - this is safe now due to deferred notification
    if (_hasCalledEnter) {
      _controller?.exit();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

extension ScreenshotSensitivityContextExt on BuildContext {
  bool get isScreenshotSensitive =>
      ScreenshotSensitivity.maybeOf(this)?.isSensitive ?? false;
}
