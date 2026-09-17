import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/model/kdf_auth_metadata_extension.dart';

/// Pins the rename migration for `activated_coins`.
///
/// Stored IDs that no longer name an asset are skipped silently, so without
/// this mapping a wallet holding Polygon from before the MATIC -> POL rename
/// would lose the row with no error anywhere.
void testActivatedCoinIdMigration() {
  group('canonicalActivatedCoinIds', () {
    test('rewrites the renamed Polygon IDs', () {
      expect(canonicalActivatedCoinIds(['MATIC', 'MATICTEST', 'NFT_MATIC']), [
        'POL',
        'POLTEST',
        'NFT_POL',
      ]);
    });

    test('leaves every other ID untouched, including PLG20 tokens', () {
      const ids = ['BTC', 'ETH', 'AAVE-PLG20', 'MATIC-ERC20', 'POL'];
      expect(canonicalActivatedCoinIds(ids), ids);
    });

    test('collapses the duplicate a rename can create', () {
      // A wallet that enabled POL after the rename can still hold the legacy
      // MATIC entry; both must not survive as two rows.
      expect(canonicalActivatedCoinIds(['MATIC', 'POL']), ['POL']);
      expect(canonicalActivatedCoinIds(['POL', 'MATIC']), ['POL']);
    });

    test('preserves order so the wallet list does not reshuffle', () {
      expect(canonicalActivatedCoinIds(['BTC', 'MATIC', 'ETH']), [
        'BTC',
        'POL',
        'ETH',
      ]);
    });

    test('handles an empty list', () {
      expect(canonicalActivatedCoinIds(const []), isEmpty);
    });
  });
}
