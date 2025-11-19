import 'package:collection/collection.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:web_dex/mm2/mm2_api/rpc/orderbook_depth/orderbook_depth_response.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/coin_type.dart';
import 'package:web_dex/model/typedef.dart';
import 'package:web_dex/shared/utils/utils.dart';

/// Sorts coins according to priority rules:
/// 1. First by balance (non-zero balances come first, sorted by USD value descending)
/// 2. If no balance, sort by priority (higher priority first)
/// 3. If same priority, sort alphabetically
List<Coin> sortByPriorityAndBalance(List<Coin> coins, KomodoDefiSdk sdk) {
  final List<Coin> list = List.of(coins);
  list.sort((a, b) {
    final double usdBalanceA = a.lastKnownUsdBalance(sdk) ?? 0.00;
    final double usdBalanceB = b.lastKnownUsdBalance(sdk) ?? 0.00;

    // Both have balance - sort by USD balance descending
    if (usdBalanceA > 0 && usdBalanceB > 0) {
      return usdBalanceB.compareTo(usdBalanceA);
    }

    // Only one has balance - that one comes first
    if (usdBalanceA > 0 && usdBalanceB == 0) return -1;
    if (usdBalanceB > 0 && usdBalanceA == 0) return 1;

    // Both have no balance - sort by priority then alphabetically
    final int priorityA = a.priority;
    final int priorityB = b.priority;
    if (priorityA != priorityB) return priorityB - priorityA;

    return a.abbr.compareTo(b.abbr);
  });
  return list;
}

List<Coin> sortFiatBalance(List<Coin> coins, KomodoDefiSdk sdk) {
  final List<Coin> list = List.of(coins);
  list.sort((a, b) {
    final double usdBalanceA = a.lastKnownUsdBalance(sdk) ?? 0.00;
    final double usdBalanceB = b.lastKnownUsdBalance(sdk) ?? 0.00;
    if (usdBalanceA > usdBalanceB) return -1;
    if (usdBalanceA < usdBalanceB) return 1;

    if ((a.balance(sdk) ?? 0) > (b.balance(sdk) ?? 0)) return -1;
    if ((a.balance(sdk) ?? 0) < (b.balance(sdk) ?? 0)) return 1;

    final bool isAEnabled = a.isActive;
    final bool isBEnabled = b.isActive;
    if (isAEnabled && !isBEnabled) return -1;
    if (isBEnabled && !isAEnabled) return 1;

    return a.abbr.compareTo(b.abbr);
  });
  return list;
}

List<Coin> removeTestCoins(List<Coin> coins) {
  return coins.where((Coin coin) => !coin.isTestCoin).toList();
}

List<Coin> removeWalletOnly(List<Coin> coins) {
  return coins.where((Coin coin) => !coin.walletOnly).toList();
}

Map<String, List<Coin>> removeSingleProtocol(Map<String, List<Coin>> group) {
  final Map<String, List<Coin>> copy = Map<String, List<Coin>>.from(group);
  copy.removeWhere((key, value) => value.length == 1);
  return copy;
}

CoinsByTicker removeTokensWithEmptyOrderbook(
  CoinsByTicker tokenGroups,
  List<OrderBookDepth> depths,
) {
  final CoinsByTicker copy = CoinsByTicker.from(tokenGroups);

  copy.removeWhere((key, value) {
    return value.every((coin) {
      final depth = depths.firstWhereOrNull((depth) {
        final String source = depth.source.abbr;
        final String target = depth.target.abbr;

        return (source == coin.abbr || target == coin.abbr) &&
            (abbr2Ticker(source) == abbr2Ticker(target));
      });

      return depth == null;
    });
  });

  return copy;
}

CoinsByTicker convertToCoinsByTicker(List<Coin> coinsList) {
  return coinsList.fold<CoinsByTicker>({}, (previousValue, coin) {
    final String ticker = abbr2Ticker(coin.abbr);
    final List<Coin>? coinsWithSameTicker = previousValue[ticker];

    if (coinsWithSameTicker == null) {
      previousValue[ticker] = [coin];
    } else if (!isCoinInList(coin, coinsWithSameTicker)) {
      coinsWithSameTicker.add(coin);
    }

    return previousValue;
  });
}

