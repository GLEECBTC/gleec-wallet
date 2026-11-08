import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/app_config/solana_build_config.dart';

class _CatalogBundle extends CachingAssetBundle {
  _CatalogBundle(this.content);
  final List<int> content;

  @override
  Future<ByteData> load(String key) async {
    expect(key, SolanaBuildConfig.catalogAsset);
    return ByteData.sublistView(Uint8List.fromList(content));
  }
}

void main() {
  const engine = 'b1ff8f05c880d6f118124cac9ef615aa9d91bb39';
  const coins = 'ca20611537fe84f9398d1a63f3d27a4386fb161d';
  final catalog = utf8.encode('{"SOL-DEV":{"coin":"SOL-DEV"}}');
  final digest = sha256.convert(catalog).toString();

  SolanaBuildConfig candidate({
    bool splMax = false,
    bool token2022 = false,
    String origin = 'http://localhost:8787',
  }) => SolanaBuildConfig(
    enabled: true,
    splMaxEnabled: splMax,
    token2022Enabled: token2022,
    engineCommit: engine,
    coinsCommit: coins,
    catalogSha256: digest,
    storageNamespace: 'solana-preview-${digest.substring(0, 12)}',
    previewOrigin: origin,
  );

  group('Solana candidate build boundaries', () {
    test('ordinary builds leave every experimental operation disabled', () {
      const config = SolanaBuildConfig();
      expect(config.validate, returnsNormally);
      expect(config.capabilities.enabled, isFalse);
      expect(config.capabilities.splMaxEnabled, isFalse);
      expect(config.capabilities.token2022Enabled, isFalse);
      expect(config.capabilities.devnetTradingEnabled, isFalse);
    });

    test('operation flags cannot enable Solana indirectly', () {
      expect(
        const SolanaBuildConfig(devnetTradingEnabled: true).validate,
        throwsStateError,
      );
    });

    test('incomplete candidate identities are refused', () {
      expect(const SolanaBuildConfig(enabled: true).validate, throwsStateError);
    });

    test('candidate cannot reuse the production catalog namespace', () {
      expect(
        SolanaBuildConfig(
          enabled: true,
          engineCommit: engine,
          coinsCommit: coins,
          catalogSha256: digest,
          storageNamespace: 'komodo_coins',
        ).validate,
        throwsStateError,
      );
    });

    test('known engine withdrawal defects cannot be overridden by flags', () {
      expect(candidate(splMax: true).validate, throwsStateError);
      expect(candidate(token2022: true).validate, throwsStateError);
    });

    test('browser candidate refuses missing or different preview origins', () {
      expect(
        () => candidate().verifyPreviewOrigin(
          Uri.parse('http://localhost:8787/wallet'),
        ),
        returnsNormally,
      );
      expect(
        () => candidate().verifyPreviewOrigin(
          Uri.parse('https://wallet.gleec.com'),
        ),
        throwsStateError,
      );
      expect(
        () =>
            candidate().verifyPreviewOrigin(Uri.parse('http://localhost:8788')),
        throwsStateError,
      );
      expect(
        () => const SolanaBuildConfig(
          enabled: true,
        ).verifyPreviewOrigin(Uri.parse('http://localhost:8787')),
        throwsStateError,
      );
    });

    test('runtime engine must match the manifest-bound KDF version tag', () {
      final config = candidate();
      expect(
        () => config.verifyEngineVersion('3.2.0-beta_$engine'),
        returnsNormally,
      );
      expect(
        () => config.verifyEngineVersion('3.2.0-beta_b1ff8f0'),
        returnsNormally,
      );
      expect(() => config.verifyEngineVersion('b1ff8f0'), throwsStateError);
      expect(
        () => config.verifyEngineVersion('3.2.0-beta_$coins'),
        throwsStateError,
      );
      for (final version in [
        'unexpected $engine output',
        '3.2.0-beta_${engine}_wrong',
        '3.2.0-beta_${coins}_${engine.substring(0, 7)}',
      ]) {
        expect(() => config.verifyEngineVersion(version), throwsStateError);
      }
    });

    test('origin isolation requires a valid dedicated non-default port', () {
      for (final origin in [
        'https://wallet.example',
        'https://wallet.example:443',
        'http://localhost:80',
        'http://localhost:0',
        'http://localhost:65536',
        ' http://localhost:8787',
        'http://local\\host:8787',
      ]) {
        expect(
          () => candidate(
            origin: origin,
          ).verifyPreviewOrigin(Uri.parse(origin.trim())),
          throwsStateError,
          reason: origin,
        );
      }
    });

    test(
      'catalog snapshot must match the exact bytes in the manifest',
      () async {
        await candidate().verifyCatalog(bundle: _CatalogBundle(catalog));
        await expectLater(
          candidate().verifyCatalog(bundle: _CatalogBundle([...catalog, 10])),
          throwsStateError,
        );
      },
    );
  });
}
