import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/shared/swap/swap_services.dart';

import 'swap_src_sdk_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers what the swap surface reads about the wallet's assets through
/// [SwapServices]: the catalogue, addresses, balances and prices — and that
/// reading an address or a balance never activates an asset.
void main() {
  final arb = assetOf(
    'ETH-ARB20',
    subClass: CoinSubClass.arbitrum,
    chainId: 42161,
  );
  late SrcSdk sdk;
  late SrcCoinsRepo coins;
  late SwapServices services;

  setUp(() {
    sdk = SrcSdk();
    coins = SrcCoinsRepo();
    for (final id in [eth, usdc, btc]) {
      sdk.assets.add(assetFor(id));
    }
    services = servicesOf(sdk, coins: coins);
  });

  tearDown(() => services.dispose());

  group('the asset catalogue', () {
    test('names networks from it, rebuilt only when it changes', () {
      final first = services.networks();

      expect(services.networks(), same(first));
      expect(first.networkOfEvmChain(42161), isNull);

      sdk.assets.add(assetFor(arb));
      final second = services.networks();
      expect(second, isNot(same(first)));
      expect(second.networkOfEvmChain(42161), 'Arbitrum');
    });

    test('a catalogue that cannot be read is empty', () {
      sdk.assets.broken = true;

      expect(services.knownAssets, isEmpty);
      expect(services.swappableAssets(), isEmpty);
      expect(services.assetOf(eth), isNull);
      expect(services.networks().networkOfEvmChain(1), isNull);
      expect(services.resolveAsset('ETH'), isNull);
    });

    test('a ticker resolves to the wallet\'s asset', () {
      expect(services.resolveAsset('USDC-ERC20'), usdc);
      expect(services.resolveAsset('NOPE'), isNull);
    });

    test('assets excluded outright are known but never swappable', () {
      final nft = assetOf('NFT_ETH');
      sdk.assets.add(assetFor(nft));

      expect(services.knownAssets, contains(nft));
      expect(services.assetOf(nft)!.id, nft);
      expect(services.swappableAssets(), {eth, usdc, btc});
    });

    test('wallet-only, testnet and token contract come from the config', () {
      final token = assetOf('TKN-ERC20', parent: eth);
      sdk.assets.add(
        assetFor(
          token,
          walletOnly: true,
          protocol: SrcProtocol(testnet: true, contract: '0xcontract'),
        ),
      );

      expect(services.isWalletOnly(token), isTrue);
      expect(services.isTestnet(token), isTrue);
      expect(services.contractOf(token), '0xcontract');
      expect(services.isWalletOnly(eth), isFalse);
      expect(services.isTestnet(eth), isFalse);
      expect(services.contractOf(eth), isNull);
    });

    test('an asset the wallet does not know is plain', () {
      final unknown = assetOf('NOPE');

      expect(services.isWalletOnly(unknown), isFalse);
      expect(services.isTestnet(unknown), isFalse);
      expect(services.contractOf(unknown), isNull);
      expect(services.explorerTxUrl(unknown, '0xhash'), isNull);
    });

    test('a coin config that cannot be read claims nothing', () {
      sdk.assets.add(assetFor(arb, protocol: SrcProtocol(broken: true)));

      expect(services.isTestnet(arb), isFalse);
      expect(services.contractOf(arb), isNull);
      expect(services.explorerTxUrl(arb, '0xhash'), isNull);
    });

    test('explorer links come from the asset\'s network', () {
      expect(
        services.explorerTxUrl(eth, '0xhash'),
        Uri.parse('https://explorer.test/tx/0xhash'),
      );
      expect(services.explorerTxUrl(null, '0xhash'), isNull);
    });
  });

  group('activation', () {
    test('activated assets are the wallet\'s', () async {
      coins.activated = {eth, btc};

      expect(await services.activatedAssets(), {eth, btc});
    });

    test('activating hands a known asset to the wallet', () async {
      await services.activate(usdc);

      expect(coins.activations.single.single.id, usdc);
    });

    test('an asset the wallet does not know cannot be activated', () async {
      await expectLater(services.activate(assetOf('NOPE')), throwsStateError);
      expect(coins.activations, isEmpty);
    });
  });

  group('the swap address', () {
    test('is the first address of the account', () async {
      sdk.pubkeys.known[eth] = pubkeysOf(eth, [
        keyOf('0xsecond', path: "m/44'/60'/0'/0/1"),
        keyOf('0xfirst', path: "m/44'/60'/0'/0/0"),
      ]);
      sdk.pubkeys.known[btc] = pubkeysOf(btc, [keyOf('bc1-single')]);

      expect(await services.addressOf(eth), '0xfirst');
      expect(await services.addressOf(btc), 'bc1-single');
    });

    test('falls back to the first address listed', () async {
      sdk.pubkeys.known[eth] = pubkeysOf(eth, [
        keyOf('0xa', path: "m/44'/60'/0'/0/1"),
        keyOf('0xb', path: "m/44'/60'/0'/0/2"),
      ]);

      expect(await services.addressOf(eth), '0xa');
    });

    test('an active asset without cached keys asks the wallet', () async {
      coins.activated = {eth, btc};
      sdk.pubkeys
        ..known[btc] = pubkeysOf(btc, const [])
        ..fetchable[eth] = pubkeysOf(eth, [keyOf('0xfetched')])
        ..fetchable[btc] = pubkeysOf(btc, [keyOf('bc1-fetched')]);

      expect(await services.addressOf(eth), '0xfetched');
      expect(await services.addressOf(btc), 'bc1-fetched');
      expect(sdk.pubkeys.fetched, [eth, btc]);
    });

    test('reading it never activates an asset', () async {
      sdk.pubkeys.fetchable[eth] = pubkeysOf(eth, [keyOf('0xfetched')]);

      expect(await services.addressOf(eth), isNull);
      expect(sdk.pubkeys.fetched, isEmpty);
      expect(coins.activations, isEmpty);
    });

    test('an address that cannot be read is unknown', () async {
      final unknown = assetOf('NOPE');
      coins.activated = {eth, unknown};

      expect(await services.addressOf(unknown), isNull);
      expect(await services.addressOf(eth), isNull);

      coins.activatedError = StateError('get_enabled_coins failed');
      sdk.pubkeys.fetchable[eth] = pubkeysOf(eth, [keyOf('0xfetched')]);
      expect(await services.addressOf(eth), isNull);

      sdk.pubkeys.broken = true;
      expect(await services.addressOf(btc), isNull);
      expect(sdk.pubkeys.fetched, [eth]);
    });
  });

  group('balances', () {
    test('what can be swapped is the swap address\'s spendable', () async {
      sdk.pubkeys.known[eth] = pubkeysOf(eth, [
        keyOf('0xfirst', path: "m/44'/60'/0'/0/0", spendable: '1.5'),
        keyOf('0xsecond', path: "m/44'/60'/0'/0/1", spendable: '7'),
      ]);

      expect(await services.spendableBalance(eth), d('1.5'));
      expect(coins.balanceReads, isEmpty);
    });

    test(
      'without an address, an active asset reads its whole balance',
      () async {
        coins
          ..activated = {eth, btc}
          ..balances[eth] = balanceOf('0.3')
          ..balances[btc] = balanceOf('0.02');
        sdk.pubkeys.fetchable[btc] = pubkeysOf(btc, const []);

        expect(await services.spendableBalance(eth), d('0.3'));
        expect(await services.spendableBalance(btc), d('0.02'));
      },
    );

    test('an inactive asset\'s balance is unknown, never zero', () async {
      expect(await services.spendableBalance(eth), isNull);
      expect(coins.balanceReads, isEmpty);
    });

    test('a balance that cannot be read is unknown', () async {
      coins
        ..activated = {eth}
        ..balances[eth] = null;
      expect(await services.spendableBalance(eth), isNull);

      coins.balanceError = StateError('balance failed');
      expect(await services.spendableBalance(eth), isNull);
    });

    test('the last balance read comes back without waiting', () {
      sdk.balances.known[eth] = balanceOf('2');

      expect(services.lastKnownBalance(eth), d('2'));
      expect(services.lastKnownBalance(usdc), isNull);

      sdk.balances.broken = true;
      expect(services.lastKnownBalance(eth), isNull);
    });
  });

  group('prices', () {
    test('come from market data, unknown when it cannot answer', () {
      sdk.marketData.prices[eth] = d('3000');

      expect(services.usdPrice(eth), d('3000'));
      expect(services.usdPrice(usdc), isNull);

      sdk.marketData.broken = true;
      expect(services.usdPrice(eth), isNull);
    });

    test(
      'warming fetches each asset once and survives a failed feed',
      () async {
        sdk.marketData.failing = {usdc};

        await services.pricing.prices.warm([eth, usdc, eth]);

        expect(sdk.marketData.fetched, [eth, usdc]);
      },
    );

    test('holdings are the priced assets with a balance', () async {
      coins.activated = {eth, usdc, btc, gleec};
      sdk.balances.known
        ..[eth] = balanceOf('2')
        ..[usdc] = balanceOf('0')
        ..[btc] = balanceOf('0.1');
      sdk.marketData.prices
        ..[eth] = d('3000')
        ..[usdc] = d('1')
        ..[gleec] = d('0.5');

      final holdings = await services.holdings();

      expect(holdings, [(asset: eth, usdValue: d('6000'))]);
      expect(sdk.marketData.fetched.toSet(), {eth, usdc, btc, gleec});
    });
  });
}
