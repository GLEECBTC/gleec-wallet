import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/model/kdf_auth_metadata_extension.dart';

/// Pins the rename handling for `activated_coins`.
///
/// Stored IDs that no longer name an asset are skipped silently, so a wallet
/// holding Polygon from before the MATIC -> POL rename would lose the row with
/// no error anywhere. The rename is applied as a *fallback* rather than a
/// rewrite so the same code is correct against a coins config from either side
/// of the rename.
void testActivatedCoinIdMigration() {
  group('activatedCoinIdCandidates', () {
    test('tries the stored ID before the renamed one', () {
      // Order is the whole point: against a pre-rename config `MATIC` still
      // resolves and must win, and rewriting it to `POL` would drop the row.
      expect(activatedCoinIdCandidates('MATIC'), ['MATIC', 'POL']);
      expect(activatedCoinIdCandidates('MATICTEST'), ['MATICTEST', 'POLTEST']);
      expect(activatedCoinIdCandidates('NFT_MATIC'), ['NFT_MATIC', 'NFT_POL']);
    });

    test('offers no fallback for IDs that were not renamed', () {
      for (final id in ['BTC', 'ETH', 'AAVE-PLG20', 'MATIC-ERC20', 'POL']) {
        expect(activatedCoinIdCandidates(id), [id], reason: id);
      }
    });
  });

  group('legacyActivatedCoinIds', () {
    test('maps a current ID back to the spelling it replaced', () {
      expect(legacyActivatedCoinIds('POL'), ['MATIC']);
      expect(legacyActivatedCoinIds('POLTEST'), ['MATICTEST']);
      expect(legacyActivatedCoinIds('NFT_POL'), ['NFT_MATIC']);
    });

    test('is empty for IDs that never replaced anything', () {
      expect(legacyActivatedCoinIds('BTC'), isEmpty);
      expect(legacyActivatedCoinIds('MATIC'), isEmpty);
      expect(legacyActivatedCoinIds('AAVE-PLG20'), isEmpty);
    });
  });

  group('removeActivatedCoins', () {
    // `activated_coins` is stored as raw config IDs, and the SDK's selection
    // store removes exactly the IDs it is handed - it knows nothing about the
    // rename. So the expansion has to happen here, at the caller. Without it a
    // wallet that stored `MATIC` keeps a row the UI can no longer name, and
    // therefore can no longer remove.
    late _RecordingWalletAssets assets;
    late _FakeSdk sdk;

    const walletId = WalletId(
      name: 'wallet',
      pubkeyHash: 'wallet-hash',
      authOptions: AuthOptions(derivationMethod: DerivationMethod.hdWallet),
    );

    setUp(() {
      assets = _RecordingWalletAssets();
      sdk = _FakeSdk(assets);
    });

    test('also clears the spelling the ID replaced', () async {
      await sdk.removeActivatedCoins(['POL'], expectedWalletId: walletId);

      expect(assets.removed, ['POL', 'MATIC']);
    });

    test('expands every renamed ID in one call', () async {
      await sdk.removeActivatedCoins([
        'POL',
        'NFT_POL',
      ], expectedWalletId: walletId);

      expect(assets.removed, ['POL', 'MATIC', 'NFT_POL', 'NFT_MATIC']);
    });

    test(
      'passes an ID that never replaced anything through untouched',
      () async {
        await sdk.removeActivatedCoins([
          'BTC',
          'POL',
        ], expectedWalletId: walletId);

        expect(assets.removed, ['BTC', 'POL', 'MATIC']);
      },
    );

    test('forwards the wallet the caller bound the write to', () async {
      await sdk.removeActivatedCoins(['BTC'], expectedWalletId: walletId);

      expect(assets.expectedWalletId, walletId);
    });
  });
}

/// Records what [KdfAuthMetadataExtension.removeActivatedCoins] delegates.
class _RecordingWalletAssets implements WalletAssetSelection {
  final List<String> removed = [];
  WalletId? expectedWalletId;

  @override
  Future<void> remove(
    Iterable<String> ids, {
    WalletId? expectedWalletId,
    AuthSessionContext? expectedSession,
  }) async {
    removed.addAll(ids);
    this.expectedWalletId = expectedWalletId;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSdk implements KomodoDefiSdk {
  _FakeSdk(this.walletAssets);

  @override
  final WalletAssetSelection walletAssets;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
