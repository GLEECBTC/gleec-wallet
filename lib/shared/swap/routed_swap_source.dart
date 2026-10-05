import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart'
    show DiagnosticSanitizer;
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/shared/swap/routed_swap_chains.dart';
import 'package:web_dex/shared/swap/swap_catalog.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';

part 'routed_swap_budget.dart';
part 'routed_swap_offer.dart';
part 'routed_swap_quote_log.dart';

/// Prices swaps through the aggregator, executed by KDF.
///
/// Everything hard about the routed contract lives in [RoutedSwapManager];
/// this only normalises its offers into [SwapQuote]s and its typed errors
/// into [SwapQuoteFailure]s, so the UI can compare and explain them next to
/// an atomic quote.
class RoutedSwapQuoteSource implements SwapQuoteSource {
  /// Creates a source backed by [manager]. Sources given the same [rateLimit]
  /// wait out a refusal together. Each failed quote or catalog read is
  /// described in one line to [log], for the app's exportable log.
  RoutedSwapQuoteSource(
    this.manager, {
    required SwapNetworks Function() networks,
    bool Function(AssetId from, AssetId to)? tradingAllowed,
    bool Function(AssetId asset) isCandidate = isRoutedSwapCandidate,
    Duration timeout = const Duration(seconds: 20),
    Duration catalogTimeout = const Duration(seconds: 10),
    DateTime Function()? now,
    RoutedSwapRateLimit? rateLimit,
    void Function(String line) log = _discard,
  }) : _networks = networks,
       _tradingAllowed = tradingAllowed,
       _isCandidate = isCandidate,
       _timeout = timeout,
       _catalogTimeout = catalogTimeout,
       _log = log,
       _budget = _QuoteBudget(
         now ?? DateTime.now,
         rateLimit ?? RoutedSwapRateLimit(),
       );

  /// The SDK manager doing the real work.
  final RoutedSwapManager manager;
  final SwapNetworks Function() _networks;
  final bool Function(AssetId from, AssetId to)? _tradingAllowed;
  final bool Function(AssetId asset) _isCandidate;
  final Duration _timeout;
  final void Function(String line) _log;

  static void _discard(String line) {}

  /// Shorter than a quote's: once KDF has answered, the form waits on the
  /// catalog before pricing.
  final Duration _catalogTimeout;

  Set<AssetId>? _lastEligible;

  final _QuoteBudget _budget;

  /// KDF's slippage when a request names none.
  static const _defaultSlippage = 0.005;

  @override
  SwapLiquiditySource get source => SwapLiquiditySource.routed;

  /// KDF quotes a route from the source coin's enabled address, which only an
  /// active coin in a signed-in wallet has.
  @override
  bool get pricesSignedOut => false;

  @override
  Future<SwapSourceAssets> assets({
    required Set<AssetId> known,
    required Set<AssetId> activated,
  }) async {
    final candidates = {
      for (final asset in known)
        if (_isCandidate(asset)) asset,
    };
    final onceActive = candidates.difference(activated);
    // KDF lists active coins only, and its first call waits on the provider's
    // network list with no deadline of its own. With nothing active it is not
    // asked; until it first answers, the network rule stands in.
    if (activated.isEmpty) {
      return SwapSourceAssets(source: source, onceActive: onceActive);
    }
    final guess = candidates.intersection(activated);
    final listed = _listed(guess, onceActive);
    if (_lastEligible != null) return listed;
    return SwapSourceAssets(
      source: source,
      quotable: guess,
      onceActive: onceActive,
      update: listed,
    );
  }

  Future<SwapSourceAssets> _listed(
    Set<AssetId> guess,
    Set<AssetId> onceActive,
  ) async {
    try {
      final eligible = await manager.eligibleAssets().timeout(_catalogTimeout);
      _lastEligible = eligible;
      return SwapSourceAssets(
        source: source,
        quotable: eligible,
        onceActive: onceActive,
      );
    } on Object catch (error) {
      _report(_RoutedQuoteLog.catalog(error, timeout: _catalogTimeout));
      // An outage must not empty the picker or make every pair read as
      // unsupported: keep KDF's last answer, else the wallet's own guess.
      final last = _lastEligible;
      return SwapSourceAssets(
        source: source,
        quotable: last ?? guess,
        onceActive: onceActive,
        status: last == null
            ? SwapCatalogStatus.unavailable
            : SwapCatalogStatus.stale,
      );
    }
  }

  @override
  Future<Decimal?> minimumAmount({required AssetId from}) async => null;

  @override
  Future<SwapMaxAmount?> maxAmount({
    required AssetId from,
    required AssetId to,
    required Decimal balance,
  }) async {
    if (!from.isChildAsset) {
      // A quote for this pair from moments ago knows the route's gas as well
      // as a probe would, without spending a request on one.
      final recent = _budget.latestFor(from, to);
      if (recent != null) return _nativeMax(recent, from, balance);
      // The probe is a quote: while limited it is refused and still counts.
      if (_budget.pausedUntil != null) return null;
    }
    try {
      final max = await manager
          .maxSellAmount(from: from, to: to, balance: balance)
          .timeout(_timeout);
      return SwapMaxAmount(
        amount: max.amount,
        reservedForFees: max.reservedForFees,
        feeAsset: max.feeAsset,
      );
    } on RoutedSwapRateLimitedException {
      _budget.pause();
      return null;
    } on Object {
      return null;
    }
  }

