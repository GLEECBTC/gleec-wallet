import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:web_dex/model/coin.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/shared/utils/utils.dart';

List<Coin> sortByName(List<Coin> coins, SortDirection sortDirection) {
  if (sortDirection == SortDirection.none) return coins;
  coins.sort((a, b) {
    final parentCompare = _compareParentFirst(a, b);
    if (parentCompare != 0) return parentCompare;
    return sortDirection == SortDirection.increase
        ? a.name.compareTo(b.name)
        : b.name.compareTo(a.name);
  });
  return coins;
}

List<Coin> sortByProtocol(List<Coin> coins, SortDirection sortDirection) {
  if (sortDirection == SortDirection.none) return coins;
  coins.sort((a, b) {
    final parentCompare = _compareParentFirst(a, b);
    if (parentCompare != 0) return parentCompare;
    return sortDirection == SortDirection.increase
        ? a.typeNameWithTestnet.compareTo(b.typeNameWithTestnet)
        : b.typeNameWithTestnet.compareTo(a.typeNameWithTestnet);
  });
  return coins;
}

List<Coin> sortByLastKnownUsdBalance(
  List<Coin> coins,
  SortDirection sortDirection,
  KomodoDefiSdk sdk,
) {
  if (sortDirection == SortDirection.none) return coins;
  coins.sort((a, b) {
    final parentCompare = _compareParentFirst(a, b);
    if (parentCompare != 0) return parentCompare;
    final aBalance = a.lastKnownUsdBalance(sdk) ?? 0.0;
    final bBalance = b.lastKnownUsdBalance(sdk) ?? 0.0;
    if (aBalance == bBalance) {
      return a.name.compareTo(b.name);
    }
    return sortDirection == SortDirection.increase
        ? aBalance.compareTo(bBalance)
        : bBalance.compareTo(aBalance);
  });
  return coins;
}

List<Coin> sortByUsdBalance(
  List<Coin> coins,
  SortDirection sortDirection,
  KomodoDefiSdk sdk,
) {
  if (sortDirection == SortDirection.none) return coins;

  final List<({Coin coin, double balance})> coinsWithBalances = List.generate(
    coins.length,
    (i) => (coin: coins[i], balance: coins[i].lastKnownUsdBalance(sdk) ?? 0.0),
  );

  coinsWithBalances.sort((a, b) {
    final parentCompare = _compareParentFirst(a.coin, b.coin);
    if (parentCompare != 0) return parentCompare;
    return sortDirection == SortDirection.increase
        ? a.balance.compareTo(b.balance)
        : b.balance.compareTo(a.balance);
  });

  return coinsWithBalances.map((e) => e.coin).toList();
}

int _compareParentFirst(Coin a, Coin b) {
  final bool aIsParent = a.parentCoin == null;
  final bool bIsParent = b.parentCoin == null;
  if (aIsParent != bIsParent) return aIsParent ? -1 : 1;
  return 0;
}
