import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/model/nft.dart';

/// Pins the chain set the NFT page offers, and the tickers it asks KDF for.
///
/// Polygon is deliberately withheld while KDF still hardcodes the pre-rename
/// `MATIC` / `NFT_MATIC` tickers, so this guards both halves of that decision:
/// the exclusion itself, and the POL tickers every other surface now uses.
void testNftSupportedChains() {
  group('NftBlockchains.supportedValues', () {
    test('withholds Polygon while KDF lacks POL support', () {
      expect(
        NftBlockchains.supportedValues,
        isNot(contains(NftBlockchains.polygon)),
      );
    });

    test('offers every other chain in declaration order', () {
      expect(NftBlockchains.supportedValues, [
        NftBlockchains.eth,
        NftBlockchains.bsc,
        NftBlockchains.avalanche,
        NftBlockchains.fantom,
      ]);
    });

    test('resolves Polygon to the renamed POL tickers', () {
      expect(NftBlockchains.polygon.coinAbbr(), 'POL');
      expect(NftBlockchains.polygon.nftAssetTicker(), 'NFT_POL');
    });
  });
}
