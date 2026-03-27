import 'package:flutter/material.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/views/wallet/wallet_page/common/asset_list_item.dart';
import 'package:web_dex/views/wallet/wallet_page/common/asset_ticker_group_sort.dart';
import 'package:web_dex/views/wallet/wallet_page/common/grouped_asset_ticker_item.dart';

/// A widget that displays a list of assets.
///
/// This replaces the previous AllCoinsList component and works with AssetId instead of Coin.
class AssetsList extends StatelessWidget {
  const AssetsList({
    super.key,
    required this.assets,
    required this.onAssetItemTap,
    this.onStatisticsTap,
    this.withBalance = false,
    this.searchPhrase = '',
    this.useGroupedView = false,
    this.priceChangePercentages = const {},
  });

  final List<AssetId> assets;
  final Function(AssetId) onAssetItemTap;
  final void Function(AssetId, Duration period)? onStatisticsTap;
  final bool withBalance;
  final String searchPhrase;
  final bool useGroupedView;
  final Map<String, double> priceChangePercentages;

  @override
  Widget build(BuildContext context) {
    if (useGroupedView) {
      return _buildGroupedView(context);
    }
    return _buildFlatView(context);
  }

  Widget _buildFlatView(BuildContext context) {
    final filteredAssets = _filterAssets();

    return SliverList(
      delegate: SliverChildBuilderDelegate((BuildContext context, int index) {
        final asset = filteredAssets[index];
        final Color backgroundColor = index.isEven
            ? Theme.of(context).colorScheme.surface
            : Theme.of(context).colorScheme.onSurface;

        return AssetListItem(
          assetId: asset,
          backgroundColor: backgroundColor,
          onTap: onAssetItemTap,
          onStatisticsTap: onStatisticsTap,
          priceChangePercentage24h: priceChangePercentages[asset.id],
        );
      }, childCount: filteredAssets.length),
    );
  }

  Widget _buildGroupedView(BuildContext context) {
    final groupedAssets = _groupAssetsByTicker();
    final groups = groupedAssets.entries.toList();

    return SliverList.separated(
      itemBuilder: (BuildContext context, int index) {
        final group = groups[index];
        // final Color backgroundColor = index.isEven
        //     ? Theme.of(context).colorScheme.surface
        //     : Theme.of(context).colorScheme.;
        final Color backgroundColor = Theme.of(context).cardColor;

        return GroupedAssetTickerItem(
          key: Key(group.key),
          assets: group.value,
          backgroundColor: backgroundColor,
          onTap: onAssetItemTap,
          onStatisticsTap: onStatisticsTap,
        );
      },
      separatorBuilder: (BuildContext context, int index) {
        return const SizedBox(height: 10);
      },
      itemCount: groups.length,
    );
  }

  /// Groups assets by their ticker symbol
  Map<String, List<AssetId>> _groupAssetsByTicker() {
    final filteredAssets = _filterAssets();
    final groupedAssets = <String, List<AssetId>>{};

    for (final asset in filteredAssets) {
      final symbol = asset.symbol.configSymbol;
      groupedAssets.putIfAbsent(symbol, () => []).add(asset);
    }

    for (final entry in groupedAssets.entries) {
      sortAssetIdsWithinTickerGroup(entry.value);
    }

    // Sort groups: priority tickers first (in order from list), then others (alphabetically)
    final groups = groupedAssets.entries.toList();
    groups.sort((a, b) {
      final String tickerA = a.key;
      final String tickerB = b.key;

      final int indexA = unauthenticatedUserPriorityTickers.indexOf(tickerA);
      final int indexB = unauthenticatedUserPriorityTickers.indexOf(tickerB);

      final bool aIsPriority = indexA != -1;
      final bool bIsPriority = indexB != -1;

      // Priority tickers come first
      if (aIsPriority && !bIsPriority) return -1;
      if (!aIsPriority && bIsPriority) return 1;

      // If both are priority, sort by their order in the priority list
      if (aIsPriority && bIsPriority) {
        return indexA.compareTo(indexB);
      }

      // If both are not priority, sort alphabetically
      return tickerA.compareTo(tickerB);
    });

    return Map.fromEntries(groups);
  }

  /// Filters assets based on search phrase
  List<AssetId> _filterAssets() {
    if (searchPhrase.isEmpty) {
      return assets;
    }

    return assets.where((asset) {
      final name = asset.name.toLowerCase();
      final symbol = asset.symbol.configSymbol.toLowerCase();
      final id = asset.id.toLowerCase();
      final searchLower = searchPhrase.toLowerCase();

      return name.contains(searchLower) ||
          symbol.contains(searchLower) ||
          id.contains(searchLower);
    }).toList();
  }
}
