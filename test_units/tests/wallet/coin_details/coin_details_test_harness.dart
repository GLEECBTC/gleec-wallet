import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/coin_type.dart';

import '../../utils/test_util.dart';

Coin buildTestCoin({String abbr = 'KMD', CoinType type = CoinType.smartChain}) {
  final coin = setCoin(coinAbbr: abbr);
  return coin.copyWith(type: type);
}

Transaction buildTestTransaction({
  required AssetId assetId,
  String txHash = 'tx-hash-1',
  Decimal? netChange,
  int confirmations = 0,
  int blockHeight = 0,
  FeeInfo? fee,
  String? memo,
}) {
  return Transaction(
    id: 'tx-id-1',
    internalId: 'tx-internal-1',
    assetId: assetId,
    balanceChanges: BalanceChanges(
      netChange: netChange ?? Decimal.parse('-1.0'),
      receivedByMe: Decimal.zero,
      spentByMe: Decimal.one,
      totalAmount: Decimal.one,
    ),
    timestamp: DateTime.utc(2025, 1, 1, 0, 0, 0),
    confirmations: confirmations,
    blockHeight: blockHeight,
    from: const ['from-address'],
    to: const ['to-address'],
    txHash: txHash,
    fee: fee,
    memo: memo,
  );
}

Widget wrapWithMaterial(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}
