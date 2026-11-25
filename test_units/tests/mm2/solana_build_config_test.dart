import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
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

/// Production must not depend on a bundled snapshot digest.
class _UnreadableBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) =>
      throw StateError('Production read the catalog snapshot: $key');
}

void main() {
  const engine = 'b1ff8f05c880d6f118124cac9ef615aa9d91bb39';
  const coins = 'ca20611537fe84f9398d1a63f3d27a4386fb161d';
  const production = SolanaBuildConfig.productionEngineCommit;
  final catalog = utf8.encode('{"TESTSOL":{"coin":"TESTSOL"}}');
  final digest = sha256.convert(catalog).toString();

  SolanaBuildConfig candidate({
    bool splMax = false,
    bool token2022 = false,
    String origin = 'http://localhost:8787',
    String engineCommit = engine,
  }) => SolanaBuildConfig(
    splMaxEnabled: splMax,
    token2022Enabled: token2022,
    engineCommit: engineCommit,
    coinsCommit: coins,
    catalogSha256: digest,
    storageNamespace: 'solana-preview-${digest.substring(0, 12)}',
    previewOrigin: origin,
  );

  group('Solana production builds', () {
    test('ordinary builds hold, send and receive Solana assets only', () {
      const config = SolanaBuildConfig();
      expect(config.mode, SolanaBuildMode.production);
      expect(config.validate, returnsNormally);
      expect(config.capabilities, const SolanaCapabilities(enabled: true));
      expect(config.requiredEngineCommit, production);
    });

    test('SOLANA_ENABLED=false turns every Solana operation off', () {
      const config = SolanaBuildConfig(enabled: false);
      expect(config.mode, SolanaBuildMode.disabled);
      expect(config.validate, returnsNormally);
      expect(config.capabilities, const SolanaCapabilities());
      expect(
        const SolanaBuildConfig(
          enabled: false,
          devnetTradingEnabled: true,
        ).validate,
        throwsStateError,
      );
    });

    test('SPL Max, Token-2022 and devnet trading stay off', () {
      for (final config in const [
        SolanaBuildConfig(splMaxEnabled: true),
        SolanaBuildConfig(token2022Enabled: true),
        SolanaBuildConfig(devnetTradingEnabled: true),
      ]) {
        expect(config.mode, SolanaBuildMode.production);
        expect(config.validate, throwsStateError);
        // Even unvalidated, production grants only the wallet operations.
        expect(config.capabilities, const SolanaCapabilities(enabled: true));
      }
    });

    test(
      'no preview origin, catalog digest or namespace is required',
      () async {
        const config = SolanaBuildConfig();
        expect(
          () => config.verifyPreviewOrigin(Uri.parse('https://dex.gleec.com')),
          returnsNormally,
        );
        await config.verifyCatalog(bundle: _UnreadableBundle());
      },
    );

    test('any candidate define selects candidate validation', () {
      for (final config in [
        const SolanaBuildConfig(engineCommit: engine),
        const SolanaBuildConfig(coinsCommit: coins),
        SolanaBuildConfig(catalogSha256: digest),
        const SolanaBuildConfig(previewOrigin: 'http://localhost:8787'),
        const SolanaBuildConfig(
          storageNamespace: 'solana-preview-0123456789ab',
        ),
      ]) {
        expect(config.mode, SolanaBuildMode.candidate);
        expect(config.validate, throwsStateError);
      }
    });

    test('the production engine is the KDF the SDK pins', () {
      final buildConfig = jsonDecode(
        File(
          'sdk/packages/komodo_defi_framework/app_build/'
          'build_config.json',
        ).readAsStringSync(),
      ) as Map<String, dynamic>;
      final pinned =
          (buildConfig['api'] as Map<String, dynamic>)['api_commit_hash'];
      expect(
        production,
        pinned,
        reason:
            'KDF was repinned. Review Solana on the new engine, then set '
            'SolanaBuildConfig.productionEngineCommit to it and add it to '
            'enginesWithOpenWithdrawalDefects unless SPL Max and Token-2022 '
            'withdrawals were verified there.',
      );
    });

    test(
      'the production engine is listed until its withdrawals are verified',
      () {
        expect(
          SolanaBuildConfig.enginesWithOpenWithdrawalDefects,
          contains(production),
        );
      },
    );

    test('the running engine must be the pinned production engine', () {
      const config = SolanaBuildConfig();
      expect(
        () => config.verifyEngineVersion(
          '3.2.0-beta_${production.substring(0, 7)}',
        ),
        returnsNormally,
      );
      expect(
        () => config.verifyEngineVersion('3.2.0-beta_$production'),
        returnsNormally,
      );
      for (final version in [
        '3.2.0-beta_46769c4',
        '3.2.0-beta_$engine',
        production,
        '',
      ]) {
        expect(
          () => config.verifyEngineVersion(version),
          throwsStateError,
          reason: version,
        );
      }
      expect(
        () =>
            const SolanaBuildConfig(enabled: false)
                .verifyEngineVersion('3.2.0-beta_46769c4'),
        returnsNormally,
      );
    });
  });

  group('Solana candidate build boundaries', () {
    test('a complete candidate profile selects candidate mode', () {
      final config = candidate();
      expect(config.mode, SolanaBuildMode.candidate);
      expect(config.validate, returnsNormally);
      expect(config.requiredEngineCommit, engine);
    });

    test('incomplete candidate identities are refused', () {
      expect(
        const SolanaBuildConfig(
          engineCommit: engine,
          coinsCommit: coins,
        ).validate,
        throwsStateError,
      );
    });

    test('candidate cannot reuse the production catalog namespace', () {
      expect(
        SolanaBuildConfig(
          engineCommit: engine,
          coinsCommit: coins,
          catalogSha256: digest,
          storageNamespace: 'komodo_coins',
        ).validate,
        throwsStateError,
      );
    });

    test('known engine withdrawal defects cannot be overridden by flags', () {
      expect(SolanaBuildConfig.enginesWithOpenWithdrawalDefects, {
        engine,
        '46769c4df3b043669eee59508bf1af017157dcdd',
        'fd8249c904ae1c75d66fce1c1e361686f13d723c',
      });
      for (final commit in SolanaBuildConfig.enginesWithOpenWithdrawalDefects) {
        expect(
          candidate(splMax: true, engineCommit: commit).validate,
          throwsStateError,
        );
        expect(
          candidate(token2022: true, engineCommit: commit).validate,
          throwsStateError,
        );
        expect(candidate(engineCommit: commit).validate, returnsNormally);
      }
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
        () =>
            candidate(origin: '')
                .verifyPreviewOrigin(Uri.parse('http://localhost:8787')),
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
      // A candidate is bound to its own engine, not the production one.
      expect(
        () => config.verifyEngineVersion(
          '3.2.0-beta_${production.substring(0, 7)}',
        ),
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
          () =>
              candidate(origin: origin)
                  .verifyPreviewOrigin(Uri.parse(origin.trim())),
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
