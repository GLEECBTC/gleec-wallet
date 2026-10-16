part of 'routed_swap_source.dart';

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
