import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/coins_bloc/coins_bloc.dart';
import 'package:web_dex/router/parsers/root_route_parser.dart';
import 'package:web_dex/router/routes.dart';
import 'package:web_dex/router/state/dex_state.dart';

/// `/swap` is the Swap menu's own name for `/dex`, so a link written either
/// way lands on the same surface.
void main() {
  final parser = RootRouteInformationParser(_NoCoins());

  Future<AppRoutePath> parse(String location) =>
      parser.parseRouteInformation(RouteInformation(uri: Uri.parse(location)));

  test('/swap opens the swap surface with its deep link', () async {
    final path = await parse(
      '/swap?from_currency=ETH&to_currency=USDC-ERC20&from_amount=1',
    );

    expect(path, isA<DexRoutePath>());
    final dex = path as DexRoutePath;
    expect(dex.fromCurrency, 'ETH');
    expect(dex.toCurrency, 'USDC-ERC20');
    expect(dex.fromAmount, '1');
    // It settles on the one canonical address.
    expect(
      dex.location,
      '/dex?from_currency=ETH&from_amount=1&to_currency=USDC-ERC20',
    );
  });

  test('/swap/trading_details/<uuid> opens that swap', () async {
    final path = await parse('/swap/trading_details/abc-123');
    expect((path as DexRoutePath).uuid, 'abc-123');
    expect(path.action, DexAction.tradingDetails);
  });
}

class _NoCoins implements CoinsBloc {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
