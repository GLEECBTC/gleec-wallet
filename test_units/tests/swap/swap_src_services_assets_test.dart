import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/shared/swap/swap_services.dart';
import 'package:web_dex/shared/swap/swap_spend_precision.dart';

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
  late _PrecisionSdk sdk;
  late SrcCoinsRepo coins;
  late SwapServices services;

  setUp(() {
    sdk = _PrecisionSdk();
    coins = SrcCoinsRepo();
    for (final id in [eth, usdc, btc]) {
      sdk.assets.add(assetFor(id));
    }
    services = servicesOf(sdk, coins: coins);
  });

  tearDown(() => services.dispose());

  group('spend precision', () {
    final token = assetOf('TOKEN-ERC20', parent: eth, decimals: null);

    setUp(() async {
      sdk.auth.users.add(userOf('precision'));
      await Future<void>.delayed(Duration.zero);
    });

    void addToken({String contract = '0xToken', int? decimals}) {
      sdk.assets.add(
        assetFor(
          token,
          protocol: SrcProtocol(
            config: {
              if (decimals != null) 'decimals': decimals,
              'protocol': {
                'type': 'ERC20',
                'protocol_data': {
                  'platform': 'ETH',
                  'contract_address': contract,
                },
              },
            },
          ),
        ),
      );
    }

    test('uses explicit asset or config precision without a request', () async {
      addToken(decimals: 6);
      expect(await services.spendDecimalsOf(token), 6);
      expect(await services.spendDecimalsOf(eth), 18);
      expect(sdk.client.requests, isEmpty);
    });

    test('signed-out previews use known precision without an RPC', () async {
      addToken();
      sdk.auth.users.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(await services.spendDecimalsOf(token), isNull);
      expect(await services.spendDecimalsOf(eth), 18);
      addToken(decimals: 6);
      expect(await services.spendDecimalsOf(token), 6);
      expect(sdk.client.requests, isEmpty);
    });

    test('native protocol defaults never become token defaults', () async {
      final native = assetOf('ETH-BASE', decimals: null);
      final utxo = assetOf('LTC', decimals: null, subClass: CoinSubClass.utxo);
      sdk.assets
        ..add(
          assetFor(
            native,
            protocol: SrcProtocol(
              config: {
                'protocol': {'type': 'ETH'},
              },
            ),
          ),
        )
        ..add(
          assetFor(
            utxo,
            protocol: SrcProtocol(
              config: {
                'protocol': {'type': 'UTXO'},
              },
            ),
          ),
        )
        ..add(assetFor(token));
      expect(await services.spendDecimalsOf(native), 18);
      expect(await services.spendDecimalsOf(utxo), 8);
      expect(await services.spendDecimalsOf(token), isNull);
      expect(sdk.client.requests, isEmpty);
    });

    for (final decimals in [6, 18]) {
      test(
        'reads and caches missing $decimals-decimal token metadata',
        () async {
          addToken();
          sdk.client.decimals = decimals;
          expect(await services.spendDecimalsOf(token), decimals);
          expect(await services.spendDecimalsOf(token), decimals);
          expect(sdk.client.requests, hasLength(1));
          expect(sdk.client.requests.single['params'], {
            'protocol': {
              'type': 'ERC20',
              'protocol_data': {
                'platform': 'ETH',
                'contract_address': '0xToken',
              },
            },
          });
        },
      );
    }

    test('coalesces reads but separates changed contract identity', () async {
      addToken();
      final pending = Completer<int>();
      sdk.client.read = () => pending.future;
      final first = services.spendDecimalsOf(token);
      final second = services.spendDecimalsOf(token);
      expect(sdk.client.requests, hasLength(1));
      pending.complete(6);
      expect(await first, 6);
      expect(await second, 6);
      addToken(contract: '0xDifferent');
      sdk.client.read = null;
      sdk.client.decimals = 18;
      expect(await services.spendDecimalsOf(token), 18);
      expect(sdk.client.requests, hasLength(2));
    });

    test('unreadable metadata remains unknown and can be retried', () async {
      addToken();
      sdk.client.read = () => throw StateError('metadata unavailable');
      expect(await services.spendDecimalsOf(token), isNull);
      sdk.client.read = null;
      expect(await services.spendDecimalsOf(token), 6);
      expect(sdk.client.requests, hasLength(2));
    });

    test('invalid precision is never cached as usable metadata', () async {
      addToken();
      sdk.client.decimals = 256;
      expect(await services.spendDecimalsOf(token), isNull);
      sdk.client.decimals = 6;
      expect(await services.spendDecimalsOf(token), 6);
      expect(sdk.client.requests, hasLength(2));
    });

    test(
      'wallet change discards a late result and permits a fresh read',
      () async {
        addToken();
        sdk.auth.users.add(userOf('first'));
        await Future<void>.delayed(Duration.zero);
        final pending = Completer<int>();
        sdk.client.read = () => pending.future;
        final old = services.spendDecimalsOf(token);
        sdk.auth.users.add(userOf('second'));
        await Future<void>.delayed(Duration.zero);
        sdk.client.read = null;
        sdk.client.decimals = 18;
        expect(await services.spendDecimalsOf(token), 18);
        pending.complete(6);
        expect(await old, isNull);
        expect(await services.spendDecimalsOf(token), 18);
        expect(sdk.client.requests, hasLength(2));
      },
    );

    test(
      'timed-out metadata can be retried rather than held in-flight',
      () async {
        addToken();
        var calls = 0;
        final resolver = SwapSpendPrecision(
          assetOf: services.assetOf,
          timeout: const Duration(milliseconds: 1),
          tokenDecimals:
              ({
                required protocolType,
                required platform,
                required contractAddress,
              }) {
                calls++;
                return calls == 1 ? Completer<int>().future : Future.value(6);
              },
        );
        expect(await resolver.decimalsOf(token), isNull);
        expect(await resolver.decimalsOf(token), 6);
        expect(calls, 2);
      },
    );
  });

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

    test(
      'atomic disclosure uses the token contract with an unresolved parent',
      () {
        final token = assetOf('UNRESOLVED-TOKEN', subClass: CoinSubClass.erc20);
        sdk.assets.add(
          assetFor(token, protocol: SrcProtocol(contract: '0xcontract')),
        );
        expect(token.parentId, isNull);
        expect(services.atomicTokenApproval(token), isTrue);
        expect(services.atomicTokenApproval(eth), isFalse);
      },
    );

    test('an asset the wallet does not know is plain', () {
      final unknown = assetOf('NOPE');

      expect(services.isWalletOnly(unknown), isFalse);
      expect(services.isTestnet(unknown), isFalse);
      expect(services.contractOf(unknown), isNull);
      expect(services.gasLimitsOf(unknown), isNull);
      expect(services.explorerTxUrl(unknown, '0xhash'), isNull);
    });

    test('swap gas limits come from the coin config', () {
      final movr = assetOf('MOVR', subClass: CoinSubClass.moonriver);
      sdk.assets
        ..add(
          assetFor(
            arb,
            protocol: SrcProtocol(
              config: {
                'gas_limit': {
                  'eth_payment': 100000,
                  'eth_sender_refund': 500000,
                },
              },
            ),
          ),
        )
        ..add(
          assetFor(
            movr,
            protocol: SrcProtocol(
              config: {
                'gas_limit': <Object?, Object?>{'eth_sender_refund': 500000},
              },
            ),
          ),
        );

      expect(services.gasLimitsOf(arb), {
        'eth_payment': 100000,
        'eth_sender_refund': 500000,
      });
      expect(services.gasLimitsOf(movr), {'eth_sender_refund': 500000});
      expect(services.gasLimitsOf(eth), isNull);
    });

    test('a coin config that cannot be read claims nothing', () {
      sdk.assets.add(assetFor(arb, protocol: SrcProtocol(broken: true)));

      expect(services.isTestnet(arb), isFalse);
      expect(services.contractOf(arb), isNull);
      expect(services.gasLimitsOf(arb), isNull);
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

    test('what the other addresses hold is kept apart from a swap', () {
      sdk.pubkeys
        ..known[eth] = pubkeysOf(eth, [
          keyOf('0xsecond', path: "m/44'/60'/0'/0/1", spendable: '2'),
          keyOf('0xfirst', path: "m/44'/60'/0'/0/0", spendable: '1.5'),
          keyOf('0xthird', path: "m/44'/60'/0'/0/2", spendable: '0.9'),
        ])
        ..known[btc] = pubkeysOf(btc, [keyOf('bc1-single', spendable: '3')]);

      expect(services.spendableElsewhere(eth), d('2.9'));
      expect(services.spendableElsewhere(btc), d('0'));
      expect(services.spendableElsewhere(usdc), isNull);

      sdk.pubkeys.broken = true;
      expect(services.spendableElsewhere(eth), isNull);
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
      expect(
        sdk.marketData.fetched,
        isEmpty,
        reason: 'Choosing a default pair does not wait for portfolio pricing.',
      );
    });
  });
}

class _PrecisionSdk extends SrcSdk {
  @override
  final _TokenClient client = _TokenClient();
}

class _TokenClient implements ApiClient {
  int decimals = 6;
  Future<int> Function()? read;
  final List<Map<String, dynamic>> requests = [];

  @override
  Future<Map<String, dynamic>> executeRpc(Map<String, dynamic> request) async {
    if (request['method'] != 'get_token_info') {
      throw UnsupportedError('Unexpected RPC ${request['method']}');
    }
    requests.add(request);
    final resolved = await (read?.call() ?? Future.value(decimals));
    return {
      'mmrpc': '2.0',
      'result': {
        'type': 'ERC20',
        'info': {'symbol': 'TOKEN', 'decimals': resolved},
      },
    };
  }
}
