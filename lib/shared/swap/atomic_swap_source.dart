import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/shared/swap/swap_catalog.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';
import 'package:web_dex/shared/trading/trading_asset_policy.dart';

/// What executing an atomic quote needs, carried on [SwapQuote.payload].
class AtomicSwapPlan {
  const AtomicSwapPlan({
    required this.base,
    required this.rel,
    required this.volume,
    required this.price,
  });

  /// The asset being sold.
  final AssetId base;

  /// The asset being bought.
  final AssetId rel;

  /// How much of [base] to sell.
  final Decimal volume;

  /// The worst price accepted, in [rel] per [base]. The order the plan places
  /// enforces exactly this, and the quote's guarantee is built from it.
  final Decimal price;
}

/// Prices swaps against KDF's own atomic-swap orderbook.
///
/// The only route for assets no aggregator lists — GLEEC and the GRC-20
/// tokens most of all.
///
/// A taker order is matched with **one** maker order, so a quote is priced
/// against the best single order that can absorb the whole amount, never a
/// walk across several: a walk promises a fill no single order will give, and
/// a fill-or-kill order larger than every maker order never matches at all.
/// The guarantee is exactly what the placed order enforces — volume × price,
/// less any receive-side fee paid out of the traded amount.
class AtomicSwapQuoteSource implements SwapQuoteSource {
  /// Creates a source backed by the SDK's trading manager.
  AtomicSwapQuoteSource({
    required TradingManager trading,
    required SwapNetworks Function() networks,
    Future<String?> Function(AssetId asset)? addressOf,
    bool Function(AssetId from, AssetId to)? tradingAllowed,
    bool Function()? clockValid,
    bool Function(AssetId asset)? isWalletOnly,
    DateTime Function()? now,
  }) : _trading = trading,
       _networks = networks,
       _addressOf = addressOf,
       _tradingAllowed = tradingAllowed,
       _clockValid = clockValid,
       _isWalletOnly = isWalletOnly,
       _now = now ?? DateTime.now;

  final TradingManager _trading;
  final SwapNetworks Function() _networks;
  final Future<String?> Function(AssetId asset)? _addressOf;
  final bool Function(AssetId from, AssetId to)? _tradingAllowed;
  final bool Function()? _clockValid;
  final bool Function(AssetId asset)? _isWalletOnly;
  final DateTime Function() _now;

  @override
  SwapLiquiditySource get source => SwapLiquiditySource.atomic;

  /// Whether the orderbook can trade [asset] at all.
  bool canTrade(AssetId asset) => canTradeWith(asset, _isWalletOnly);

  /// Whether the orderbook can trade [asset], given the config's
  /// [isWalletOnly] flag.
  ///
  /// Wallet-only assets are excluded here rather than at the call site, so
  /// every entry point inherits the same rule. GasFree custody-backed
  /// balances are in that set: DEX settlement spends the standard EOA, which
  /// does not hold them. So are coins the config marks wallet-only, which
  /// KDF refuses to trade.
  static bool canTradeWith(
    AssetId asset,
    bool Function(AssetId asset)? isWalletOnly,
  ) => canTradeAssetId(asset) && !(isWalletOnly?.call(asset) ?? false);

  @override
  Future<SwapSourceAssets> assets({
    required Set<AssetId> known,
    required Set<AssetId> activated,
  }) async => catalogFor(
    known: known,
    activated: activated,
    isWalletOnly: _isWalletOnly,
  );

  /// The orderbook's assets among [known].
  @visibleForTesting
  static SwapSourceAssets catalogFor({
    required Set<AssetId> known,
    required Set<AssetId> activated,
    bool Function(AssetId asset)? isWalletOnly,
  }) => SwapSourceAssets(
    source: SwapLiquiditySource.atomic,
    quotable: {
      for (final asset in activated)
        if (canTradeWith(asset, isWalletOnly)) asset,
    },
    onceActive: {
      for (final asset in known)
        if (!activated.contains(asset) && canTradeWith(asset, isWalletOnly))
          asset,
    },
  );

  @override
  Future<Decimal?> minimumAmount({required AssetId from}) async {
    try {
      final response = await _trading.minTradingVolume(coin: from.id);
      return Decimal.tryParse(response.amount);
    } on Object {
      return null;
    }
  }

