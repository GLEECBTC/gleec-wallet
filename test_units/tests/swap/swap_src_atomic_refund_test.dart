import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/shared/swap/atomic_swap_source.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';

import 'swap_src_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers the gas an order-book quote keeps in a network's own coin to refund
/// the swap if it fails, which KDF counts only for Max.
void main() {
  final bnb = assetOf('BNB', subClass: CoinSubClass.bep20, chainId: 56);
  final usdtOnBnb = assetOf(
    'USDT-BEP20',
    subClass: CoinSubClass.bep20,
    parent: bnb,
    chainId: 56,
  );
  late SrcTrading trading;
  Map<String, Object?>? limits;

  setUp(() {
    limits = null;
    trading = SrcTrading()
      ..bids = [bidOf('0.05', '0.01', '5')]
      // KDF's 155,000 gas for the payment, at 10 gwei.
      ..preimage = preimageOf(baseCoinFee: coinFeeOf('ETH', '0.00155'));
  });

  AtomicSwapQuoteSource source() => AtomicSwapQuoteSource(
    trading: trading,
    networks: () => SwapNetworks([eth, usdc, btc, bnb, usdtOnBnb]),
    gasLimitsOf: (_) => limits,
  );

  Future<SwapQuote> quote({
    AssetId? from,
    AssetId? to,
    bool indicative = false,
  }) async {
    final results = await source().quote(
      SwapQuoteRequest(
        from: from ?? eth,
        to: to ?? btc,
        amount: d('1'),
        indicative: indicative,
      ),
    );
    return (results.single as SwapQuoteAvailable).quote;
  }

  test('keeps the gas to refund a network\'s own coin, as its payment is '
      'priced', () async {
    final selling = await quote();

    // 125,000 gas at the same 10 gwei, and not a fee.
    expect(selling.refundReserve, d('0.00125'));
    expect(selling.costOnTopIn(eth), d('0.00155'));
  });

  test('a claim the coin already pays covers as much of it', () async {
    // 195,000 gas to claim a token: more than a refund takes.
    trading.preimage = preimageOf(
      baseCoinFee: coinFeeOf('ETH', '0.00155'),
      relCoinFee: coinFeeOf('ETH', '0.00195'),
    );
    final forToken = await quote(to: usdc);
    // A BEP-20 claim set at 85,000 gas: less than a refund takes.
    trading.preimage = preimageOf(
      baseCoinFee: coinFeeOf('BNB', '0.00155'),
      relCoinFee: coinFeeOf('BNB', '0.00085'),
    );
    final forBep20 = await quote(from: bnb, to: usdtOnBnb);

    expect(forToken.refundReserve, isNull);
    expect(forBep20.refundReserve, d('0.0004'));
  });

  test('a claim paid from what arrives, or in another coin, covers none of '
      'it', () async {
    trading.preimage = preimageOf(
      baseCoinFee: coinFeeOf('ETH', '0.00155'),
      relCoinFee: coinFeeOf('ETH', '0.00195', fromVolume: true),
    );
    final fromVolume = await quote(to: usdc);
    trading.preimage = preimageOf(
      baseCoinFee: coinFeeOf('ETH', '0.00155'),
      relCoinFee: coinFeeOf('BNB', '0.00085'),
    );
    final otherCoin = await quote(to: usdtOnBnb);

    expect(fromVolume.refundReserve, d('0.00125'));
    expect(otherCoin.refundReserve, d('0.00125'));
  });

  test(
    'a token, or a coin refunded out of what it locked, keeps none',
    () async {
      final token = await quote(from: usdc);
      trading.preimage = preimageOf(baseCoinFee: coinFeeOf('BTC', '0.0002'));
      final utxo = await quote(from: btc, to: eth);

      expect(token.refundReserve, isNull);
      expect(utxo.refundReserve, isNull);
    },
  );

  test('follows the gas limits in the coin\'s config', () async {
    limits = {'eth_payment': 100000, 'eth_sender_refund': 500000};
    trading.preimage = preimageOf(baseCoinFee: coinFeeOf('ETH', '0.001'));
    final both = await quote();
    limits = {'eth_sender_refund': 250000};
    trading.preimage = preimageOf(baseCoinFee: coinFeeOf('ETH', '0.00155'));
    final refundOnly = await quote();
    limits = {'eth_payment': 0, 'eth_sender_refund': 'lots'};
    final unusable = await quote();

    expect(both.refundReserve, d('0.005'));
    expect(refundOnly.refundReserve, d('0.0025'));
    expect(unusable.refundReserve, d('0.00125'));
  });

  test('a refund that does not end is rounded up to the last wei', () async {
    trading.preimage = preimageOf(baseCoinFee: coinFeeOf('ETH', '0.0012'));

    // 0.0012 × 125,000 / 155,000 = 0.000967741935483870967…
    expect((await quote()).refundReserve, d('0.000967741935483871'));
  });

  test('keeps none without a priced payment', () async {
    final indicative = await quote(indicative: true);
    trading.preimage = preimageOf();
    final unreported = await quote();
    trading.preimage = preimageOf(baseCoinFee: coinFeeOf('ETH', '0'));
    final free = await quote();
    trading.preimage = preimageOf(baseCoinFee: coinFeeOf('ETH', 'n/a'));
    final unreadable = await quote();
    trading.preimageError = StateError('preimage failed');
    final failed = await quote();

    for (final quote in [indicative, unreported, free, unreadable, failed]) {
      expect(quote.refundReserve, isNull);
    }
  });

  test('Max already keeps it back', () async {
    final max = await source().maxAmount(from: eth, to: btc, balance: d('1'));

    expect(max!.coversRefund, isTrue);
  });

  test('its default gas limits are those of the KDF this build pins', () {
    final config =
        jsonDecode(
              File(
                'sdk/packages/komodo_defi_framework/app_build/'
                'build_config.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final pinned = (config['api'] as Map<String, dynamic>)['api_commit_hash'];

    expect(
      pinned,
      startsWith('7d6fd1ea'),
      reason:
          'KDF was repinned. Check ETH_PAYMENT and ETH_SENDER_REFUND in '
          "eth.rs's gas_limit module at the new commit against the defaults "
          'in atomic_swap_source_refund.dart, then name the commit in both '
          'places.',
    );
  });
}
