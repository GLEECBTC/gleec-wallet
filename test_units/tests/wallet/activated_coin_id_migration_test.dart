import 'package:flutter_test/flutter_test.dart';
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
}
