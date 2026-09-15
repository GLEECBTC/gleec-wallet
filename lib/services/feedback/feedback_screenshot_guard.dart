import 'package:feedback/feedback.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:web_dex/shared/screenshot/screenshot_sensitivity.dart';

/// BetterFeedback previews and captures its live child. This guard prevents
/// sensitive pixels from reaching either surface while leaving its form usable.
class FeedbackScreenshotGuard extends SingleChildRenderObjectWidget {
  const FeedbackScreenshotGuard({
    super.key,
    required this.feedbackController,
    required this.sensitivityController,
    required super.child,
  });

  final FeedbackController feedbackController;
  final ScreenshotSensitivityController? sensitivityController;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderFeedbackScreenshotGuard(feedbackController, sensitivityController);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderFeedbackScreenshotGuard renderObject,
  ) {
    renderObject
      ..feedbackController = feedbackController
      ..sensitivityController = sensitivityController;
  }
}

class RenderFeedbackScreenshotGuard extends RenderProxyBox {
  RenderFeedbackScreenshotGuard(this._feedback, this._sensitivity) {
    _updateCapture();
  }

  FeedbackController _feedback;
  ScreenshotSensitivityController? _sensitivity;
  ScreenshotCapturePolicy? _policy;
  bool _wasVisible = false;

  set feedbackController(FeedbackController value) {
    if (identical(_feedback, value)) return;
    if (attached) _feedback.removeListener(_updateCapture);
    _feedback = value;
    // Replacing the controller during capture cannot make an unsafe image safe.
    if (_wasVisible) _policy = ScreenshotCapturePolicy.capture(null);
    if (attached) _feedback.addListener(_updateCapture);
    _updateCapture();
  }

  set sensitivityController(ScreenshotSensitivityController? value) {
    if (identical(_sensitivity, value)) return;
    if (_wasVisible) _policy = ScreenshotCapturePolicy.capture(null);
    if (attached) {
      _sensitivity?.captureChanges.removeListener(_markPrivacyChanged);
    }
    _sensitivity = value;
    if (attached) _listenForSensitivityChanges();
    _markPrivacyChanged();
  }

  bool get _blocked =>
      _feedback.isVisible &&
      !(_policy?.canIncludeScreenshot(_sensitivity) ?? false);

  void _updateCapture() {
    if (_feedback.isVisible && !_wasVisible) {
      _policy = ScreenshotCapturePolicy.capture(_sensitivity);
    }
    _wasVisible = _feedback.isVisible;
    _markPrivacyChanged();
  }

  void _markPrivacyChanged() {
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  void _listenForSensitivityChanges() {
    final sensitivity = _sensitivity;
    if (sensitivity != null && !sensitivity.isDisposed) {
      sensitivity.captureChanges.addListener(_markPrivacyChanged);
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _feedback.addListener(_updateCapture);
    _listenForSensitivityChanges();
    _updateCapture();
  }

  @override
  void detach() {
    _feedback.removeListener(_updateCapture);
    _sensitivity?.captureChanges.removeListener(_markPrivacyChanged);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_blocked) {
      context.canvas.drawRect(
        offset & size,
        Paint()..color = const Color(0xff202020),
      );
      return;
    }
    super.paint(context, offset);
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      !_blocked && super.hitTest(result, position: position);

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    if (!_blocked) super.visitChildrenForSemantics(visitor);
  }
}
