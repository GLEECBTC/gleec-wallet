import 'package:flutter/material.dart';

class DexScrollbar extends StatefulWidget {
  final Widget child;
  final bool isMobile;
  final ScrollController scrollController;

  const DexScrollbar({
    super.key,
    required this.child,
    required this.scrollController,
    this.isMobile = false,
  });

  @override
  DexScrollbarState createState() => DexScrollbarState();
}

class DexScrollbarState extends State<DexScrollbar> {
  bool isScrollbarVisible = false;

  @override
  void initState() {
    super.initState();
    _attachControllerListener(widget.scrollController);
    _scheduleVisibilityCheck();
  }

  @override
  void didUpdateWidget(covariant DexScrollbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController == widget.scrollController) {
      return;
    }

    _detachControllerListener(oldWidget.scrollController);
    _attachControllerListener(widget.scrollController);
    _scheduleVisibilityCheck();
  }

  void _checkScrollbarVisibility() {
    if (!mounted || !widget.scrollController.hasClients) return;

    final maxScroll = widget.scrollController.position.maxScrollExtent;
    _updateScrollbarVisibility(maxScroll > 0);
  }

  void _updateScrollbarVisibility(bool visible) {
    if (isScrollbarVisible == visible) {
      return;
    }

    setState(() {
      isScrollbarVisible = visible;
    });
  }

  bool _onScrollMetricsChanged(ScrollMetricsNotification notification) {
    _updateScrollbarVisibility(notification.metrics.maxScrollExtent > 0);
    return false;
  }

  void _attachControllerListener(ScrollController controller) {
    controller.addListener(_checkScrollbarVisibility);
  }

  void _detachControllerListener(ScrollController controller) {
    controller.removeListener(_checkScrollbarVisibility);
  }

  void _scheduleVisibilityCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkScrollbarVisibility();
    });
  }

  @override
  void dispose() {
    _detachControllerListener(widget.scrollController);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isMobile) return widget.child;

    final double rightPadding = isScrollbarVisible ? 10 : 0;

    return Scrollbar(
      thumbVisibility: isScrollbarVisible,
      trackVisibility: isScrollbarVisible,
      thickness: 5,
      controller: widget.scrollController,
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: _onScrollMetricsChanged,
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: Padding(
            padding: EdgeInsets.only(right: rightPadding),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
