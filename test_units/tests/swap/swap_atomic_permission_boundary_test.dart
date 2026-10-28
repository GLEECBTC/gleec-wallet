import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/shared/trading/trading_asset_policy.dart';
import 'package:web_dex/bloc/settings/settings_repository.dart';
import 'package:web_dex/bloc/market_maker_bot/market_maker_bot/market_maker_bot_repository.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_sdk/src/assets/asset_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/mm2/mm2.dart';
import 'package:web_dex/mm2/mm2_api/mm2_api.dart';
import 'package:web_dex/mm2/mm2_api/rpc/sell/sell_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/setprice/setprice_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/trade_preimage/trade_preimage_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/trade_preimage/trade_preimage_errors.dart';
import 'package:web_dex/mm2/mm2_api/rpc/market_maker_bot/market_maker_bot_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/market_maker_bot/market_maker_bot_parameters.dart';
import 'package:web_dex/mm2/mm2_api/rpc/market_maker_bot/trade_coin_pair_config.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';

class _Assets extends Fake implements AssetManager {
  final assets = <Asset>{};
  @override
  Set<Asset> findAssetsByConfigId(String id) =>
      assets.where((asset) => asset.id.id == id).toSet();
}

class _Sdk extends Fake implements KomodoDefiSdk {
  @override
  final _Assets assets = _Assets();
}

void main() {
  test(
    'a permanent bot permission refusal is surfaced without retries',
    () async {
      final api = _RefusingBotApi();
      final repository = _ConfiguredBotRepository(api);
      await expectLater(
        repository.start(botId: 1, retries: 3, delay: Duration.zero),
        throwsA(isA<AtomicPermissionUnavailableException>()),
      );
      expect(api.calls, 1);
    },
  );

  test(
    'Advanced and bot starts reject token approval before reaching KDF',
    () async {
      final token = Asset.fromJson({
        'coin': 'TOKEN-WITHOUT-PROTOCOL-SUFFIX',
        'fname': 'Synthetic token',
        'type': 'ERC-20',
        'chain_id': 1,
        'protocol': {
          'type': 'ERC20',
          'protocol_data': {
            'platform': 'ETH',
            'contract_address': '0x0000000000000000000000000000000000000002',
          },
        },
        'nodes': const [],
        'swap_contract_address': '0x0000000000000000000000000000000000000001',
        'fallback_swap_contract': '0x0000000000000000000000000000000000000001',
      }, knownIds: const {});
      expect(token.id.parentId, isNull); // Intrinsic protocol must decide.
      final sdk = _Sdk()..assets.assets.add(token);
      // MM2 is deliberately uninitialized. Any accidental engine call fails;
      // permission refusals must be returned before transport is consulted.
      final api = Mm2Api(mm2: mm2, sdk: sdk);
      addTearDown(api.dispose);
      for (final ticker in [token.id.id, 'UNRESOLVED-ASSET']) {
        final preimageRequest = TradePreimageRequest(
          base: ticker,
          rel: 'BTC',
          swapMethod: 'sell',
          price: Rational.one,
          volume: Rational.one,
        );
        final preimage = await api.getTradePreimage(preimageRequest);
        expect(
          tradePreimageErrorFactory
              .getError(preimage.error!, preimageRequest)
              .message,
          LocaleKeys.swapPermissionUnavailableBody,
        );
        final request = SellRequest(
          orderType: SellBuyOrderType.fillOrKill,
          base: ticker,
          rel: 'BTC',
          volume: Rational.one,
          price: Rational.one,
        );
        expect(
          (await api.sell(request))['error'],
          LocaleKeys.swapPermissionUnavailableBody,
        );
        expect(
          (await api.sellOrThrow(request))['error'],
          LocaleKeys.swapPermissionUnavailableBody,
        );
        expect(
          (await api.setprice(
            SetPriceRequest(
              base: ticker,
              rel: 'BTC',
              volume: Rational.one,
              price: Rational.one,
            ),
          ))!['error'],
          LocaleKeys.swapPermissionUnavailableBody,
        );
        await expectLater(
          api.startStopMarketMakerBot(
            MarketMakerBotRequest(
              id: 1,
              params: MarketMakerBotParameters(
                tradeCoinPairs: {
                  'pair': TradeCoinPairConfig(
                    name: 'pair',
                    baseCoinId: ticker,
                    relCoinId: 'BTC',
                    spread: '0.01',
                  ),
                },
              ),
            ),
          ),
          throwsA(
            isA<AtomicPermissionUnavailableException>().having(
              (e) => e.message,
              'permission',
              LocaleKeys.swapPermissionUnavailableBody,
            ),
          ),
        );
      }
    },
  );
}

class _UnusedSettings extends Fake implements SettingsRepository {}

class _ConfiguredBotRepository extends MarketMakerBotRepository {
  _ConfiguredBotRepository(Mm2Api api) : super(api, _UnusedSettings());
  @override
  Future<MarketMakerBotParameters> loadStoredConfig() async =>
      const MarketMakerBotParameters(
        tradeCoinPairs: {
          'pair': TradeCoinPairConfig(
            name: 'pair',
            baseCoinId: 'ETH',
            relCoinId: 'BTC',
            spread: '0.01',
          ),
        },
      );
}

class _RefusingBotApi extends Fake implements Mm2Api {
  int calls = 0;
  @override
  Future<void> startStopMarketMakerBot(MarketMakerBotRequest request) async {
    calls++;
    throw const AtomicPermissionUnavailableException('Unverified permission');
  }
}
