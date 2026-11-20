import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/shared/swap/swap_pricing.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';
import 'package:web_dex/shared/swap/unified_swap_repository.dart';

import 'swap_test_fixtures.dart';

/// Independent quote arrivals must not compromise Max, freshness, or wallet
/// boundaries. These tests hold dependencies open rather than measure a timer
/// race between otherwise immediate fake services.
void main() {
  final request = SwapQuoteRequest(from: eth, to: usdc, amount: d('1'));

  UnifiedSwapRepository repository(
    List<SwapQuoteSource> sources, {
    SwapPriceSource? prices,
  }) => UnifiedSwapRepository(
    sources: sources,
    pricing: SwapPricingService(
      prices ?? FakePriceSource({eth: d('3000'), usdc: d('1')}),
    ),
  );

  test(
    'a usable source arrives before another source and fiat prices',
    () async {
      final pending = Completer<void>();
      final prices = _HeldPrices();
      final atomic = FakeQuoteSource(
        SwapLiquiditySource.atomic,
        results: [
          SwapQuoteAvailable(
            quoteOf(id: 'first', source: SwapLiquiditySource.atomic),
          ),
        ],
      );
      final routed = FakeQuoteSource(
        SwapLiquiditySource.routed,
        results: [SwapQuoteAvailable(quoteOf(id: 'later'))],
      )..gate = pending;
      final updates = <SwapQuoteUpdate>[];
      final first = Completer<SwapQuoteUpdate>();
      final done = Completer<void>();
      repository([atomic, routed], prices: prices).watchQuotes(request).listen((
        u,
      ) {
        updates.add(u);
        if (!u.quotes.isEmpty && !first.isCompleted) first.complete(u);
      }, onDone: done.complete);

      final available = await first.future;
      expect(atomic.requests, hasLength(1));
      expect(routed.requests, hasLength(1));
      expect(available.quotes.options.single.id, 'first');
      expect(available.pendingSources, {SwapLiquiditySource.routed});
      expect(available.sourcesComplete, isFalse);
      expect(available.pricingComplete, isFalse);
      expect(available.quotes.options.single.pricing.payUsd, isNull);
      expect(available.quotes.comparisonComplete, isFalse);

      prices.prices.addAll({eth: d('3000'), usdc: d('1')});
      prices.gate.complete();
      pending.complete();
      await done.future;

      expect(updates.last.complete, isTrue);
      expect(
        updates.last.quotes.options.map((q) => q.id),
        containsAll(['first', 'later']),
      );
      expect(
        updates.last.quotes.options.every((q) => q.pricing.payUsd != null),
        isTrue,
      );
    },
  );

  test('a timed-out source does not remove an already usable quote', () async {
    final hanging = FakeQuoteSource(SwapLiquiditySource.routed)
      ..gate = Completer<void>();
    final atomic = FakeQuoteSource(
      SwapLiquiditySource.atomic,
      results: [
        SwapQuoteAvailable(quoteOf(source: SwapLiquiditySource.atomic)),
      ],
    );
    final updates = await repository([hanging, atomic])
        .watchQuotes(request, timeout: const Duration(milliseconds: 30))
        .toList();

    expect(updates.any((u) => !u.quotes.isEmpty && !u.sourcesComplete), isTrue);
    final last = updates.last;
    expect(last.complete, isTrue);
    expect(last.quotes.options.single.source, SwapLiquiditySource.atomic);
    expect(last.quotes.failures.single.source, SwapLiquiditySource.routed);
    expect(last.quotes.failures.single.kind, SwapQuoteFailureKind.timeout);
    expect(
      last.sources[SwapLiquiditySource.routed],
      SwapQuoteSourceStatus.unavailable,
    );
    hanging.gate!.complete();
  });

  test('price enrichment is bounded and remains explicitly unpriced', () async {
    final prices = _HeldPrices();
    final routed = FakeQuoteSource(
      SwapLiquiditySource.routed,
      results: [SwapQuoteAvailable(quoteOf())],
    );
    final updates = await repository([routed], prices: prices)
        .watchQuotes(request, pricingTimeout: const Duration(milliseconds: 20))
        .toList();

    expect(updates.any((u) => u.sourcesComplete && !u.pricingComplete), isTrue);
    expect(updates.last.complete, isTrue);
    expect(updates.last.quotes.unrankable, hasLength(1));
    expect(updates.last.quotes.options.single.pricing.payUsd, isNull);
    prices.gate.complete();
  });

  test(
    'collecting API waits for newly discovered fee currency enrichment',
    () async {
      final prices = _FeePrices();
      final routed = FakeQuoteSource(
        SwapLiquiditySource.routed,
        results: [
          SwapQuoteAvailable(
            quoteOf(
              fees: [
                SwapFeeComponent(
                  kind: SwapFeeKind.network,
                  amount: d('0.001'),
                  deductedFromReceive: false,
                  asset: btc,
                ),
              ],
            ),
          ),
        ],
      );
      final repo = repository([routed], prices: prices);
      var completed = false;
      final result = repo.quote(request).then((value) {
        completed = true;
        return value;
      });
      await prices.requested.future;
      expect(completed, isFalse);
      prices.prices[btc] = d('50000');
      prices.gate.complete();

      expect((await result).options.single.pricing.networkCostUsd, d('50'));
    },
  );

  test(
    'Max publishes its own snapshot then compares its concrete amount',
    () async {
      final maximum = Completer<void>();
      final routed = FakeQuoteSource(
        SwapLiquiditySource.routed,
        results: [SwapQuoteAvailable(quoteOf(id: 'max', sell: '0.96'))],
      )..gate = maximum;
      final atomic = FakeQuoteSource(
        SwapLiquiditySource.atomic,
        respond: (r) => [
          SwapQuoteAvailable(
            quoteOf(
              id: 'comparison',
              source: SwapLiquiditySource.atomic,
              sell: r.amount.toString(),
            ),
          ),
        ],
      );
      final started = Completer<void>();
      final updates = <SwapQuoteUpdate>[];
      final done = Completer<void>();
      repository([routed, atomic])
          .watchQuotes(
            SwapQuoteRequest(
              from: eth,
              to: usdc,
              amount: d('1'),
              maxSource: SwapLiquiditySource.routed,
            ),
          )
          .listen((u) {
            updates.add(u);
            if (!started.isCompleted) started.complete();
          }, onDone: done.complete);
      await started.future;
      expect(atomic.requests, isEmpty);
      maximum.complete();
      await done.future;

      expect(atomic.requests.single.amount, d('0.96'));
      expect(atomic.requests.single.maxSource, isNull);
      final firstQuote = updates.firstWhere((u) => !u.quotes.isEmpty);
      expect(firstQuote.quotes.options.single.id, 'max');
      expect(firstQuote.pendingSources, {SwapLiquiditySource.atomic});
      expect(
        updates.last.quotes.options.every((q) => q.sellAmount == d('0.96')),
        isTrue,
      );
    },
  );

  test(
    'failed Max never asks alternatives with a provisional balance',
    () async {
      final routed = FakeQuoteSource(
        SwapLiquiditySource.routed,
        results: [rejected(SwapQuoteFailureKind.insufficientFunds)],
      );
      final atomic = FakeQuoteSource(SwapLiquiditySource.atomic);
      final last = await repository([routed, atomic])
          .watchQuotes(
            SwapQuoteRequest(
              from: eth,
              to: usdc,
              amount: d('1'),
              maxSource: SwapLiquiditySource.routed,
            ),
          )
          .last;

      expect(last.complete, isTrue);
      expect(last.quotes.isEmpty, isTrue);
      expect(
        last.quotes.failures.single.kind,
        SwapQuoteFailureKind.insufficientFunds,
      );
      expect(atomic.requests, isEmpty);
    },
  );

  test(
    'only identical in-flight previews in an explicit scope share work',
    () async {
      final gate = Completer<void>();
      final routed = FakeQuoteSource(
        SwapLiquiditySource.routed,
        results: [SwapQuoteAvailable(quoteOf())],
      )..gate = gate;
      final repo = repository([routed]);
      final sameScope = Object();
      final first = repo.watchQuotes(request, scope: sameScope).last;
      final second = repo.watchQuotes(request, scope: sameScope).last;
      final otherWallet = repo.watchQuotes(request, scope: Object()).last;
      final noScope = repo.watchQuotes(request).last;
      await Future<void>.delayed(Duration.zero);
      expect(routed.requests, hasLength(3));

      // Final validation uses its own source method, never a preview result.
      final finalCheck = await repo.requote(quoteOf());
      expect(finalCheck, isA<SwapQuoteAvailable>());
      expect(routed.requoted, hasLength(1));
      gate.complete();
      await Future.wait([first, second, otherWallet, noScope]);

      await repo.watchQuotes(request, scope: sameScope).last;
      expect(routed.requests, hasLength(4));
    },
  );

  test('cancellation discards later source and price arrivals', () async {
    final gate = Completer<void>();
    final source = FakeQuoteSource(
      SwapLiquiditySource.routed,
      results: [SwapQuoteAvailable(quoteOf())],
    )..gate = gate;
    final prices = _HeldPrices();
    final updates = <SwapQuoteUpdate>[];
    final initial = Completer<void>();
    final subscription = repository([source], prices: prices)
        .watchQuotes(request)
        .listen((u) {
          updates.add(u);
          if (!initial.isCompleted) initial.complete();
        });
    await initial.future;
    await subscription.cancel();
    final count = updates.length;
    gate.complete();
    prices.gate.complete();
    await Future<void>.delayed(Duration.zero);
    expect(updates, hasLength(count));
  });

  test(
    'a completed source is not cached behind a pending competitor',
    () async {
      final gate = Completer<void>();
      final routed = FakeQuoteSource(SwapLiquiditySource.routed)..gate = gate;
      final atomic = FakeQuoteSource(
        SwapLiquiditySource.atomic,
        results: [
          SwapQuoteAvailable(quoteOf(source: SwapLiquiditySource.atomic)),
        ],
      );
      final repo = repository([routed, atomic]);
      final scope = Object();
      final available = Completer<void>();
      final first = repo.watchQuotes(request, scope: scope).map((update) {
        if (!update.quotes.isEmpty && !available.isCompleted) {
          available.complete();
        }
        return update;
      }).toList();
      await available.future;
      final second = repo.watchQuotes(request, scope: scope).toList();
      await Future<void>.delayed(Duration.zero);

      expect(routed.requests, hasLength(1));
      expect(atomic.requests, hasLength(2));
      gate.complete();
      await Future.wait([first, second]);
    },
  );
}

class _HeldPrices extends FakePriceSource {
  final gate = Completer<void>();

  @override
  Future<void> warm(Iterable<AssetId> assets) => gate.future;
}

class _FeePrices extends FakePriceSource {
  _FeePrices() : super({eth: d('3000'), usdc: d('1')});
  final gate = Completer<void>();
  final requested = Completer<void>();

  @override
  Future<void> warm(Iterable<AssetId> assets) async {
    if (assets.contains(btc)) {
      if (!requested.isCompleted) requested.complete();
      await gate.future;
    }
  }
}
