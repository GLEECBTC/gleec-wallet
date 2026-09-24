import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/shared/swap/routed_swap_chains.dart';
import 'package:web_dex/shared/swap/swap_catalog.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';

/// Prices swaps through the aggregator, executed by KDF.
///
/// Everything hard about the routed contract lives in [RoutedSwapManager];
/// this only normalises its offers into [SwapQuote]s and its typed errors
/// into [SwapQuoteFailure]s, so the UI can compare and explain them next to
/// an atomic quote.
class RoutedSwapQuoteSource implements SwapQuoteSource {
  /// Creates a source backed by [manager].
  RoutedSwapQuoteSource(
    this.manager, {
    required SwapNetworks Function() networks,
    bool Function(AssetId from, AssetId to)? tradingAllowed,
    bool Function(AssetId asset) isCandidate = isRoutedSwapCandidate,
    Duration timeout = const Duration(seconds: 20),
    Duration catalogTimeout = const Duration(seconds: 10),
  }) : _networks = networks,
       _tradingAllowed = tradingAllowed,
       _isCandidate = isCandidate,
       _timeout = timeout,
       _catalogTimeout = catalogTimeout;

  /// The SDK manager doing the real work.
  final RoutedSwapManager manager;
  final SwapNetworks Function() _networks;
  final bool Function(AssetId from, AssetId to)? _tradingAllowed;
  final bool Function(AssetId asset) _isCandidate;
  final Duration _timeout;

  /// Shorter than a quote's: the form waits on the catalog before pricing.
  final Duration _catalogTimeout;

  /// What KDF last listed, for when it cannot be read again.
  Set<AssetId>? _lastEligible;

