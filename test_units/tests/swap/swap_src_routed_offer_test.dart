// The analyzer does not treat test_units as tests, so @visibleForTesting
// members read as violations here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/shared/swap/routed_swap_chains.dart';
import 'package:web_dex/shared/swap/routed_swap_source.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';

import 'swap_src_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers how an aggregator offer becomes a quote the form can compare with
/// an order-book one, and how each typed contract error becomes an entry
/// state.
void main() {
  final arb = assetOf(
    'ETH-ARB20',
    subClass: CoinSubClass.arbitrum,
    chainId: 42161,
  );
  final usdcArb = assetOf(
    'USDC-ARB20',
    subClass: CoinSubClass.arbitrum,
    parent: arb,
    chainId: 42161,
  );
  final networks = SwapNetworks([eth, usdc, arb, usdcArb]);

  SwapQuote quoteFrom(RoutedSwapOffer offer, {SwapQuoteOrder? order}) =>
      routedQuoteFromOffer(offer, networks: networks, order: order);

  SwapRouteStage stage(
    SwapRouteStageKind kind, [
    String? network,
    AssetId? asset,
  ]) => SwapRouteStage(kind: kind, network: network, asset: asset);

  group('offers become quotes', () {
    test('a same-chain offer carries every figure and cost', () {
      final offer = offerOf(
        costs: [
          RoutedSwapCost(
            label: 'LI.FI fee',
            amount: d('1.5'),
            kind: RoutedSwapCostKind.providerFee,
            isDeductedFromReceive: true,
            assetId: usdc,
            usdValue: d('1.5'),
          ),
          RoutedSwapCost(
            label: 'Network fee',
            amount: d('0.0005'),
            kind: RoutedSwapCostKind.gas,
            isDeductedFromReceive: false,
            assetId: eth,
            usdValue: d('1.5'),
          ),
          RoutedSwapCost(
            label: 'Approval',
            amount: d('0.0001'),
            kind: RoutedSwapCostKind.approvalGas,
            isDeductedFromReceive: false,
            symbol: 'WETH',
          ),
        ],
        duration: const Duration(seconds: 45),
      );

      final quote = quoteFrom(offer);

      expect(quote.id, 'routed-cheapest');
      expect(quote.source, SwapLiquiditySource.routed);
      expect(quote.routeKind, SwapRouteKind.sameChain);
      expect(quote.order, SwapQuoteOrder.cheapest);
      expect(quote.sellAmount, d('1'));
      expect(quote.expectedReceive, d('3000'));
      expect(quote.guaranteedReceive, d('2985'));
      expect(quote.fees.map((fee) => fee.kind), [
        SwapFeeKind.swap,
        SwapFeeKind.network,
        SwapFeeKind.approvalNetwork,
      ]);
      expect(
        quote.fees.first,
        SwapFeeComponent(
          kind: SwapFeeKind.swap,
          amount: d('1.5'),
          deductedFromReceive: true,
          asset: usdc,
          usdValue: d('1.5'),
        ),
      );
      expect(quote.fees.last.symbol, 'WETH');
      expect(quote.fees.last.asset, isNull);
      expect(quote.stages, [
        stage(SwapRouteStageKind.prepare),
        stage(SwapRouteStageKind.send, 'Ethereum', eth),
        stage(SwapRouteStageKind.convert, 'Ethereum'),
        stage(SwapRouteStageKind.receive, 'Ethereum', usdc),
      ]);
      expect(quote.approval, isNull);
      expect(quote.fromAddress, '0xfrom');
      expect(quote.toAddress, '0xto');
      expect(quote.estimatedDuration, const Duration(seconds: 45));
      expect(quote.slippage, 0.005);
      expect(quote.quotedAt, offer.quotedAt);
      expect(quote.diagnostic, 'lifi · Tool (tool)');
      expect(quote.payload, same(offer));
    });

    test('the offer\'s own route order applies when none is named', () {
      final fastest = quoteFrom(offerOf(order: RoutedSwapOrder.fastest));
      final cheapest = quoteFrom(offerOf(order: RoutedSwapOrder.cheapest));
      final named = quoteFrom(
        offerOf(order: RoutedSwapOrder.fastest, slippage: 0.01),
        order: SwapQuoteOrder.cheapest,
      );

      expect(fastest.order, SwapQuoteOrder.fastest);
      expect(fastest.id, 'routed-fastest');
      expect(cheapest.order, SwapQuoteOrder.cheapest);
      expect(named.order, SwapQuoteOrder.cheapest);
      expect(named.slippage, 0.01);
    });

    test('a token that resets its permission first takes two steps', () {
      final quote = quoteFrom(
        offerOf(
          from: usdc,
          to: eth,
          sell: '100',
          approval: const RoutedSwapApprovalInfo(
            txCount: 2,
            resetsFirst: true,
            spender: '0xspender',
          ),
        ),
      );

      expect(quote.stages.take(4), [
        stage(SwapRouteStageKind.prepare),
        stage(SwapRouteStageKind.resetApproval, 'Ethereum', usdc),
        stage(SwapRouteStageKind.approve, 'Ethereum', usdc),
        stage(SwapRouteStageKind.send, 'Ethereum', usdc),
      ]);
      expect(
        quote.approval,
        SwapApprovalRequirement(
          asset: usdc,
          exactAmount: d('100'),
          resetsFirst: true,
        ),
      );
      expect(quote.requiresApproval, isTrue);
    });

    test('an exact approval alone takes one step', () {
      final quote = quoteFrom(
        offerOf(
          from: usdc,
          to: eth,
          approval: const RoutedSwapApprovalInfo(
            txCount: 1,
            resetsFirst: false,
            spender: '0xspender',
          ),
        ),
      );

      expect(quote.stages.map((s) => s.kind).take(3), [
        SwapRouteStageKind.prepare,
        SwapRouteStageKind.approve,
        SwapRouteStageKind.send,
      ]);
      expect(quote.approval!.resetsFirst, isFalse);
    });

    test('legs describe the middle of the route, network by network', () {
      final quote = quoteFrom(
        offerOf(
          to: usdcArb,
          kind: RoutedSwapRouteKind.crossChain,
          legs: const [
            RoutedSwapLeg(type: RoutedSwapStepType.swap, chainId: 1),
            RoutedSwapLeg(
              type: RoutedSwapStepType.cross,
              fromChainId: 1,
              toChainId: 42161,
            ),
            RoutedSwapLeg(type: RoutedSwapStepType.swap, chainId: 42161),
            RoutedSwapLeg(type: RoutedSwapStepType.unknown),
          ],
        ),
      );

      expect(quote.routeKind, SwapRouteKind.crossChain);
      expect(quote.stages, [
        stage(SwapRouteStageKind.prepare),
        stage(SwapRouteStageKind.send, 'Ethereum', eth),
        stage(SwapRouteStageKind.convert, 'Ethereum'),
        stage(SwapRouteStageKind.bridge, 'Arbitrum'),
        stage(SwapRouteStageKind.convert, 'Arbitrum'),
        stage(SwapRouteStageKind.receive, 'Arbitrum', usdcArb),
      ]);
    });

    test(
      'a leg on a chain the wallet does not know uses the route\'s ends',
      () {
        final quote = quoteFrom(
          offerOf(
            to: usdcArb,
            kind: RoutedSwapRouteKind.crossChain,
            legs: const [
              RoutedSwapLeg(type: RoutedSwapStepType.swap),
              RoutedSwapLeg(type: RoutedSwapStepType.cross, toChainId: 888888),
            ],
          ),
        );

        expect(quote.stages.sublist(2, 4), [
          stage(SwapRouteStageKind.convert, 'Ethereum'),
          stage(SwapRouteStageKind.bridge, 'Arbitrum'),
        ]);
      },
    );

    test('without legs, the route\'s kind decides its middle', () {
      List<SwapRouteStage> middle(
        RoutedSwapRouteKind kind, {
        bool odd = false,
      }) {
        final stages = quoteFrom(
          offerOf(
            to: usdcArb,
            kind: kind,
            legs: [
              if (odd) const RoutedSwapLeg(type: RoutedSwapStepType.unknown),
            ],
          ),
        ).stages;
        return stages.sublist(2, stages.length - 1);
      }

      expect(middle(RoutedSwapRouteKind.crossChain), [
        stage(SwapRouteStageKind.bridge, 'Arbitrum'),
      ]);
      expect(middle(RoutedSwapRouteKind.sameChain, odd: true), [
        stage(SwapRouteStageKind.convert, 'Ethereum'),
      ]);
      // An unknown kind may hide a bridge wait, so it is described as one.
      expect(middle(RoutedSwapRouteKind.unknown), [
        stage(SwapRouteStageKind.bridge, 'Arbitrum'),
      ]);
    });
  });

  group('typed errors become entry states', () {
    SwapQuoteFailure classify(
      RoutedSwapRpcException error, {
      DateTime? retryAt,
    }) => RoutedSwapQuoteSource.failureFor(
      error,
      from: eth,
      to: usdc,
      retryAt: retryAt,
    );

    test('an inactive coin points at the side KDF named', () {
      SwapQuoteFailure inactive(String coin) => classify(
        RoutedSwapCoinNotActiveException(coin: coin, message: 'inactive'),
      );

      expect(inactive('ETH').asset, eth);
      expect(inactive('USDC-ERC20').asset, usdc);
      expect(inactive('ETH').kind, SwapQuoteFailureKind.assetInactive);
    });

    test('an unsupported pair can never be priced here', () {
      final failure = classify(
        const RoutedSwapPairNotSupportedException(
          from: 'ETH',
          to: 'USDC-ERC20',
          reason: 'not eligible',
          message: 'unsupported',
        ),
      );

      expect(failure.kind, SwapQuoteFailureKind.pairUnsupported);
      expect(failure.isPermanent, isTrue);
    });

    test('an invalid parameter blames the amount only if it is one', () {
      SwapQuoteFailure invalid(String param) => classify(
        RoutedSwapInvalidParamException(
          param: param,
          reason: 'bad value',
          message: 'invalid',
        ),
      );

      expect(invalid('order').kind, SwapQuoteFailureKind.unknown);
      expect(invalid('amount').kind, SwapQuoteFailureKind.invalidAmount);
    });

    test('a signer or node that cannot route sends the user elsewhere', () {
      final signer = classify(
        const RoutedSwapMyAddressException(
          coin: 'ETH',
          detail: 'hardware wallet',
          message: 'no single address',
        ),
      );
      final config = classify(
        const RoutedSwapInvalidConfigException(
          detail: 'no provider',
          message: 'invalid config',
        ),
      );

      expect(signer.kind, SwapQuoteFailureKind.unsupportedSigner);
      expect(config.kind, SwapQuoteFailureKind.notConfigured);
      expect(config.isPermanent, isTrue);
      expect(config.detail, 'InvalidConfig: invalid config');
    });

    test('bounds read as above or below, whichever the amount broke', () {
      SwapQuoteFailure bounds(String value, {String max = '50'}) => classify(
        RoutedSwapAmountOutOfBoundsException(
          param: 'amount',
          value: value,
          min: '0.01',
          max: max,
          message: 'out of bounds',
        ),
      );

      final above = bounds('60');
      final below = bounds('0.001');
      final unreadable = bounds('lots');
      final noCeiling = bounds('60', max: 'none');

      expect(above.kind, SwapQuoteFailureKind.aboveMaximum);
      expect(above.maximum, d('50'));
      expect(above.minimum, isNull);
      expect(below.kind, SwapQuoteFailureKind.belowMinimum);
      expect(below.minimum, d('0.01'));
      expect(below.maximum, d('50'));
      expect(unreadable.kind, SwapQuoteFailureKind.belowMinimum);
      expect(noCeiling.kind, SwapQuoteFailureKind.belowMinimum);
      expect(noCeiling.maximum, isNull);
    });

    test('provider, transport and engine failures may pass', () {
      final kinds = [
        classify(
          const RoutedSwapProviderException(
            detail: 'bad gateway',
            message: 'provider',
            providerRequestId: 'req-2',
          ),
        ),
        classify(const RoutedSwapTransportException(detail: 'x', message: 'x')),
        classify(const RoutedSwapInternalException(detail: 'x', message: 'x')),
      ];

      expect(
        kinds.map((f) => f.kind),
        everyElement(SwapQuoteFailureKind.serviceError),
      );
      expect(kinds.every((f) => f.isTransient), isTrue);
      expect(kinds.first.providerRequestId, 'req-2');
    });

    test('task errors and unknown error types read as unknown', () {
      final failures = [
        classify(const RoutedSwapNoSuchTaskException(message: 'gone')),
        classify(const RoutedSwapTaskFinishedException(message: 'done')),
        classify(const RoutedSwapTaskAlreadyBroadcastException(message: 'x')),
        classify(
          const RoutedSwapUnknownRpcException(
            errorType: 'NewThing',
            message: 'new',
            errorData: {'provider_request_id': 'req-3'},
          ),
        ),
      ];

      expect(
        failures.map((f) => f.kind),
        everyElement(SwapQuoteFailureKind.unknown),
      );
      expect(failures.last.providerRequestId, 'req-3');
      expect(failures.last.detail, 'NewThing: new');
    });

    test('a failure keeps the error, its source and any retry time', () {
      final retryAt = DateTime(2026, 9, 24, 12, 1);
      final failure = classify(
        const RoutedSwapRateLimitedException(message: 'slow down'),
        retryAt: retryAt,
      );

      expect(failure.source, SwapLiquiditySource.routed);
      expect(failure.kind, SwapQuoteFailureKind.rateLimited);
      expect(failure.retryAt, retryAt);
      expect(failure.detail, 'RateLimited: slow down');
    });
  });

  test('only EVM assets on a network the aggregator serves are routable', () {
    final gleecEvm = assetOf(
      'GLEEC',
      subClass: CoinSubClass.grc20,
      chainId: 11169,
    );

    expect(isRoutedSwapCandidate(usdcArb), isTrue);
    expect(isRoutedSwapCandidate(eth), isTrue);
    expect(isRoutedSwapCandidate(gleecEvm), isFalse);
    expect(isRoutedSwapCandidate(btc), isFalse);
  });
}
