import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/shared/swap/swap_pricing.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';
import 'package:web_dex/shared/swap/unified_swap_repository.dart';

import 'swap_test_fixtures.dart';

/// Covers what a user is shown when both sources answer.
///
/// The two sources make different promises — a routed quote's headline is
/// subject to slippage, an atomic fill is not — so ranking is on the
/// guaranteed minimum's value net of costs, never on the headline.
void main() {
  final prices = FakePriceSource({
    eth: d('3000'),
    usdc: d('1'),
    btc: d('60000'),
  });
  final pricing = SwapPricingService(prices);

  SwapQuote unpriced({
    required String id,
    required SwapLiquiditySource source,
    required String guaranteed,
    String expected = '3000',
    List<SwapFeeComponent>? fees,
    Duration? duration = const Duration(seconds: 45),
  }) => quoteOf(
    id: id,
    source: source,
    expected: expected,
    guaranteed: guaranteed,
    duration: duration,
    fees:
        fees ??
        [
          SwapFeeComponent(
            kind: SwapFeeKind.network,
            amount: d('0.001'),
            deductedFromReceive: false,
            asset: eth,
          ),
        ],
    pricing: const SwapQuotePricing(),
  );

  UnifiedSwapRepository repoOf(List<FakeQuoteSource> sources) =>
      UnifiedSwapRepository(sources: sources, pricing: pricing);

  final request = SwapQuoteRequest(from: eth, to: usdc, amount: d('1'));

  group('ranking', () {
    test('ranks on net return, not the headline estimate', () async {
      final repo = repoOf([
        FakeQuoteSource(
          SwapLiquiditySource.routed,
          results: [
            SwapQuoteAvailable(
              unpriced(
                id: 'routed',
                source: SwapLiquiditySource.routed,
                expected: '3100',
                guaranteed: '2950',
              ),
            ),
          ],
        ),
        FakeQuoteSource(
          SwapLiquiditySource.atomic,
          results: [
            SwapQuoteAvailable(
              unpriced(
                id: 'atomic',
                source: SwapLiquiditySource.atomic,
                expected: '2990',
                guaranteed: '2990',
              ),
            ),
          ],
        ),
      ]);

      final result = await repo.quote(request);

      expect(result.ranked.map((q) => q.id), ['atomic', 'routed']);
      expect(result.preselected!.id, 'atomic');
      expect(result.canClaimBestNetReturn, isTrue);
    });

    test('subtracts costs the receive amount does not account for', () async {
      final repo = repoOf([
        FakeQuoteSource(
          SwapLiquiditySource.routed,
          results: [
            SwapQuoteAvailable(
              unpriced(
                id: 'cheap-headline',
                source: SwapLiquiditySource.routed,
                guaranteed: '2990',
                fees: [
                  SwapFeeComponent(
                    kind: SwapFeeKind.network,
                    amount: d('0.01'),
                    deductedFromReceive: false,
                    asset: eth,
                  ),
                ],
              ),
            ),
            SwapQuoteAvailable(
              unpriced(
                id: 'low-cost',
                source: SwapLiquiditySource.routed,
                guaranteed: '2980',
                fees: [
                  SwapFeeComponent(
                    kind: SwapFeeKind.network,
                    amount: d('0.001'),
                    deductedFromReceive: false,
                    asset: eth,
                  ),
                ],
              ),
            ),
          ],
        ),
      ]);

      final result = await repo.quote(request);

      // 2990 - 30 = 2960 against 2980 - 3 = 2977.
      expect(result.ranked.first.id, 'low-cost');
      expect(result.ranked.first.netReturnUsd, d('2977'));
    });

    test('does not double count a fee already taken from the receive', () {
      final quote = pricing.price(
        unpriced(
          id: 'included',
          source: SwapLiquiditySource.routed,
          guaranteed: '2990',
          fees: [
            SwapFeeComponent(
              kind: SwapFeeKind.swap,
              amount: d('5'),
              deductedFromReceive: true,
              asset: usdc,
            ),
            SwapFeeComponent(
              kind: SwapFeeKind.network,
              amount: d('0.001'),
              deductedFromReceive: false,
              asset: eth,
            ),
          ],
        ),
      );
      expect(quote.netReturnUsd, d('2987'));
      expect(quote.pricing.totalCostUsd, d('8'));
    });

    test('breaks an exact tie toward speed, then peer-to-peer', () {
      final a = pricing.price(
        unpriced(
          id: 'slow-routed',
          source: SwapLiquiditySource.routed,
          guaranteed: '2990',
          duration: const Duration(minutes: 5),
        ),
      );
      final b = pricing.price(
        unpriced(
          id: 'fast-routed',
          source: SwapLiquiditySource.routed,
          guaranteed: '2990',
          duration: const Duration(seconds: 30),
        ),
      );
      final c = pricing.price(
        unpriced(
          id: 'fast-atomic',
          source: SwapLiquiditySource.atomic,
          guaranteed: '2990',
          duration: const Duration(seconds: 30),
        ),
      );

      final result = UnifiedSwapRepository.rank([a, b, c], const []);

      expect(result.ranked.map((q) => q.id), [
        'fast-atomic',
        'fast-routed',
        'slow-routed',
      ]);
    });

    test('keeps an option with an unpriced cost out of the ranking', () async {
      final repo = repoOf([
        FakeQuoteSource(
          SwapLiquiditySource.routed,
          results: [
            SwapQuoteAvailable(
              unpriced(
                id: 'unknown-fee',
                source: SwapLiquiditySource.routed,
                guaranteed: '2999',
                fees: [
                  SwapFeeComponent(
                    kind: SwapFeeKind.swap,
                    amount: Decimal.one,
                    deductedFromReceive: false,
                    symbol: 'XYZ',
                  ),
                ],
              ),
            ),
            SwapQuoteAvailable(
              unpriced(
                id: 'priced',
                source: SwapLiquiditySource.routed,
                guaranteed: '2980',
              ),
            ),
          ],
        ),
      ]);

      final result = await repo.quote(request);

      // Ranking on the costs that happen to be priced would put the option
      // with the hidden cost on top.
      expect(result.ranked.map((q) => q.id), ['priced']);
      expect(result.unrankable.map((q) => q.id), ['unknown-fee']);
      expect(result.canClaimBestNetReturn, isFalse);
    });

    test('preselects nothing when several options cannot be ranked', () {
      final result = UnifiedSwapRepository.rank([
        unpriced(id: 'a', source: SwapLiquiditySource.routed, guaranteed: '1'),
        unpriced(id: 'b', source: SwapLiquiditySource.atomic, guaranteed: '2'),
      ], const []);

      expect(result.preselected, isNull);
      expect(result.unrankable.first.id, 'b');
    });

    test('preselects a lone unrankable option', () {
      final result = UnifiedSwapRepository.rank([
        unpriced(
          id: 'only',
          source: SwapLiquiditySource.routed,
          guaranteed: '1',
        ),
      ], const []);
      expect(result.preselected!.id, 'only');
    });
  });

  group('failures', () {
    test('a throwing source does not withhold the other price', () async {
      final repo = UnifiedSwapRepository(
        sources: [
          _ThrowingSource(),
          FakeQuoteSource(
            SwapLiquiditySource.atomic,
            results: [
              SwapQuoteAvailable(
                unpriced(
                  id: 'atomic',
                  source: SwapLiquiditySource.atomic,
                  guaranteed: '2990',
                ),
              ),
            ],
          ),
        ],
        pricing: pricing,
      );

      final result = await repo.quote(request);

      expect(result.options.single.id, 'atomic');
      expect(result.failures.single.kind, SwapQuoteFailureKind.unknown);
    });

    test('explains an empty result with the most actionable failure', () async {
      final repo = repoOf([
        FakeQuoteSource(
          SwapLiquiditySource.routed,
          results: [rejected(SwapQuoteFailureKind.noRoute)],
        ),
        FakeQuoteSource(
          SwapLiquiditySource.atomic,
          results: [
            rejected(
              SwapQuoteFailureKind.assetInactive,
              source: SwapLiquiditySource.atomic,
              asset: usdc,
            ),
          ],
        ),
      ]);

      final result = await repo.quote(request);

      expect(result.isEmpty, isTrue);
      expect(result.primaryFailure!.kind, SwapQuoteFailureKind.assetInactive);
    });

    test('a pair nobody lists is permanently unsupported', () async {
      final repo = repoOf([
        FakeQuoteSource(
          SwapLiquiditySource.routed,
          results: [rejected(SwapQuoteFailureKind.pairUnsupported)],
        ),
        FakeQuoteSource(
          SwapLiquiditySource.atomic,
          results: [
            rejected(
              SwapQuoteFailureKind.pairUnsupported,
              source: SwapLiquiditySource.atomic,
            ),
          ],
        ),
      ]);

      final result = await repo.quote(request);
      expect(result.isPermanentlyUnsupported, isTrue);
    });

    test('asks nobody for a price of nothing', () async {
      final source = FakeQuoteSource(SwapLiquiditySource.routed);
      final repo = repoOf([source]);

      final result = await repo.quote(
        SwapQuoteRequest(from: eth, to: usdc, amount: Decimal.zero),
      );

      expect(result.isEmpty, isTrue);
      expect(source.requests, isEmpty);
    });
  });

  group('max and requote', () {
    test('reports each source its own maximum', () async {
      final repo = repoOf([
        FakeQuoteSource(
          SwapLiquiditySource.routed,
          max: SwapMaxAmount(
            amount: d('0.99'),
            reservedForFees: d('0.01'),
            feeAsset: eth,
          ),
        ),
        FakeQuoteSource(SwapLiquiditySource.atomic),
      ]);

      final maxes = await repo.maxAmounts(from: eth, to: usdc, balance: d('1'));

      expect(maxes.keys, [SwapLiquiditySource.routed]);
      expect(maxes[SwapLiquiditySource.routed]!.amount, d('0.99'));
    });

    test('re-prices on the same source and prices the result', () async {
      final routed = FakeQuoteSource(
        SwapLiquiditySource.routed,
        requoteResult: SwapQuoteAvailable(
          unpriced(
            id: 'fresh',
            source: SwapLiquiditySource.routed,
            guaranteed: '2970',
          ),
        ),
      );
      final repo = repoOf([
        routed,
        FakeQuoteSource(SwapLiquiditySource.atomic),
      ]);

      final result = await repo.requote(quoteOf());

      expect(routed.requoted, hasLength(1));
      final fresh = (result as SwapQuoteAvailable).quote;
      expect(fresh.pricing.minimumUsd, d('2970'));
    });
  });
}

class _ThrowingSource extends FakeQuoteSource {
  _ThrowingSource() : super(SwapLiquiditySource.routed);

  @override
  Future<List<SwapQuoteResult>> quote(SwapQuoteRequest request) =>
      Future.error(StateError('provider exploded'));
}
