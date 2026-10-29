import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Stacks the pay and receive cards with the switch button straddling the
/// seam between them.
///
/// The switch sits over both cards, so it has to paint after both and be hit
/// tested first. A `Column` cannot express that (the second card paints over
/// the switch), and a `Stack` would need the first card's height up front,
/// which changes with every error line and text-scale setting.
class SwapCardPair extends MultiChildRenderObjectWidget {
  SwapCardPair({
    required Widget top,
    required Widget bottom,
    required Widget switcher,
    this.gap = 32,
    super.key,
  }) : super(children: [top, bottom, switcher]);

  /// Space between the cards. The switcher is centred on it.
  final double gap;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSwapCardPair(gap: gap);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderSwapCardPair).gap = gap;
  }
}

class _SwapCardPairParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderSwapCardPair extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _SwapCardPairParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _SwapCardPairParentData> {
  _RenderSwapCardPair({required double gap}) : _gap = gap;

  double _gap;
  set gap(double value) {
    if (value == _gap) return;
    _gap = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _SwapCardPairParentData) {
      child.parentData = _SwapCardPairParentData();
    }
  }

  List<RenderBox> get _children {
    final result = <RenderBox>[];
    var child = firstChild;
    while (child != null) {
      result.add(child);
      child = childAfter(child);
    }
    return result;
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final children = _children;
    if (children.length != 3) return constraints.smallest;
    final cardConstraints = BoxConstraints(
      minWidth: constraints.maxWidth,
      maxWidth: constraints.maxWidth,
    );
    final top = children[0].getDryLayout(cardConstraints);
    final bottom = children[1].getDryLayout(cardConstraints);
    return constraints.constrain(
      Size(constraints.maxWidth, top.height + _gap + bottom.height),
    );
  }

  @override
  void performLayout() {
    final children = _children;
    assert(children.length == 3, 'SwapCardPair takes exactly three children');
    final width = constraints.maxWidth;
    final cardConstraints = BoxConstraints(minWidth: width, maxWidth: width);

    final top = children[0]..layout(cardConstraints, parentUsesSize: true);
    final bottom = children[1]..layout(cardConstraints, parentUsesSize: true);
    final switcher = children[2]
      ..layout(
        BoxConstraints.loose(Size(width, double.infinity)),
        parentUsesSize: true,
      );

    (top.parentData! as _SwapCardPairParentData).offset = Offset.zero;
    final bottomTop = top.size.height + _gap;
    (bottom.parentData! as _SwapCardPairParentData).offset = Offset(
      0,
      bottomTop,
    );
    final seam = top.size.height + _gap / 2;
    (switcher.parentData! as _SwapCardPairParentData).offset = Offset(
      (width - switcher.size.width) / 2,
      math.max(0, seam - switcher.size.height / 2),
    );

    size = constraints.constrain(Size(width, bottomTop + bottom.size.height));
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    final children = _children;
    if (children.length != 3) return 0;
    return children[0].getMinIntrinsicHeight(width) +
        _gap +
        children[1].getMinIntrinsicHeight(width);
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    final children = _children;
    if (children.length != 3) return 0;
    return children[0].getMaxIntrinsicHeight(width) +
        _gap +
        children[1].getMaxIntrinsicHeight(width);
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    final children = _children;
    if (children.length != 3) return 0;
    return math.max(
      children[0].getMinIntrinsicWidth(double.infinity),
      children[1].getMinIntrinsicWidth(double.infinity),
    );
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    final children = _children;
    if (children.length != 3) return 0;
    return math.max(
      children[0].getMaxIntrinsicWidth(double.infinity),
      children[1].getMaxIntrinsicWidth(double.infinity),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
