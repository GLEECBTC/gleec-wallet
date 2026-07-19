import 'package:app_theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:komodo_ui_kit/src/painter/dash_rect_painter.dart';

class FocusDecorator extends StatefulWidget {
  const FocusDecorator({
    required this.child,
    this.edgeInsets,
    this.skipTraversal = true,
    super.key,
  });

  final Widget child;
  final bool skipTraversal;
  final EdgeInsets? edgeInsets;

  @override
  State<FocusDecorator> createState() => _FocusDecoratorState();
}

class _FocusDecoratorState extends State<FocusDecorator> {
  bool _hasFocus = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      skipTraversal: widget.skipTraversal,
      onFocusChange: (value) {
        setState(() {
          _hasFocus = value;
        });
      },
      child: Container(
        padding: widget.edgeInsets,
        child: CustomPaint(
          painter: DashRectPainter(
            color: _hasFocus
                ? Theme.of(context)
                      .calmCoreCompatibility
                      .buttonColorDefaultHover
                      .withValues(alpha: .8)
                : Colors.transparent,
            strokeWidth: 1,
            gap: 2,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