  @override
  Future<SwapMaxAmount?> maxAmount({
    required AssetId from,
    required AssetId to,
    required Decimal balance,
  }) async {
    try {
      // KDF's own answer, which already keeps the trading fee and the
      // transaction fees back.
      final response = await _trading.maxTakerVolume(
        coin: from.id,
        tradeWith: to.id,
      );
      final max = Decimal.tryParse(response.amount);
      if (max == null) return null;
      final amount = max > balance ? balance : max;
      return SwapMaxAmount(
        amount: amount < Decimal.zero ? Decimal.zero : amount,
        reservedForFees: balance > amount ? balance - amount : Decimal.zero,
        feeAsset: from,
      );
    } on Object {
      return null;
    }
  }

  @override
  Future<List<SwapQuoteResult>> quote(SwapQuoteRequest request) async => [
    await _quote(
      request.from,
      request.to,
      request.amount,
      indicative: request.indicative,
    ),
  ];

  @override
  Future<SwapQuoteResult> requote(SwapQuote quote) =>
      _quote(quote.from, quote.to, quote.sellAmount);

  Future<SwapQuoteResult> _quote(
    AssetId from,
    AssetId to,
    Decimal amount, {
    bool indicative = false,
  }) async {
    SwapQuoteRejected reject(
      SwapQuoteFailureKind kind, {
      AssetId? asset,
      Decimal? minimum,
      String? detail,
    }) => SwapQuoteRejected(
      SwapQuoteFailure(
        source: SwapLiquiditySource.atomic,
        kind: kind,
        asset: asset,
        minimum: minimum,
        detail: detail,
      ),
    );

    if (!canTrade(from) || !canTrade(to)) {
      return reject(SwapQuoteFailureKind.pairUnsupported);
    }
    if (_tradingAllowed != null && !_tradingAllowed(from, to)) {
      return reject(SwapQuoteFailureKind.tradingBlocked);
    }
    if (_clockValid != null && !_clockValid()) {
      return reject(SwapQuoteFailureKind.clockInvalid);
    }

    final minimum = await minimumAmount(from: from);
    if (minimum != null && amount < minimum) {
      return reject(SwapQuoteFailureKind.belowMinimum, minimum: minimum);
    }

    final OrderbookResponse book;
    try {
      book = await _trading.getOrderbook(base: from.id, rel: to.id);
    } on Object catch (error) {
      return reject(
        SwapQuoteFailureKind.serviceError,
        detail: error.toString(),
      );
    }

    final order = bestFillingBid(book.bids, amount);
    if (order == null) {
      return reject(SwapQuoteFailureKind.noRoute);
    }

    // KDF's preimage refuses an amount the wallet cannot pay, which would hide
    // the order's price from someone looking it up. The quote then carries
    // no fees.
    final preimage = indicative
        ? const _PreimageUnavailable()
        : await _preimage(from, to, amount, order.price);
    if (preimage case _PreimageRejected(:final failure)) {
      return SwapQuoteRejected(failure);
    }
    final fees = switch (preimage) {
      _PreimageFees(:final fees) => fees,
      _ => const <SwapFeeComponent>[],
    };

    // Fees paid out of the received amount reduce what arrives, so the
    // guarantee subtracts them; every other fee is paid on top.
    var guaranteed = amount * order.price;
    for (final fee in fees) {
      if (fee.deductedFromReceive && fee.asset == to) {
        guaranteed -= fee.amount;
      }
    }
    if (guaranteed <= Decimal.zero) {
      return reject(SwapQuoteFailureKind.belowMinimum, minimum: minimum);
    }

    final networks = _networks();
    return SwapQuoteAvailable(
      SwapQuote(
        id: 'atomic',
        source: SwapLiquiditySource.atomic,
        routeKind: SwapRouteKind.direct,
        from: from,
        to: to,
        sellAmount: amount,
        // A fill-or-kill order fills at the matched maker's price or better,
        // or not at all: expected and guaranteed are the same promise.
        expectedReceive: guaranteed,
        guaranteedReceive: guaranteed,
        fees: fees,
        stages: [
          const SwapRouteStage(kind: SwapRouteStageKind.prepare),
          SwapRouteStage(
            kind: SwapRouteStageKind.send,
            network: networks.networkOf(from),
            asset: from,
          ),
          SwapRouteStage(
            kind: SwapRouteStageKind.exchange,
            network: networks.networkOf(to),
            asset: to,
          ),
          SwapRouteStage(
            kind: SwapRouteStageKind.receive,
            network: networks.networkOf(to),
            asset: to,
          ),
        ],
        fromAddress: await _address(from),
        toAddress: await _address(to),
        quotedAt: _now(),
        feesKnown: preimage is _PreimageFees,
        payload: AtomicSwapPlan(
          base: from,
          rel: to,
          volume: amount,
          price: order.price,
        ),
      ),
    );
  }

