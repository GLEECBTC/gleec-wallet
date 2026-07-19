import 'package:app_theme/app_theme.dart';
import 'package:flutter/material.dart';

class TextDropdownButton<T> extends StatefulWidget {
  final List<T> items;
  final String Function(T) itemAsString;
  final String hint;
  final T? initialValue;
  final void Function(T)? onChanged;

  const TextDropdownButton({
    Key? key,
    required this.items,
    required this.itemAsString,
    this.hint = 'Select an item',
    this.initialValue,
    this.onChanged,
  }) : super(key: key);

  @override
  State<TextDropdownButton<T>> createState() => _TextDropdownButtonState<T>();
}

class _TextDropdownButtonState<T> extends State<TextDropdownButton<T>> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  T? _selectedItem;
  bool _isOpen = false;

  @override
  void initState() {
    super.initState();
    _selectedItem = widget.initialValue;
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: GestureDetector(
        onTap: _toggleDropdown,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).calmCoreCompatibility.dexPageTheme.frontPlateInner,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  _selectedItem != null
                      ? widget.itemAsString(_selectedItem as T)
                      : widget.hint,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                Icons.arrow_drop_down,
                color: Theme.of(context).textTheme.labelLarge?.color,
              ),
            ],
          ),
        ),
      ),
    );
  }

  OverlayEntry _createOverlayEntry() {
    RenderBox renderBox = context.findRenderObject() as RenderBox;
    var size = renderBox.size;

    return OverlayEntry(
      builder: (context) => Positioned(
        width: size.width,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: Offset(0, size.height + 5),
          child: Material(
            elevation: 4,
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: widget.items
                  .map(
                    (item) => ListTile(
                      title: Text(widget.itemAsString(item)),
                      onTap: () {
                        setState(() {
                          _selectedItem = item;
                          _isOpen = false;
                        });
                        widget.onChanged?.call(_selectedItem as T);
                        _overlayEntry?.remove();
                        _overlayEntry = null;
                      },
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }

  void _toggleDropdown() {
    if (_isOpen) {
      _overlayEntry?.remove();
      _overlayEntry = null;
    } else {
      _overlayEntry = _createOverlayEntry();
      Overlay.of(context).insert(_overlayEntry!);
    }
    setState(() {
      _isOpen = !_isOpen;
    });
  }

  @override
  void dispose() {
    _overlayEntry?.remove();
    super.dispose();
  }
}
