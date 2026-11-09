import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/mm2/mm2.dart';
import 'package:web_dex/mm2/mm2_api/mm2_api.dart';
import 'package:web_dex/mm2/mm2_api/rpc/sell/sell_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/order_status/cancellation_reason.dart';
import 'package:web_dex/shared/swap/atomic_swap_execution.dart';
import 'package:web_dex/shared/swap/swap_execution.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/shared/trading/trading_asset_policy.dart';

import 'swap_exec_atomic_fakes.dart';
import 'swap_test_fixtures.dart';

final _sol = assetOf(
  'TESTSOL',
  name: 'Solana Devnet',
  subClass: CoinSubClass.solana,
  decimals: 9,
);
final _spl = assetOf(
  'TESTUSDC-TESTSOL',
  subClass: CoinSubClass.solanaToken,
  parent: _sol,
  decimals: 6,
);
final _marty = assetOf('MARTY', subClass: CoinSubClass.utxo, decimals: 8);
final _assets = [_sol, _spl, _marty];
const _signature = '5SigBase58ABCabcXYZxyz123';

/// Same real executor and source-shaped swap parser as existing atomic tests,
/// with Solana platform/token identities resolved during restored executions.
class _SolanaRig extends AtomicRig {
  _SolanaRig(super.async);

  late final _solanaExecutor = AtomicSwapExecutor(
    auth: testSwapAuth,
    dexRepository: dex,
    orders: orders,
    networks: () => SwapNetworks(_assets),
    resolveAsset: (ticker) =>
        _assets.where((asset) => asset.id == ticker).firstOrNull,
    pollInterval: AtomicRig.pollInterval,
    now: () => now,
  );

  @override
  AtomicSwapExecutor get executor => _solanaExecutor;
}

Future<void> _withRig(void Function(_SolanaRig rig) body) async {
  fakeAsync((async) => body(_SolanaRig(async)));
  await pumpEventQueue();
}

List<String> _paid(bool maker) => maker
    ? ['Started', 'Negotiated', 'TakerFeeValidated', 'MakerPaymentSent']
    : [
        'Started',
        'Negotiated',
        'TakerFeeSent',
        'MakerPaymentReceived',
        'MakerPaymentWaitConfirmStarted',
        'MakerPaymentValidatedAndConfirmed',
        'TakerPaymentSent',
      ];

