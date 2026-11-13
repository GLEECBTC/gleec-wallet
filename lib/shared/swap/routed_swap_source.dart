import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart'
    show DiagnosticSanitizer;
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/shared/swap/routed_swap_chains.dart';
import 'package:web_dex/shared/swap/routed_swap_max_policy.dart';
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
    this.nativeMaxGasReserve = RoutedSwapMaxPolicy.enabledByDefault,
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

  /// Retains gas headroom in native Max through the release quote policy.
  final bool nativeMaxGasReserve;
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
    SwapQuoteOrder order = SwapQuoteOrder.cheapest,
    double? slippage,
  }) async {
    final result = await _quote(
      from,
      to,
      balance,
      order,
      slippage ?? _defaultSlippage,
      max: true,
    );
    if (result case SwapQuoteRejected(:final failure)) {
      throw SwapMaxUnavailableException(failure);
    }
    final quote = (result as SwapQuoteAvailable).quote;
    return _maxFromQuote(quote);
  }

  SwapMaxAmount _maxFromQuote(SwapQuote quote) {
    final offer = quote.payload! as RoutedSwapOffer;
    final providerFees = offer.costs
        .where(
          (cost) =>
              cost.kind == RoutedSwapCostKind.providerFee &&
              !cost.isDeductedFromReceive &&
              cost.assetId == quote.from,
        )
        .fold<Decimal>(Decimal.zero, (sum, cost) => sum + cost.amount);
    return SwapMaxAmount(
      amount: quote.sellAmount,
      reservedForFees:
          quote.maxRetainedBalance ?? quote.fundingOnTopIn(quote.from),
      feeAsset: quote.from.isChildAsset && providerFees == Decimal.zero
          ? quote.from.parentId
          : quote.from,
      reserveCovers: _reserveCovers(quote.from, providerFees),
      source: source,
      quote: quote,
    );
  }

  bool _blocked(AssetId from, AssetId to) =>
      _tradingAllowed != null && !_tradingAllowed(from, to);

  @override
  Future<List<SwapQuoteResult>> quote(SwapQuoteRequest request) async {
    if (_blocked(request.from, request.to)) {
      return [_rejected(SwapQuoteFailureKind.tradingBlocked)];
    }
    final orders = request.orders.isEmpty
        ? const {SwapQuoteOrder.cheapest}
        : request.orders;
    final results = <SwapQuoteResult>[];
    var amount = request.amount;
    if (request.maxSource == source) {
      final result = await _quote(
        request.from,
        request.to,
        amount,
        request.maxOrder,
        request.slippage ?? _defaultSlippage,
        automatic: request.automatic,
        max: true,
      );
      if (result is SwapQuoteRejected) return [result];
      amount = (result as SwapQuoteAvailable).quote.sellAmount;
      results.add(result);
    }
    results.addAll(
      await Future.wait([
        for (final order in orders)
          if (request.maxSource != source || order != request.maxOrder)
            _quote(
              request.from,
              request.to,
              amount,
              order,
              request.slippage ?? _defaultSlippage,
              automatic: request.automatic,
            ),
      ]),
    );
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
  /// better price must still execute against the accepted minimum.
  @override
  Future<SwapQuoteResult> requote(SwapQuote quote) async {
    if (_blocked(quote.from, quote.to)) {
      return _rejected(SwapQuoteFailureKind.tradingBlocked);
    }
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
    bool max = false,
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
      amount: max ? Decimal.zero : amount,
      order: order,
      slippage: slippage,
      max: max,
    );
    final recent = _budget.recent(key);
    if (recent != null) return SwapQuoteAvailable(recent);
    try {
      final routedOrder = order == SwapQuoteOrder.fastest
          ? RoutedSwapOrder.fastest
          : null;
      final ({RoutedSwapOffer offer, Decimal? retainedBalance}) priced;
      if (max) {
        priced = await const RoutedSwapMaxPolicy().quote(
          manager: manager,
          from: from,
          to: to,
          slippage: slippage,
          order: routedOrder,
          timeout: _timeout * 3,
          enabled: nativeMaxGasReserve,
        );
      } else {
        priced = (
          offer: await manager
              .quote(
                from: from,
                to: to,
                amount: amount,
                slippage: slippage,
                order: routedOrder,
              )
              .timeout(_timeout),
          retainedBalance: null,
        );
      }
      final quote = routedQuoteFromOffer(
        priced.offer,
        networks: _networks(),
        order: order,
        maxRetainedBalance: priced.retainedBalance,
      );
      _budget.remember(key, quote);
      return SwapQuoteAvailable(quote);
    } on SwapMaxUnavailableException catch (error) {
      _report(
        _RoutedQuoteLog.unexpected(
          from,
          to,
          order,
          error.failure.detail ?? 'Native Max unavailable',
        ),
      );
      return SwapQuoteRejected(error.failure);
    } on TimeoutException {
      _report(
        _RoutedQuoteLog.timedOut(
          from,
          to,
          order,
          max ? _timeout * 3 : _timeout,
        ),
      );
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

  /// What a Max reserve in [from] pays for: a token's holds only its
  /// [providerFees], as its gas is paid in its network's coin. Taken from
  /// the coin, not the reserve, which is rounded up to the coin's places.
  static SwapMaxReserve _reserveCovers(AssetId from, Decimal providerFees) {
    if (providerFees <= Decimal.zero) return SwapMaxReserve.networkFees;
    return from.isChildAsset
        ? SwapMaxReserve.providerFees
        : SwapMaxReserve.networkAndProviderFees;
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
      RoutedSwapInsufficientBalanceException(
        :final coin,
        :final available,
        :final required,
        :final lockedBySwaps,
      ) =>
        SwapQuoteFailure(
          source: SwapLiquiditySource.routed,
          kind: SwapQuoteFailureKind.insufficientFunds,
          asset: [
            from,
            to,
            from.parentId,
            to.parentId,
          ].whereType<AssetId>().where((a) => a.id == coin).firstOrNull,
          ticker: coin,
          minimum: Decimal.tryParse(required),
          available: Decimal.tryParse(available),
          lockedBySwaps: lockedBySwaps == null
              ? null
              : Decimal.tryParse(lockedBySwaps),
          detail: error.message,
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
      // A node that won't estimate gas for an address without the network's
      // coin answers the same as one that is down, so a failed estimate reads
      // as a service error, whose copy names the coin to check.
      RoutedSwapProviderException() ||
      RoutedSwapTransportException() ||
      RoutedSwapInternalException() ||
      RoutedSwapGasEstimationFailedException() => failure(
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