bool isCoinInList(Coin coin, List<Coin> list) {
  return list.firstWhereOrNull((element) => element.abbr == coin.abbr) != null;
}

Iterable<Coin> filterCoinsByPhrase(Iterable<Coin> coins, String phrase) {
  if (phrase.isEmpty) return coins;
  return coins.where((Coin coin) => compareCoinByPhrase(coin, phrase));
}

bool compareCoinByPhrase(Coin coin, String phrase) {
  final String compareName = coin.displayName.toLowerCase();
  final String compareAbbr = abbr2Ticker(coin.abbr).toLowerCase();
  final lowerCasePhrase = phrase.toLowerCase();

  if (lowerCasePhrase.isEmpty) return false;
  return compareName.contains(lowerCasePhrase) ||
      compareAbbr.contains(lowerCasePhrase);
}

String getCoinTypeName(CoinType type, [String? symbol]) {
  if (type == CoinType.sia) {
    return 'SIA';
  }
  // Override for parent chain coins like ETH, AVAX etc.
  if (symbol != null && isParentCoin(type, symbol)) {
    return 'Native';
  }
  switch (type) {
    case CoinType.erc20:
      return 'ERC-20';
    case CoinType.bep20:
      return 'BEP-20';
    case CoinType.qrc20:
      return 'QRC-20';
    case CoinType.utxo:
      return 'Native';
    case CoinType.smartChain:
      return 'Smart Chain';
    case CoinType.sia:
      return 'SIA';
    case CoinType.ftm20:
      return 'FTM-20';
    case CoinType.arb20:
      return 'ARB-20';
    case CoinType.base20:
      return 'BASE';
    case CoinType.etc:
      return 'ETC';
    case CoinType.avx20:
      return 'AVX-20';
    case CoinType.hrc20:
      return 'HRC-20';
    case CoinType.mvr20:
      return 'MVR-20';
    case CoinType.hco20:
      return 'HCO-20';
    case CoinType.plg20:
      return 'PLG-20';
    case CoinType.sbch:
      return 'SmartBCH';
    case CoinType.ubiq:
      return 'Ubiq';
    case CoinType.krc20:
      return 'KRC-20';
    case CoinType.tendermint:
      return 'Tendermint';
    case CoinType.tendermintToken:
      return 'Tendermint Token';
    case CoinType.slp:
      return 'SLP';
    case CoinType.zhtlc:
      return 'ZHTLC';
  }
}

bool isParentCoin(CoinType type, String symbol) {
  switch (type) {
    case CoinType.utxo:
    case CoinType.sia:
    case CoinType.tendermint:
      return true;
    case CoinType.erc20:
      return symbol == 'ETH';
    case CoinType.bep20:
      return symbol == 'BNB';
    case CoinType.avx20:
      return symbol == 'AVAX';
    case CoinType.etc:
      return symbol == 'ETC';
    case CoinType.ftm20:
      return symbol == 'FTM';
    case CoinType.arb20:
      return symbol == 'ETH-ARB20';
    case CoinType.base20:
      return symbol == 'ETH-BASE';
    case CoinType.hrc20:
      return symbol == 'ONE';
    case CoinType.plg20:
      return symbol == 'MATIC';
    case CoinType.mvr20:
      return symbol == 'MOVR';
    case CoinType.krc20:
      return symbol == 'KCS';
    case CoinType.qrc20:
      return symbol == 'QTUM';
    default:
      return false;
  }
}

Iterable<Coin> sortByPriority(Iterable<Coin> list) {
  final sortedList = List<Coin>.from(list);
  sortedList.sort((a, b) {
    final int priorityA = a.priority;
    final int priorityB = b.priority;
    if (priorityA != priorityB) return priorityB - priorityA;

    // Ensure deterministic ordering when priorities are equal
    return a.abbr.compareTo(b.abbr);
  });
  return sortedList;
}
