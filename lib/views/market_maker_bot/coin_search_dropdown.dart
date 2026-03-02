import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui/komodo_ui.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/widgets/coin_item/coin_item_body.dart';

bool doesCoinMatchSearch(String searchQuery, DropdownMenuItem<String> item) {
  final lowerCaseQuery = searchQuery.toLowerCase();
  if (item.value == null) return false;

  final name = item.value!;
  final nameContains = name.toLowerCase().contains(lowerCaseQuery);
  final idMatches = name.toLowerCase().contains(lowerCaseQuery);

  return nameContains || idMatches;
}

Future<String?> showCoinSearch(
  BuildContext context, {
  required List<String> coins,
  DropdownMenuItem<String> Function(String coinId)? customCoinItemBuilder,
  double maxHeight = 330,
}) async {
  final isMobile = MediaQuery.of(context).size.width < 600;

  final items = coins
      .map(
        (coin) =>
            customCoinItemBuilder?.call(coin) ?? _defaultCoinItemBuilder(coin),
      )
      .toList();

  if (isMobile) {
    return showSearch<String?>(
      context: context,
      delegate: SearchableSelectorDelegate(items, searchHint: 'Search coins'),
    );
  } else {
    return showSearchableSelect(
      context: context,
      items: items,
      searchHint: 'Search coins',
    );
  }
}

DropdownMenuItem<String> _defaultCoinItemBuilder(String coin) {
  return DropdownMenuItem<String>(
    value: coin,
    child: Row(
      children: [
        AssetIcon.ofTicker(coin),
        const SizedBox(width: 12),
        Text(coin),
      ],
    ),
  );
}

class CoinDropdown extends StatefulWidget {
  final List<DropdownMenuItem<String>> items;
  final Widget? child;
  final Function(String) onItemSelected;

  const CoinDropdown({
    super.key,
    required this.items,
    required this.onItemSelected,
    this.child,
  });

  @override
  State<CoinDropdown> createState() => _CoinDropdownState();
}

class _CoinDropdownState extends State<CoinDropdown> {
  String? selectedItem;
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  void _showSearch() async {
    if (_overlayEntry != null) {
      _removeOverlay();
      return;
    }
    _overlayEntry = _createOverlayEntry();
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  OverlayEntry _createOverlayEntry() {
    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);

    final screenSize = MediaQuery.of(context).size;
    final availableHeightBelow = screenSize.height - offset.dy - size.height;
    final availableHeightAbove = offset.dy;

    final showAbove =
        availableHeightBelow < widget.items.length * 48 &&
        availableHeightAbove > availableHeightBelow;

    final dropdownHeight =
        (showAbove ? availableHeightAbove : availableHeightBelow).clamp(
          100.0,
          330.0,
        );

    return OverlayEntry(
      builder: (context) {
        return GestureDetector(
          onTap: _removeOverlay,
          behavior: HitTestBehavior.translucent,
          child: Stack(
            children: [
              Positioned.fill(
                child: Listener(
                  onPointerSignal: (event) {
                    if (event is PointerScrollEvent) {
                      _removeOverlay();
                    }
                  },
                  child: const SizedBox.expand(),
                ),
              ),
              CompositedTransformFollower(
                link: _layerLink,
                showWhenUnlinked: false,
                offset: Offset(0, showAbove ? -dropdownHeight : size.height),
                child: SizedBox(
                  width: size.width,
                  child: _SearchableDropdown(
                    items: widget.items,
                    onItemSelected: (value) {
                      if (value != null) {
                        setState(() => selectedItem = value);
                        widget.onItemSelected(value);
                      }
                      _removeOverlay();
                    },
                    maxHeight: dropdownHeight,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final coinsRepository = RepositoryProvider.of<CoinsRepo>(context);
    final coin = selectedItem == null
        ? null
        : coinsRepository.getCoin(selectedItem!);

    return CompositedTransformTarget(
      link: _layerLink,
      child: InkWell(
        onTap: _showSearch,
        child:
            widget.child ??
            Padding(
              padding: const EdgeInsets.only(left: 15),
              child: CoinItemBody(coin: coin),
            ),
      ),
    );
  }
}

class _SearchableDropdown extends StatefulWidget {
  final List<DropdownMenuItem<String>> items;
  final ValueChanged<String?> onItemSelected;
  final double maxHeight;

  const _SearchableDropdown({
    required this.items,
    required this.onItemSelected,
    this.maxHeight = 300,
  });

  @override
  State<_SearchableDropdown> createState() => _SearchableDropdownState();
}

class _SearchableDropdownState extends State<_SearchableDropdown> {
  late List<DropdownMenuItem<String>> filteredItems;
  String query = '';
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    filteredItems = widget.items;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  void updateSearchQuery(String newQuery) {
    setState(() {
      query = newQuery;
      filteredItems = widget.items
          .where((item) => doesCoinMatchSearch(query, item))
          .toList();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: colorScheme.surfaceContainer,
      child: Container(
        constraints: BoxConstraints(maxHeight: widget.maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextFormField(
                focusNode: _focusNode,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search',
                  hintStyle: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: colorScheme.outlineVariant),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: colorScheme.primary),
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                onChanged: updateSearchQuery,
              ),
            ),
            if (filteredItems.isNotEmpty)
              Expanded(
                child: ListView.builder(
                  itemCount: filteredItems.length,
                  itemBuilder: (context, index) {
                    final item = filteredItems[index];
                    return ListTile(
                      title: item.child,
                      onTap: () => widget.onItemSelected(item.value),
                    );
                  },
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(LocaleKeys.nothingFound.tr()),
              ),
          ],
        ),
      ),
    );
  }
}
