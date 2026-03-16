import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class UiDropdown extends StatefulWidget {
  const UiDropdown({
    Key? key,
    required this.dropdown,
    required this.switcher,
    this.borderRadius,
    this.onSwitch,
    this.switcherKey,
    this.isOpen = false,
  }) : super(key: key);
  final Widget dropdown;
  final Widget switcher;
  final GlobalKey? switcherKey;
  final BorderRadius? borderRadius;
  final Function(bool)? onSwitch;
  final bool isOpen;

  @override
  State<UiDropdown> createState() => _UiDropdownState();
}

class _UiDropdownState extends State<UiDropdown> with WidgetsBindingObserver {
  OverlayEntry? _tooltipWrapper;
  GlobalKey _switcherKey = GlobalKey();
  Size? _switcherSize;
  Offset? _switcherOffset;

  @override
  void initState() {
    final switcherKey = widget.switcherKey;
    if (switcherKey != null) {
      _switcherKey = switcherKey;
    }
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final RenderBox? renderObject =
          _switcherKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderObject != null) {
        _switcherSize = renderObject.size;
        _switcherOffset = renderObject.localToGlobal(Offset.zero);
      }
      _tooltipWrapper = _buildTooltipWrapper();

      if (widget.isOpen) _open();
    });

    super.initState();
  }

  @override
  void didUpdateWidget(covariant UiDropdown oldWidget) {
    if (widget.isOpen == oldWidget.isOpen) return;

    if (widget.isOpen != (_tooltipWrapper?.mounted ?? false)) _switch();
    super.didUpdateWidget(oldWidget);
  }

  @override
  void didChangeMetrics() {
    final RenderBox? renderObject =
        _switcherKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderObject != null) {
      setState(() {
        _switcherSize = renderObject.size;
        _switcherOffset = renderObject.localToGlobal(Offset.zero);
      });
    }
    if (_tooltipWrapper?.mounted == true) {
      _close();
    }
    _tooltipWrapper = _buildTooltipWrapper();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_tooltipWrapper?.mounted == true) {
      _tooltipWrapper!.remove();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: widget.borderRadius,
        key: _switcherKey,
        onTap: _switch,
        child: widget.switcher,
      ),
    );
  }

  OverlayEntry _buildTooltipWrapper() {
    return OverlayEntry(
      builder: (context) => Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            bottom: 0,
            child: Material(
              color: Colors.transparent,
              child: Listener(
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent) {
                    _close();
                  }
                },
                child: InkWell(
                  splashColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  hoverColor: Colors.transparent,
                  onTap: () => _switch(),
                ),
              ),
            ),
          ),
          Positioned(
            top: (_top ?? 0) + 10,
            right: _right,
            child: Material(color: Colors.transparent, child: widget.dropdown),
          ),
        ],
      ),
    );
  }

  void _switch() {
    if (_tooltipWrapper?.mounted == true) {
      _close();
    } else {
      _open();
    }
  }

  void _open() {
    if (_tooltipWrapper != null) {
      Overlay.of(context).insert(_tooltipWrapper!);
      final onSwitch = widget.onSwitch;
      if (onSwitch != null) onSwitch(true);
    }
  }

  void _close() {
    if (_tooltipWrapper != null) {
      _tooltipWrapper!.remove();
      final onSwitch = widget.onSwitch;
      if (onSwitch != null) onSwitch(false);
    }
  }

  double? get _top {
    final Offset? switcherOffset = _switcherOffset;
    final Size? switcherSize = _switcherSize;
    if (switcherOffset == null || switcherSize == null) {
      return null;
    }

    return switcherOffset.dy + switcherSize.height;
  }

  double? get _right {
    final Offset? switcherOffset = _switcherOffset;
    final Size? switcherSize = _switcherSize;

    if (switcherOffset == null || switcherSize == null) {
      return null;
    }
    final double windowWidth = MediaQuery.of(context).size.width;

    return windowWidth - (switcherOffset.dx + switcherSize.width);
  }
}
