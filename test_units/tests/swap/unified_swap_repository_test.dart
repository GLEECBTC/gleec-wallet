import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/unified_swap_repository.dart';

/// Covers the aggregation rules that decide what a user is shown.
///
/// The ranking is the part with teeth: the two sources make different promises
/// — a routed quote's headline is subject to slippage, an atomic fill is not —
/// so a naive comparison systematically favours the looser promise.
void main() {
  AssetId assetOf(String id) => AssetId(
    id: id,
    name: id,
    symbol: AssetSymbol(assetConfigId: id),
    chainId: AssetChainId(chainId: 1),
    derivationPath: null,
    subClass: CoinSubClass.erc20,
  );

  final gleec = assetOf('GLEEC');
  final usdt = assetOf('USDT-PLG20');

  SwapQuote quoteOf({
    required SwapLiquiditySource source,
    required String expected,
    required String guaranteed,
    Duration? duration,
  }) => SwapQuote(
    source: source,
    from: gleec,
    to: usdt,
    sellAmount: Decimal.parse('100'),
    expectedReceive: Decimal.parse(expected),
    guaranteedReceive: Decimal.parse(guaranteed),
    costs: const [],
    quotedAt: DateTime(2026),
    hasUndisclosedCosts: false,
    estimatedDuration: duration,
  );

  group('ranking', () {
    test(
      'prefers the larger guaranteed amount, not the larger estimate',
      () async {
        // The routed option looks better on its headline number and worse on
        // what it actually promises. Ranking on the headline would put a swap
        // that may deliver less at the top.
        final repo = UnifiedSwapRepository(
          sources: [
            _StubSource(
              SwapLiquiditySource.routed,
              priced: quoteOf(
                source: SwapLiquiditySource.routed,
                expected: '105',
                guaranteed: '99',
              ),
            ),
            _StubSource(
              SwapLiquiditySource.atomic,
              priced: quoteOf(
                source: SwapLiquiditySource.atomic,
                expected: '101',
                guaranteed: '101',
              ),
            ),
          ],
        );

        final result = await repo.quote(
          from: gleec,
          to: usdt,
          amount: Decimal.parse('100'),
        );

        expect(result.best!.source, SwapLiquiditySource.atomic);
        expect(result.quotes, hasLength(2));
      },
    );

    test('breaks an exact tie toward the peer-to-peer option', () async {
      final repo = UnifiedSwapRepository(
        sources: [
          _StubSource(
            SwapLiquiditySource.routed,
            priced: quoteOf(
              source: SwapLiquiditySource.routed,
              expected: '100',
              guaranteed: '100',
            ),
          ),
          _StubSource(
            SwapLiquiditySource.atomic,
            priced: quoteOf(
              source: SwapLiquiditySource.atomic,
              expected: '100',
              guaranteed: '100',
            ),
          ),
        ],
      );

      final result = await repo.quote(
        from: gleec,
        to: usdt,
        amount: Decimal.parse('100'),
      );

      // Equal promises, so prefer the one where no third party ever holds the
      // funds.
      expect(result.best!.source, SwapLiquiditySource.atomic);
    });
  });

  group('resilience', () {
    test('one broken source does not withhold the other price', () async {
      final repo = UnifiedSwapRepository(
        sources: [
          _ThrowingSource(SwapLiquiditySource.routed),
          _StubSource(
            SwapLiquiditySource.atomic,
            priced: quoteOf(
              source: SwapLiquiditySource.atomic,
              expected: '101',
              guaranteed: '101',
            ),
          ),
        ],
      );

      final result = await repo.quote(
        from: gleec,
        to: usdt,
        amount: Decimal.parse('100'),
      );

      expect(result.best, isNotNull);
      expect(result.rejections, hasLength(1));
      expect(
        result.rejections.single.reason,
        SwapQuoteUnavailableReason.temporarilyUnavailable,
      );
    });

    test('a source that throws is reported, not swallowed', () async {
      final repo = UnifiedSwapRepository(
        sources: [_ThrowingSource(SwapLiquiditySource.routed)],
      );

      final result = await repo.quote(
        from: gleec,
        to: usdt,
        amount: Decimal.parse('100'),
      );

      expect(result.isEmpty, isTrue);
      expect(result.rejections, hasLength(1));
      expect(
        result.isPermanentlyUnsupported,
        isFalse,
        reason: 'a crash is not proof the pair is unsupported',
      );
    });
  });

  group('unsupported pairs', () {
    test('is permanent only when every source says so', () async {
      // GLEEC is the case this exists for: no aggregator indexes the Gleec
      // chain, so routed will always decline. If atomic declines too, the
      // pair genuinely cannot be traded and a retry button would be a lie.
      final repo = UnifiedSwapRepository(
        sources: [
          _RejectingSource(
            SwapLiquiditySource.routed,
            SwapQuoteUnavailableReason.pairUnsupported,
          ),
          _RejectingSource(
            SwapLiquiditySource.atomic,
            SwapQuoteUnavailableReason.pairUnsupported,
          ),
        ],
      );

      final result = await repo.quote(
        from: gleec,
        to: usdt,
        amount: Decimal.parse('100'),
      );

      expect(result.isPermanentlyUnsupported, isTrue);
    });

    test('is not permanent when one source merely has no liquidity', () async {
      final repo = UnifiedSwapRepository(
        sources: [
          _RejectingSource(
            SwapLiquiditySource.routed,
            SwapQuoteUnavailableReason.pairUnsupported,
          ),
          _RejectingSource(
            SwapLiquiditySource.atomic,
            SwapQuoteUnavailableReason.noLiquidity,
          ),
        ],
      );

      final result = await repo.quote(
        from: gleec,
        to: usdt,
        amount: Decimal.parse('100'),
      );

      expect(
        result.isPermanentlyUnsupported,
        isFalse,
        reason: 'an empty book today says nothing about tomorrow',
      );
    });
  });

  group('asset gating', () {
    test('offers the union of what any source can trade', () async {
      final repo = UnifiedSwapRepository(
        sources: [
          _StubSource(SwapLiquiditySource.routed, assets: {usdt}),
          _StubSource(SwapLiquiditySource.atomic, assets: {gleec}),
        ],
      );

      final assets = await repo.tradableAssets();

      // GLEEC is only reachable peer-to-peer. Gating the picker on the routed
      // list alone would hide the wallet's own asset from its swap screen.
      expect(assets, {usdt, gleec});
    });

    test('reports which sources can trade an asset', () async {
      final repo = UnifiedSwapRepository(
        sources: [
          _StubSource(SwapLiquiditySource.routed, assets: {usdt}),
          _StubSource(SwapLiquiditySource.atomic, assets: {gleec, usdt}),
        ],
      );

      expect(await repo.sourcesFor(gleec), {SwapLiquiditySource.atomic});
      expect(await repo.sourcesFor(usdt), {
        SwapLiquiditySource.atomic,
        SwapLiquiditySource.routed,
      });
    });
  });

  test('a non-positive amount is not sent to any source', () async {
    final source = _StubSource(
      SwapLiquiditySource.routed,
      priced: quoteOf(
        source: SwapLiquiditySource.routed,
        expected: '1',
        guaranteed: '1',
      ),
    );
    final repo = UnifiedSwapRepository(sources: [source]);

    final result = await repo.quote(
      from: gleec,
      to: usdt,
      amount: Decimal.zero,
    );

    expect(result.isEmpty, isTrue);
    expect(source.quoteCalls, 0);
  });
}

