import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';

import 'swap_bloc_fakes.dart';
import 'swap_test_fixtures.dart';

void main() {
  group('background pair preparation', () {
    swapBlocTest('a later failed balance refresh becomes retryable', (h) {
      final bloc = h.open();
      h.unreadableBalances.add(eth);
      bloc.add(const UnifiedSwapBalancesRefreshed());
      h.settle();
      expect(bloc.state.preparationFailedAsset, eth);
      expect(bloc.state.fundingReady, isFalse);
      expect(bloc.state.canReview, isFalse);
      h.unreadableBalances.clear();
      bloc.add(const UnifiedSwapPreparationRetried());
      h.settle();
      expect(bloc.state.canReview, isTrue);
      expect(bloc.state.inputText, '1');
    });

    swapBlocTest('stalled portfolio loading yields an editable default pair', (
      h,
    ) {
      h.holdingsGate = Completer<void>();
      final bloc = h.build()..add(const UnifiedSwapStarted());
      h.elapse(const Duration(milliseconds: 300));
      expect((bloc.state.pay, bloc.state.receive), (eth, usdc));
      expect(bloc.state.loadingAssets, isFalse);
      expect(bloc.state.preparingAssets, isFalse);
      expect(bloc.state.amountMode, SwapAmountMode.fiat);
      bloc.add(const UnifiedSwapAmountChanged('300'));
      h.settle();
      expect(bloc.state.canReview, isTrue);
      h.holdingsGate!.complete();
      h.settle();
      expect(bloc.state.inputText, '300');
    });

    swapBlocTest(
      'a session draft restores its units and obtains a fresh quote',
      (h) {
        final bloc = h.build()
          ..add(const UnifiedSwapStarted())
          ..add(
            const UnifiedSwapDraftRestored(
              pay: 'ETH',
              receive: 'USDC-ERC20',
              input: '300',
              amountMode: SwapAmountMode.fiat,
              slippage: 0.01,
            ),
          );
        h.settle();
        expect(bloc.state.inputText, '300');
        expect(bloc.state.amountMode, SwapAmountMode.fiat);
        expect(bloc.state.slippage, 0.01);
        expect(h.routed.requests.single.amount, d('0.1'));
        expect(bloc.state.review, isNull);
        expect(bloc.state.maxRequested, isFalse);
        expect(h.routedExecutor.started, isEmpty);
      },
    );

    swapBlocTest('an explicit asset-detail intent supersedes a session draft', (
      h,
    ) {
      final bloc = h.build()
        ..add(const UnifiedSwapStarted())
        ..add(
          const UnifiedSwapDraftRestored(
            pay: 'ETH',
            receive: 'USDC-ERC20',
            input: '300',
            amountMode: SwapAmountMode.fiat,
            slippage: 0.01,
          ),
        )
        ..add(
          const UnifiedSwapIntentApplied(
            pay: 'BTC',
            receive: 'ETH',
            amount: '0.25',
          ),
        );
      h.settle();
      expect((bloc.state.pay, bloc.state.receive), (btc, eth));
      expect(bloc.state.inputText, '0.25');
      expect(bloc.state.amountMode, SwapAmountMode.token);
      expect(h.routed.requests.last.from, btc);
    });

    swapBlocTest(
      'selection is immediate and an old activation cannot restore it',
      (h) {
        final activation = Completer<void>();
        h.inactiveAssets.add(btc);
        final bloc = h.open(
          bloc: h.build(
            activateAsset: (asset) async {
              await activation.future;
              h.inactiveAssets.remove(asset);
            },
          ),
        );
        bloc.add(UnifiedSwapReceiveAssetChanged(btc));
        h.settle();
        expect(bloc.state.receive, btc);
        expect(bloc.state.inputText, '1');
        expect(bloc.state.preparingAssets, isTrue);
        expect(bloc.state.receiveAddress, isNull);

        bloc.add(UnifiedSwapReceiveAssetChanged(usdc));
        h.settle();
        expect(bloc.state.fundingReady, isTrue);
        final selected = bloc.state.selectedId;
        activation.complete();
        h.settle();
        expect(bloc.state.receive, usdc);
        expect(bloc.state.selectedId, selected);
        expect(bloc.state.preparationFailedAsset, isNull);
      },
    );

    swapBlocTest(
      'a failed activation can be retried without losing the draft',
      (h) {
        var attempts = 0;
        h.inactiveAssets.add(usdc);
        final bloc = h.open(
          bloc: h.build(
            activateAsset: (asset) async {
              if (++attempts == 1) throw StateError('temporarily unavailable');
              h.inactiveAssets.remove(asset);
            },
          ),
        );
        expect(bloc.state.preparingAssets, isFalse);
        expect(bloc.state.preparationFailedAsset, usdc);
        expect(bloc.state.canReview, isFalse);
        bloc.add(const UnifiedSwapPreparationRetried());
        h.settle();
        expect(bloc.state.inputText, '1');
        expect(bloc.state.preparationFailedAsset, isNull);
        expect(bloc.state.canReview, isTrue);
        expect(attempts, 2);
      },
    );

    swapBlocTest(
      'unknown funds and addresses are retryable, never affordability',
      (h) {
        h.unreadableBalances.add(eth);
        h.unreadableAddresses.add(usdc);
        final bloc = h.open();
        expect(bloc.state.balance, isNull);
        expect(bloc.state.issue, isNull);
        expect(bloc.state.preparationFailedAsset, eth);
        expect(bloc.state.fundingReady, isFalse);
        expect(bloc.state.canReview, isFalse);
        expect(bloc.state.selectedQuote, isNotNull);
        h.unreadableBalances.clear();
        h.unreadableAddresses.clear();
        bloc.add(const UnifiedSwapPreparationRetried());
        h.settle();
        expect(bloc.state.fundingReady, isTrue);
        expect(bloc.state.canReview, isTrue);
        expect(bloc.state.inputText, '1');
      },
    );

    swapBlocTest('balances and both addresses begin independently', (h) {
      final balance = Completer<void>();
      final addresses = Completer<void>();
      final requested = <String>[];
      h.balanceReader = (asset) async {
        requested.add('balance-${asset.id}');
        await balance.future;
        return h.balances[asset];
      };
      h.addressReader = (asset) async {
        requested.add('address-${asset.id}');
        await addresses.future;
        return 'own-${asset.id}';
      };
      final bloc = h.open(pay: 'USDC-ERC20', receive: 'ETH');
      expect(
        requested,
        containsAll([
          'balance-USDC-ERC20',
          'balance-ETH',
          'address-USDC-ERC20',
          'address-ETH',
        ]),
      );
      expect(bloc.state.preparingAssets, isTrue);
      addresses.complete();
      h.settle();
      expect(bloc.state.receiveAddress, 'own-ETH');
      expect(bloc.state.fundingReady, isFalse);
      balance.complete();
      h.settle();
      expect(bloc.state.fundingReady, isTrue);
    });

    swapBlocTest('returning to the same pair discards older reads', (h) {
      final stale = Completer<void>();
      var slow = false;
      h.balanceReader = (asset) async {
        if (slow) {
          await stale.future;
          return d('0');
        }
        return h.balances[asset];
      };
      h.addressReader = (asset) async {
        if (slow) {
          await stale.future;
          return 'stale-${asset.id}';
        }
        return 'current-${asset.id}';
      };
      final bloc = h.open();
      slow = true;
      bloc.add(const UnifiedSwapPreparationRetried());
      h.settle();
      slow = false;
      bloc.add(UnifiedSwapReceiveAssetChanged(btc));
      h.settle();
      bloc.add(UnifiedSwapReceiveAssetChanged(usdc));
      h.settle();
      stale.complete();
      h.settle();
      expect(bloc.state.balance, d('2'));
      expect(bloc.state.payAddress, 'current-ETH');
      expect(bloc.state.receiveAddress, 'current-USDC-ERC20');
      expect(bloc.state.fundingReady, isTrue);
    });

    swapBlocTest(
      'typing while Max pair preparation runs cancels deferred Max',
      (h) {
        h.routed.max = SwapMaxAmount(
          amount: d('1.99'),
          reservedForFees: d('0.01'),
        );
        final bloc = h.open()..add(const UnifiedSwapMaxRequested());
        h.settle();
        final reading = h.balanceGate = Completer<void>();
        bloc.add(UnifiedSwapReceiveAssetChanged(btc));
        h.settle();
        bloc.add(const UnifiedSwapAmountChanged('0.25'));
        h.settle();
        reading.complete();
        h.settle();
        expect(bloc.state.inputText, '0.25');
        expect(h.routed.maxCalls, 1);
        expect(h.routed.requests.last.amount, d('0.25'));
      },
    );

    swapBlocTest(
      'an intent chosen before the catalog resumes after it arrives',
      (h) {
        final catalog = h.catalogGate = Completer<void>();
        final bloc = h.open();
        expect(bloc.state.pay, eth);
        expect(bloc.state.preparingAssets, isTrue);
        catalog.complete();
        h.settle();
        expect(bloc.state.preparingAssets, isFalse);
        expect(bloc.state.canReview, isTrue);
      },
    );

    swapBlocTest(
      'an unknown final balance prevents starting a reviewed quote',
      (h) {
        h.resolve(h.terms.recordAcceptance(at: h.now()));
        final bloc = h.inReview();
        h.unreadableBalances.add(eth);
        bloc.add(const UnifiedSwapStartRequested());
        h.settle();
        expect(bloc.state.review!.status, SwapReviewStatus.revalidationFailed);
        expect(h.routedExecutor.started, isEmpty);
      },
    );
    swapBlocTest('accepting changed terms freshly checks funding again', (h) {
      h.resolve(h.terms.recordAcceptance(at: h.now()));
      final bloc = h.inReview();
      h.routed.requoteResult = SwapQuoteAvailable(
        quoteOf(id: 'updated', guaranteed: '2900'),
      );
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();
      expect(bloc.state.review!.status, SwapReviewStatus.materialUpdate);
      h.unreadableBalances.add(eth);
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();
      expect(bloc.state.review!.status, SwapReviewStatus.revalidationFailed);
      expect(h.routed.requoted, hasLength(2));
      expect(h.routedExecutor.started, isEmpty);
    });
  });
  group('spend precision for dollar input', () {
    swapBlocTest(
      'signed-out previews use metadata without activating or reading funds',
      (h) {
        final native = assetOf('ETH-METADATA', decimals: null);
        h.extraAssets.add(native);
        h.atomic.tradable.add(native);
        h.prices.prices[native] = d('3000');
        var balanceReads = 0;
        var activations = 0;
        h.balanceReader = (_) async {
          balanceReads++;
          return null;
        };
        final bloc =
            h.build(
                spendDecimalsOf: (_) async => 18,
                activateAsset: (_) async {
                  activations++;
                },
              )
              ..add(
                const UnifiedSwapCapabilitiesChanged(
                  tradingEnabled: true,
                  clockValid: true,
                  signedIn: false,
                ),
              )
              ..add(const UnifiedSwapStarted())
              ..add(
                UnifiedSwapIntentApplied(
                  pay: native.id,
                  receive: 'USDC-ERC20',
                  amount: '300',
                  amountMode: SwapAmountMode.fiat,
                ),
              );
        h.settle();
        expect(bloc.amountOf(bloc.state), d('0.1'));
        expect(h.atomic.requests.single.amount, d('0.1'));
        expect(h.routed.requests, isEmpty);
        expect(balanceReads, 0);
        expect(activations, 0);
        expect(bloc.state.canReview, isFalse);
      },
    );

    swapBlocTest(
      'resolves missing token precision before either source quotes',
      (h) {
        final token = _tokenWithoutDecimals(h);
        final precision = Completer<int?>();
        final bloc = h.build(spendDecimalsOf: (_) => precision.future)
          ..add(const UnifiedSwapStarted())
          ..add(
            UnifiedSwapIntentApplied(
              pay: token.id,
              receive: 'ETH',
              amount: '10',
              amountMode: SwapAmountMode.fiat,
            ),
          );
        h.settle();
        expect(bloc.state.preparingAssets, isTrue);
        expect(h.routed.requests, isEmpty);
        expect(h.atomic.requests, isEmpty);
        expect(bloc.amountOf(bloc.state), isNull);
        precision.complete(6);
        h.settle();
        final expected = d('10.002300');
        expect(bloc.state.preparingAssets, isFalse);
        expect(bloc.state.converted!.amount, expected);
        expect(bloc.amountOf(bloc.state), expected);
        expect(h.routed.requests.single.amount, expected);
        expect(h.atomic.requests.single.amount, expected);
        expect(bloc.state.inputText, '10');
        expect(bloc.state.canReview, isTrue);
      },
    );

    swapBlocTest(
      'resolved principal survives new fiat prices, toggles and final requote',
      (h) {
        final token = _tokenWithoutDecimals(h);
        h.resolve(h.terms.recordAcceptance(at: h.now()));
        final bloc = h.build(spendDecimalsOf: (_) async => 6)
          ..add(const UnifiedSwapStarted())
          ..add(
            UnifiedSwapIntentApplied(
              pay: token.id,
              receive: 'ETH',
              amount: '10',
              amountMode: SwapAmountMode.fiat,
            ),
          );
        h.settle();
        final principal = d('10.002300');
        h.prices.prices[token] = d('1.01');
        expect(bloc.amountOf(bloc.state), principal);
        bloc.add(const UnifiedSwapAmountModeToggled());
        h.settle();
        expect(bloc.state.inputText, principal.toString());
        expect(bloc.state.amountMode, SwapAmountMode.token);
        bloc.add(const UnifiedSwapAmountModeToggled());
        h.settle();
        expect(bloc.state.amountMode, SwapAmountMode.fiat);
        expect(bloc.amountOf(bloc.state), principal);
        // Even an old conversion snapshot cannot bypass resolved token units.
        expect(
          bloc.amountOf(
            bloc.state.copyWith(
              converted: (
                asset: token,
                text: bloc.state.inputText,
                amount: d('10.00230052912169799'),
              ),
            ),
          ),
          principal,
        );
        bloc.add(const UnifiedSwapReviewOpened());
        h.settle();
        expect(bloc.state.review!.quote.sellAmount, principal);
        bloc.add(const UnifiedSwapStartRequested());
        h.settle();
        expect(h.routed.requoted.single.sellAmount, principal);
        expect(h.routedExecutor.started.single.sellAmount, principal);
      },
    );

    swapBlocTest('eighteen-decimal tokens retain their actual precision', (h) {
      final token = _tokenWithoutDecimals(h);
      h.prices.prices[token] = d('3');
      final bloc = h.build(spendDecimalsOf: (_) async => 18)
        ..add(const UnifiedSwapStarted())
        ..add(
          UnifiedSwapIntentApplied(
            pay: token.id,
            receive: 'ETH',
            amount: '1',
            amountMode: SwapAmountMode.fiat,
          ),
        );
      h.settle();
      expect(bloc.amountOf(bloc.state), d('0.333333333333333333'));
      expect(h.routed.requests.single.amount, d('0.333333333333333333'));
    });

    swapBlocTest('a dollar amount below one base unit is not quoted', (h) {
      final token = _tokenWithoutDecimals(h);
      h.prices.prices[token] = d('1');
      final bloc = h.build(spendDecimalsOf: (_) async => 6)
        ..add(const UnifiedSwapStarted())
        ..add(
          UnifiedSwapIntentApplied(
            pay: token.id,
            receive: 'ETH',
            amount: '0.0000001',
            amountMode: SwapAmountMode.fiat,
          ),
        );
      h.settle();
      expect(bloc.amountOf(bloc.state), d('0'));
      expect(bloc.state.issue, SwapFormIssue.amountZero);
      expect(bloc.state.evaluation, SwapEvaluationStatus.idle);
      expect(h.routed.requests, isEmpty);
      expect(bloc.state.canReview, isFalse);
    });

    swapBlocTest('missing metadata is retryable and cannot fabricate a quote', (
      h,
    ) {
      final token = _tokenWithoutDecimals(h);
      var available = false;
      final bloc = h.build(spendDecimalsOf: (_) async => available ? 6 : null)
        ..add(const UnifiedSwapStarted())
        ..add(
          UnifiedSwapIntentApplied(
            pay: token.id,
            receive: 'ETH',
            amount: '10',
            amountMode: SwapAmountMode.fiat,
          ),
        );
      h.settle();
      expect(bloc.state.inputText, '10');
      expect(bloc.state.preparationFailedAsset, token);
      expect(bloc.state.issue, SwapFormIssue.fiatUnavailable);
      expect(bloc.state.canReview, isFalse);
      expect(h.routed.requests, isEmpty);
      bloc.add(const UnifiedSwapBalancesRefreshed());
      h.settle();
      expect(bloc.state.preparationFailedAsset, token);
      available = true;
      bloc.add(const UnifiedSwapPreparationRetried());
      h.settle();
      expect(bloc.state.inputText, '10');
      expect(bloc.state.preparationFailedAsset, isNull);
      expect(h.routed.requests.single.amount, d('10.002300'));
    });

    swapBlocTest(
      'an earlier pair precision response cannot replace the new one',
      (h) {
        final token = _tokenWithoutDecimals(h);
        final other = _tokenWithoutDecimals(h, ticker: 'OTHER-ERC20');
        h.prices.prices[other] = d('3');
        final stale = Completer<int?>();
        final bloc =
            h.build(
                spendDecimalsOf: (asset) =>
                    asset == token ? stale.future : Future.value(18),
              )
              ..add(const UnifiedSwapStarted())
              ..add(
                UnifiedSwapIntentApplied(
                  pay: token.id,
                  receive: 'ETH',
                  amount: '10',
                  amountMode: SwapAmountMode.fiat,
                ),
              );
        h.settle();
        bloc.add(
          UnifiedSwapIntentApplied(
            pay: other.id,
            receive: 'ETH',
            amount: '1',
            amountMode: SwapAmountMode.fiat,
          ),
        );
        h.settle();
        stale.complete(6);
        h.settle();
        expect(bloc.state.pay, other);
        expect(bloc.state.inputText, '1');
        expect(bloc.amountOf(bloc.state), d('0.333333333333333333'));
        expect(h.routed.requests.every((r) => r.from == other), isTrue);
      },
    );

    swapBlocTest(
      'a signed-out precision response cannot enter the next session',
      (h) {
        final token = _tokenWithoutDecimals(h);
        final stale = Completer<int?>();
        var reads = 0;
        final bloc =
            h.build(
                spendDecimalsOf: (_) =>
                    ++reads == 1 ? stale.future : Future.value(6),
              )
              ..add(const UnifiedSwapStarted())
              ..add(
                UnifiedSwapIntentApplied(
                  pay: token.id,
                  receive: 'ETH',
                  amount: '10',
                  amountMode: SwapAmountMode.fiat,
                ),
              );
        h.settle();
        bloc.add(
          const UnifiedSwapCapabilitiesChanged(
            tradingEnabled: true,
            clockValid: true,
            signedIn: false,
          ),
        );
        h.settle();
        bloc.add(
          const UnifiedSwapCapabilitiesChanged(
            tradingEnabled: true,
            clockValid: true,
            signedIn: true,
          ),
        );
        h.settle();
        stale.complete(18);
        h.settle();
        bloc.add(const UnifiedSwapAmountChanged('11'));
        h.settle();
        expect(bloc.state.signedIn, isTrue);
        expect(bloc.state.preparationFailedAsset, isNull);
        expect(h.routed.requests.last.amount, d('11.002530'));
      },
    );
  });
}

AssetId _tokenWithoutDecimals(
  SwapBlocHarness h, {
  String ticker = 'USD6-ERC20',
}) {
  final token = assetOf(ticker, parent: eth, decimals: null);
  h.extraAssets.add(token);
  h.routed.tradable.add(token);
  h.atomic.tradable.add(token);
  h.balances[token] = d('100');
  h.prices.prices[token] = d('0.99977');
  return token;
}