  @override
  SwapLiquiditySource get source => SwapLiquiditySource.routed;

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
    try {
      final eligible = await manager.eligibleAssets().timeout(_catalogTimeout);
      _lastEligible = eligible;
      return SwapSourceAssets(
        source: source,
        quotable: eligible,
        onceActive: onceActive,
      );
    } on Object {
      // An outage must not empty the picker or make every pair read as
      // unsupported: keep KDF's last answer, else the wallet's own guess.
      final last = _lastEligible;
      return SwapSourceAssets(
        source: source,
        quotable: last ?? candidates.intersection(activated),
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
    try {
      final max = await manager
          .maxSellAmount(from: from, to: to, balance: balance)
          .timeout(_timeout);
      return SwapMaxAmount(
        amount: max.amount,
        reservedForFees: max.reservedForFees,
        feeAsset: max.feeAsset,
      );
    } on Object {
      return null;
    }
  }

  @override
  Future<List<SwapQuoteResult>> quote(SwapQuoteRequest request) async {
    if (_tradingAllowed != null && !_tradingAllowed(request.from, request.to)) {
      return [_rejected(SwapQuoteFailureKind.tradingBlocked)];
    }

    final cheapest = _quote(
      request.from,
      request.to,
      request.amount,
      SwapQuoteOrder.cheapest,
    );
    if (!request.includeAlternatives) return [await cheapest];

    // Both orders in parallel, so comparison costs one round trip. When the
    // provider rate-limits the second, the first still stands.
    final results = await Future.wait([
      cheapest,
      _quote(request.from, request.to, request.amount, SwapQuoteOrder.fastest),
    ]);
    final best = results.first;
    final fastest = results.last;
    if (best is SwapQuoteAvailable && fastest is SwapQuoteAvailable) {
      // The same route under both orders is one option, not two.
      final a = best.quote;
      final b = fastest.quote;
      if (a.diagnostic == b.diagnostic &&
          a.guaranteedReceive == b.guaranteedReceive) {
        return [best];
      }
      return results;
    }
    // A failed alternative is not a reason to show an error: the default
    // route decides what the user sees.
    return [best];
  }

  @override
  Future<SwapQuoteResult> requote(SwapQuote quote) => _quote(
    quote.from,
    quote.to,
    quote.sellAmount,
    quote.order ?? SwapQuoteOrder.cheapest,
  );

  Future<SwapQuoteResult> _quote(
    AssetId from,
    AssetId to,
    Decimal amount,
    SwapQuoteOrder order,
  ) async {
    try {
      final offer = await manager
          .quote(
            from: from,
            to: to,
            amount: amount,
            order: order == SwapQuoteOrder.fastest
                ? RoutedSwapOrder.fastest
                : null,
          )
          .timeout(_timeout);
      return SwapQuoteAvailable(
        routedQuoteFromOffer(offer, networks: _networks(), order: order),
      );
    } on TimeoutException {
      return _rejected(SwapQuoteFailureKind.timeout);
    } on RoutedSwapRpcException catch (error) {
      return SwapQuoteRejected(failureFor(error, from: from, to: to));
    } on Object catch (error) {
      return _rejected(SwapQuoteFailureKind.unknown, detail: error.toString());
    }
  }

  SwapQuoteRejected _rejected(SwapQuoteFailureKind kind, {String? detail}) =>
      SwapQuoteRejected(
        SwapQuoteFailure(
          source: SwapLiquiditySource.routed,
          kind: kind,
          detail: detail,
        ),
      );

  /// Classifies a typed contract error. Never matches on message text.
  @visibleForTesting
  static SwapQuoteFailure failureFor(
    RoutedSwapRpcException error, {
    required AssetId from,
    required AssetId to,
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
      RoutedSwapMyAddressException() => failure(
        SwapQuoteFailureKind.unsupportedSigner,
      ),
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

/// Normalises a routed [offer] into a [SwapQuote], naming networks with
/// [networks]. Shared by quoting and by execution, so a running swap describes
/// its stages exactly as its quote did.
SwapQuote routedQuoteFromOffer(
  RoutedSwapOffer offer, {
  required SwapNetworks networks,
  SwapQuoteOrder? order,
}) {
  final resolvedOrder =
      order ??
      (offer.order == RoutedSwapOrder.fastest
          ? SwapQuoteOrder.fastest
          : SwapQuoteOrder.cheapest);
  final fromNetwork = networks.networkOf(offer.from);
  final toNetwork = networks.networkOf(offer.to);

  final stages = <SwapRouteStage>[
    const SwapRouteStage(kind: SwapRouteStageKind.prepare),
    if (offer.approval?.resetsFirst ?? false)
      SwapRouteStage(
        kind: SwapRouteStageKind.resetApproval,
        network: fromNetwork,
        asset: offer.from,
      ),
    if (offer.approval != null)
      SwapRouteStage(
        kind: SwapRouteStageKind.approve,
        network: fromNetwork,
        asset: offer.from,
      ),
    SwapRouteStage(
      kind: SwapRouteStageKind.send,
      network: fromNetwork,
      asset: offer.from,
    ),
    ..._routedLegStages(offer, networks, fromNetwork, toNetwork),
    SwapRouteStage(
      kind: SwapRouteStageKind.receive,
      network: toNetwork,
      asset: offer.to,
    ),
  ];

  return SwapQuote(
    id: 'routed-${resolvedOrder.name}',
    source: SwapLiquiditySource.routed,
    routeKind: offer.isCrossChain
        ? SwapRouteKind.crossChain
        : SwapRouteKind.sameChain,
    order: resolvedOrder,
    from: offer.from,
    to: offer.to,
    sellAmount: offer.sellAmount,
    expectedReceive: offer.expectedReceive,
    guaranteedReceive: offer.guaranteedReceive,
    fees: [
      for (final cost in offer.costs)
        SwapFeeComponent(
          kind: switch (cost.kind) {
            RoutedSwapCostKind.providerFee => SwapFeeKind.swap,
            RoutedSwapCostKind.gas => SwapFeeKind.network,
            RoutedSwapCostKind.approvalGas => SwapFeeKind.approvalNetwork,
          },
          amount: cost.amount,
          deductedFromReceive: cost.isDeductedFromReceive,
          asset: cost.assetId,
          symbol: cost.symbol,
          usdValue: cost.usdValue,
        ),
    ],
    stages: stages,
    approval: offer.approval == null
        ? null
        : SwapApprovalRequirement(
            asset: offer.from,
            exactAmount: offer.sellAmount,
            resetsFirst: offer.approval!.resetsFirst,
          ),
    fromAddress: offer.fromAddress,
    toAddress: offer.toAddress,
    estimatedDuration: offer.estimatedDuration,
    slippage: offer.slippage ?? 0.005,
    quotedAt: offer.quotedAt,
    diagnostic: '${offer.provider} · ${offer.toolName} (${offer.toolKey})',
    payload: offer,
  );
}

/// The middle of the route, from its legs: a bridge moves to the leg's
/// destination network; a swap converts on the leg's network.
List<SwapRouteStage> _routedLegStages(
  RoutedSwapOffer offer,
  SwapNetworks networks,
  String fromNetwork,
  String toNetwork,
) {
  final stages = <SwapRouteStage>[];
  for (final leg in offer.legs) {
    switch (leg.type) {
      case RoutedSwapStepType.cross:
        stages.add(
          SwapRouteStage(
            kind: SwapRouteStageKind.bridge,
            network: networks.networkOfEvmChain(leg.toChainId) ?? toNetwork,
          ),
        );
      case RoutedSwapStepType.swap:
        stages.add(
          SwapRouteStage(
            kind: SwapRouteStageKind.convert,
            network: networks.networkOfEvmChain(leg.chainId) ?? fromNetwork,
          ),
        );
      case RoutedSwapStepType.unknown:
        break;
    }
  }
  if (stages.isNotEmpty) return stages;
  // No legs reported: describe the route from its kind alone.
  return [
    if (offer.isCrossChain)
      SwapRouteStage(kind: SwapRouteStageKind.bridge, network: toNetwork)
    else
      SwapRouteStage(kind: SwapRouteStageKind.convert, network: fromNetwork),
  ];
}
