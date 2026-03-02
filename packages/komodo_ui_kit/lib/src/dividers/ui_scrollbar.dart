import 'package:flutter/material.dart';

class DexScrollbar extends StatefulWidget {
  final Widget child;
  final bool isMobile;
  final ScrollController scrollController;

  const DexScrollbar({
    Key? key,
    required this.child,
    required this.scrollController,
    this.isMobile = false,
  }) : super(key: key);

  @override
  DexScrollbarState createState() => DexScrollbarState();
}

class DexScrollbarState extends State<DexScrollbar> {
  bool isScrollbarVisible = false;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_checkScrollbarVisibility);
  }

  void _checkScrollbarVisibility() {
    if (!mounted || !widget.scrollController.hasClients) return;

    final maxScroll = widget.scrollController.position.maxScrollExtent;
    final newVisibility = maxScroll > 0;

    if (isScrollbarVisible != newVisibility) {
      setState(() {
        isScrollbarVisible = newVisibility;
      });
    }
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_checkScrollbarVisibility);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isMobile) return widget.child;

    return LayoutBuilder(
      builder: (context, constraints) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _checkScrollbarVisibility();
        });

        return isScrollbarVisible
            ? Scrollbar(
                thumbVisibility: true,
                trackVisibility: true,
                thickness: 5,
                controller: widget.scrollController,
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(
                    context,
                  ).copyWith(scrollbars: false),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: widget.child,
                  ),
                ),
              )
            : widget.child;
      },
    );
  }
}
