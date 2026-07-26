// test_units is this repository's test root, but analyzer's visibleForTesting
// path heuristic only recognizes a directory named exactly `test`.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/views/bitrefill/bitrefill_button.dart';

const _authOptions = AuthOptions(derivationMethod: DerivationMethod.hdWallet);
final _coinId = AssetId(
  id: 'USDT-TRC20',
  name: 'Tether',
  symbol: AssetSymbol(assetConfigId: 'USDT-TRC20'),
  chainId: AssetChainId(chainId: 195),
  derivationPath: "m/44'/195'",
  subClass: CoinSubClass.trc20,
);
const _walletA = WalletId(
  name: 'same-wallet-name',
  authOptions: _authOptions,
  pubkeyHash: 'wallet-a-public-key-hash',
);
const _walletB = WalletId(
  name: 'same-wallet-name',
  authOptions: _authOptions,
  pubkeyHash: 'wallet-b-public-key-hash',
);

void testBitrefillWalletBinding() {
  group('Bitrefill GasFree wallet binding', () {
    test('accepts an equivalent identity throughout refund selection', () {
      const equivalentWalletA = WalletId(
        name: 'same-wallet-name',
        authOptions: _authOptions,
        pubkeyHash: 'wallet-a-public-key-hash',
      );

      expect(
        isBitrefillRefundSelectionContextCurrent(
          isMounted: true,
          initialWalletId: _walletA,
          currentWalletId: equivalentWalletA,
          initialCoinId: _coinId,
          currentCoinId: _coinId,
          selectionIsCurrent: () => true,
        ),
        isTrue,
      );
    });

    test(
      'same-type wallet switch rejects a stale GasFree address after URL refresh',
      () async {
        const staleGasfreeAddress = 'TWalletAGasFreeAddress000000000001';
        final urlRefresh = Completer<String>();
        var currentWallet = _walletA;

        expect(
          _walletB.authOptions.derivationMethod,
          _walletA.authOptions.derivationMethod,
        );

        Future<String?> acceptRefreshedUrl() async {
          final refreshedUrl = await urlRefresh.future;
          final contextIsCurrent = isBitrefillRefundSelectionContextCurrent(
            isMounted: true,
            initialWalletId: _walletA,
            currentWalletId: currentWallet,
            initialCoinId: _coinId,
            currentCoinId: _coinId,
            // Even if an old address snapshot still appears valid, the
            // captured wallet identity must independently fail closed.
            selectionIsCurrent: () => true,
          );
          return contextIsCurrent ? refreshedUrl : null;
        }

        final pendingLaunch = acceptRefreshedUrl();
        currentWallet = _walletB;
        urlRefresh.complete(
          Uri.https('embed.bitrefill.com', '/', {
            'refund_address': staleGasfreeAddress,
          }).toString(),
        );

        expect(await pendingLaunch, isNull);
      },
    );

    test('disposed selection rejects before context-dependent validation', () {
      var selectionValidationCalls = 0;

      final isCurrent = isBitrefillRefundSelectionContextCurrent(
        isMounted: false,
        initialWalletId: _walletA,
        currentWalletId: _walletA,
        initialCoinId: _coinId,
        currentCoinId: _coinId,
        selectionIsCurrent: () {
          selectionValidationCalls++;
          throw StateError('disposed context must never be read');
        },
      );

      expect(isCurrent, isFalse);
      expect(selectionValidationCalls, isZero);
    });
  });
}
