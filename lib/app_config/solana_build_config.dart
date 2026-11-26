import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// How a build exposes Solana.
enum SolanaBuildMode {
  /// `SOLANA_ENABLED=false`: no Solana asset or operation.
  disabled,

  /// The default. SOL and classic SPL tokens are wallet assets on the engine
  /// this build pins; SPL Max, Token-2022 and devnet trading stay off.
  production,

  /// An isolated preview bound to an exact engine, catalog snapshot, storage
  /// namespace and browser origin. Only a candidate may turn on SPL Max,
  /// Token-2022 or devnet trading.
  candidate,
}

/// Solana support is tied to an exact engine. Protocol recognition alone must
/// never expose assets to an engine nobody reviewed them on.
class SolanaBuildConfig {
  const SolanaBuildConfig({
    this.enabled = true,
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
    enabled: bool.fromEnvironment('SOLANA_ENABLED', defaultValue: true),
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

  /// The SDK build configuration bundled with the app. Its `api_commit_hash`
  /// names the KDF whose binaries this build packaged.
  static const sdkBuildConfigAsset =
      'packages/komodo_defi_framework/app_build/build_config.json';

  /// The engine production Solana support was reviewed on. A unit test holds
  /// it equal to the KDF commit the SDK pins, so repinning KDF means reviewing
  /// Solana on the new engine and listing it in
  /// [enginesWithOpenWithdrawalDefects] until SPL Max and Token-2022
  /// withdrawals are verified there.
  static const productionEngineCommit =
      'fd8249c904ae1c75d66fce1c1e361686f13d723c';

  /// These revisions share the withdrawal code with unresolved SPL Max
  /// and Token-2022 defects.
  static const enginesWithOpenWithdrawalDefects = {
    'b1ff8f05c880d6f118124cac9ef615aa9d91bb39',
    '46769c4df3b043669eee59508bf1af017157dcdd',
    'fd8249c904ae1c75d66fce1c1e361686f13d723c',
  };

  static const _candidateNamespacePrefix = 'solana-preview-';

  final bool enabled;
  final bool splMaxEnabled;
  final bool token2022Enabled;
  final bool devnetTradingEnabled;
  final String engineCommit;
  final String coinsCommit;
  final String catalogSha256;
  final String storageNamespace;
  final String previewOrigin;

  /// Any candidate define selects candidate mode, so an incomplete preview
  /// profile fails validation instead of running as a production build.
  SolanaBuildMode get mode {
    if (!enabled) return SolanaBuildMode.disabled;
    final candidate =
        engineCommit.isNotEmpty ||
        coinsCommit.isNotEmpty ||
        catalogSha256.isNotEmpty ||
        previewOrigin.isNotEmpty ||
        storageNamespace.startsWith(_candidateNamespacePrefix);
    return candidate ? SolanaBuildMode.candidate : SolanaBuildMode.production;
  }

  bool get isCandidate => mode == SolanaBuildMode.candidate;

  /// The engine this configuration was reviewed on.
  String get requiredEngineCommit =>
      isCandidate ? engineCommit : productionEngineCommit;

  /// The engine the running KDF has to report. A candidate names it in its
  /// profile. Production expects the KDF this build packaged: a wallet built
  /// against another SDK still starts, and the unit test above, not the
  /// runtime, ties that pin to [productionEngineCommit].
  Future<String> expectedEngineCommit({AssetBundle? bundle}) async {
    validate();
    if (isCandidate) return engineCommit;
    final Object? config = jsonDecode(
      await (bundle ?? rootBundle).loadString(sdkBuildConfigAsset),
    );
    final api = config is Map ? config['api'] : null;
    final commit = api is Map ? api['api_commit_hash'] : null;
    if (commit is! String || !RegExp(r'^[a-f0-9]{40}$').hasMatch(commit)) {
      throw StateError(
        'The bundled SDK build configuration names no full KDF commit.',
      );
    }
    return commit;
  }

  /// Production grants only the wallet operations, even if [validate] is
  /// skipped.
  SolanaCapabilities get capabilities => switch (mode) {
    SolanaBuildMode.disabled => const SolanaCapabilities(),
    SolanaBuildMode.production => const SolanaCapabilities(enabled: true),
    SolanaBuildMode.candidate => SolanaCapabilities(
      enabled: true,
      splMaxEnabled: splMaxEnabled,
      token2022Enabled: token2022Enabled,
      devnetTradingEnabled: devnetTradingEnabled,
    ),
  };

  void validate() {
    final experimental =
        splMaxEnabled || token2022Enabled || devnetTradingEnabled;
    switch (mode) {
      case SolanaBuildMode.disabled:
        if (experimental) {
          throw StateError('Solana operations require SOLANA_ENABLED.');
        }
      case SolanaBuildMode.production:
        if (experimental) {
          throw StateError(
            'SPL Max, Token-2022 and devnet trading need a Solana candidate '
            'build.',
          );
        }
      case SolanaBuildMode.candidate:
        _validateCandidate();
    }
  }

  void _validateCandidate() {
    if (!RegExp(r'^[a-f0-9]{40}$').hasMatch(engineCommit) ||
        !RegExp(r'^[a-f0-9]{40}$').hasMatch(coinsCommit) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(catalogSha256)) {
      throw StateError(
        'Solana integration requires full engine/coin revisions and the '
        'candidate catalog SHA-256.',
      );
    }
    if (storageNamespace !=
        '$_candidateNamespacePrefix${catalogSha256.substring(0, 12)}') {
      throw StateError(
        'The Solana candidate must use its isolated catalog storage namespace.',
      );
    }
    if (enginesWithOpenWithdrawalDefects.contains(engineCommit) &&
        (splMaxEnabled || token2022Enabled)) {
      throw StateError(
        'This KDF revision has unresolved SPL Max and Token-2022 withdrawals.',
      );
    }
  }

  /// Production uses the SDK's updatable catalog; only a candidate's
  /// snapshot is bound to a digest.
  Future<void> verifyCatalog({AssetBundle? bundle}) async {
    validate();
    if (!isCandidate) return;
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
    if (!isCandidate) return;
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

  /// KDF's `version` ends in an abbreviated commit: seven characters from KDF
  /// CI (`git rev-parse --short=7`), more when git needs them to stay unique,
  /// or the full commit. A candidate manifest binds that tag to the complete
  /// commit and artifact digest; in production it must name the KDF the build
  /// packaged ([expectedEngineCommit]). Either way this check detects an
  /// unintended runtime binary.
  void verifyEngineVersion(String version, {String? expectedCommit}) {
    if (!enabled) return;
    validate();
    // A candidate is always held to its own manifest engine.
    final expected = isCandidate
        ? engineCommit
        : expectedCommit ?? productionEngineCommit;
    final versionTag = RegExp(r'^[A-Za-z0-9][A-Za-z0-9.+-]*_([a-f0-9]{7,40})$')
        .firstMatch(version)
        ?.group(1);
    if (versionTag == null || !expected.startsWith(versionTag)) {
      throw StateError(
        isCandidate
            ? 'The running KDF does not match the Solana candidate.'
            : 'The running KDF is not the engine this build pins for Solana.',
      );
    }
  }

  /// Useful to callers recording a non-secret build identity.
  String get identity => jsonEncode({
    'mode': mode.name,
    'engine_commit': requiredEngineCommit,
    'coins_commit': coinsCommit,
    'catalog_sha256': catalogSha256,
  });
}
