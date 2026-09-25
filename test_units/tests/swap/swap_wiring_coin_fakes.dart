import 'package:decimal/decimal.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
// The SDK does not export the asset manager's type.
// ignore: implementation_imports
import 'package:komodo_defi_sdk/src/assets/asset_manager.dart'
    show AssetManager;
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/analytics/analytics_event.dart';
import 'package:web_dex/bloc/analytics/analytics_bloc.dart';
import 'package:web_dex/bloc/cex_market_data/portfolio_growth/portfolio_growth_repository.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/profit_loss_repository.dart';
import 'package:web_dex/bloc/coins_bloc/coins_bloc.dart';
import 'package:web_dex/bloc/taker_form/taker_bloc.dart';
import 'package:web_dex/bloc/taker_form/taker_event.dart';
import 'package:web_dex/bloc/transaction_history/transaction_history_bloc.dart';
import 'package:web_dex/bloc/transaction_history/transaction_history_state.dart';

/// DOC, a test-network UTXO coin.
final docAsset = Asset.fromJson(const {
  'coin': 'DOC',
  'type': 'Smart Chain',
  'name': 'Doc',
  'fname': 'Doc',
  'wallet_only': false,
  'mm2': 1,
  'chain_id': 141,
  'decimals': 8,
  'is_testnet': true,
  'required_confirmations': 1,
  'derivation_path': "m/44'/141'/0'",
  'protocol': {'type': 'UTXO'},
});

/// What a coin page reads from the SDK: one signed-in wallet holding one
/// coin, [docAsset], with no price.
class CoinPageSdk implements KomodoDefiSdk {
  CoinPageSdk(KdfUser user) : auth = _CoinPageAuth(user);

  @override
  final KomodoDefiLocalAuth auth;

  @override
  final BalanceManager balances = _OneCoin();

  @override
  final MarketDataManager marketData = _NoPrices();

  @override
  final AssetManager assets = _OneAsset();

  @override
  final ActivatedAssetsCache activatedAssetsCache = _NothingActive();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CoinPageAuth implements KomodoDefiLocalAuth {
  _CoinPageAuth(this.user);

  final KdfUser user;

  @override
  Future<KdfUser?> get currentUser async => user;

  @override
  Stream<KdfUser?> watchCurrentUser() => Stream.value(user);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _OneCoin implements BalanceManager {
  static final _balance = BalanceInfo(
    total: Decimal.one,
    spendable: Decimal.one,
    unspendable: Decimal.zero,
  );

  @override
  BalanceInfo? lastKnown(AssetId assetId) => _balance;

  @override
  Future<BalanceInfo> getBalance(
    AssetId assetId, {
    bool forceRefresh = false,
  }) async => _balance;

  @override
  Stream<BalanceInfo> watchBalance(
    AssetId assetId, {
    bool activateIfNeeded = true,
  }) => Stream.value(_balance);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoPrices implements MarketDataManager {
  @override
  Decimal? priceIfKnown(
    AssetId assetId, {
    DateTime? priceDate,
    QuoteCurrency quoteCurrency = Stablecoin.usdt,
  }) => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _OneAsset implements AssetManager {
  @override
  Map<AssetId, Asset> get available => {docAsset.id: docAsset};

  @override
  Set<Asset> findAssetsByConfigId(String ticker) =>
      ticker == docAsset.id.id ? {docAsset} : const {};

  @override
  Asset? fromId(AssetId id) => id == docAsset.id ? docAsset : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NothingActive implements ActivatedAssetsCache {
  @override
  Future<Set<AssetId>> getActivatedAssetIds({
    bool forceRefresh = false,
  }) async => const {};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Analytics that drops every event.
class SilentAnalytics implements AnalyticsBloc {
  @override
  void add(AnalyticsEvent event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class NoGrowthCharts implements PortfolioGrowthRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class NoProfitLoss implements ProfitLossRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeCoinsBloc extends Cubit<CoinsState> implements CoinsBloc {
  FakeCoinsBloc() : super(CoinsState.initial());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeTransactionHistoryBloc extends Cubit<TransactionHistoryState>
    implements TransactionHistoryBloc {
  FakeTransactionHistoryBloc()
    : super(
        const TransactionHistoryState(
          transactions: [],
          loading: false,
          error: null,
        ),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The full trading form's bloc, recording what it is asked to do.
class RecordingTakerBloc implements TakerBloc {
  final List<TakerEvent> events = [];

  @override
  void add(TakerEvent event) => events.add(event);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
