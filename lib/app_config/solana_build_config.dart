import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// The experimental integration is tied to an exact engine and catalog.
/// Protocol recognition alone must never expose assets to the production KDF.
class SolanaBuildConfig {
  const SolanaBuildConfig({
    this.enabled = false,
    this.splMaxEnabled = false,
    this.token2022Enabled = false,
    this.devnetTradingEnabled = false,
    this.engineCommit = '',
    this.coinsCommit = '',
    this.catalogSha256 = '',
    this.storageNamespace = '',
    this.previewOrigin = '',
  });

  static const environment = SolanaBuildConfig(
    enabled: bool.fromEnvironment('SOLANA_ENABLED'),
    splMaxEnabled: bool.fromEnvironment('SOLANA_SPL_MAX_ENABLED'),
    token2022Enabled: bool.fromEnvironment('SOLANA_TOKEN_2022_ENABLED'),
    devnetTradingEnabled: bool.fromEnvironment('SOLANA_DEVNET_TRADING_ENABLED'),
    engineCommit: String.fromEnvironment('SOLANA_KDF_COMMIT'),
    coinsCommit: String.fromEnvironment('SOLANA_COINS_COMMIT'),
    catalogSha256: String.fromEnvironment('SOLANA_CATALOG_SHA256'),
    storageNamespace: String.fromEnvironment('KDF_COINS_STORAGE_NAMESPACE'),
    previewOrigin: String.fromEnvironment('SOLANA_PREVIEW_ORIGIN'),
  );

  static const catalogAsset =
      'packages/komodo_defi_framework/assets/config/coins_config.json';

  final bool enabled;
  final bool splMaxEnabled;
  final bool token2022Enabled;
  final bool devnetTradingEnabled;
  final String engineCommit;
  final String coinsCommit;
  final String catalogSha256;
  final String storageNamespace;
  final String previewOrigin;

  SolanaCapabilities get capabilities => SolanaCapabilities(
    enabled: enabled,
    splMaxEnabled: enabled && splMaxEnabled,
    token2022Enabled: enabled && token2022Enabled,
    devnetTradingEnabled: enabled && devnetTradingEnabled,
  );

  void validate() {
    if (!enabled) {
      if (splMaxEnabled || token2022Enabled || devnetTradingEnabled) {
        throw StateError('Solana operations require SOLANA_ENABLED.');
      }
      return;
    }
    if (!RegExp(r'^[a-f0-9]{40}$').hasMatch(engineCommit) ||
        !RegExp(r'^[a-f0-9]{40}$').hasMatch(coinsCommit) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(catalogSha256)) {
      throw StateError(
        'Solana integration requires full engine/coin revisions and the '
        'candidate catalog SHA-256.',
      );
    }
    if (storageNamespace !=
        'solana-preview-${catalogSha256.substring(0, 12)}') {
      throw StateError(
        'The Solana candidate must use its isolated catalog storage namespace.',
      );
    }
    if (engineCommit == 'b1ff8f05c880d6f118124cac9ef615aa9d91bb39' &&
        (splMaxEnabled || token2022Enabled)) {
      throw StateError(
        'This KDF revision has unresolved SPL Max and Token-2022 withdrawals.',
      );
    }
  }

  Future<void> verifyCatalog({AssetBundle? bundle}) async {
    validate();
    if (!enabled) return;
    final bytes = await (bundle ?? rootBundle).load(catalogAsset);
    final actual = sha256
        .convert(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        )
        .toString();
    if (actual != catalogSha256) {
      throw StateError(
        'The bundled Solana catalog does not match its manifest.',
      );
    }
  }

  /// Browser wallet credentials and engine storage are origin-scoped. A
  /// candidate built for a dedicated preview origin must refuse another host.
  void verifyPreviewOrigin(Uri current) {
    if (!enabled) return;
    final expected = Uri.tryParse(previewOrigin);
    if (expected == null ||
        !const {'http', 'https'}.contains(expected.scheme) ||
        expected.host.isEmpty ||
        !expected.hasPort ||
        expected.port <= 0 ||
        expected.port > 65535 ||
        expected.userInfo.isNotEmpty ||
        RegExp(r'\s|\\').hasMatch(previewOrigin) ||
        (expected.path.isNotEmpty && expected.path != '/') ||
        expected.hasQuery ||
        expected.hasFragment ||
        current.origin != expected.origin) {
      throw StateError(
        'This Solana build requires its dedicated preview origin.',
      );
    }
  }

  /// KDF development builds expose a seven-character tag in `version`.
  /// The candidate manifest/tooling binds that tag to the complete commit and
  /// artifact digest; this check detects an unintended runtime binary.
  void verifyEngineVersion(String version) {
    if (!enabled) return;
    validate();
    final versionTag = RegExp(
      r'^[A-Za-z0-9][A-Za-z0-9.+-]*_([a-f0-9]{7}|[a-f0-9]{40})$',
    ).firstMatch(version)?.group(1);
    if (versionTag != engineCommit &&
        versionTag != engineCommit.substring(0, 7)) {
      throw StateError('The running KDF does not match the Solana candidate.');
    }
  }

  /// Useful to callers recording a non-secret candidate identity.
  String get identity => jsonEncode({
    'engine_commit': engineCommit,
    'coins_commit': coinsCommit,
    'catalog_sha256': catalogSha256,
  });
}
