import 'package:app_theme/app_theme.dart';
import 'package:flutter/material.dart';

class UiSwitcher extends StatefulWidget {
  const UiSwitcher({
    required this.value,
    required this.onChanged,
    this.width = 46,
    this.height = 24,
    super.key,
  });
  final bool value;
  final double width;
  final double height;
  final void Function(bool) onChanged;

  @override
  State<UiSwitcher> createState() => _UiSwitcherState();
}

class _UiSwitcherState extends State<UiSwitcher>
    with SingleTickerProviderStateMixin {
  late final Animation<Alignment> _toggleAnimation;
  late final AnimationController _animationController;

  @override
  void initState() {
    _animationController = AnimationController(
      vsync: this,
      value: widget.value ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
    );
    _toggleAnimation =
        AlignmentTween(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ).animate(
          CurvedAnimation(parent: _animationController, curve: Curves.linear),
        );
    super.initState();
  }

  @override
  void didUpdateWidget(UiSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.value == widget.value) return;

    if (widget.value) {
      _animationController.forward();
    } else {
      _animationController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return InkWell(
          hoverColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          onTap: () => widget.onChanged(!widget.value),
          child: Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.all(Radius.circular(18)),
              gradient: Theme.of(
                context,
              ).calmCoreCompatibility.defaultSwitchColor,
            ),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.all(Radius.circular(16)),
                  color: widget.value
                      ? null
                      : Theme.of(context).colorScheme.surface,
                ),
                child: Container(
                  alignment: _toggleAnimation.value,
                  padding: const EdgeInsets.all(1),
                  child: Container(
                    width: widget.height - 4,
                    height: widget.height - 4,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.value ? Colors.white : null,
                      gradient: widget.value
                          ? null
                          : Theme.of(
                              context,
                            ).calmCoreCompatibility.defaultSwitchColor,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
