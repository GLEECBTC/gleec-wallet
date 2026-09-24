import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/swap/swap_catalog.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';
import 'package:web_dex/views/swap/common/swap_failure_copy.dart';

import 'swap_test_fixtures.dart';

/// Covers the rule that a "can't" says why: a permanent limit is never
/// presented as an outage, and an outage is never presented as a limit.
///
/// Without a loaded translation, copy renders as its key, so these assert
/// which message was chosen rather than its English.
void main() {
  final gleecEvm = assetOf(
    'GLEEC',
    subClass: CoinSubClass.grc20,
    chainId: 11169,
  );
  final paxg = assetOf('PAXG-ERC20', parent: eth);
  final networks = SwapNetworks([eth, usdc, btc, gleecEvm, paxg]);

  SwapQuoteFailure failure(
    SwapQuoteFailureKind kind, {
    SwapLiquiditySource source = SwapLiquiditySource.routed,
  }) => SwapQuoteFailure(source: source, kind: kind);

  group('pricing failures', () {
    final noRoute = failure(
      SwapQuoteFailureKind.noRoute,
      source: SwapLiquiditySource.atomic,
    );

    test('no route with nothing else to say is a plain no-route', () {
      final copy = SwapFailureCopy.of(noRoute, eth, all: [noRoute]);
      expect(copy.message, LocaleKeys.swapErrorNoRoute);
      expect(copy.detail, isNull);
    });

    test('no route while the other source could not look says both', () {
      final copy = SwapFailureCopy.of(
        noRoute,
        eth,
        all: [noRoute, failure(SwapQuoteFailureKind.serviceError)],
      );
      expect(copy.message, LocaleKeys.swapErrorNoRouteOrderBook);
      expect(copy.action, SwapEntryAction.retry);
    });

    test('a GLEEC pair with no offer says why there is no other option', () {
      final copy = SwapFailureCopy.of(
        noRoute,
        gleecEvm,
        all: [noRoute],
        support: SwapPairSupport(
          sources: const {SwapLiquiditySource.atomic},
          routesUnavailableFor: gleecEvm,
        ),
      );
      expect(copy.message, LocaleKeys.swapErrorNoRoute);
      expect(copy.detail, LocaleKeys.swapHelperOrderBookOnly);
    });

    test('a token service error suggests checking the network coin', () {
      final copy = SwapFailureCopy.of(
        failure(SwapQuoteFailureKind.serviceError),
        usdc,
        networks: networks,
      );
      expect(copy.message, LocaleKeys.swapErrorServiceToken);
    });

    test('a native coin service error stays generic', () {
      final copy = SwapFailureCopy.of(
        failure(SwapQuoteFailureKind.serviceError),
        eth,
        networks: networks,
      );
      expect(copy.message, LocaleKeys.swapErrorService);
    });
  });

  group('form issues', () {
    UnifiedSwapState stateFor(AssetId pay, AssetId receive) => UnifiedSwapState(
      loadingAssets: false,
      pay: pay,
      receive: receive,
      catalog: SwapCatalog(
        sources: [
          SwapSourceAssets(
            source: SwapLiquiditySource.atomic,
            quotable: {eth, usdc, gleecEvm, btc},
          ),
          SwapSourceAssets(
            source: SwapLiquiditySource.routed,
            quotable: {eth, usdc, paxg},
          ),
        ],
      ),
    );

    test('a disjoint pair names both assets and the network reason', () {
      final copy = SwapIssueCopy.of(
        SwapFormIssue.pairUnsupported,
        stateFor(gleecEvm, paxg),
        networks: networks,
      )!;
      expect(copy.message, LocaleKeys.swapErrorPairDisjoint);
      expect(copy.detail, LocaleKeys.swapHelperRoutesNoNetwork);
      expect(copy.action, SwapEntryAction.chooseAnother);
    });

    test('a non-EVM order-book asset says routes cover EVM only', () {
      final copy = SwapIssueCopy.of(
        SwapFormIssue.pairUnsupported,
        stateFor(btc, paxg),
        networks: networks,
      )!;
      expect(copy.message, LocaleKeys.swapErrorPairDisjoint);
      expect(copy.detail, LocaleKeys.swapHelperRoutesEvmOnly);
    });

    test('an inactive asset offers to activate it', () {
      final copy = SwapIssueCopy.of(
        SwapFormIssue.assetInactive,
        stateFor(eth, usdc),
        networks: networks,
      )!;
      expect(copy.message, LocaleKeys.swapErrorInactive);
      expect(copy.action, SwapEntryAction.activate);
    });

    test('a token without its network coin says which coin', () {
      final copy = SwapIssueCopy.of(
        SwapFormIssue.noFeeBalance,
        stateFor(usdc, eth),
        networks: networks,
      )!;
      expect(copy.message, LocaleKeys.swapErrorNoFeeBalance);
    });

    test('a missing amount is not an error', () {
      expect(
        SwapIssueCopy.of(
          SwapFormIssue.amountMissing,
          stateFor(eth, usdc),
          networks: networks,
        ),
        isNull,
      );
    });
  });
}
