part of 'swap_timeline_view.dart';

/// The line joining one step to the next: [color], with [fillColor] drawn
/// down from the top as far as [fill] has run.
class SwapStepLine extends StatelessWidget {
  const SwapStepLine({
    required this.fill,
    required this.color,
    required this.fillColor,
    super.key,
  });

  final Animation<double> fill;
  final Color color;
  final Color fillColor;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 2,
    child: CustomPaint(
      painter: _LinePainter(fill: fill, color: color, fillColor: fillColor),
    ),
  );
}

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.fill,
    required this.color,
    required this.fillColor,
  }) : super(repaint: fill);

  final Animation<double> fill;
  final Color color;
  final Color fillColor;

  @override
  void paint(Canvas canvas, Size size) {
    final filled = size.height * fill.value.clamp(0.0, 1.0);
    canvas
      ..drawRect(
        Rect.fromLTRB(0, filled, size.width, size.height),
        Paint()..color = color,
      )
      ..drawRect(
        Rect.fromLTWH(0, 0, size.width, filled),
        Paint()..color = fillColor,
      );
  }

  @override
  bool shouldRepaint(_LinePainter oldDelegate) =>
      oldDelegate.fill != fill ||
      oldDelegate.color != color ||
      oldDelegate.fillColor != fillColor;
}
