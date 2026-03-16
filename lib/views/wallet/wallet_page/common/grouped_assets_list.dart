import 'package:flutter/material.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/views/wallet/wallet_page/common/grouped_asset_ticker_item.dart';

/// A widget that displays a list of assets grouped by their ticker symbols.
///
/// This is an alternative to the [AssetsList] component that groups assets
/// with the same ticker symbol together and allows expanding to see all
/// related assets.
class GroupedAssetsList extends StatelessWidget {
  const GroupedAssetsList({
    super.key,
    required this.assets,
    required this.onAssetItemTap,
    this.onStatisticsTap,
    this.searchPhrase = '',
  });

  /// The complete list of assets to display
  final List<AssetId> assets;

  /// Callback function when an asset is tapped
  final Function(AssetId) onAssetItemTap;
  final void Function(AssetId, Duration period)? onStatisticsTap;

  /// Optional search phrase to filter assets
  final String searchPhrase;

  @override
  Widget build(BuildContext context) {
    final groupedAssets = _groupAssetsByTicker();

    return SliverList.separated(
      separatorBuilder: (BuildContext context, int index) {
        return const SizedBox(height: 16);
      },
      itemBuilder: (BuildContext context, int index) {
        final ticker = groupedAssets.keys.elementAt(index);
        final assetGroup = groupedAssets[ticker]!;

        // final Color backgroundColor = index.isEven
        //     ? Theme.of(context).colorScheme.surface
        //     : Theme.of(context).colorScheme.onSurface;
        final backgroundColor = Theme.of(context).cardTheme.color!;

        return GroupedAssetTickerItem(
          key: Key(ticker),
          assets: assetGroup,
          backgroundColor: backgroundColor,
          onTap: onAssetItemTap,
          onStatisticsTap: onStatisticsTap,
        );
      },
      itemCount: groupedAssets.length,
    );
  }

  /// Groups assets by their ticker symbol
  Map<String, List<AssetId>> _groupAssetsByTicker() {
    final filteredAssets = _filterAssets();
    final groupedAssets = <String, List<AssetId>>{};

    for (final asset in filteredAssets) {
      final ticker = asset.symbol.configSymbol;
      groupedAssets.putIfAbsent(ticker, () => []).add(asset);
    }

    for (final entry in groupedAssets.entries) {
      entry.value.sort((a, b) {
        final bool aIsParent = a.parentId == null;
        final bool bIsParent = b.parentId == null;
        if (aIsParent != bIsParent) return aIsParent ? -1 : 1;
        return a.id.compareTo(b.id);
      });
    }

    return groupedAssets;
  }

  /// Filters assets based on search phrase
  Iterable<AssetId> _filterAssets() {
    if (searchPhrase.isEmpty) {
      return assets;
    }

    return assets.where((asset) {
      final searchLower = searchPhrase.toLowerCase();
      final isFound = asset.toJson().toJsonString().toLowerCase().contains(
        searchLower,
      );

      return isFound;
    });
  }
}