  @override
  Future<List<SwapQuoteResult>> quote(SwapQuoteRequest request) async {
    if (_tradingAllowed != null && !_tradingAllowed(request.from, request.to)) {
      return [_rejected(SwapQuoteFailureKind.tradingBlocked)];
    }
    final orders = request.orders.isEmpty
        ? const {SwapQuoteOrder.cheapest}
        : request.orders;
    final results = await Future.wait([
      for (final order in orders)
        _quote(
          request.from,
          request.to,
          request.amount,
          order,
          request.slippage ?? _defaultSlippage,
          automatic: request.automatic,
        ),
    ]);
    if (results.length < 2) return results;

    final available = results.whereType<SwapQuoteAvailable>().toList();
    // A failed alternative is not a reason to show an error: the routes
    // that were priced decide what the user sees.
    if (available.isEmpty) return [results.first];
    // The same route under two orders is one option, not two.
    final distinct = <SwapQuoteAvailable>[];
    for (final result in available) {
      final same = distinct.any(
        (kept) =>
            kept.quote.diagnostic == result.quote.diagnostic &&
            kept.quote.guaranteedReceive == result.quote.guaranteedReceive,
      );
      if (!same) distinct.add(result);
    }
    return distinct;
  }

  /// Re-prices [quote]'s route. A route that still clears the minimum
  /// [quote] showed keeps it: quotes seconds apart differ slightly, and a
  /// move smaller than the guard margin should neither ask again nor start
  /// against a number the user did not see.
  @override
  Future<SwapQuoteResult> requote(SwapQuote quote) async {
    final order = quote.order ?? SwapQuoteOrder.cheapest;
    final result = await _quote(
      quote.from,
      quote.to,
      quote.sellAmount,
      order,
      quote.slippage ?? _defaultSlippage,
    );
    if (result case SwapQuoteAvailable(
      quote: SwapQuote(payload: final RoutedSwapOffer fresh),
    )) {
      final kept = fresh.keepingMinimum(quote.guaranteedReceive);
      if (kept != null && !identical(kept, fresh)) {
        return SwapQuoteAvailable(
          routedQuoteFromOffer(kept, networks: _networks(), order: order),
        );
      }
    }
    return result;
  }

  Future<SwapQuoteResult> _quote(
    AssetId from,
    AssetId to,
    Decimal amount,
    SwapQuoteOrder order,
    double slippage, {
    bool automatic = false,
  }) async {
    final pausedUntil = _budget.pausedUntil;
    if (pausedUntil != null) {
      return _rejected(SwapQuoteFailureKind.rateLimited, retryAt: pausedUntil);
    }
    if (automatic && _budget.holdsAutomatic) {
      return _rejected(SwapQuoteFailureKind.rateLimited);
    }
    final key = (
      from: from,
      to: to,
      amount: amount,
      order: order,
      slippage: slippage,
    );
    final recent = _budget.recent(key);
    if (recent != null) {
      return SwapQuoteAvailable(
        routedQuoteFromOffer(recent, networks: _networks(), order: order),
      );
    }
    try {
      final offer = await manager
          .quote(
            from: from,
            to: to,
            amount: amount,
            slippage: slippage,
            order: order == SwapQuoteOrder.fastest
                ? RoutedSwapOrder.fastest
                : null,
          )
          .timeout(_timeout);
      _budget.remember(key, offer);
      return SwapQuoteAvailable(
        routedQuoteFromOffer(offer, networks: _networks(), order: order),
      );
    } on TimeoutException {
      _report(_RoutedQuoteLog.timedOut(from, to, order, _timeout));
      return _rejected(SwapQuoteFailureKind.timeout);
    } on RoutedSwapRateLimitedException catch (error) {
      final failure = failureFor(
        error,
        from: from,
        to: to,
        retryAt: _budget.pause(),
      );
      _report(_RoutedQuoteLog.refused(from, to, order, failure.kind, error));
      return SwapQuoteRejected(failure);
    } on RoutedSwapRpcException catch (error) {
      final failure = failureFor(error, from: from, to: to);
      _report(_RoutedQuoteLog.refused(from, to, order, failure.kind, error));
      return SwapQuoteRejected(failure);
    } on Object catch (error) {
      _report(_RoutedQuoteLog.unexpected(from, to, order, error));
      return _rejected(SwapQuoteFailureKind.unknown, detail: error.toString());
    }
  }

  /// Writes [line] to the log; a failing sink never fails a quote.
  void _report(String line) {
    try {
      _log(line);
    } on Object {
      // Diagnostics are best effort.
    }
  }