class _StubSource implements SwapQuoteSource {
  _StubSource(this.source, {this.priced, this.assets = const {}});

  @override
  final SwapLiquiditySource source;

  final SwapQuote? priced;
  final Set<AssetId> assets;
  int quoteCalls = 0;

  @override
  Future<Set<AssetId>> tradableAssets() async => assets;

  @override
  Future<SwapQuoteResult> quote({
    required AssetId from,
    required AssetId to,
    required Decimal amount,
  }) async {
    quoteCalls++;
    final priced = this.priced;
    if (priced == null) {
      return SwapQuoteRejected(
        SwapQuoteUnavailable(
          source: source,
          reason: SwapQuoteUnavailableReason.noLiquidity,
        ),
      );
    }
    return SwapQuoteAvailable(priced);
  }
}

class _RejectingSource implements SwapQuoteSource {
  _RejectingSource(this.source, this.reason);

  @override
  final SwapLiquiditySource source;

  final SwapQuoteUnavailableReason reason;

  @override
  Future<Set<AssetId>> tradableAssets() async => const {};

  @override
  Future<SwapQuoteResult> quote({
    required AssetId from,
    required AssetId to,
    required Decimal amount,
  }) async =>
      SwapQuoteRejected(SwapQuoteUnavailable(source: source, reason: reason));
}

class _ThrowingSource implements SwapQuoteSource {
  _ThrowingSource(this.source);

  @override
  final SwapLiquiditySource source;

  @override
  Future<Set<AssetId>> tradableAssets() async => const {};

  @override
  Future<SwapQuoteResult> quote({
    required AssetId from,
    required AssetId to,
    required Decimal amount,
  }) async => throw StateError('source exploded');
}
