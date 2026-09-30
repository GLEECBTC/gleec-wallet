import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:web_dex/views/swap/motion/swap_motion_tokens.dart';

/// Grows or shrinks to [child]'s size instead of jumping, so what sits below
/// glides rather than snaps.
///
/// It takes its first size at once, never clips, and a hit anywhere on the
/// child reaches it even while the reported size is still catching up. With
/// [animate] false, or when the user asked for less motion, it follows the
/// child exactly.
class SwapSmoothSize extends StatefulWidget {
  const SwapSmoothSize({
    required this.child,
    this.animate = true,
    this.duration = SwapMotion.grow,
    this.curve = SwapMotion.standard,
    this.alignment = AlignmentDirectional.topStart,
    super.key,
  });

  final Widget child;
  final bool animate;
  final Duration duration;
  final Curve curve;
  final AlignmentGeometry alignment;

  @override
  State<SwapSmoothSize> createState() => _SwapSmoothSizeState();
}

class _SwapSmoothSizeState extends State<SwapSmoothSize>
    with SingleTickerProviderStateMixin {
  @override
  Widget build(BuildContext context) => _SmoothSize(
    vsync: this,
    duration: widget.animate
        ? SwapMotion.of(context, widget.duration)
        : Duration.zero,
    curve: widget.curve,
    alignment: widget.alignment,
    child: widget.child,
  );
}

class _SmoothSize extends SingleChildRenderObjectWidget {
  const _SmoothSize({
    required this.vsync,
    required this.duration,
    required this.curve,
    required this.alignment,
    super.child,
  });

  final TickerProvider vsync;
  final Duration duration;
  final Curve curve;
  final AlignmentGeometry alignment;

  @override
  _RenderSmoothSize createRenderObject(BuildContext context) =>
      _RenderSmoothSize(
        vsync: vsync,
        duration: duration,
        curve: curve,
        alignment: alignment,
        textDirection: Directionality.maybeOf(context),
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSmoothSize renderObject,
  ) {
    renderObject
      ..vsync = vsync
      ..duration = duration
      ..curve = curve
      ..alignment = alignment
      ..textDirection = Directionality.maybeOf(context);
  }
}

class _RenderSmoothSize extends RenderAligningShiftedBox {
  _RenderSmoothSize({
    required TickerProvider vsync,
    required Duration duration,
    required Curve curve,
    required super.alignment,
    super.textDirection,
  }) : _vsync = vsync,
       _duration = duration {
    _controller = AnimationController(
      vsync: vsync,
      duration: duration == Duration.zero ? SwapMotion.grow : duration,
    )..addListener(_tick);
    _animation = CurvedAnimation(parent: _controller, curve: curve);
  }

  late final AnimationController _controller;
  late final CurvedAnimation _animation;
  final _sizes = SizeTween();

  // What the controller read at the start of the last layout: a change the
  // layout itself makes must not ask for another one.
  double _laidOutAt = 0;

  TickerProvider _vsync;
  set vsync(TickerProvider value) {
    if (identical(value, _vsync)) return;
    _vsync = value;
    _controller.resync(value);
  }

  Duration _duration;
  set duration(Duration value) {
    _duration = value;
    if (value > Duration.zero) _controller.duration = value;
  }

  set curve(Curve value) => _animation.curve = value;

  void _tick() {
    if (_controller.value != _laidOutAt) markNeedsLayout();
  }

  @override
  void performLayout() {
    _laidOutAt = _controller.value;
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(constraints, parentUsesSize: true);
    final target = child.size;
    if (_sizes.end == null || _duration == Duration.zero) {
      _controller.stop();
      _sizes
        ..begin = target
        ..end = target;
    } else if (target != _sizes.end) {
      _sizes
        ..begin = _sizes.evaluate(_animation)
        ..end = target;
      _laidOutAt = 0;
      _controller.forward(from: 0);
    }
    size = constraints.constrain(_sizes.evaluate(_animation)!);
    alignChild();
  }

  // While growing, the child is larger than the size reported to the parent;
  // test the child itself rather than only this box's bounds.
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (hitTestChildren(result, position: position)) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    return false;
  }

  @override
  void detach() {
    _controller.stop();
    _sizes.begin = _sizes.end;
    super.detach();
  }

  @override
  void dispose() {
    _animation.dispose();
    _controller.dispose();
    super.dispose();
  }
}
