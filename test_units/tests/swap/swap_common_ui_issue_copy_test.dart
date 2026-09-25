import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_catalog.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/views/swap/common/swap_failure_copy.dart';

import 'swap_common_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// The entry form's words for a form it cannot price yet, and the action it
/// offers.
void main() {
  final gleecEvm = assetOf(
    'GLEEC',
    subClass: CoinSubClass.grc20,
    chainId: 11169,
  );
  final paxg = assetOf('PAXG-ERC20', parent: eth);
  final doge = assetOf('DOGE', subClass: CoinSubClass.utxo, chainId: 0);
  final networks = SwapNetworks([eth, usdc, btc, gleecEvm, paxg]);

  UnifiedSwapState stateFor(
    AssetId? pay,
    AssetId? receive, {
    Decimal? balance,
    Set<AssetId>? activated,
  }) => UnifiedSwapState(
    loadingAssets: false,
    pay: pay,
    receive: receive,
    balance: balance,
    catalog: SwapCatalog(
      activated: activated,
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

  SwapIssueCopy? issueOf(
    SwapFormIssue issue,
    UnifiedSwapState state, {
    String? feeNeeded,
    String? feeHeld,
  }) => SwapIssueCopy.of(
    issue,
    state,
    networks: networks,
    feeNeeded: feeNeeded,
    feeHeld: feeHeld,
  );

  group('swap form issue copy', () {
    useEnglishCopy();

    void expectCopy(
      SwapIssueCopy? copy,
      String message, {
      SwapEntryAction action = SwapEntryAction.none,
      String? detail,
    }) {
      expect(copy, isNotNull);
      expect(copy!.message, message);
      expect(copy.action, action);
      expect(copy.detail, detail);
    }

    test('a missing amount has no message yet', () {
      expect(issueOf(SwapFormIssue.amountMissing, stateFor(eth, usdc)), isNull);
    });

    group('unsupported pair', () {
      test('without a known reason, asks for another asset', () {
        expectCopy(
          issueOf(SwapFormIssue.pairUnsupported, stateFor(eth, null)),
          "This pair can't be swapped here. Choose another asset.",
          action: SwapEntryAction.chooseAnother,
        );
      });

      test('names the asset no source trades', () {
        expectCopy(
          issueOf(SwapFormIssue.pairUnsupported, stateFor(doge, eth)),
          "DOGE can't be swapped in this wallet. Choose another asset.",
          action: SwapEntryAction.chooseAnother,
        );
      });

      test('a disjoint pair names both sides and why routes stop short', () {
        expectCopy(
          issueOf(SwapFormIssue.pairUnsupported, stateFor(gleecEvm, paxg)),
          'PAXG can only be swapped across networks, and GLEEC trades only '
          'on the order book. Choose another asset.',
          action: SwapEntryAction.chooseAnother,
          detail: "Cross-network swaps don't reach Gleec yet.",
        );
        expectCopy(
          issueOf(SwapFormIssue.pairUnsupported, stateFor(paxg, btc)),
          'PAXG can only be swapped across networks, and BTC trades only on '
          'the order book. Choose another asset.',
          action: SwapEntryAction.chooseAnother,
          detail: 'Cross-network swaps cover EVM networks only for now.',
        );
      });
    });

    test('an inactive asset is named, receive side included', () {
      const message =
          " isn't active in this wallet yet. Activate it to see its balance "
          'and prices.';
      expectCopy(
        issueOf(
          SwapFormIssue.assetInactive,
          stateFor(eth, usdc, activated: {eth}),
        ),
        'USDC$message',
        action: SwapEntryAction.activate,
      );
      expectCopy(
        issueOf(SwapFormIssue.assetInactive, stateFor(eth, usdc)),
        'ETH$message',
        action: SwapEntryAction.activate,
      );
    });

    test("a token without its network's coin names that coin", () {
      expectCopy(
        issueOf(SwapFormIssue.noFeeBalance, stateFor(usdc, eth)),
        'You need some ETH on Ethereum to pay the network fees. This address '
        'has none.',
      );
    });

    test('amount mistakes say what a valid amount is', () {
      expectCopy(
        issueOf(SwapFormIssue.amountMalformed, stateFor(eth, usdc)),
        'Enter a valid number.',
      );
      expectCopy(
        issueOf(SwapFormIssue.amountZero, stateFor(eth, usdc)),
        'Amount must be greater than 0.',
      );
      expectCopy(
        issueOf(SwapFormIssue.tooManyDecimals, stateFor(usdc, eth)),
        'USDC supports up to 18 decimal places.',
      );
      expectCopy(
        issueOf(
          SwapFormIssue.tooManyDecimals,
          stateFor(assetOf('XYZ', decimals: null), eth),
        ),
        'XYZ supports up to 8 decimal places.',
      );
    });

    test('too much names the spendable balance, rounded down', () {
      expectCopy(
        issueOf(
          SwapFormIssue.insufficient,
          stateFor(eth, usdc, balance: d('1.23456789')),
        ),
        'Only 1.2345 ETH is spendable at this address.',
      );
      expectCopy(
        issueOf(SwapFormIssue.insufficient, stateFor(eth, usdc)),
        'Only ETH is spendable at this address.',
      );
    });

    test('short on fees says what is needed and what is held', () {
      expectCopy(
        issueOf(
          SwapFormIssue.insufficientForFees,
          stateFor(usdc, eth),
          feeNeeded: '0.002 ETH',
          feeHeld: '0.0005 ETH',
        ),
        'You need about 0.002 ETH for network fees. This address has 0.0005 '
        'ETH.',
      );
    });

    test('the same asset twice asks for another', () {
      expectCopy(
        issueOf(SwapFormIssue.sameAsset, stateFor(eth, eth)),
        'Choose two different assets.',
        action: SwapEntryAction.chooseAnother,
      );
    });

    test('an unpriced dollar amount asks for tokens instead', () {
      expectCopy(
        issueOf(SwapFormIssue.fiatUnavailable, stateFor(eth, usdc)),
        "A USD price isn't available for ETH. Enter the amount in ETH.",
      );
    });

    test('every issue but a missing amount reads as English', () {
      for (final issue in SwapFormIssue.values) {
        if (issue == SwapFormIssue.amountMissing) continue;
        final copy = issueOf(issue, stateFor(usdc, eth, balance: d('1')));
        expect(copy!.message, isNot(startsWith('swap')), reason: issue.name);
      }
    });

    test('the copy defaults to no action and no detail', () {
      const copy = SwapIssueCopy(message: 'm');
      expect(copy.action, SwapEntryAction.none);
      expect(copy.detail, isNull);
    });
  });

  group('why cross-network routes cannot reach an asset', () {
    useEnglishCopy();

    test('an EVM asset names its network', () {
      expect(
        routesReachDetail(gleecEvm, networks),
        "Cross-network swaps don't reach Gleec yet.",
      );
      expect(
        routesReachDetail(usdc, networks),
        "Cross-network swaps don't reach Ethereum yet.",
      );
    });

    test('anything else is outside the EVM networks routes cover', () {
      expect(
        routesReachDetail(btc, networks),
        'Cross-network swaps cover EVM networks only for now.',
      );
    });
  });
}
