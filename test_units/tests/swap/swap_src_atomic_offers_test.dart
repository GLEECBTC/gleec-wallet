// The analyzer does not treat test_units as tests, so @visibleForTesting
// members read as violations here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/shared/swap/atomic_swap_source.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/shared/swap/swap_order_book_offers.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';

import 'swap_src_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers what the order book says about its offers: why an amount misses,
/// how far Max may go, and which assets anyone trades.
void main() {
  final kmd = assetOf('KMD', subClass: CoinSubClass.utxo, chainId: 0);
  final avn = assetOf('AVN', subClass: CoinSubClass.utxo, chainId: 0);
  late SrcTrading trading;

  setUp(() => trading = SrcTrading());

  AtomicSwapQuoteSource source({bool Function(AssetId asset)? isWalletOnly}) =>
      AtomicSwapQuoteSource(
        trading: trading,
        networks: () => SwapNetworks([eth, btc]),
        isWalletOnly: isWalletOnly,
      );

  Future<SwapQuoteFailure> miss(String amount) async {
    final result = (await source().quote(
      SwapQuoteRequest(from: btc, to: eth, amount: d(amount)),
    )).single;
    return (result as SwapQuoteRejected).failure;
  }

  group('an amount no order takes', () {
    test('an empty book is no offers', () async {
      trading.bids = [];

      final reason = await miss('1');

      expect(reason.kind, SwapQuoteFailureKind.noRoute);
      expect(reason.offers, const SwapOrderBookOffers());
      expect(trading.preimages, isEmpty);
    });

    test('a book of only the wallet\'s own orders is no offers', () async {
      trading.bids = [bidOf('20', '0.01', '5', mine: true)];

      final reason = await miss('1');

      expect(reason.kind, SwapQuoteFailureKind.noRoute);
      expect(reason.offers!.isEmpty, isTrue);
    });

    test('more than every order is above the largest offer', () async {
      trading.bids = [bidOf('20', '0.1', '2'), bidOf('19', '1', '4')];

      final reason = await miss('5');

      expect(reason.kind, SwapQuoteFailureKind.aboveMaximum);
      expect(reason.maximum, d('4'));
      expect(reason.offers!.maximum, d('4'));
    });

    test('less than every order is below the smallest offer', () async {
      trading.bids = [bidOf('20', '0.5', '2')];

      final reason = await miss('0.1');

      expect(reason.kind, SwapQuoteFailureKind.belowMinimum);
      expect(reason.minimum, d('0.5'));
    });

    test('an amount between orders names the ones around it', () async {
      trading.bids = [bidOf('20', '0.01', '0.5'), bidOf('19', '2', '5')];

      final reason = await miss('1');

      expect(reason.kind, SwapQuoteFailureKind.noRoute);
      expect(reason.offers!.largestUpTo(d('1')), d('0.5'));
      expect(reason.offers!.smallestFrom(d('1')), d('2'));
    });
  });

  test('the wallet\'s own order is never the one priced against', () {
    final best = AtomicSwapQuoteSource.bestFillingBid([
      bidOf('30', '0', '5', mine: true),
      bidOf('20', '0', '5'),
    ], d('1'));

    expect(best, (price: d('20'), maxVolume: d('5')));
  });

  group('Max', () {
    test('stops at the largest offer the wallet can fill', () async {
      trading
        ..maxTaker = '10'
        ..bids = [bidOf('20', '0.1', '2'), bidOf('19', '6', '8')];

      final max = await source().maxAmount(from: btc, to: eth, balance: d('4'));

      expect(max!.amount, d('2'));
      expect(max.offerLimit, isTrue);
      expect(max.reservedForFees, d('0'));
    });

    test('keeps what KDF allows when an offer takes it all', () async {
      trading
        ..maxTaker = '3'
        ..bids = [bidOf('20', '0.1', '5')];

      final max = await source().maxAmount(from: btc, to: eth, balance: d('4'));

      expect(max!.amount, d('3'));
      expect(max.offerLimit, isFalse);
      expect(max.reservedForFees, d('1'));
    });

    test('with no offer to fill, still shows what could be sold', () async {
      trading
        ..maxTaker = '3'
        ..bids = [];
      final none = await source().maxAmount(
        from: btc,
        to: eth,
        balance: d('4'),
      );
      trading.bookError = StateError('orderbook offline');
      final unread = await source().maxAmount(
        from: btc,
        to: eth,
        balance: d('4'),
      );

      expect(none!.amount, d('3'));
      expect(none.offerLimit, isFalse);
      expect(unread!.amount, d('3'));
    });
  });

  group('offers for a pair', () {
    test('are read from the pair\'s book above the coin minimum', () async {
      trading
        ..minimum = '0.5'
        ..bids = [bidOf('20', '0.1', '2')];

      final offers = await source().offers(btc, eth);

      expect(offers!.bands, [SwapOfferBand(d('0.5'), d('2'))]);
      expect(trading.books.single, (base: 'BTC', rel: 'ETH'));
    });

    test('are unknown when the book cannot be read or traded', () async {
      trading.bookError = StateError('orderbook offline');

      expect(await source().offers(btc, eth), isNull);
      expect(
        await source(isWalletOnly: (a) => a == eth).offers(btc, eth),
        isNull,
      );
    });
  });

  group('which assets anyone trades', () {
    test('paying the anchor asks for orders selling each candidate', () async {
      trading.depths = {('KMD', 'AVN'): 0, ('KMD', 'BTC'): 3};

      final offered = await source().offered(kmd, [avn, btc], anchorPays: true);

      expect(offered, {avn: false, btc: true});
      expect(trading.depthCalls.single.map((p) => (p.base, p.rel)), [
        ('KMD', 'AVN'),
        ('KMD', 'BTC'),
      ]);
    });

    test('receiving the anchor asks for orders selling it', () async {
      trading.depths = {('BTC', 'AVN'): 2};

      final offered = await source().offered(avn, [
        btc,
        kmd,
      ], anchorPays: false);

      expect(offered, {btc: true, kmd: false});
      expect(trading.depthCalls.single.map((p) => (p.base, p.rel)), [
        ('BTC', 'AVN'),
        ('KMD', 'AVN'),
      ]);
    });

    test('never asks about a wallet-only coin or the anchor itself', () async {
      final offered = await source(
        isWalletOnly: (a) => a == gleec,
      ).offered(kmd, [kmd, gleec, btc], anchorPays: true);

      expect(offered!.keys, [btc]);
      expect(trading.depthCalls.single.map((p) => p.rel), ['BTC']);
    });

    test('an anchor the order book cannot trade is unknown', () async {
      final offered = await source(
        isWalletOnly: (a) => a == kmd,
      ).offered(kmd, [btc], anchorPays: true);

      expect(offered, isNull);
      expect(trading.depthCalls, isEmpty);
    });

    test('pairs KDF adds or leaves out are not guessed at', () async {
      trading
        ..depths = {('KMD', 'BTC'): 1}
        ..unansweredDepths = {('KMD', 'AVN')}
        ..extraDepths = [
          const OrderbookPairDepth(base: 'KMD', rel: 'ETH', asks: 0, bids: 9),
        ];

      final offered = await source().offered(kmd, [avn, btc], anchorPays: true);

      expect(offered, {btc: true});
    });

    test(
      'many candidates are asked in batches; a lost batch is unknown',
      () async {
        final candidates = [
          for (var i = 0; i < AtomicSwapQuoteSource.offeredBatch + 1; i++)
            assetOf('C$i', subClass: CoinSubClass.utxo, chainId: 0),
        ];
        trading.failingDepthCalls = {1};

        final offered = await source().offered(
          kmd,
          candidates,
          anchorPays: true,
        );

        expect(trading.depthCalls.map((call) => call.length), [
          AtomicSwapQuoteSource.offeredBatch,
          1,
        ]);
        expect(offered!.length, AtomicSwapQuoteSource.offeredBatch);
        expect(offered.containsKey(candidates.last), isFalse);
      },
    );

    test('nothing answering at all is unknown', () async {
      trading.depthError = StateError('No response from any peer');

      expect(await source().offered(kmd, [btc], anchorPays: true), isNull);
    });
  });
}
