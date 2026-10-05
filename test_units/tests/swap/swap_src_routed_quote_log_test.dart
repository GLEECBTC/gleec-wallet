import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart'
    show DiagnosticSanitizer;
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/shared/swap/routed_swap_source.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';

import 'swap_src_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers the line each failed routed quote leaves in the app's exportable
/// log: on 2026-10-05 a proxy outage read as "prices couldn't be checked",
/// and nothing recorded which step had failed.
void main() {
  late SrcRoutedSwaps manager;
  late List<String> lines;
  late DateTime clock;

  setUp(() {
    manager = SrcRoutedSwaps();
    lines = [];
    clock = DateTime(2026, 10, 5, 12, 46);
  });

  RoutedSwapQuoteSource source({
    bool Function(AssetId from, AssetId to)? tradingAllowed,
    Duration timeout = const Duration(seconds: 20),
    Duration catalogTimeout = const Duration(seconds: 10),
    void Function(String line)? log,
  }) => RoutedSwapQuoteSource(
    manager,
    networks: () => SwapNetworks([eth, usdc]),
    tradingAllowed: tradingAllowed,
    timeout: timeout,
    catalogTimeout: catalogTimeout,
    now: () => clock,
    log: log ?? lines.add,
  );

  SwapQuoteRequest request({
    String amount = '1',
    Set<SwapQuoteOrder> orders = const {SwapQuoteOrder.cheapest},
  }) =>
      SwapQuoteRequest(from: eth, to: usdc, amount: d(amount), orders: orders);

  const head = 'Swap quote failed: source=routed pair=ETH/USDC-ERC20';

  /// [expected] were written, and each survives the log's sanitizer whole.
  void expectLines(List<String> expected) {
    expect(lines, expected);
    for (final line in lines) {
      expect(DiagnosticSanitizer.sanitizeMessage(line), line);
    }
  }

  group('a failed quote', () {
    test('an unreachable provider is named in KDF\'s words', () async {
      manager.quoteError = const RoutedSwapTransportException(
        detail: 'Unable to reach routed swap provider',
        message: 'Unable to reach routed swap provider',
      );

      await source().quote(request());

      expectLines([
        '$head order=cheapest kind=serviceError type=TransportError '
            'message=Unable to reach routed swap provider',
      ]);
    });

    test('a provider error carries its support request id', () async {
      manager.quoteError = const RoutedSwapProviderException(
        detail: 'No available quotes for the requested transfer',
        message: 'No available quotes for the requested transfer',
        providerRequestId: 'a1b2c3d4-0000-4000-8000-000000000001',
      );

      await source().quote(request());

      expectLines([
        '$head order=cheapest kind=serviceError type=ProviderApiError '
            'request=a1b2c3d4-0000-4000-8000-000000000001 '
            'message=No available quotes for the requested transfer',
      ]);
    });

    test('a rate limit is written once, then waited out quietly', () async {
      manager.quoteError = const RoutedSwapRateLimitedException(
        message: 'Routed swap provider rate limit exceeded',
        providerRequestId: 'req-9',
      );
      final routed = source();

      await routed.quote(request());
      await routed.quote(request(amount: '2'));

      expect(manager.quotes, hasLength(1));
      expectLines([
        '$head order=cheapest kind=rateLimited type=RateLimited request=req-9 '
            'message=Routed swap provider rate limit exceeded',
      ]);
    });

    test('a quote that takes too long says how long it was given', () async {
      manager.hangQuotes = true;

      await source(timeout: Duration.zero).quote(request());

      expectLines(['$head order=cheapest kind=timeout after=0s']);
    });

    test('an unexpected error is written as its category only', () async {
      manager.quoteError = StateError(
        'socket closed for 0x20C3E0c4A8d438f01B1C59376D83519d53b716Ad',
      );

      await source().quote(request());

      expectLines(['$head order=cheapest kind=unknown error=state']);
    });

    test(
      'an amount out of bounds names the parameter, never the amount',
      () async {
        manager.quoteError = const RoutedSwapAmountOutOfBoundsException(
          param: 'amount',
          value: '0.0000001',
          min: '0.000001',
          max: '1000',
          message:
              'Parameter amount out of bounds, value: 0.0000001, '
              'min: 0.000001 max: 1000',
        );

        await source().quote(request());

        expectLines([
          '$head order=cheapest kind=belowMinimum type=AmountOutOfBounds '
              'param=amount',
        ]);
      },
    );

    test('each route asked for is written, by its order', () async {
      manager.quoteError = const RoutedSwapTransportException(
        detail: 'x',
        message: 'Unable to reach routed swap provider',
      );

      await source().quote(
        request(orders: {SwapQuoteOrder.cheapest, SwapQuoteOrder.fastest}),
      );

      expectLines([
        '$head order=cheapest kind=serviceError type=TransportError '
            'message=Unable to reach routed swap provider',
        '$head order=fastest kind=serviceError type=TransportError '
            'message=Unable to reach routed swap provider',
      ]);
    });

    test('pricing again at Start is written too', () async {
      manager.quoteError = const RoutedSwapTransportException(
        detail: 'x',
        message: 'Unable to reach routed swap provider',
      );
      final quote = quoteOf(order: SwapQuoteOrder.fastest);

      await source().requote(quote);

      expectLines([
        'Swap quote failed: source=routed '
            'pair=${quote.from.id}/${quote.to.id} order=fastest '
            'kind=serviceError type=TransportError '
            'message=Unable to reach routed swap provider',
      ]);
    });
  });

  group('what the line leaves out', () {
    test('addresses, URLs, brackets and line breaks are cleaned', () async {
      manager.quoteError = const RoutedSwapTransportException(
        detail: 'x',
        message:
            'Node {"id":1}\nfailed at https://pol.example/rpc?key=abc '
            'for 0x20C3E0c4A8d438f01B1C59376D83519d53b716Ad [retry]',
      );

      await source().quote(request());

      expectLines([
        '$head order=cheapest kind=serviceError type=TransportError '
            'message=Node ("id":1) failed at <url> for 0x… (retry)',
      ]);
    });

    test('a shortened address and other control characters go too', () async {
      manager.quoteError = const RoutedSwapTransportException(
        detail: 'x',
        message: 'Nonce too low for 0x8710aBcD\x00 on retry',
      );

      await source().quote(request());

      expectLines([
        '$head order=cheapest kind=serviceError type=TransportError '
            'message=Nonce too low for 0x… on retry',
      ]);
    });

    test('text the sanitizer would refuse is omitted, the rest kept', () async {
      manager.quoteError = const RoutedSwapMyAddressException(
        coin: 'ETH',
        detail: 'x',
        message: 'Cannot use ETH source address: derivation failed',
      );

      await source().quote(request());

      expectLines([
        '$head order=cheapest kind=unknown type=MyAddressError text=omitted',
      ]);
    });

    test('a request id the sanitizer would refuse is left out', () async {
      manager.quoteError = RoutedSwapProviderException(
        detail: 'x',
        message: 'Bad gateway',
        providerRequestId: 'f' * 40,
      );

      await source().quote(request());

      expectLines([
        '$head order=cheapest kind=serviceError type=ProviderApiError '
            'message=Bad gateway',
      ]);
    });

    test('a long message is cut to 160 characters', () async {
      // Twelve plain words in a row would be refused as prose, so these are
      // numbered.
      final text = List.generate(30, (i) => 'node$i timed out;').join(' ');
      manager.quoteError = RoutedSwapTransportException(
        detail: 'x',
        message: text,
      );

      await source().quote(request());

      final written = lines.single.split('message=').last;
      expect(written, hasLength(160));
      expect(written, startsWith('node0 timed out; node1'));
      expect(written, endsWith('…'));
      expect(DiagnosticSanitizer.sanitizeMessage(lines.single), lines.single);
    });

    test(
      'prose the sanitizer refuses is omitted rather than dropped',
      () async {
        manager.quoteError = const RoutedSwapProviderException(
          detail: 'x',
          message:
              'The route could not be built because none of the tools the '
              'provider tried had enough liquidity',
        );

        await source().quote(request());

        expectLines([
          '$head order=cheapest kind=serviceError type=ProviderApiError '
              'text=omitted',
        ]);
      },
    );
  });

  group('nothing is written', () {
    test('for a priced quote, or a reply reused from moments ago', () async {
      manager.respond = (call) => offerOf(quotedAt: clock);
      final routed = source();

      await routed.quote(request());
      await routed.quote(request());

      expect(manager.quotes, hasLength(1));
      expect(lines, isEmpty);
    });

    test('for a pair the wallet refuses before asking', () async {
      await source(tradingAllowed: (from, to) => false).quote(request());

      expect(lines, isEmpty);
    });

    test('and a failing log never fails the quote', () async {
      manager.quoteError = const RoutedSwapTransportException(
        detail: 'x',
        message: 'Unable to reach routed swap provider',
      );

      final [result] = await source(
        log: (line) => throw StateError('log store closed'),
      ).quote(request());

      expect(
        (result as SwapQuoteRejected).failure.kind,
        SwapQuoteFailureKind.serviceError,
      );
    });
  });

  group('a failed catalog read', () {
    test('an unreachable provider is named in KDF\'s words', () async {
      manager.eligibleError = const RoutedSwapTransportException(
        detail: 'x',
        message: 'Unable to reach routed swap provider',
      );

      final assets = await source().assets(
        known: {eth, usdc},
        activated: {eth, usdc},
      );
      await assets.update;

      expectLines([
        'Swap catalog failed: source=routed type=TransportError '
            'message=Unable to reach routed swap provider',
      ]);
    });

    test('a read that takes too long says how long it was given', () async {
      manager.hangEligible = true;

      final assets = await source(
        catalogTimeout: Duration.zero,
      ).assets(known: {eth, usdc}, activated: {eth, usdc});
      await assets.update;

      expectLines(['Swap catalog failed: source=routed kind=timeout after=0s']);
    });
  });
}
