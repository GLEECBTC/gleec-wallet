// The analyzer does not treat test_units as tests, so @visibleForTesting
// members read as violations here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:web_dex/shared/swap/atomic_swap_source.dart';
import 'package:web_dex/shared/swap/routed_swap_source.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';

import 'swap_test_fixtures.dart';

/// Covers the pure halves of both quote sources: how an atomic quote picks
/// the order it will actually fill against, and how a routed error becomes
/// the entry form's state.
void main() {
  group('atomic: one order, whole', () {
    OrderInfo bid(String price, String min, String max) => OrderInfo(
      price: NumericValue(decimal: price),
      baseMinVolume: NumericValue(decimal: min),
      baseMaxVolume: NumericValue(decimal: max),
    );

    test('takes the best price among orders that can fill the amount', () {
      final best = AtomicSwapQuoteSource.bestFillingBid([
        bid('3010', '0.1', '0.5'), // too small for 1 ETH
        bid('2990', '0.1', '5'),
        bid('3000', '0.5', '2'),
      ], d('1'));

      // A walk across several orders would promise 3010 for part of the
      // amount; the placed order matches one maker only.
      expect(best!.price, d('3000'));
    });

    test('finds nothing when no single order is large enough', () {
      final best = AtomicSwapQuoteSource.bestFillingBid([
        bid('3000', '0.1', '0.6'),
        bid('2990', '0.1', '0.6'),
      ], d('1'));
      expect(best, isNull);
    });

    test('respects an order\'s minimum', () {
      final best = AtomicSwapQuoteSource.bestFillingBid([
        bid('3000', '2', '5'),
      ], d('1'));
      expect(best, isNull);
    });
  });

  group('routed: errors become typed entry states', () {
    SwapQuoteFailure classify(RoutedSwapRpcException error) =>
        RoutedSwapQuoteSource.failureFor(error, from: eth, to: usdc);

    test('an inactive destination points at the destination', () {
      final failure = classify(
        const RoutedSwapCoinNotActiveException(
          coin: 'USDC-ERC20',
          message: 'not active',
        ),
      );
      expect(failure.kind, SwapQuoteFailureKind.assetInactive);
      expect(failure.asset, usdc);
    });

    test('out of bounds splits into above and below', () {
      final above = classify(
        const RoutedSwapAmountOutOfBoundsException(
          param: 'amount',
          value: '100',
          min: '0.01',
          max: '50',
          message: 'too much',
        ),
      );
      final below = classify(
        const RoutedSwapAmountOutOfBoundsException(
          param: 'amount',
          value: '0.001',
          min: '0.01',
          max: '50',
          message: 'too little',
        ),
      );
      expect(above.kind, SwapQuoteFailureKind.aboveMaximum);
      expect(above.maximum, d('50'));
      expect(below.kind, SwapQuoteFailureKind.belowMinimum);
      expect(below.minimum, d('0.01'));
    });

    test('no route keeps its reasons and support id', () {
      final failure = classify(
        const RoutedSwapNoRouteException(
          message: 'no route',
          reasons: ['Insufficient liquidity'],
          providerRequestId: 'req-1',
        ),
      );
      expect(failure.kind, SwapQuoteFailureKind.noRoute);
      expect(failure.reasons, ['Insufficient liquidity']);
      expect(failure.providerRequestId, 'req-1');
    });

    test('maps the remaining contract errors', () {
      expect(
        classify(const RoutedSwapRateLimitedException(message: 'slow')).kind,
        SwapQuoteFailureKind.rateLimited,
      );
      expect(
        classify(
          const RoutedSwapMyAddressException(
            coin: 'ETH',
            detail: 'hw',
            message: 'x',
          ),
        ).kind,
        SwapQuoteFailureKind.unsupportedSigner,
      );
      expect(
        classify(
          const RoutedSwapInvalidConfigException(detail: 'x', message: 'x'),
        ).kind,
        SwapQuoteFailureKind.notConfigured,
      );
      expect(
        classify(
          const RoutedSwapTransportException(detail: 'x', message: 'x'),
        ).kind,
        SwapQuoteFailureKind.serviceError,
      );
      expect(
        classify(
          const RoutedSwapInvalidParamException(
            param: 'amount',
            reason: 'decimals',
            message: 'x',
          ),
        ).kind,
        SwapQuoteFailureKind.invalidAmount,
      );
    });
  });
}
