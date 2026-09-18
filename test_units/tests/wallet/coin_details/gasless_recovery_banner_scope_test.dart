import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/shared/gasless/tron_gasless_policy.dart';
import 'package:web_dex/views/wallet/coin_details/coin_details_info/coin_addresses.dart';

/// The "GasFree deposits paused" notice must not appear on the TRX page.
///
/// Observed on a deployed preview: the TRX address page raised the banner even
/// though the build had GasFree fully enabled, the provider was healthy and
/// USDT-TRC20 behaved correctly. GasFree is a property of the eligible TRC-20
/// token, never of the platform coin - but KDF returns a `gasfree_address` on
/// *every* TRON address, so the "there is custody to talk about" precondition
/// was satisfied on TRX too. Nothing set a reason code on that path, so the
/// message fell through to the generic paused copy and read like an outage.
void main() {
  group('shouldShowGaslessRecoveryBanner', () {
    test('never fires for a coin that is not a GasFree asset', () {
      // TRX: every one of its addresses carries a custody address, and no
      // custody surface is rendered for it - which is exactly the input
      // combination that used to produce the false positive.
      expect(
        shouldShowGaslessRecoveryBanner(
          isGaslessRecoveryAsset: false,
          gaslessReceiveEnabled: false,
          hasRetainedCustodyAddress: true,
          gaslessCustodyVisible: false,
        ),
        isFalse,
        reason:
            'TRX never had GasFree deposits to pause; the banner read as a '
            'provider outage on a coin GasFree does not apply to',
      );
    });

    test('a non-GasFree coin stays silent whatever the other inputs say', () {
      for (final receiveEnabled in [true, false]) {
        for (final retained in [true, false]) {
          for (final custodyVisible in [true, false]) {
            expect(
              shouldShowGaslessRecoveryBanner(
                isGaslessRecoveryAsset: false,
                gaslessReceiveEnabled: receiveEnabled,
                hasRetainedCustodyAddress: retained,
                gaslessCustodyVisible: custodyVisible,
              ),
              isFalse,
            );
          }
        }
      }
    });

    test('still fires for a GasFree asset with no custody surface', () {
      // The case the banner exists for: receive is off, there is custody on
      // record, and no custody row is rendered to carry its own paused tag.
      expect(
        shouldShowGaslessRecoveryBanner(
          isGaslessRecoveryAsset: true,
          gaslessReceiveEnabled: false,
          hasRetainedCustodyAddress: true,
          gaslessCustodyVisible: false,
        ),
        isTrue,
      );
    });

    test('stays silent while GasFree receive is working', () {
      expect(
        shouldShowGaslessRecoveryBanner(
          isGaslessRecoveryAsset: true,
          gaslessReceiveEnabled: true,
          hasRetainedCustodyAddress: true,
          gaslessCustodyVisible: true,
        ),
        isFalse,
      );
    });

    test('stays silent when the custody rows carry the tag themselves', () {
      expect(
        shouldShowGaslessRecoveryBanner(
          isGaslessRecoveryAsset: true,
          gaslessReceiveEnabled: false,
          hasRetainedCustodyAddress: true,
          gaslessCustodyVisible: true,
        ),
        isFalse,
        reason: 'the custody row already shows a paused tag',
      );
    });

    test('stays silent when there is no custody address on record', () {
      expect(
        shouldShowGaslessRecoveryBanner(
          isGaslessRecoveryAsset: true,
          gaslessReceiveEnabled: false,
          hasRetainedCustodyAddress: false,
          gaslessCustodyVisible: false,
        ),
        isFalse,
      );
    });
  });

  group('the premise: GasFree eligibility is token-only', () {
    AssetId tronAssetId(String id, CoinSubClass subClass) => AssetId(
      id: id,
      name: id,
      symbol: AssetSymbol(assetConfigId: id),
      chainId: AssetChainId(chainId: 195, decimalsValue: 6),
      derivationPath: "m/44'/195'",
      subClass: subClass,
    );

    test('TRX is not a GasFree-eligible asset', () {
      // This is what makes `isGaslessRecoveryAsset` false for TRX, and so what
      // the fix above leans on. `isTronGaslessAssetIdEligible` rejects any
      // subclass other than trc20 on its first line.
      expect(
        isTronGaslessAssetIdEligible(
          tronAssetId('TRX', CoinSubClass.trx),
          isCustomToken: false,
          isTestnet: false,
          platform: null,
          contractAddress: null,
          providerNetworkPath: 'tron',
        ),
        isFalse,
      );
    });

    test('USDT-TRC20 on mainnet is eligible', () {
      expect(
        isTronGaslessAssetIdEligible(
          tronAssetId('USDT-TRC20', CoinSubClass.trc20),
          isCustomToken: false,
          isTestnet: false,
          platform: 'TRX',
          contractAddress: 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
          providerNetworkPath: 'tron',
        ),
        isTrue,
        reason: 'the fix must not touch the asset the banner is meant for',
      );
    });
  });
}
