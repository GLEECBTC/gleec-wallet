import 'package:decimal/decimal.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';
import 'package:web_dex/bloc/coins_bloc/coins_bloc.dart';
import 'package:web_dex/model/cex_price.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/coin_type.dart';
import 'package:web_dex/shared/utils/balance_utils.dart';

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
    isTestCoin: false,
    logoImageUrl: null,
    coingeckoId: null,
    fallbackSwapContract: null,
    priority: 0,
    state: CoinState.active,
    swapContractAddress: null,
    walletOnly: false,
    mode: CoinMode.standard,
    usdPrice: null,
  );
}

CexPrice _cexPrice(AssetId id, double price) => CexPrice(
  assetId: id,
  price: Decimal.parse(price.toString()),
  change24h: Decimal.zero,
  lastUpdated: DateTime.fromMillisecondsSinceEpoch(0),
);

class _FakeBalanceManager implements BalanceManager {
  _FakeBalanceManager(this._byAsset);
  final Map<AssetId, BalanceInfo?> _byAsset;

  @override
  BalanceInfo? lastKnown(AssetId assetId) => _byAsset[assetId];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSdk implements KomodoDefiSdk {
  _FakeSdk(this._balances);
  final Map<AssetId, BalanceInfo?> _balances;

  @override
  BalanceManager get balances => _FakeBalanceManager(_balances);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

CoinsState _stateWithPrices({
  required Map<String, Coin> coins,
  required Map<String, CexPrice> prices,
}) {
  return CoinsState(
    coins: coins,
    walletCoins: coins,
    pubkeys: const {},
    prices: prices,
  );
}

void testComputeWalletTotalUsd() {
  final btc = _buildCoin('BTC');
  final kmd = _buildCoin('KMD');

  test('sums balances using CEX prices from CoinsState', () {
    final sdk = _FakeSdk({
      btc.id: BalanceInfo(
        total: null,
        spendable: Decimal.fromInt(2),
        unspendable: Decimal.zero,
      ),
      kmd.id: BalanceInfo(
        total: null,
        spendable: Decimal.fromInt(100),
        unspendable: Decimal.zero,
      ),
    });
    final state = _stateWithPrices(
      coins: {'BTC': btc, 'KMD': kmd},
      prices: {'BTC': _cexPrice(btc.id, 30_000), 'KMD': _cexPrice(kmd.id, 1)},
    );

    expect(
      computeWalletTotalUsd(coins: [btc, kmd], coinsState: state, sdk: sdk),
      60_100.0,
    );
  });

  test('returns null when no coin has both balance and price', () {
    final sdk = _FakeSdk({
      btc.id: BalanceInfo(
        total: null,
        spendable: Decimal.one,
        unspendable: Decimal.zero,
      ),
    });
    final state = _stateWithPrices(coins: {'BTC': btc}, prices: {});

    expect(
      computeWalletTotalUsd(coins: [btc], coinsState: state, sdk: sdk),
      isNull,
    );
  });

  test('sums only coins that have both balance and price', () {
    final sdk = _FakeSdk({
      btc.id: BalanceInfo(
        total: null,
        spendable: Decimal.fromInt(2),
        unspendable: Decimal.zero,
      ),
      kmd.id: BalanceInfo(
        total: null,
        spendable: Decimal.fromInt(100),
        unspendable: Decimal.zero,
      ),
    });
    final state = _stateWithPrices(
      coins: {'BTC': btc, 'KMD': kmd},
      prices: {'BTC': _cexPrice(btc.id, 30_000)},
    );

    expect(
      computeWalletTotalUsd(coins: [btc, kmd], coinsState: state, sdk: sdk),
      60_000.0,
    );
  });

  test('returns 0 when priced balances are all zero', () {
    final sdk = _FakeSdk({btc.id: BalanceInfo.zero()});
    final state = _stateWithPrices(
      coins: {'BTC': btc},
      prices: {'BTC': _cexPrice(btc.id, 30_000)},
    );

    expect(
      computeWalletTotalUsd(coins: [btc], coinsState: state, sdk: sdk),
      0.0,
    );
  });

  test('returns 0.01 for positive dust totals below 0.01', () {
    final sdk = _FakeSdk({
      btc.id: BalanceInfo(
        total: null,
        spendable: Decimal.parse('0.0001'),
        unspendable: Decimal.zero,
      ),
    });
    final state = _stateWithPrices(
      coins: {'BTC': btc},
      prices: {'BTC': _cexPrice(btc.id, 10)},
    );

    expect(
      computeWalletTotalUsd(coins: [btc], coinsState: state, sdk: sdk),
      0.01,
    );
  });

  test('returns null when lastKnown balance is missing', () {
    final sdk = _FakeSdk({});
    final state = _stateWithPrices(
      coins: {'BTC': btc},
      prices: {'BTC': _cexPrice(btc.id, 30_000)},
    );

    expect(
      computeWalletTotalUsd(coins: [btc], coinsState: state, sdk: sdk),
      isNull,
    );
  });
}
