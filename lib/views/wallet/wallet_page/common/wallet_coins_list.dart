import 'package:flutter/material.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/views/wallet/wallet_page/common/asset_list_item.dart';

class KnownAssetsList extends StatelessWidget {
  const KnownAssetsList({
    super.key,
    required this.assets,
    required this.onAssetItemTap,
  });

  final List<AssetId> assets;
  final void Function(AssetId) onAssetItemTap;

  @override
  Widget build(BuildContext context) {
    return SliverList.separated(
      key: const Key('wallet-page-coins-list'),
      itemBuilder: (BuildContext context, int index) {
        final asset = assets[index];
        final Color backgroundColor = index.isEven
            ? Theme.of(context).colorScheme.surface
            : Theme.of(context).scaffoldBackgroundColor;
        return AssetListItem(
          assetId: asset,
          backgroundColor: backgroundColor,
          onTap: (assetId) => onAssetItemTap(assetId),
        );
      },
      separatorBuilder: (BuildContext context, int index) {
        return const SizedBox(height: 8);
      },
      itemCount: assets.length,
    );
  }
}
