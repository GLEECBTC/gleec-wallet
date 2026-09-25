import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/shared/swap/swap_history_repository.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';
import 'package:web_dex/shared/swap/swap_services.dart';

import 'swap_src_sdk_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers the app-wide half of [SwapServices]: requests to the Swap surface,
/// following the signed-in wallet's swaps across sign-in, sign-out and
/// restarts, Activity's atomic history, and the quote repository's wiring.
void main() {
  late SrcSdk sdk;
  late SrcCoinsRepo coins;
  late SrcDex dex;
  late SrcMm2Api mm2;
  late SwapServices services;

  setUp(() {
    sdk = SrcSdk();
    coins = SrcCoinsRepo();
    dex = SrcDex();
    mm2 = SrcMm2Api();
    for (final id in [eth, usdc, btc]) {
      sdk.assets.add(assetFor(id));
    }
    services = servicesOf(sdk, coins: coins, dex: dex, mm2: mm2);
  });

  tearDown(() => services.dispose());

  Future<void> signIn(KdfUser? user) async {
    sdk.auth.users.add(user);
    await pumpEventQueue();
  }

  List<String> followed() => [for (final s in services.registry.current) s.id];

  group('asking the Swap surface', () {
    const intent = (pay: 'ETH', receive: 'USDC-ERC20', amount: '1');
    const ref = (id: 'swap-1', source: SwapLiquiditySource.routed);

    test(
      'an intent reaches the surface, and waits for one not mounted',
      () async {
        final seen = <SwapIntent>[];
        final subscription = services.intents.listen(seen.add);

        services.requestIntent(intent);
        await pumpEventQueue();

        expect(seen, [intent]);
        expect(services.takePendingIntent(), intent);
        expect(services.takePendingIntent(), isNull);
        await subscription.cancel();
      },
    );

    test('a request to show a swap does the same', () async {
      final seen = <({String id, SwapLiquiditySource source})>[];
      final subscription = services.openRequests.listen(seen.add);

      services.requestOpen(ref);
      await pumpEventQueue();

      expect(seen, [ref]);
      expect(services.takePendingOpen(), ref);
      expect(services.takePendingOpen(), isNull);
      await subscription.cancel();
    });

    test('after dispose, requests are kept but no longer announced', () async {
      await services.dispose();

      services
        ..requestIntent(intent)
        ..requestOpen(ref);

      expect(services.takePendingIntent(), intent);
      expect(services.takePendingOpen(), ref);
      await expectLater(services.intents, emitsDone);
      await expectLater(services.openRequests, emitsDone);
    });
  });

  group('the signed-in wallet', () {
    setUp(() {
      sdk.routedSwaps
        ..inFlightIds = ['r-1']
        ..watchable = {'r-1', 'r-2'};
    });

    test('signing in picks up the wallet\'s running swaps', () async {
      await signIn(userOf('alice'));

      expect(sdk.routedSwaps.inFlightCalls, 1);
      expect(followed(), ['r-1']);
    });

    test('the same wallet signing in again changes nothing', () async {
      await signIn(userOf('alice'));
      await signIn(userOf('alice'));

      expect(sdk.routedSwaps.inFlightCalls, 1);
      expect(followed(), ['r-1']);
    });

    test('signing out forgets the swaps; signing in resumes them', () async {
      await signIn(userOf('alice'));
      await signIn(null);

      expect(followed(), isEmpty);

      await signIn(userOf('alice'));
      expect(sdk.routedSwaps.inFlightCalls, 2);
      expect(followed(), ['r-1']);
    });

    test('another wallet never sees the first one\'s swaps', () async {
      await signIn(userOf('alice'));
      sdk.routedSwaps.inFlightIds = ['r-2'];

      await signIn(userOf('bob'));

      expect(sdk.routedSwaps.inFlightCalls, 2);
      expect(followed(), ['r-2']);
    });

    test('an error from sign-in is ignored', () async {
      sdk.auth.users.addError(StateError('auth failed'));
      await signIn(userOf('alice'));

      expect(followed(), ['r-1']);
    });

    test('preferences use the signed-in wallet, else ask the SDK', () async {
      await services.preferences.lastPair();
      expect(sdk.auth.currentUserReads, 1);

      await signIn(userOf('alice'));
      await services.preferences.recentAssets();
      await services.terms.hasAccepted();

      expect(sdk.auth.currentUserReads, 1);
    });

    test('after dispose, signing in follows nothing', () async {
      await services.dispose();

      await signIn(userOf('alice'));

      expect(sdk.routedSwaps.inFlightCalls, 0);
      expect(followed(), isEmpty);
    });
  });

  group('resuming after a restart', () {
    test('resumes running atomic swaps of the last week only', () async {
      final now = DateTime.now();
      mm2.page = recentSwapsOf([
        atomicSwapOf('running', [
          'Started',
          'Negotiated',
        ], lastAt: now.subtract(const Duration(days: 1))),
        atomicSwapOf('finished', ['Started', 'Negotiated', 'Finished']),
        atomicSwapOf('failed', ['Started', 'NegotiateFailed', 'Finished']),
        atomicSwapOf('abandoned', [
          'Started',
        ], lastAt: now.subtract(const Duration(days: 8))),
        atomicSwapOf('empty', const []),
      ]);
      sdk.routedSwaps.inFlightIds = ['routed-1'];

      await signIn(userOf('alice'));

      expect(dex.statusReads, ['running']);
      expect(sdk.routedSwaps.watched, ['routed-1']);
      expect(mm2.requests.single.limit, 50);
      expect(mm2.requests.single.pageNumber, 1);
    });

    test('a routed outage does not stop atomic swaps resuming', () async {
      sdk.routedSwaps.inFlightError = StateError('routed history down');
      mm2.page = recentSwapsOf([
        atomicSwapOf('running', ['Started']),
      ]);

      await signIn(userOf('alice'));

      expect(dex.statusReads, ['running']);
    });

    test('an atomic outage does not stop routed swaps resuming', () async {
      mm2.page = null;
      sdk.routedSwaps.inFlightIds = ['routed-1'];

      await signIn(userOf('alice'));

      expect(sdk.routedSwaps.watched, ['routed-1']);
      expect(dex.statusReads, isEmpty);
    });
  });

  group('Activity', () {
    test('reads the recent-swaps list a page at a time', () async {
      mm2.page = recentSwapsOf([
        atomicSwapOf('running', ['Started']),
      ], pages: 3);

      final page = await services.history.load(
        filter: SwapActivityFilter.active,
      );

      expect(page.entries.map((e) => e.id), ['running']);
      expect(page.hasMore, isTrue);
      expect(page.failedSources, isEmpty);
      expect(mm2.requests.single.limit, 25);
      expect(mm2.requests.single.pageNumber, 1);
    });

    test('the last page has nothing more', () async {
      mm2.page = recentSwapsOf(
        [
          atomicSwapOf('running', ['Started']),
        ],
        page: 2,
        pages: 2,
      );

      final page = await services.history.load(
        filter: SwapActivityFilter.active,
      );

      expect(page.hasMore, isFalse);
    });

    test(
      'a list KDF refuses marks the order book\'s history missing',
      () async {
        mm2.page = null;

        final page = await services.history.load(
          filter: SwapActivityFilter.active,
        );

        expect(page.failedSources, {SwapLiquiditySource.atomic});
      },
    );
  });

  group('the quote repository', () {
    final walletOnly = assetOf('WO-ERC20', parent: eth);
    final nft = assetOf('NFT_ETH');

    setUp(() {
      sdk.assets
        ..add(assetFor(walletOnly, walletOnly: true))
        ..add(assetFor(nft));
      coins.activated = {eth, btc, walletOnly};
      sdk.routedSwaps.eligible = {eth};
    });

    test('lists what each source can trade among swappable assets', () async {
      final repo = services.createRepository(
        tradingAllowed: (_, _) => true,
        clockValid: () => true,
      );

      final catalog = await repo.catalog();

      expect(catalog.activated, {eth, btc, walletOnly});
      expect(catalog.of(SwapLiquiditySource.atomic)!.quotable, {eth, btc});
      expect(catalog.of(SwapLiquiditySource.atomic)!.onceActive, {usdc});
      expect(catalog.of(SwapLiquiditySource.routed)!.quotable, {eth});
      expect(catalog.of(SwapLiquiditySource.routed)!.onceActive, {usdc});
      expect(catalog.assets, isNot(contains(nft)));
    });

    test('prices with the wallet\'s addresses and market prices', () async {
      sdk.pubkeys
        ..known[btc] = pubkeysOf(btc, [keyOf('bc1-swap')])
        ..known[eth] = pubkeysOf(eth, [keyOf('0xswap')]);
      sdk.marketData.prices
        ..[btc] = d('60000')
        ..[eth] = d('3000');
      final repo = services.createRepository(
        tradingAllowed: (_, _) => true,
        clockValid: () => true,
      );
      await repo.catalog();

      final result = await repo.quote(
        SwapQuoteRequest(from: btc, to: eth, amount: d('1')),
      );

      final quote = result.options.single;
      expect(quote.source, SwapLiquiditySource.atomic);
      expect(quote.fromAddress, 'bc1-swap');
      expect(quote.toAddress, '0xswap');
      expect(quote.pricing.minimumUsd, d('60000'));
      expect(sdk.routedSwaps.quotes, isEmpty);
      expect(repo.pricing, same(services.pricing));
    });

    test('applies the live trading restriction to both sources', () async {
      final repo = services.createRepository(
        tradingAllowed: (_, _) => false,
        clockValid: () => true,
      );

      final result = await repo.quote(
        SwapQuoteRequest(from: eth, to: usdc, amount: d('1')),
      );

      expect(result.failures.map((f) => (f.source, f.kind)).toSet(), {
        (SwapLiquiditySource.routed, SwapQuoteFailureKind.tradingBlocked),
        (SwapLiquiditySource.atomic, SwapQuoteFailureKind.tradingBlocked),
      });
    });

    test('applies the clock check to the order book only', () async {
      final repo = services.createRepository(
        tradingAllowed: (_, _) => true,
        clockValid: () => false,
      );

      final result = await repo.quote(
        SwapQuoteRequest(from: eth, to: usdc, amount: d('1')),
      );

      expect(result.options.single.source, SwapLiquiditySource.routed);
      expect(result.failures.single.kind, SwapQuoteFailureKind.clockInvalid);
    });
  });
}
