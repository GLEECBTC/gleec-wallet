import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';

void main() {
  testWidgets('keeps text field focus when scrollability changes', (
    tester,
  ) async {
    final focusNode = FocusNode();
    final hostKey = GlobalKey<_DexScrollbarFocusHostState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _DexScrollbarFocusHost(
            key: hostKey,
            searchFocusNode: focusNode,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('search-field')));
    await tester.pumpAndSettle();
    expect(focusNode.hasFocus, isTrue);

    hostKey.currentState!.setScrollable(false);
    await tester.pump();
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);

    hostKey.currentState!.setScrollable(true);
    await tester.pump();
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);

    focusNode.dispose();
  });
}

class _DexScrollbarFocusHost extends StatefulWidget {
  const _DexScrollbarFocusHost({required this.searchFocusNode, super.key});

  final FocusNode searchFocusNode;

  @override
  State<_DexScrollbarFocusHost> createState() => _DexScrollbarFocusHostState();
}

class _DexScrollbarFocusHostState extends State<_DexScrollbarFocusHost> {
  static const int _scrollableItemCount = 50;
  static const int _notScrollableItemCount = 1;

  final ScrollController _scrollController = ScrollController();
  bool _isScrollable = true;

  void setScrollable(bool value) {
    if (_isScrollable == value) {
      return;
    }
    setState(() {
      _isScrollable = value;
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 420,
        height: 260,
        child: DexScrollbar(
          isMobile: false,
          scrollController: _scrollController,
          child: Column(
            children: [
              const SizedBox(height: 8),
              TextFormField(
                key: const Key('search-field'),
                focusNode: widget.searchFocusNode,
                decoration: const InputDecoration(hintText: 'Search'),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  itemCount: _isScrollable
                      ? _scrollableItemCount
                      : _notScrollableItemCount,
                  itemExtent: 36,
                  itemBuilder: (context, index) {
                    return Text('Item $index');
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
