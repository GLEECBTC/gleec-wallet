import 'package:flutter/foundation.dart';

enum UnifiedSwapLifiTransport { gleecProxy, direct, invalid }

enum UnifiedSwapConfigurationFailure {
  initRequiresQuote,
  lifiDisabled,
  caseADisabled,
  transportMissing,
  proxyUrlInvalid,
  directTransportNotAllowed,
}

@immutable
class UnifiedSwapConfig {
  const UnifiedSwapConfig({
    this.quoteEnabled = false,
    this.initEnabled = false,
    this.kdfLifiEnabled = false,
    this.kdfLifiCaseAEnabled = false,
    this.transport = UnifiedSwapLifiTransport.invalid,
    this.proxyUrl,
    this.allowDirectLifiNonProduction = false,
    this.production = false,
    this.configurationFailures = const [],
  });

  /// Resolves compile-time product and KDF switches into one fail-closed
  /// wallet configuration.
  ///
  /// The default constructor remains useful for deterministic previews and
  /// tests. Production composition must use this factory so a partially set
  /// collection of `--dart-define` values can never enable quoting or init.
  factory UnifiedSwapConfig.fromEnvironment({bool production = kReleaseMode}) {
    return UnifiedSwapConfig.resolve(
      quoteEnabled: const bool.fromEnvironment('UNIFIED_SWAP_QUOTE_ENABLED'),
      initEnabled: const bool.fromEnvironment('UNIFIED_SWAP_INIT_ENABLED'),
      kdfLifiEnabled: const bool.fromEnvironment('KDF_LIFI_ENABLED'),
      kdfLifiCaseAEnabled: const bool.fromEnvironment(
        'KDF_LIFI_CASE_A_ENABLED',
      ),
      transport: const String.fromEnvironment('KDF_LIFI_TRANSPORT'),
      proxyUrl: const String.fromEnvironment('KDF_LIFI_PROXY_URL'),
      allowDirectLifiNonProduction: const bool.fromEnvironment(
        'ALLOW_DIRECT_LIFI_NON_PROD',
      ),
      production: production,
    );
  }

  @visibleForTesting
  factory UnifiedSwapConfig.resolve({
    required bool quoteEnabled,
    required bool initEnabled,
    required bool kdfLifiEnabled,
    required bool kdfLifiCaseAEnabled,
    required String transport,
    required String proxyUrl,
    required bool allowDirectLifiNonProduction,
    required bool production,
  }) {
    final failures = <UnifiedSwapConfigurationFailure>[];
    final resolvedTransport = switch (transport) {
      'gleec_proxy' => UnifiedSwapLifiTransport.gleecProxy,
      'direct' => UnifiedSwapLifiTransport.direct,
      _ => UnifiedSwapLifiTransport.invalid,
    };
    final requested = quoteEnabled || initEnabled;
    if (initEnabled && !quoteEnabled) {
      failures.add(UnifiedSwapConfigurationFailure.initRequiresQuote);
    }
    if (requested && !kdfLifiEnabled) {
      failures.add(UnifiedSwapConfigurationFailure.lifiDisabled);
    }
    if (requested && !kdfLifiCaseAEnabled) {
      failures.add(UnifiedSwapConfigurationFailure.caseADisabled);
    }
    if (requested) {
      switch (resolvedTransport) {
        case UnifiedSwapLifiTransport.gleecProxy:
          if (!_validProxyBaseUrl(proxyUrl, production: production)) {
            failures.add(UnifiedSwapConfigurationFailure.proxyUrlInvalid);
          }
        case UnifiedSwapLifiTransport.direct:
          if (production || !allowDirectLifiNonProduction) {
            failures.add(
              UnifiedSwapConfigurationFailure.directTransportNotAllowed,
            );
          }
        case UnifiedSwapLifiTransport.invalid:
          failures.add(UnifiedSwapConfigurationFailure.transportMissing);
      }
    }
    return UnifiedSwapConfig(
      quoteEnabled: quoteEnabled,
      initEnabled: initEnabled,
      kdfLifiEnabled: kdfLifiEnabled,
      kdfLifiCaseAEnabled: kdfLifiCaseAEnabled,
      transport: resolvedTransport,
      proxyUrl: proxyUrl.trim().isEmpty ? null : proxyUrl.trim(),
      allowDirectLifiNonProduction: allowDirectLifiNonProduction,
      production: production,
      configurationFailures: List.unmodifiable(failures),
    );
  }

  final bool quoteEnabled;
  final bool initEnabled;
  final bool kdfLifiEnabled;
  final bool kdfLifiCaseAEnabled;
  final UnifiedSwapLifiTransport transport;
  final String? proxyUrl;
  final bool allowDirectLifiNonProduction;
  final bool production;
  final List<UnifiedSwapConfigurationFailure> configurationFailures;

  bool get isValid => configurationFailures.isEmpty;
  bool get canQuote => quoteEnabled && isValid;
  bool get canExecute => canQuote && initEnabled;

  bool get canStartKdfExternalExecution {
    if (!isValid || !kdfLifiEnabled) {
      return false;
    }
    return switch (transport) {
      UnifiedSwapLifiTransport.gleecProxy =>
        proxyUrl != null &&
            _validProxyBaseUrl(proxyUrl!, production: production),
      UnifiedSwapLifiTransport.direct =>
        !production && allowDirectLifiNonProduction,
      UnifiedSwapLifiTransport.invalid => false,
    };
  }
}

bool _validProxyBaseUrl(String value, {required bool production}) {
  if (value.isEmpty || value.trim() != value) return false;
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !uri.hasScheme ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      uri.path != '/lifi/v1') {
    return false;
  }
  return uri.scheme == 'https';
}
