import 'package:app_theme/app_theme.dart';
import 'package:flutter/material.dart';

class ActionButton extends StatefulWidget {
  const ActionButton({required this.child, required this.onTap, super.key});

  final void Function(Offset, Size) onTap;
  final Widget child;

  @override
  State<ActionButton> createState() => _ActionButton();
}

class _ActionButton extends State<ActionButton> {
  final _keyInkWell = GlobalKey();
  bool _hasFocus = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          key: _keyInkWell,
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          onFocusChange: (value) {
            setState(() {
              _hasFocus = value;
            });
          },
          onTap: _onTap,
          child: Padding(
            padding: EdgeInsets.zero,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                border: Border.all(
                  color: _hasFocus
                      ? Theme.of(
                          context,
                        ).calmCoreCompatibility.headerFloatBoxColor
                      : Colors.transparent,
                ),
                borderRadius: BorderRadius.circular(10),
                color: Theme.of(context).colorScheme.tertiary,
              ),
              child: widget.child,
            ),
          ),
        ),
      ],
    );
  }

  void _onTap() {
    final renderBoxInkwell =
        _keyInkWell.currentContext!.findRenderObject() as RenderBox?;
    final position = renderBoxInkwell!.localToGlobal(Offset.zero);
    final size = renderBoxInkwell.size;
    widget.onTap(position, size);
  }
}
