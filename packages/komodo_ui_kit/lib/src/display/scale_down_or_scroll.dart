import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'auto_scroll_text.dart';
import 'edge_fade.dart';

/// Shrinks [child] to fit its width, but no further than [minScale]; a child
/// still too wide is drawn at [minScale], clipped, and scrolled to show its
/// end, at [AutoScrollText]'s pace. Each edge with content hidden past it
/// fades out, as [TextOverflow.fade] does.
///
/// [AutoScrollText] does this for a string; this does it for any widget that
/// sizes itself to its content, such as a row of an icon and text. Taps reach
/// the child where it is drawn.
class ScaleDownOrScroll extends StatefulWidget {
  const ScaleDownOrScroll({
    required this.child,
    this.minScale = 0.8,
    this.alignment = AlignmentDirectional.centerStart,
    super.key,
  }) : assert(minScale > 0 && minScale <= 1);

  final Widget child;

  /// The smallest the child is drawn, as a share of its full size.
  final double minScale;

  /// Where the child sits when it is narrower than the room it is given.
  final AlignmentGeometry alignment;

  @override
  State<ScaleDownOrScroll> createState() => _ScaleDownOrScrollState();
}

class _ScaleDownOrScrollState extends State<ScaleDownOrScroll>
    with SingleTickerProviderStateMixin {
  // The same pacing as AutoScrollText, so the two move together in a row.
  static const _initialPause = Duration(seconds: 2);
  static const _pauseBeforeReverse = Duration(seconds: 3);
  static const _pauseBeforeRepeat = Duration(seconds: 10);
  static const _moving = Duration(seconds: 4);

  late final AnimationController _scroll = AnimationController(vsync: this);

  bool _overflows = false;

  /// Bumped to stop a running scroll loop.
  int _run = 0;

  Timer? _pauseTimer;
  Completer<bool>? _pauseCompleter;

  void _onOverflowChanged(bool overflows) {
    if (!mounted || overflows == _overflows) return;
    _overflows = overflows;
    _stop();
    if (overflows) unawaited(_loop(_run));
  }

  void _stop() {
    _run++;
    _cancelPause();
    _scroll.stop();
    // Setting the value repaints even when it is unchanged.
    if (_scroll.value != 0) _scroll.value = 0;
  }

  Future<void> _loop(int run) async {
    bool live() => mounted && run == _run;
    if (!await _pauseFor(_initialPause) || !live()) return;
    while (live()) {
      try {
        await _scroll.animateTo(1, duration: _moving).orCancel;
        if (!await _pauseFor(_pauseBeforeReverse) || !live()) return;
        await _scroll.animateBack(0, duration: _moving).orCancel;
        if (!await _pauseFor(_pauseBeforeRepeat)) return;
      } on TickerCanceled {
        return;
      }
    }
  }

  /// Waits [duration] and answers whether to carry on: false once the wait
  /// is cancelled, so a disposed widget leaves no timer running.
  Future<bool> _pauseFor(Duration duration) {
    _cancelPause();
    final completer = _pauseCompleter = Completer<bool>();
    _pauseTimer = Timer(duration, () {
      _pauseTimer = null;
      _pauseCompleter = null;
      completer.complete(mounted);
    });
    return completer.future;
  }

  void _cancelPause() {
    _pauseTimer?.cancel();
    _pauseTimer = null;
    _pauseCompleter?.complete(false);
    _pauseCompleter = null;
  }

  @override
  void dispose() {
    _run++;
    _cancelPause();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ScaleDownOrScrollBox(
      minScale: widget.minScale,
      alignment: widget.alignment.resolve(Directionality.of(context)),
      scroll: _scroll,
      onOverflowChanged: _onOverflowChanged,
      child: widget.child,
    );
  }
}

class _ScaleDownOrScrollBox extends SingleChildRenderObjectWidget {
  const _ScaleDownOrScrollBox({
    required this.minScale,
    required this.alignment,
    required this.scroll,
    required this.onOverflowChanged,
    required super.child,
  });

  final double minScale;
  final Alignment alignment;
  final Animation<double> scroll;
  final ValueChanged<bool> onOverflowChanged;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderScaleDownOrScroll(
        minScale: minScale,
        alignment: alignment,
        scroll: scroll,
        onOverflowChanged: onOverflowChanged,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderScaleDownOrScroll renderObject,
  ) {
    renderObject
      ..minScale = minScale
      ..alignment = alignment
      ..scroll = scroll
      ..onOverflowChanged = onOverflowChanged;
  }
}

class _RenderScaleDownOrScroll extends RenderProxyBox {
  _RenderScaleDownOrScroll({
    required double minScale,
    required Alignment alignment,
    required Animation<double> scroll,
    required this.onOverflowChanged,
  }) : _minScale = minScale,
       _alignment = alignment,
       _scroll = scroll;

  ValueChanged<bool> onOverflowChanged;

  double get minScale => _minScale;
  double _minScale;
  set minScale(double value) {
    if (value == _minScale) return;
    _minScale = value;
    markNeedsLayout();
  }

