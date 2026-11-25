part of 'swap_asset_picker.dart';

/// The picker's search field and network filter: two controls of one shape.
extension _PickerFilters on _SwapAssetPickerState {
  static const _fieldHeight = 52.0;
  static const _fieldRadius = BorderRadius.all(Radius.circular(14));

  Widget _searchField(BuildContext context) {
    final palette = SwapPalette.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: _fieldHeight),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: palette.surfaceHigh,
        borderRadius: _fieldRadius,
        border: Border.all(color: palette.controlBorder),
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, color: palette.textTertiary),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _search,
              autofocus: MediaQuery.sizeOf(context).width >= 768,
              onChanged: (_) => _searchChanged(),
              style: SwapText.body(context).copyWith(color: palette.text),
              decoration: InputDecoration(
                contentPadding: EdgeInsets.zero,
                visualDensity: VisualDensity.standard,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                hintText: LocaleKeys.swapPickerSearch.tr(),
                hintMaxLines: 4,
                hintStyle: SwapText.body(context)
                    .copyWith(color: palette.textTertiary),
              ),
            ),
          ),
          if (_search.text.isNotEmpty)
            SwapLinkButton(
              label: LocaleKeys.clear.tr(),
              onPressed: _clearSearch,
            ),
        ],
      ),
    );
  }

  Widget _networkFilter(BuildContext context) {
    final palette = SwapPalette.of(context);
    final networks = <String, String>{
      for (final id in _offered())
        (id.parentId ?? id).id: widget.services.networks().networkOf(id),
    };
    final entries = networks.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    OutlineInputBorder border(Color color, {double width = 1}) =>
        OutlineInputBorder(
          borderRadius: _fieldRadius,
          borderSide: BorderSide(color: color, width: width),
        );
    final style = SwapText.body(context).copyWith(color: palette.text);
    return Semantics(
      container: true,
      label: 'swapNetworkFilter'.tr(),
      // The field reads its value once, so it is keyed on it: a filter the
      // picker drops, as when its network leaves the list, shows as dropped.
      child: KeyedSubtree(
        key: ValueKey(_network),
        child: DropdownButtonFormField<String>(
          key: const Key('swap-picker-network'),
          initialValue: _network,
          isExpanded: true,
          style: style,
          dropdownColor: palette.surfaceRaised,
          borderRadius: _fieldRadius,
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: palette.textSecondary,
          ),
          decoration: InputDecoration(
            // With the 24 dp row of a dense dropdown, as tall as the search.
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: (_fieldHeight - 24) / 2,
            ),
            filled: true,
            fillColor: palette.surfaceHigh,
            prefixIcon: Icon(Icons.hub_outlined, color: palette.textTertiary),
            border: border(palette.controlBorder),
            enabledBorder: border(palette.controlBorder),
            focusedBorder: border(palette.brand, width: 2),
          ),
          items: [
            DropdownMenuItem(value: '', child: Text('swapAllNetworks'.tr())),
            for (final entry in entries)
              DropdownMenuItem(
                value: entry.key,
                child: Text(
                  entry.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (network) => _setNetwork(network ?? ''),
        ),
      ),
    );
  }
}