void main() {
  group('Solana atomic lifecycle replay (no chain execution)', () {
    for (final maker in [false, true]) {
      final role = maker ? 'maker' : 'taker';

      test(
        '$role SOL and classic SPL in both directions wait for KDF finality',
        () async {
          for (final asset in [_sol, _spl]) {
            for (final receiveSolana in [false, true]) {
              final sold = receiveSolana ? _marty : asset;
              final bought = receiveSolana ? asset : _marty;
              final spent = maker ? 'TakerPaymentSpent' : 'MakerPaymentSpent';
              final payment = maker ? 'MakerPaymentSent' : 'TakerPaymentSent';
              final confirming = maker
                  ? 'TakerPaymentSpendConfirmStarted'
                  : 'MakerPaymentSpendConfirmStarted';
              final confirmed = maker
                  ? 'TakerPaymentSpendConfirmed'
                  : 'MakerPaymentSpendConfirmed';
              await _withRig((rig) {
                var events = [..._paid(maker), spent, confirming];
                void publish() {
                  rig.dex.swaps['sol-finality'] = atomicSwapOf(
                    'sol-finality',
                    events,
                    maker: maker,
                    sell: sold.id,
                    buy: bought.id,
                    txHashes: {
                      payment: receiveSolana ? 'utxo-payment' : _signature,
                      spent: receiveSolana ? _signature : 'utxo-spend',
                    },
                  );
                }

                publish();
                rig.resume('sol-finality');
                rig.firstPoll();
                rig.polls(4);
                expect(rig.latest.isTerminal, isFalse);
                expect(rig.latest.fundsMovement, SwapFundsMovement.sent);
                expect(rig.latest.from, sold);
                expect(rig.latest.to, bought);
                expect(rig.latest.canCancel, isFalse);

                // Neither elapsed time nor an observed spend is finality. The
                // v1 engine drives confirmation and Finished; no block counter
                // or local timer is substituted for those events.
                events = [...events, confirmed];
                publish();
                rig.polls();
                expect(rig.latest.isTerminal, isFalse);
                events = [...events, 'Finished'];
                publish();
                rig.polls();
                expect(rig.latest.outcome!.kind, SwapOutcomeKind.completed);
                expect(rig.latest.outcome!.receivedAsset, bought);
                expect(
                  receiveSolana
                      ? rig.latest.evidence.destinationTxHash
                      : rig.latest.evidence.sourceTxHash,
                  _signature,
                );
                expect(rig.dex.sells, isEmpty);
                final reads = rig.dex.statusCalls;
                rig.polls(2);
                expect(rig.dex.statusCalls, reads);
              });
            }
          }
        },
      );

      test('$role SOL and classic SPL refunds return the sold asset', () async {
        for (final asset in [_sol, _spl]) {
          await _withRig((rig) {
            final wait = maker
                ? 'MakerPaymentWaitRefundStarted'
                : 'TakerPaymentWaitRefundStarted';
            final refunded = maker
                ? 'MakerPaymentRefunded'
                : 'TakerPaymentRefunded';
            var events = [..._paid(maker), wait];
            void publish() {
              rig.dex.swaps['sol-refund'] = atomicSwapOf(
                'sol-refund',
                events,
                maker: maker,
                sell: asset.id,
                buy: _marty.id,
                data: {
                  'Started': {
                    'maker_payment_lock': 1800000000,
                    'taker_payment_lock': 1800000000,
                  },
                },
              );
            }

            publish();
            rig.resume('sol-refund');
            rig.firstPoll();
            expect(rig.latest.stage, SwapProgressStage.refunding);
            expect(rig.latest.fundsMovement, SwapFundsMovement.sent);
            expect(rig.latest.canCancel, isFalse);
            expect(
              rig.latest.refundUnlocksAt,
              DateTime.fromMillisecondsSinceEpoch(1800000000000),
            );
            events = [...events, refunded, 'Finished'];
            publish();
            rig.polls();
            expect(rig.latest.outcome!.kind, SwapOutcomeKind.refunded);
            expect(rig.latest.outcome!.receivedAsset, asset);
            expect(rig.latest.needsAttention, isFalse);
            expect(rig.dex.sells, isEmpty);
          });
        }
      });
    }

    test(
      'a new executor restores locked SOL/SPL in either role without resubmitting',
      () async {
        for (final maker in [false, true]) {
          for (final asset in [_sol, _spl]) {
            await _withRig((rig) {
              final saved = atomicSwapOf(
                'sol-restart',
                _paid(maker),
                maker: maker,
                sell: asset.id,
                buy: _marty.id,
              );
              rig.dex.swaps[saved.uuid] = saved;
              rig.resume(saved.uuid);
              rig.firstPoll();
              final before = rig.latest;
              unawaited(rig.handle!.close());
              rig.async.flushMicrotasks();

              // Simulate a fresh application executor with the saved engine
              // record, without an accepted quote or in-memory trade handle.
              final restored = _SolanaRig(rig.async);
              restored.dex.swaps[saved.uuid] = saved;
              restored.resume(saved.uuid);
              restored.firstPoll();
              expect(restored.latest.from, asset);
              expect(
                restored.latest.from!.chainId.decimals,
                asset == _sol ? 9 : 6,
              );
              expect(restored.latest.to, _marty);
              expect(restored.latest.fundsMovement, before.fundsMovement);
              expect(restored.latest.canCancel, isFalse);
              expect(restored.latest.isTerminal, isFalse);
              expect(restored.dex.sells, isEmpty);

              // A failed status read after restart proves neither a refund nor
              // that the original payment disappeared.
              restored.dex.statusError = StateError('offline');
              restored.polls(4);
              expect(restored.latest.fundsMovement, SwapFundsMovement.sent);
              expect(restored.latest.isTerminal, isFalse);
              expect(restored.latest.delayedSince, isNotNull);
              expect(restored.dex.sells, isEmpty);
              unawaited(restored.handle!.close());
              rig.async.flushMicrotasks();
            });
          }
        }
      },
    );

    test(
      'certain local refusal stays rejected, while a lost response stays uncertain',
      () async {
        await _withRig((rig) {
          rig.dex.sellError = TradePreflightRejected(
            StateError('funding unavailable'),
          );
          rig.start();
          expect(rig.error, isA<SwapStartRejectedException>());
          rig.dex.sellError = StateError('network response lost');
          rig.start();
          expect(rig.error, isA<SwapStartUnconfirmedException>());
        });
      },
    );

    test(
      'disabled new Solana trading preserves cancellation of a restored order',
      () async {
        final transport = _RecoveryTransport();
        final catalog = {
          _sol.id: Asset(
            id: _sol,
            protocol: SolanaProtocol.fromJson({
              'is_testnet': true,
              'nodes': [
                {'url': 'https://api.devnet.solana.com'},
              ],
            }),
            isWalletOnly: false,
            signMessagePrefix: null,
          ),
          _marty.id: Asset(
            id: _marty,
            protocol: UtxoProtocol.fromJson({
              'is_testnet': true,
            }, subClass: CoinSubClass.utxo),
            isWalletOnly: false,
            signMessagePrefix: null,
          ),
        };
        var capabilities = const SolanaCapabilities(
          enabled: true,
          devnetTradingEnabled: true,
        );
        final policy = TradingAssetPolicy(
          assetOf: (ticker) => catalog[ticker],
          solanaCapabilities: () => capabilities,
        );
        expect(policy.allowsPair(_sol.id, _marty.id), isTrue);
        capabilities = const SolanaCapabilities();
        expect(policy.allowsPair(_sol.id, _marty.id), isFalse);
        final api = Mm2Api(
          mm2: MM2(),
          sdk: _UnusedSdk(),
          tradingPolicy: policy,
          tradingTransport: transport.call,
        );
        addTearDown(api.dispose);
        await expectLater(
          api.sellOrThrow(
            SellRequest(
              base: _sol.id,
              rel: _marty.id,
              volume: Rational.one,
              price: Rational.one,
              orderType: SellBuyOrderType.fillOrKill,
            ),
          ),
          throwsA(isA<TradePreflightRejected>()),
        );
        expect(transport.methods, isEmpty);
        await _withRig((rig) {
          rig.orders.takers['sol-existing-order'] =
              TakerOrderCancellationReason.none;
          rig.resume('sol-existing-order');
          rig.firstPoll();
          expect(rig.latest.canCancel, isTrue);
          unawaited(rig.handle!.cancel());
          rig.async.flushMicrotasks();
          expect(rig.orders.cancelled, ['sol-existing-order']);
          expect(rig.dex.sells, isEmpty);
        });
      },
    );
  });
}

class _UnusedSdk extends Fake implements KomodoDefiSdk {}

class _RecoveryTransport {
  final methods = <String>[];

  Future<Map<String, dynamic>> call(dynamic request) async {
    final method = request.method as String;
    methods.add(method);
    return {
      'result': method == 'recover_funds_of_swap'
          ? {
              'action': 'RefundedMyPayment',
              'coin': _sol.id,
              'tx_hash': _signature,
              'tx_hex': '00',
            }
          : <String, dynamic>{},
    };
  }
}