  /// The best-priced single order that can absorb [amount] whole.
  @visibleForTesting
  static ({Decimal price, Decimal maxVolume})? bestFillingBid(
    List<OrderInfo> bids,
    Decimal amount,
  ) {
    ({Decimal price, Decimal maxVolume})? best;
    for (final bid in bids) {
      final price = _decimalOf(bid.price);
      final max = _decimalOf(bid.baseMaxVolume);
      if (price == null || max == null || price <= Decimal.zero) continue;
      final min = _decimalOf(bid.baseMinVolume) ?? Decimal.zero;
      if (amount > max || amount < min) continue;
      if (best == null || price > best.price) {
        best = (price: price, maxVolume: max);
      }
    }
    return best;
  }

  Future<_Preimage> _preimage(
    AssetId base,
    AssetId rel,
    Decimal volume,
    Decimal price,
  ) async {
    try {
      final preimage = await _trading.tradePreimage(
        base: base.id,
        rel: rel.id,
        swapMethod: SwapMethod.sell,
        volume: volume.toString(),
        price: price.toString(),
      );
      SwapFeeComponent? fee(PreimageCoinFee? raw, SwapFeeKind kind) {
        if (raw == null) return null;
        final amount = Decimal.tryParse(raw.amount);
        if (amount == null || amount == Decimal.zero) return null;
        return SwapFeeComponent(
          kind: kind,
          amount: amount,
          deductedFromReceive: raw.paidFromTradingVol,
          asset: raw.coin == base.id
              ? base
              : raw.coin == rel.id
              ? rel
              : base.parentId?.id == raw.coin
              ? base.parentId
              : rel.parentId?.id == raw.coin
              ? rel.parentId
              : null,
          symbol: raw.coin,
        );
      }

      return _PreimageFees([
        ?fee(preimage.takerFee, SwapFeeKind.dexFee),
        ?fee(preimage.feeToSendTakerFee, SwapFeeKind.network),
        ?fee(preimage.baseCoinFee, SwapFeeKind.network),
        ?fee(preimage.relCoinFee, SwapFeeKind.network),
      ]);
    } on TradePreimageRpcErrorNotSufficientBalanceException catch (error) {
      return _PreimageRejected(_insufficient(error.coin, error.required));
    } on TradePreimageRpcErrorNotSufficientBaseCoinBalanceException catch (
      error
    ) {
      return _PreimageRejected(_insufficient(error.coin, error.required));
    } on TradePreimageRpcErrorVolumeTooLowException catch (error) {
      return _PreimageRejected(
        SwapQuoteFailure(
          source: SwapLiquiditySource.atomic,
          kind: SwapQuoteFailureKind.belowMinimum,
          minimum: Decimal.tryParse(error.threshold.toString()),
        ),
      );
    } on Object {
      // A preimage failure should not hide an otherwise valid price. The
      // quote carries no fees and says so, which leaves its costs unpriced —
      // it cannot be ranked or presented with a total.
      return const _PreimageUnavailable();
    }
  }

  SwapQuoteFailure _insufficient(String coin, Object required) =>
      SwapQuoteFailure(
        source: SwapLiquiditySource.atomic,
        kind: SwapQuoteFailureKind.insufficientFunds,
        minimum: Decimal.tryParse(required.toString()),
        detail: coin,
      );

  Future<String?> _address(AssetId asset) async {
    try {
      return await _addressOf?.call(asset);
    } on Object {
      return null;
    }
  }

  /// Reads a decimal out of KDF's numeric envelope.
  static Decimal? _decimalOf(NumericValue? value) =>
      value == null ? null : Decimal.tryParse(value.decimal);
}

sealed class _Preimage {
  const _Preimage();
}

final class _PreimageFees extends _Preimage {
  const _PreimageFees(this.fees);
  final List<SwapFeeComponent> fees;
}

final class _PreimageRejected extends _Preimage {
  const _PreimageRejected(this.failure);
  final SwapQuoteFailure failure;
}

final class _PreimageUnavailable extends _Preimage {
  const _PreimageUnavailable();
}
