import 'package:decimal/decimal.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/coins_bloc/coins_bloc.dart';
import 'package:web_dex/bloc/settings/settings_bloc.dart';
import 'package:web_dex/bloc/settings/settings_state.dart';
import 'package:web_dex/model/cex_price.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/coin_type.dart';
import 'package:web_dex/model/stored_settings.dart';

/// One asset of a [FakeWallet]: what it is, its price, and how much is held.
typedef FakeHolding = ({
  String id,
  String name,
  CoinSubClass subClass,
  double price,
  double change,
  double amount,
});

/// Wallet coins with balances and prices, and an SDK that reports them.
class FakeWallet {
  FakeWallet(List<FakeHolding> holdings) {
    for (final holding in holdings) {
      final id = AssetId(
        id: holding.id,
        name: holding.name,
        parentId: null,
        symbol: AssetSymbol(assetConfigId: holding.id),
        derivationPath: null,
        chainId: AssetChainId(chainId: 1),
        subClass: holding.subClass,
      );
      coins[holding.id] = Coin(
        type: CoinType.utxo,
        abbr: holding.id,
        id: id,
        name: holding.name,
        explorerUrl: '',
        explorerTxUrl: '',
        explorerAddressUrl: '',
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
      final amount = Decimal.parse(holding.amount.toString());
      balances[id] = BalanceInfo(
        total: amount,
        spendable: amount,
        unspendable: Decimal.zero,
      );
      prices[id.symbol.configSymbol.toUpperCase()] = CexPrice(
        assetId: id,
        price: Decimal.parse(holding.price.toString()),
        change24h: Decimal.parse(holding.change.toString()),
        lastUpdated: DateTime(2026, 11, 24),
      );
    }
  }

  final coins = <String, Coin>{};
  final balances = <AssetId, BalanceInfo>{};
  final prices = <String, CexPrice>{};

  late final sdk = _FakeSdk(this);

  CoinsState get state => CoinsState(
    coins: coins,
    walletCoins: coins,
    pubkeys: const {},
    prices: prices,
  );
}

class _FakeSdk implements KomodoDefiSdk {
  _FakeSdk(this._wallet);

  final FakeWallet _wallet;

  @override
  BalanceManager get balances => _FakeBalances(_wallet);

  @override
  MarketDataManager get marketData => _FakeMarketData(_wallet);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBalances implements BalanceManager {
  _FakeBalances(this._wallet);

  final FakeWallet _wallet;

  @override
  BalanceInfo? lastKnown(AssetId assetId) => _wallet.balances[assetId];

  @override
  Stream<BalanceInfo> watchBalance(
    AssetId assetId, {
    bool activateIfNeeded = true,
  }) => Stream.value(_wallet.balances[assetId]!);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMarketData implements MarketDataManager {
  _FakeMarketData(this._wallet);

  final FakeWallet _wallet;

  @override
  Decimal? priceIfKnown(
    AssetId assetId, {
    DateTime? priceDate,
    QuoteCurrency quoteCurrency = Stablecoin.usdt,
  }) => _wallet.prices[assetId.symbol.configSymbol.toUpperCase()]?.price;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeWalletCoins extends Cubit<CoinsState> implements CoinsBloc {
  FakeWalletCoins(super.initialState);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeWalletSettings extends Cubit<SettingsState> implements SettingsBloc {
  FakeWalletSettings({bool hideBalances = false})
    : super(
        SettingsState.fromStored(StoredSettings.initial())
            .copyWith(hideBalances: hideBalances),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