  /// Max from [offer]: its gas times the SDK probe's margin, and the provider
  /// fees it charges on top in [from], which the form counts too.
  SwapMaxAmount _nativeMax(
    RoutedSwapOffer offer,
    AssetId from,
    Decimal balance,
  ) {
    final gas = offer.networkFees
        .where((fee) => fee.assetId == from || fee.ticker == from.id)
        .fold<Decimal>(Decimal.zero, (sum, fee) => sum + fee.amount);
    // The gas among the costs is counted above, with its margin.
    final providerFees = offer.costs
        .where(
          (cost) =>
              cost.kind == RoutedSwapCostKind.providerFee &&
              !cost.isDeductedFromReceive &&
              cost.assetId == from,
        )
        .fold<Decimal>(Decimal.zero, (sum, cost) => sum + cost.amount);
    var reserve = gas * RoutedSwapManager.maxSellFeeMargin + providerFees;
    var amount = balance - reserve;
    final decimals = from.chainId.decimals;
    if (decimals != null) {
      reserve = reserve.ceil(scale: decimals);
      amount = (balance - reserve).floor(scale: decimals);
    }
    return SwapMaxAmount(
      amount: amount < Decimal.zero ? Decimal.zero : amount,
      reservedForFees: reserve,
      feeAsset: from,
      reserveCovers: providerFees > Decimal.zero
          ? SwapMaxReserve.networkAndProviderFees
          : SwapMaxReserve.networkFees,
    );
  }

  SwapQuoteRejected _rejected(
    SwapQuoteFailureKind kind, {
    String? detail,
    DateTime? retryAt,
  }) => SwapQuoteRejected(
    SwapQuoteFailure(
      source: SwapLiquiditySource.routed,
      kind: kind,
      detail: detail,
      retryAt: retryAt,
    ),
  );

  /// Classifies a typed contract error. Never matches on message text.
  @visibleForTesting
  static SwapQuoteFailure failureFor(
    RoutedSwapRpcException error, {
    required AssetId from,
    required AssetId to,
    DateTime? retryAt,
  }) {
    SwapQuoteFailure failure(
      SwapQuoteFailureKind kind, {
      AssetId? asset,
      Decimal? minimum,
      Decimal? maximum,
      List<String> reasons = const [],
    }) => SwapQuoteFailure(
      source: SwapLiquiditySource.routed,
      kind: kind,
      asset: asset,
      minimum: minimum,
      maximum: maximum,
      reasons: reasons,
      providerRequestId: error.providerRequestId,
      detail: '${error.errorType}: ${error.message}',
      retryAt: retryAt,
    );

    return switch (error) {
      RoutedSwapCoinNotActiveException(:final coin) => failure(
        SwapQuoteFailureKind.assetInactive,
        asset: coin == to.id ? to : from,
      ),
      RoutedSwapPairNotSupportedException() => failure(
        SwapQuoteFailureKind.pairUnsupported,
      ),
      RoutedSwapInvalidParamException(:final param) => failure(
        param == 'amount'
            ? SwapQuoteFailureKind.invalidAmount
            : SwapQuoteFailureKind.unknown,
      ),
      RoutedSwapAmountOutOfBoundsException(
        :final param,
        :final value,
        :final min,
        :final max,
      ) =>
        // KDF reports a slippage outside its cap the same way; only the
        // amount's bounds tell the user to change the amount.
        param == 'amount'
            ? _bounds(value, min, max, failure)
            : failure(SwapQuoteFailureKind.unknown),
      // KDF derives the one address it sends from for every active coin, so
      // its absence is an engine fault: no asset the user picks changes it.
      RoutedSwapMyAddressException() => failure(SwapQuoteFailureKind.unknown),
      RoutedSwapInvalidConfigException() => failure(
        SwapQuoteFailureKind.notConfigured,
      ),
      RoutedSwapNoRouteException(:final reasons) => failure(
        SwapQuoteFailureKind.noRoute,
        reasons: reasons,
      ),
      RoutedSwapRateLimitedException() => failure(
        SwapQuoteFailureKind.rateLimited,
      ),
      RoutedSwapProviderException() ||
      RoutedSwapTransportException() ||
      RoutedSwapInternalException() => failure(
        SwapQuoteFailureKind.serviceError,
      ),
      _ => failure(SwapQuoteFailureKind.unknown),
    };
  }

  static SwapQuoteFailure _bounds(
    String value,
    String min,
    String max,
    SwapQuoteFailure Function(
      SwapQuoteFailureKind kind, {
      AssetId? asset,
      Decimal? minimum,
      Decimal? maximum,
      List<String> reasons,
    })
    failure,
  ) {
    final amount = Decimal.tryParse(value);
    final minimum = Decimal.tryParse(min);
    final maximum = Decimal.tryParse(max);
    if (amount != null && maximum != null && amount > maximum) {
      return failure(SwapQuoteFailureKind.aboveMaximum, maximum: maximum);
    }
    return failure(
      SwapQuoteFailureKind.belowMinimum,
      minimum: minimum,
      maximum: maximum,
    );
  }
}
