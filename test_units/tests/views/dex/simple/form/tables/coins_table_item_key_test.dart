import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart'
    show AssetChainId, AssetId, CoinSubClass;
import 'package:komodo_defi_types/src/assets/asset_symbol.dart';
import 'package:web_dex/model/cex_price.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/coin_type.dart';
import 'package:web_dex/views/dex/simple/form/tables/coins_table/coins_table_item.dart';

/// The DEX coin row is addressed by key from the integration suites, so its key
/// has to mean the same thing in every build mode.
///
/// It used to be built from `T.toString()`. dart2js minifies type names in a
/// release build, so that expression answered `Coin` in debug and profile and
/// `minified:c9` in release - and the release web build was the one CI ran on
/// macOS. The row was present and the asset was active; only the key differed,
/// so the suite waited the full timeout for a row it could never name.
///
/// Asserting the literal alone would not catch a return to `T.toString()`,
/// because these tests run unminified, where that expression still produces
/// `Coin`. Rendering the same prefix over two different type arguments does
/// catch it: under `T.toString()` the two keys differ, and under a caller-given
/// prefix they are identical.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CoinsTableItem key', () {
    testWidgets('is named by the table, not by the row type', (tester) async {
      final coin = _buildCoin('DOC');

      await tester.pumpWidget(
        _host(
          Column(
            children: [
              CoinsTableItem<Coin>(
                itemKeyPrefix: 'Shared',
                data: coin,
                coin: coin,
                onSelect: (_) {},
                trailing: const SizedBox.shrink(),
              ),
              CoinsTableItem<_OtherRowType>(
                itemKeyPrefix: 'Shared',
                data: const _OtherRowType(),
                coin: coin,
                onSelect: (_) {},
                trailing: const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );

      // Two different type arguments, one prefix: exactly one key spelling, and
      // both rows carry it.
      expect(find.byKey(const Key('Shared-table-item-DOC')), findsNWidgets(2));
    });

    testWidgets('spells the prefix the caller gave it', (tester) async {
      final coin = _buildCoin('DOC');

      await tester.pumpWidget(
        _host(
          CoinsTableItem<Coin>(
            itemKeyPrefix: 'Coin',
            data: coin,
            coin: coin,
            onSelect: (_) {},
            trailing: const SizedBox.shrink(),
          ),
        ),
      );

      expect(find.byKey(const Key('Coin-table-item-DOC')), findsOneWidget);
    });

    testWidgets('a group header carries no row key', (tester) async {
      final coin = _buildCoin('DOC');

      await tester.pumpWidget(
        _host(
          CoinsTableItem<Coin>(
            itemKeyPrefix: 'Coin',
            data: coin,
            coin: coin,
            isGroupHeader: true,
            onSelect: (_) {},
            trailing: const SizedBox.shrink(),
          ),
        ),
      );

      expect(find.byKey(const Key('Coin-table-item-DOC')), findsNothing);
    });
  });
}

class _OtherRowType {
  const _OtherRowType();
}

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

Coin _buildCoin(String abbr) {
  final assetId = AssetId(
    id: abbr,
    name: '$abbr Coin',
    symbol: AssetSymbol(assetConfigId: abbr),
    chainId: AssetChainId(chainId: 1),
    derivationPath: null,
    subClass: CoinSubClass.utxo,
  );

  return Coin(
    type: CoinType.utxo,
    abbr: abbr,
    id: assetId,
    name: '$abbr Coin',
    explorerUrl: 'https://example.com/$abbr',
    explorerTxUrl: 'https://example.com/$abbr/tx',
    explorerAddressUrl: 'https://example.com/$abbr/address',
    protocolType: 'UTXO',
    protocolData: null,
    isTestCoin: true,
    logoImageUrl: null,
    coingeckoId: null,
    fallbackSwapContract: null,
    priority: 0,
    state: CoinState.active,
    swapContractAddress: null,
    walletOnly: false,
    mode: CoinMode.standard,
    usdPrice: CexPrice(
      assetId: assetId,
      price: Decimal.zero,
      change24h: Decimal.zero,
      lastUpdated: DateTime.fromMillisecondsSinceEpoch(0),
    ),
  );
}
