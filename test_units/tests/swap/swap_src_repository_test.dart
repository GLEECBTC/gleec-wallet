import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/shared/swap/swap_catalog.dart';
import 'package:web_dex/shared/swap/swap_pricing.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';
import 'package:web_dex/shared/swap/unified_swap_repository.dart';

import 'swap_bloc_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers the repository when a source or the wallet cannot answer — Max
/// included — how options that cannot be ranked are ordered, and how quotes
/// are priced in dollars without inventing a price nobody gave.
void main() {
  final prices = FakePriceSource({eth: d('3000'), usdc: d('1')});
  final pricing = SwapPricingService(prices);

  group('reading the catalog', () {
    test('a source whose list fails is unavailable, the rest load', () async {
      final repo = UnifiedSwapRepository(
        sources: [_BrokenSource(), FakeQuoteSource(SwapLiquiditySource.atomic)],
        pricing: pricing,
      );

      final catalog = await repo.catalog();

      final routed = catalog.of(SwapLiquiditySource.routed)!;
      expect(routed.status, SwapCatalogStatus.unavailable);
      expect(routed.quotable, isEmpty);
      expect(
        catalog.of(SwapLiquiditySource.atomic)!.status,
        SwapCatalogStatus.fresh,
      );
      expect(catalog.isIncomplete, isTrue);
    });

    test('unreadable activation keeps the last one read', () async {
      Set<AssetId>? activated = {eth};
      final repo = UnifiedSwapRepository(
        sources: [FakeQuoteSource(SwapLiquiditySource.atomic)],
        pricing: pricing,
        activatedAssets: () async =>
            activated ?? (throw StateError('get_enabled_coins failed')),
      );

      await repo.catalog();
      activated = null;
      final catalog = await repo.catalog();

      expect(catalog.activated, {eth});
      expect(catalog.isActive(usdc), isFalse);
    });

    test('activation never read counts every asset as active', () async {
      final repo = UnifiedSwapRepository(
        sources: [FakeQuoteSource(SwapLiquiditySource.atomic)],
        pricing: pricing,
        activatedAssets: () async => throw StateError('offline'),
      );

      final catalog = await repo.catalog();

      expect(catalog.activated, isNull);
      expect(catalog.isActive(usdc), isTrue);
    });
  });

  group('requote', () {
    test('a source the repository does not have is refused', () async {
      final repo = UnifiedSwapRepository(
        sources: [FakeQuoteSource(SwapLiquiditySource.atomic)],
        pricing: pricing,
      );

      final result = await repo.requote(quoteOf());

      final failure = (result as SwapQuoteRejected).failure;
      expect(failure.source, SwapLiquiditySource.routed);
      expect(failure.kind, SwapQuoteFailureKind.unknown);
    });

    test('a source that throws is refused, with the error kept', () async {
      final repo = UnifiedSwapRepository(
        sources: [_BrokenSource()],
        pricing: pricing,
      );

      final result = await repo.requote(quoteOf());

      final failure = (result as SwapQuoteRejected).failure;
      expect(failure.kind, SwapQuoteFailureKind.unknown);
      expect(failure.detail, contains('requote exploded'));
    });

    test('a source\'s refusal is passed on unchanged', () async {
      final refusal = rejected(SwapQuoteFailureKind.noRoute);
      final repo = UnifiedSwapRepository(
        sources: [
          FakeQuoteSource(SwapLiquiditySource.routed, requoteResult: refusal),
        ],
        pricing: pricing,
      );

      expect(await repo.requote(quoteOf()), same(refusal));
    });
  });

  group('max amounts', () {
    const tick = Duration(milliseconds: 1);
    // The ordinary 25 s pricing budget: a preferred source is asked alone
    // for half of it, the order book beside another source has all of it,
    // and Max stops waiting at three times it.
    const budget = Duration(seconds: 25);
    const halfway = Duration(milliseconds: 12500);
    const limit = Duration(seconds: 75);
    Duration limitOf(SwapLiquiditySource source) =>
        source == SwapLiquiditySource.atomic ? budget : limit;
    SwapLiquiditySource otherThan(SwapLiquiditySource source) =>
        SwapLiquiditySource.values.singleWhere((other) => other != source);

    ScriptedQuoteSource held(SwapLiquiditySource source, [String? amount]) =>
        ScriptedQuoteSource(source)
          ..max = amount == null ? null : _maxOf(amount)
          ..maxGate = Completer<void>();

    ScriptedQuoteSource answering(SwapLiquiditySource source) =>
        ScriptedQuoteSource(source)..max = _maxOf('1.99');

    for (final stalled in SwapLiquiditySource.values) {
      test('a stalled ${stalled.name} Max times out, the other is kept', () {
        fakeAsync((async) {
          final working = otherThan(stalled);
          final max = _askMax(pricing, [
            held(stalled, '1.995'),
            answering(working),
          ]);

          async.elapse(limitOf(stalled) - tick);
          expect(max.answer, isNull);
          async.elapse(tick);

          expect(max.answer, {working: _maxOf('1.99')});
        });
      });
    }

    for (final silent in SwapLiquiditySource.values) {
      test('a preferred ${silent.name} source silent halfway has the other '
          'asked too', () {
        fakeAsync((async) {
          final other = answering(otherThan(silent));
          final max = _askMax(pricing, [
            other,
            held(silent, '1.995'),
          ], preferred: silent);

          async.elapse(halfway - tick);
          expect(other.maxCalls, 0);
          async.elapse(tick);
          expect(other.maxCalls, 1);
          // The preferred source may still answer until it times out.
          async.elapse(limitOf(silent) - halfway - tick);
          expect(max.answer, isNull);
          async.elapse(tick);

          expect(max.answer, {other.source: _maxOf('1.99')});
        });
      });
    }

    test('a preferred source that answers after halfway is still used', () {
      fakeAsync((async) {
        final routed = answering(SwapLiquiditySource.routed);
        final atomic = held(SwapLiquiditySource.atomic, '1.995');
        final max = _askMax(pricing, [
          routed,
          atomic,
        ], preferred: SwapLiquiditySource.atomic);

        async.elapse(const Duration(seconds: 20));
        expect(routed.maxCalls, 1);
        atomic.maxGate!.complete();
        async.flushMicrotasks();

        expect(max.answer, {SwapLiquiditySource.atomic: _maxOf('1.995')});
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('a late empty preferred answer returns the others at once', () {
      fakeAsync((async) {
        final routed = answering(SwapLiquiditySource.routed);
        final atomic = held(SwapLiquiditySource.atomic);
        final max = _askMax(pricing, [
          routed,
          atomic,
        ], preferred: SwapLiquiditySource.atomic);

        async.elapse(const Duration(seconds: 20));
        expect(max.answer, isNull);
        atomic.maxGate!.complete();
        async.flushMicrotasks();

        expect(max.answer, {SwapLiquiditySource.routed: _maxOf('1.99')});
        expect(routed.maxCalls, 1);
      });
    });

    test('a Max nothing answers in time is a timeout', () {
      fakeAsync((async) {
        final max = _askMax(pricing, [
          held(SwapLiquiditySource.routed, '1.99'),
          // One that cannot tell has nothing to explain.
          ScriptedQuoteSource(SwapLiquiditySource.atomic),
        ]);

        async.elapse(limit);

        expect(
          max.failure,
          const SwapQuoteFailure(
            source: SwapLiquiditySource.routed,
            kind: SwapQuoteFailureKind.timeout,
          ),
        );
      });
    });

    test("one source's timeout does not hide another's reason", () {
      fakeAsync((async) {
        final short = _RefusedMax(
          SwapLiquiditySource.routed,
          SwapQuoteFailureKind.insufficientFunds,
        )..maxGate = Completer<void>();
        final max = _askMax(pricing, [
          short,
          _RefusedMax(SwapLiquiditySource.atomic, SwapQuoteFailureKind.timeout),
        ]);
        // The order book runs out of time first.
        async.flushMicrotasks();
        short.maxGate!.complete();
        async.flushMicrotasks();

        expect(max.failure!.kind, SwapQuoteFailureKind.insufficientFunds);
        expect(max.failures!.map((f) => (f.source, f.kind)), [
          (SwapLiquiditySource.atomic, SwapQuoteFailureKind.timeout),
          (SwapLiquiditySource.routed, SwapQuoteFailureKind.insufficientFunds),
        ]);
      });
    });
  });

  group('options', () {
    SwapQuote unpriced(
      String id,
      SwapLiquiditySource source, {
      String guaranteed = '2990',
      Duration duration = const Duration(seconds: 30),
    }) => quoteOf(
      id: id,
      source: source,
      guaranteed: guaranteed,
      duration: duration,
      pricing: const SwapQuotePricing(),
    );

    test(
      'unrankable options of equal minimum go to speed, then peer-to-peer',
      () {
        final result = UnifiedSwapRepository.rank([
          unpriced(
            'slow',
            SwapLiquiditySource.routed,
            duration: const Duration(minutes: 5),
          ),
          unpriced('fast-routed', SwapLiquiditySource.routed),
          unpriced('fast-atomic', SwapLiquiditySource.atomic),
          unpriced('lowest', SwapLiquiditySource.atomic, guaranteed: '2900'),
        ], const []);

        expect(result.unrankable.map((q) => q.id), [
          'fast-atomic',
          'fast-routed',
          'slow',
          'lowest',
        ]);
        expect(result.ranked, isEmpty);
      },
    );

    test('an option can be found again by its id', () {
      final result = UnifiedSwapRepository.rank([
        quoteOf(id: 'ranked'),
        unpriced('unranked', SwapLiquiditySource.atomic),
      ], const []);

      expect(result.options.map((q) => q.id), ['ranked', 'unranked']);
      expect(result.byId('unranked')!.source, SwapLiquiditySource.atomic);
      expect(result.byId('gone'), isNull);
      expect(result.hasAlternatives, isTrue);
      expect(result.canClaimBestNetReturn, isFalse);
      expect(result.primaryFailure, isNull);
      expect(result.isPermanentlyUnsupported, isFalse);
    });
  });

  group('dollar pricing', () {
    SwapFeeComponent cost(
      SwapFeeKind kind,
      String amount, {
      AssetId? asset,
      String? usd,
      bool deducted = false,
    }) => SwapFeeComponent(
      kind: kind,
      amount: d(amount),
      deductedFromReceive: deducted,
      asset: asset,
      usdValue: usd == null ? null : d(usd),
    );

    test('an amount of an unpriced or unknown asset has no value', () {
      expect(pricing.usdValue(eth, d('2')), d('6000'));
      expect(pricing.usdValue(btc, d('1')), isNull);
      expect(pricing.usdValue(null, d('1')), isNull);
      expect(pricing.prices, same(prices));
    });

    test('prices every cost, keeping a value the provider gave', () {
      final quote = pricing.price(
        quoteOf(
          fees: [
            cost(SwapFeeKind.network, '0.001', asset: eth),
            cost(SwapFeeKind.approvalNetwork, '0.0005', asset: eth),
            cost(SwapFeeKind.swap, '2', asset: usdc, usd: '2.5'),
            cost(SwapFeeKind.dexFee, '1', asset: usdc, deducted: true),
          ],
          pricing: const SwapQuotePricing(),
        ),
      );

      expect(quote.fees.map((fee) => fee.usdValue), [
        d('3'),
        d('1.5'),
        d('2.5'),
        d('1'),
      ]);
      expect(
        quote.pricing,
        SwapQuotePricing(
          payUsd: d('3000'),
          expectedUsd: d('3000'),
          minimumUsd: d('2985'),
          networkCostUsd: d('4.5'),
          approvalNetworkCostUsd: d('1.5'),
          swapCostUsd: d('3.5'),
          // The routed receive already had the deducted trading fee taken out.
          deductedCostUsd: d('1'),
          isComplete: true,
        ),
      );
    });

    test('one unpriced cost leaves its total unknown and incomplete', () {
      final quote = pricing.price(
        quoteOf(
          fees: [
            cost(SwapFeeKind.network, '0.001', asset: eth),
            cost(SwapFeeKind.swap, '1', asset: btc),
          ],
          pricing: const SwapQuotePricing(),
        ),
      );

      expect(quote.pricing.networkCostUsd, d('3'));
      expect(quote.pricing.swapCostUsd, isNull);
      expect(quote.pricing.isComplete, isFalse);
      expect(quote.isRankable, isFalse);
    });

    test('a quote read without its fees claims no costs at all', () {
      final quote = pricing.price(
        SwapQuote(
          id: 'atomic',
          source: SwapLiquiditySource.atomic,
          routeKind: SwapRouteKind.direct,
          from: eth,
          to: usdc,
          sellAmount: d('1'),
          expectedReceive: d('2990'),
          guaranteedReceive: d('2990'),
          fees: const [],
          stages: const [],
          quotedAt: DateTime(2026, 9, 24, 12),
          feesKnown: false,
        ),
      );

      expect(quote.pricing.minimumUsd, d('2990'));
      expect(quote.pricing.networkCostUsd, isNull);
      expect(quote.pricing.swapCostUsd, isNull);
      expect(quote.pricing.approvalNetworkCostUsd, isNull);
      expect(quote.pricing.isComplete, isFalse);
    });
  });
}

SwapMaxAmount _maxOf(String amount) =>
    SwapMaxAmount(amount: d(amount), reservedForFees: d('0.01'));

/// A Max asked of the repository, as it stands so far.
class _AskedMax {
  Map<SwapLiquiditySource, SwapMaxAmount>? answer;

  /// Why no source had an answer, and each source's own reason.
  SwapQuoteFailure? failure;
  List<SwapQuoteFailure>? failures;
}

/// Asks [sources] for Max on 2 ETH sold for USDC.
_AskedMax _askMax(
  SwapPricingService pricing,
  List<FakeQuoteSource> sources, {
  SwapLiquiditySource? preferred,
}) {
  final asked = _AskedMax();
  unawaited(
    UnifiedSwapRepository(sources: sources, pricing: pricing)
        .maxAmounts(from: eth, to: usdc, balance: d('2'), preferred: preferred)
        .then<void>(
          (answer) {
            asked.answer = answer;
          },
          onError: (Object error) {
            error as SwapMaxUnavailableException;
            asked
              ..failure = error.failure
              ..failures = error.failures;
          },
        ),
  );
  return asked;
}

/// A source whose Max is refused for [kind], once [maxGate] lets it answer.
class _RefusedMax extends ScriptedQuoteSource {
  _RefusedMax(super.source, this.kind);

  final SwapQuoteFailureKind kind;

  @override
  Future<SwapMaxAmount?> maxAmount({
    required AssetId from,
    required AssetId to,
    required Decimal balance,
    SwapQuoteOrder order = SwapQuoteOrder.cheapest,
    double? slippage,
  }) async {
    await maxGate?.future;
    throw SwapMaxUnavailableException(
      SwapQuoteFailure(source: source, kind: kind),
    );
  }
}

class _BrokenSource extends FakeQuoteSource {
  _BrokenSource() : super(SwapLiquiditySource.routed);

  @override
  Future<SwapSourceAssets> assets({
    required Set<AssetId> known,
    required Set<AssetId> activated,
  }) => Future.error(StateError('list exploded'));

  @override
  Future<SwapQuoteResult> requote(SwapQuote quote) =>
      Future.error(StateError('requote exploded'));
}
