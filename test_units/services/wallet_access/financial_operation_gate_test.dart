import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart' show RpcDispatchGuard;
import 'package:web_dex/bloc/market_maker_bot/market_maker_bot/market_maker_bot_repository.dart';
import 'package:web_dex/bloc/nft_withdraw/nft_withdraw_repo.dart';
import 'package:web_dex/bloc/settings/settings_repository.dart';
import 'package:web_dex/mm2/mm2.dart';
import 'package:web_dex/mm2/mm2_api/mm2_api.dart';
import 'package:web_dex/mm2/mm2_api/rpc/cancel_order/cancel_order_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/market_maker_bot/market_maker_bot_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/market_maker_bot/trade_coin_pair_config.dart';
import 'package:web_dex/mm2/mm2_api/rpc/send_raw_transaction/send_raw_transaction_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/send_raw_transaction/send_raw_transaction_response.dart';
import 'package:web_dex/model/stored_settings.dart';
import 'package:web_dex/services/wallet_access/wallet_operation_gate.dart';

const _pair = TradeCoinPairConfig(
  name: 'KMD/BTC',
  baseCoinId: 'KMD',
  relCoinId: 'BTC',
  spread: '1.04',
);

StoredSettings _settings() {
  final initial = StoredSettings.initial();
  return initial.copyWith(
    marketMakerBotSettings: initial.marketMakerBotSettings.copyWith(
      tradeCoinPairConfigs: const [_pair],
    ),
  );
}

class _Settings extends Fake implements SettingsRepository {
  final loadStarted = Completer<void>();
  final result = Completer<StoredSettings>();
  int writes = 0;

  @override
  Future<StoredSettings> loadSettings() {
    if (!loadStarted.isCompleted) loadStarted.complete();
    return result.future;
  }

  @override
  Future<void> updateSettings(StoredSettings settings) async {
    writes++;
  }
}

class _Api extends Fake implements Mm2Api {
  int dispatches = 0;
  void Function()? beforeResponse;

  @override
  Future<void> startStopMarketMakerBot(MarketMakerBotRequest request) async {
    dispatches++;
    beforeResponse?.call();
  }
}

class _Sdk extends Fake implements KomodoDefiSdk {}

class _NftApi extends Fake implements Mm2Api {
  final preparing = Completer<void>();
  final prepared = Completer<void>();
  int sends = 0;

  @override
  Future<SendRawTransactionResponse> sendRawTransaction(
    SendRawTransactionRequest request,
  ) async {
    preparing.complete();
    await prepared.future;
    RpcDispatchGuard.ensureCurrent('send_raw_transaction');
    sends++;
    return SendRawTransactionResponse(txHash: 'accepted', error: null);
  }
}

void main() {
  group('Financial operation authorization', () {
    test('queued NFT send is refused before transport after locking', () async {
      final gate = WalletOperationGate()
        ..attachWallet('first', allowOperations: true);
      final api = _NftApi();
      final repository = NftWithdrawRepo(api: api, operationGate: gate);
      final operation = repository.confirmSend('ETH', 'signed-nft-transaction');
      await api.preparing.future;
      gate.block();
      api.prepared.complete();
      final result = await operation;
      expect(api.sends, 0);
      expect(result.txHash, isNull);
      expect(result.error, isNotNull);
    });

    test(
      'order cancellation queued behind identity verification cannot dispatch after lock',
      () async {
        final gate = WalletOperationGate()
          ..attachWallet('first', allowOperations: true);
        final api = Mm2Api(mm2: mm2, sdk: _Sdk(), operationGate: gate);
        final verificationStarted = Completer<void>();
        final finishVerification = Completer<void>();
        final operation = api.cancelOrder(
          CancelOrderRequest(uuid: 'queued-order'),
          beforeMutation: () async {
            verificationStarted.complete();
            await finishVerification.future;
          },
        );
        final result = expectLater(
          operation,
          throwsA(isA<WalletOperationDenied>()),
        );
        await verificationStarted.future;
        gate.block();
        gate.allow(walletEntryId: 'first');
        finishVerification.complete();
        await result;
        await api.dispose();
      },
    );

    for (final switchWallet in [false, true]) {
      test(
        'bot configuration awaited before ${switchWallet ? 'wallet switch' : 'lock'} cannot start',
        () async {
          final gate = WalletOperationGate()
            ..attachWallet('first', allowOperations: true);
          final settings = _Settings();
          final api = _Api();
          final repository = MarketMakerBotRepository(
            api,
            settings,
            operationGate: gate,
          );
          final operation = repository.start(botId: 1);
          final result = expectLater(
            operation,
            throwsA(isA<WalletOperationDenied>()),
          );
          await settings.loadStarted.future;
          if (switchWallet) {
            gate.attachWallet('second', allowOperations: true);
          } else {
            gate.block();
            gate.allow(walletEntryId: 'first');
          }
          settings.result.complete(_settings());
          await result;
          expect(api.dispatches, 0);
        },
      );
    }

    test('queued bot settings change cannot persist after locking', () async {
      final gate = WalletOperationGate()
        ..attachWallet('first', allowOperations: true);
      final settings = _Settings();
      final repository = MarketMakerBotRepository(
        _Api(),
        settings,
        operationGate: gate,
      );
      final operation = repository.addTradePairToStoredSettings(_pair);
      final result = expectLater(
        operation,
        throwsA(isA<WalletOperationDenied>()),
      );
      await settings.loadStarted.future;
      gate.block();
      settings.result.complete(_settings());
      await result;
      expect(settings.writes, 0);
    });

    test(
      'accepted bot start remains accepted after application lock',
      () async {
        final gate = WalletOperationGate()
          ..attachWallet('first', allowOperations: true);
        final settings = _Settings()..result.complete(_settings());
        final api = _Api()..beforeResponse = gate.block;
        final repository = MarketMakerBotRepository(
          api,
          settings,
          operationGate: gate,
        );
        await repository.start(botId: 1);
        expect(api.dispatches, 1);
        expect(gate.allowsOperations, isFalse);
      },
    );

    test('lock during a bot restart never sends a second start', () async {
      final gate = WalletOperationGate()
        ..attachWallet('first', allowOperations: true);
      final settings = _Settings()..result.complete(_settings());
      final api = _Api()..beforeResponse = gate.block;
      final repository = MarketMakerBotRepository(
        api,
        settings,
        operationGate: gate,
      );
      await expectLater(
        repository.updateOrder(_pair, botId: 1).toList(),
        throwsA(isA<WalletOperationDenied>()),
      );
      expect(api.dispatches, 1);
    });
  });
}
