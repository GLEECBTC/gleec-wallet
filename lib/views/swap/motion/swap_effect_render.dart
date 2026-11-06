part of 'swap_effects.dart';

/// Where an effect starts; it always ends on the child as laid out.
@immutable
class _EffectStart {
  const _EffectStart({
    this.opacity = 1,
    this.offset = Offset.zero,
    this.scale = 1,
    this.turns = 0,
  });

  final double opacity;
  final Offset offset;
  final double scale;
  final double turns;

  @override
  bool operator ==(Object other) =>
      other is _EffectStart &&
      other.opacity == opacity &&
      other.offset == offset &&
      other.scale == scale &&
      other.turns == turns;

  @override
  int get hashCode => Object.hash(opacity, offset, scale, turns);
}

/// Paints [child] part of the way from [start] to itself, as [progress] goes
/// from 0 to 1.
///
/// Only painting changes. Layout, hit testing and semantics stay the child's,
/// so finders, taps and screen readers see where it will settle from the first
/// frame, and a faded child keeps its semantics.
class _SwapEffect extends SingleChildRenderObjectWidget {
  const _SwapEffect({
    required this.progress,
    required this.start,
    required this.alignment,
    super.child,
  });

  final Animation<double> progress;
  final _EffectStart start;
  final AlignmentGeometry alignment;

  @override
  _RenderSwapEffect createRenderObject(BuildContext context) =>
      _RenderSwapEffect(
        progress: progress,
        start: start,
        alignment: alignment,
        textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSwapEffect renderObject,
  ) {
    renderObject
      ..progress = progress
      ..start = start
      ..alignment = alignment
      ..textDirection = Directionality.maybeOf(context) ?? TextDirection.ltr;
  }
}

class _RenderSwapEffect extends RenderProxyBox {
  _RenderSwapEffect({
    required Animation<double> progress,
    required _EffectStart start,
    required AlignmentGeometry alignment,
    required TextDirection textDirection,
  }) : _progress = progress,
       _start = start,
       _alignment = alignment,
       _textDirection = textDirection;

  final _opacityLayer = LayerHandle<OpacityLayer>();
  final _transformLayer = LayerHandle<TransformLayer>();
  bool _wasActive = false;

  Animation<double> _progress;
  set progress(Animation<double> value) {
    if (identical(value, _progress)) return;
    if (attached) _progress.removeListener(_changed);
    _progress = value;
    if (attached) _progress.addListener(_changed);
    _changed();
  }

  _EffectStart _start;
  set start(_EffectStart value) {
    if (value == _start) return;
    _start = value;
    markNeedsPaint();
  }

  AlignmentGeometry _alignment;
  set alignment(AlignmentGeometry value) {
    if (value == _alignment) return;
    _alignment = value;
    markNeedsPaint();
  }

  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsPaint();
  }

  bool get _active => _progress.value != 1;

  void _changed() {
    if (_active != _wasActive) {
      _wasActive = _active;
      markNeedsCompositingBitsUpdate();
    }
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _progress.addListener(_changed);
    _wasActive = _active;
  }

  @override
  void detach() {
    _progress.removeListener(_changed);
    super.detach();
  }

  // An opacity layer needs compositing, but only while the effect runs.
  @override
  bool get alwaysNeedsCompositing => child != null && _active;

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    if (!_active) {
      _opacityLayer.layer = null;
      _transformLayer.layer = null;
      context.paintChild(child, offset);
      return;
    }
    final t = _progress.value;
    final opacity = (_start.opacity + (1 - _start.opacity) * t).clamp(0.0, 1.0);
    final alpha = Color.getAlphaFromOpacity(opacity);
    if (alpha == 0) {
      _opacityLayer.layer = null;
      _transformLayer.layer = null;
      return;
    }
    final direction = _textDirection == TextDirection.rtl ? -1.0 : 1.0;
    final shift = Offset(
      _start.offset.dx * direction * (1 - t),
      _start.offset.dy * (1 - t),
    );
    final scale = _start.scale + (1 - _start.scale) * t;
    final origin = _alignment.resolve(_textDirection).alongSize(size);
    final transform =
        Matrix4.translationValues(shift.dx + origin.dx, shift.dy + origin.dy, 0)
          ..multiply(Matrix4.rotationZ(_start.turns * (1 - t) * 2 * math.pi))
          ..multiply(Matrix4.diagonal3Values(scale, scale, 1))
          ..multiply(Matrix4.translationValues(-origin.dx, -origin.dy, 0));
    _transformLayer.layer = context.pushTransform(
      needsCompositing,
      offset,
      transform,
      (context, offset) {
        _opacityLayer.layer = context.pushOpacity(
          offset,
          alpha,
          super.paint,
          oldLayer: _opacityLayer.layer,
        );
      },
      oldLayer: _transformLayer.layer,
    );
  }

  @override
  void dispose() {
    _opacityLayer.layer = null;
    _transformLayer.layer = null;
    super.dispose();
  }
}
