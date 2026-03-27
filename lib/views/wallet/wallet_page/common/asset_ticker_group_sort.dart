import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Sorts assets that share a display ticker so parent-chain entries (no
/// [AssetId.parentId]) appear before wrapped tokens, then by [AssetId.id].
///
/// Used by grouped ticker UIs so the primary row represents the native asset.
void sortAssetIdsWithinTickerGroup(List<AssetId> assets) {
  assets.sort((a, b) {
    final bool aIsParent = a.parentId == null;
    final bool bIsParent = b.parentId == null;
    if (aIsParent != bIsParent) return aIsParent ? -1 : 1;
    return a.id.compareTo(b.id);
  });
}
