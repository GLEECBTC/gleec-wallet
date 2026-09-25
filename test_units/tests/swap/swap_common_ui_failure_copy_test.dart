import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/shared/swap/swap_catalog.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';
import 'package:web_dex/views/swap/common/swap_failure_copy.dart';

import 'swap_common_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// The entry form's words for a price it could not get, and the action it
/// offers instead.
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
    AssetId? asset,
    String? minimum,
    String? maximum,
    List<String> reasons = const [],
  }) => SwapQuoteFailure(
    source: source,
    kind: kind,
    asset: asset,
    minimum: minimum == null ? null : d(minimum),
    maximum: maximum == null ? null : d(maximum),
    reasons: reasons,
  );

  group('swap pricing failure copy', () {
    useEnglishCopy();

    void expectCopy(
      SwapFailureCopy copy,
      String message, {
      SwapEntryAction action = SwapEntryAction.retry,
      String? detail,
    }) {
      expect(copy.message, message);
      expect(copy.action, action);
      expect(copy.detail, detail);
    }

    test('an inactive asset names it and offers to activate it', () {
      const message =
          " isn't active in this wallet yet. Activate it to see its balance "
          'and prices.';
      final kind = SwapQuoteFailureKind.assetInactive;
      expectCopy(
        SwapFailureCopy.of(failure(kind, asset: usdc), eth),
        'USDC$message',
        action: SwapEntryAction.activate,
      );
      expectCopy(
        SwapFailureCopy.of(failure(kind), eth),
        'ETH$message',
        action: SwapEntryAction.activate,
      );
    });

    test('limits name the bound in the pay asset, rounded to stay valid', () {
      expectCopy(
        SwapFailureCopy.of(
          failure(
            SwapQuoteFailureKind.belowMinimum,
            minimum: '0.123401',
            maximum: '5',
          ),
          eth,
        ),
        'Minimum swap: 0.1235 ETH',
        action: SwapEntryAction.none,
      );
      expectCopy(
        SwapFailureCopy.of(
          failure(SwapQuoteFailureKind.aboveMaximum, maximum: '5.123456'),
          eth,
        ),
        'Maximum swap: 5.1234 ETH',
        action: SwapEntryAction.none,
      );
    });

    test('a missing minimum is never filled in with the maximum', () {
      final copy = SwapFailureCopy.of(
        failure(SwapQuoteFailureKind.belowMinimum, maximum: '5'),
        eth,
      );
      expect(copy.message, isNot('Minimum swap: 5 ETH'));
    });

    group('no route', () {
      final atomicNoRoute = failure(
        SwapQuoteFailureKind.noRoute,
        source: SwapLiquiditySource.atomic,
      );
      final routedNoRoute = failure(SwapQuoteFailureKind.noRoute);
      const plain = 'No swap is available for this amount and pair right now.';

      test('says the other source could not be checked when it could not', () {
        expectCopy(
          SwapFailureCopy.of(
            atomicNoRoute,
            eth,
            all: [atomicNoRoute, failure(SwapQuoteFailureKind.timeout)],
          ),
          "No order-book offer fits this amount right now, and cross-network "
          "prices couldn't be checked. Try again in a moment.",
        );
        expectCopy(
          SwapFailureCopy.of(
            routedNoRoute,
            eth,
            all: [
              routedNoRoute,
              failure(
                SwapQuoteFailureKind.rateLimited,
                source: SwapLiquiditySource.atomic,
              ),
            ],
          ),
          'No cross-network route fits this amount right now, and order-book '
          "prices couldn't be checked. Try again in a moment.",
        );
      });

      test(
        'an answer from the same source, or a firm one, changes nothing',
        () {
          expectCopy(
            SwapFailureCopy.of(
              routedNoRoute,
              eth,
              all: [routedNoRoute, failure(SwapQuoteFailureKind.serviceError)],
            ),
            plain,
          );
          expectCopy(
            SwapFailureCopy.of(
              routedNoRoute,
              eth,
              all: [
                routedNoRoute,
                failure(
                  SwapQuoteFailureKind.pairUnsupported,
                  source: SwapLiquiditySource.atomic,
                ),
              ],
            ),
            plain,
          );
        },
      );

      test("passes on the provider's reasons before anything else", () {
        expectCopy(
          SwapFailureCopy.of(
            failure(
              SwapQuoteFailureKind.noRoute,
              reasons: ['Amount too small', 'No liquidity'],
            ),
            eth,
            support: SwapPairSupport(routesUnavailableFor: gleecEvm),
          ),
          plain,
          detail: 'Why: Amount too small · No liquidity',
        );
      });

      test('explains an asset only the order book trades', () {
        expectCopy(
          SwapFailureCopy.of(
            atomicNoRoute,
            gleecEvm,
            support: SwapPairSupport(routesUnavailableFor: gleecEvm),
          ),
          plain,
          detail:
              "GLEEC trades only on the order book, so there's no "
              'cross-network option.',
        );
      });
    });

    group('service error', () {
      final routed = failure(SwapQuoteFailureKind.serviceError);
      const generic =
          "We couldn't check swap options. Your selections are preserved and "
          'nothing was signed or sent.';

      test("a routed token suggests checking its network's coin", () {
        expectCopy(
          SwapFailureCopy.of(routed, usdc, networks: networks),
          "We couldn't check swap options. If this keeps happening, check "
          'you have enough ETH on Ethereum for network fees.',
        );
      });

      test('stays generic for a native coin, the order book or no names', () {
        expectCopy(
          SwapFailureCopy.of(routed, eth, networks: networks),
          generic,
        );
        expectCopy(
          SwapFailureCopy.of(
            failure(
              SwapQuoteFailureKind.serviceError,
              source: SwapLiquiditySource.atomic,
            ),
            usdc,
            networks: networks,
          ),
          generic,
        );
        expectCopy(SwapFailureCopy.of(routed, usdc), generic);
      });
    });

    test('every other kind has its own words and next step', () {
      final cases = <(SwapQuoteFailure, String, SwapEntryAction)>[
        (
          failure(SwapQuoteFailureKind.pairUnsupported),
          "This pair can't be swapped here. Choose another asset.",
          SwapEntryAction.chooseAnother,
        ),
        (
          failure(SwapQuoteFailureKind.rateLimited),
          "We're checking too often. Wait a moment, then try again. Your "
              'selections are preserved.',
          SwapEntryAction.wait,
        ),
        (
          failure(SwapQuoteFailureKind.timeout),
          'Checking options took too long. Your selections are preserved and '
              'nothing was signed or sent.',
          SwapEntryAction.retry,
        ),
        (
          failure(SwapQuoteFailureKind.invalidAmount),
          'This amount has more decimal places than USDC supports.',
          SwapEntryAction.none,
        ),
        (
          failure(SwapQuoteFailureKind.insufficientFunds, asset: eth),
          'Not enough ETH to cover this swap and its network fees.',
          SwapEntryAction.none,
        ),
        (
          failure(SwapQuoteFailureKind.insufficientFunds),
          'Not enough USDC to cover this swap and its network fees.',
          SwapEntryAction.none,
        ),
        (
          failure(SwapQuoteFailureKind.unsupportedSigner),
          "This address can't sign every step required for this swap.",
          SwapEntryAction.chooseAnother,
        ),
        (
          failure(SwapQuoteFailureKind.notConfigured),
          "This route isn't available right now. Your selections are "
              'preserved.',
          SwapEntryAction.chooseAnother,
        ),
        (
          failure(SwapQuoteFailureKind.tradingBlocked),
          'Trading unavailable in your location',
          SwapEntryAction.none,
        ),
        (
          failure(SwapQuoteFailureKind.clockInvalid),
          'Your device clock is out of sync. Peer-to-peer swaps need an '
              'accurate clock.',
          SwapEntryAction.none,
        ),
        (
          failure(SwapQuoteFailureKind.unknown),
          "We couldn't check swap options. Try again.",
          SwapEntryAction.retry,
        ),
      ];
      for (final (quoteFailure, message, action) in cases) {
        expectCopy(
          SwapFailureCopy.of(quoteFailure, usdc),
          message,
          action: action,
        );
      }
    });

    test('every kind reads as English, never as a key', () {
      for (final kind in SwapQuoteFailureKind.values) {
        final copy = SwapFailureCopy.of(failure(kind, minimum: '1'), usdc);
        expect(copy.message, isNotEmpty, reason: kind.name);
        expect(copy.message, isNot(startsWith('swap')), reason: kind.name);
      }
    });

    test('the copy defaults to a retry without detail', () {
      const copy = SwapFailureCopy(message: 'm');
      expect(copy.action, SwapEntryAction.retry);
      expect(copy.detail, isNull);
    });
  });
}