  Alignment get alignment => _alignment;
  Alignment _alignment;
  set alignment(Alignment value) {
    if (value == _alignment) return;
    _alignment = value;
    markNeedsPaint();
  }

  Animation<double> get scroll => _scroll;
  Animation<double> _scroll;
  set scroll(Animation<double> value) {
    if (value == _scroll) return;
    if (attached) _scroll.removeListener(_onScroll);
    _scroll = value;
    if (attached) _scroll.addListener(_onScroll);
  }

  double _scale = 1;

  /// How far the scaled child is wider than this box; 0 when it fits.
  double _overflow = 0;
  bool? _reportedOverflow;

  final _clipLayer = LayerHandle<ClipRectLayer>();
  final _fadeLayer = LayerHandle<ShaderMaskLayer>();
  final _transformLayer = LayerHandle<TransformLayer>();

  /// The fade needs a layer of its own, so only while the child overflows.
  @override
  bool get alwaysNeedsCompositing => _overflow > 0;

  void _onScroll() {
    if (_overflow > 0) markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _scroll.addListener(_onScroll);
  }

  @override
  void detach() {
    _scroll.removeListener(_onScroll);
    super.detach();
  }

  @override
  void dispose() {
    _clipLayer.layer = null;
    _fadeLayer.layer = null;
    _transformLayer.layer = null;
    super.dispose();
  }

  /// The child's full size: as wide as it likes, as tall as this box allows.
  static BoxConstraints _childConstraints(BoxConstraints constraints) =>
      BoxConstraints(maxHeight: constraints.maxHeight);

  /// The scale to draw a child [childWidth] wide at in [maxWidth].
  double _scaleFor(double childWidth, double maxWidth) {
    if (childWidth <= maxWidth || childWidth == 0) return 1;
    // An overflow too small for a scroll to be worth it shrinks a little
    // further instead, as AutoScrollText would leave it clipped.
    final overflowAtMin = childWidth * minScale - maxWidth;
    if (overflowAtMin <= AutoScrollText.animationThresholdWidth) {
      return maxWidth / childWidth;
    }
    return minScale;
  }

  Size _sizeFor(BoxConstraints constraints, Size childSize) {
    final scale = _scaleFor(childSize.width, constraints.maxWidth);
    return constraints.constrain(
      Size(
        math.min(childSize.width * scale, constraints.maxWidth),
        childSize.height * scale,
      ),
    );
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final child = this.child;
    if (child == null) return constraints.smallest;
    return _sizeFor(
      constraints,
      child.getDryLayout(_childConstraints(constraints)),
    );
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      _overflow = 0;
      return;
    }
    child.layout(_childConstraints(constraints), parentUsesSize: true);
    _scale = _scaleFor(child.size.width, constraints.maxWidth);
    size = _sizeFor(constraints, child.size);
    _overflow = math.max(0, child.size.width * _scale - size.width);

    final overflows = _overflow > 0;
    if (overflows != _reportedOverflow) {
      _reportedOverflow = overflows;
      markNeedsCompositingBitsUpdate();
      // Not during layout: starting the scroll schedules frames.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (attached) onOverflowChanged(overflows);
      });
    }
  }

  Matrix4 get _childTransform {
    final drawn = child!.size * _scale;
    final free = Size(size.width - drawn.width, size.height - drawn.height);
    // A scrolling child starts at its leading edge, as AutoScrollText does.
    final aligned = _overflow > 0
        ? Offset(0, alignment.alongSize(free).dy)
        : alignment.alongSize(free);
    return Matrix4.translationValues(
      aligned.dx - _overflow * _scroll.value,
      aligned.dy,
      0,
    )..scaleByDouble(_scale, _scale, 1, 1);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    void paintScaled(PaintingContext context, Offset offset) {
      _transformLayer.layer = context.pushTransform(
        needsCompositing,
        offset,
        _childTransform,
        (context, offset) => context.paintChild(child, offset),
        oldLayer: _transformLayer.layer,
      );
    }

    if (_overflow > 0) {
      final fade = _fadeLayer.layer ??= ShaderMaskLayer();
      fade
        ..shader = edgeFadeShader(
          Offset.zero & size,
          hiddenBefore: _overflow * _scroll.value,
          hiddenAfter: _overflow * (1 - _scroll.value),
          // About the width of an ellipsis, as TextOverflow.fade uses.
          fadeWidth: size.height * 0.75,
        )
        ..maskRect = offset & size
        ..blendMode = BlendMode.dstIn;
      _clipLayer.layer = context.pushClipRect(
        needsCompositing,
        offset,
        Offset.zero & size,
        (context, offset) => context.pushLayer(fade, paintScaled, offset),
        oldLayer: _clipLayer.layer,
      );
    } else {
      _clipLayer.layer = null;
      _fadeLayer.layer = null;
      paintScaled(context, offset);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) return false;
    return result.addWithPaintTransform(
      transform: _childTransform,
      position: position,
      hitTest: (result, position) => child.hitTest(result, position: position),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.multiply(_childTransform);
  }
}
