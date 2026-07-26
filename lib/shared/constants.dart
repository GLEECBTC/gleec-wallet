import 'package:flutter/foundation.dart' show kDebugMode;

RegExp numberRegExp = RegExp('^\$|^(0|([1-9][0-9]{0,12}))([.,]{1}[0-9]{0,8})?');
RegExp emailRegex = RegExp(
  r'^[a-zA-Z0-9.!#$%&*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$',
);
const int decimalRange = 8;

const int _activationPollingIntervalMs = int.fromEnvironment(
  'ACTIVATION_POLLING_INTERVAL_MS',
  defaultValue: 2000,
);
const Duration kActivationPollingInterval = Duration(
  milliseconds: _activationPollingIntervalMs,
);

// stored app preferences
const String storedSettingsKey = '_atomicDexStoredSettings';
// New settings key to avoid breaking older versions reading the legacy key
const String storedSettingsKeyV2 = 'komodo_wallet_settings_v2';
const String storedAnalyticsSettingsKey = 'analytics_settings';
const String storedMarketMakerSettingsKey = 'market_maker_settings';
const String lastLoggedInWalletKey = 'last_logged_in_wallet';
const String hdWalletModePreferenceKey = 'wallet_hd_mode_preference';
const String defaultFiatPreferenceKey = 'default_fiat_preference_v1';

// anchor: protocols support
const String ercTxHistoryUrl = 'https://etherscan.gleec.com/api';

const String updateCheckerEndpoint =
    'https://defistats.gleec.com/api/v3/dex_version';
const String txByHashUrl = '$ercTxHistoryUrl/v2/transactions_by_hash';

const int feedbackMaxLength = 1000;
const int contactDetailsMaxLength = 100;
// Maximum allowed length for passwords across the app
// TODO: Mirror this limit in the SDK validation and any backend API constraints
const int passwordMaxLength = 128;
const String maskedBalanceText = '****';

/// Shown when balance or fiat value is unavailable (e.g. still loading).
const String kBalancePlaceholder = '--';
final RegExp discordUsernameRegex = RegExp(r'^[a-zA-Z0-9._]{2,32}$');
final RegExp telegramUsernameRegex = RegExp(r'^[a-zA-Z0-9_]{5,32}$');
final RegExp matrixIdRegex = RegExp(
  r'^@[a-zA-Z0-9._=-]+:[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
);
final Uri pricesUrlV3 = Uri.parse(
  'https://prices.gleec.com/api/v2/tickers?expire_at=60',
);

const int millisecondsIn24H = 86400000;

const bool isTestMode = bool.fromEnvironment(
  'testing_mode',
  defaultValue: false,
);

/// Permits withdraw-form self-transfers (recipient matches source) in debug builds.
const bool kAllowSameAddressWithdrawals = kDebugMode;

// Analytics & CI environment configuration
// These values are provided via --dart-define at build/run time in CI and app builds
const bool isCiEnvironment = bool.fromEnvironment('CI', defaultValue: false);

/// When true, providers should not send analytics (used in CI/tests or privacy-first builds)
const bool analyticsDisabled = bool.fromEnvironment(
  'ANALYTICS_DISABLED',
  defaultValue: false,
);

/// Matomo configuration (only used when both are non-empty)
const String matomoUrl = String.fromEnvironment('MATOMO_URL', defaultValue: '');

const String matomoSiteId = String.fromEnvironment(
  'MATOMO_SITE_ID',
  defaultValue: '',
);

/// Optional: Custom dimension id in Matomo used to store platform name
/// Provide via --dart-define=MATOMO_PLATFORM_DIMENSION_ID=123
const int? matomoPlatformDimensionId =
    int.fromEnvironment('MATOMO_PLATFORM_DIMENSION_ID', defaultValue: -1) == -1
    ? null
    : int.fromEnvironment('MATOMO_PLATFORM_DIMENSION_ID');
const String moralisProxyUrl = 'https://moralis.gleec.com';
const String nftAntiSpamUrl = 'https://nft-antispam.gleec.com';

/// Explicit build-time kill switch for the TRON GasFree rail.
///
/// Provider/runtime policy must also validate before sending or receiving is
/// eligible.
const bool tronGaslessEnabled = bool.fromEnvironment(
  'TRON_GASLESS_ENABLED',
  defaultValue: false,
);

/// Additional kill switch for exposing GasFree custody addresses to depositors.
///
/// Receive requires both GasFree switches because users may keep depositing
/// after the send rail is disabled. Runtime account, provider, response-shape,
/// and remote-control gates remain fail-closed.
const bool tronGaslessReceiveEnabled = bool.fromEnvironment(
  'TRON_GASLESS_RECEIVE_ENABLED',
  defaultValue: false,
);

const String _tronGaslessBuildPolicyDisabled =
    'gleec-gasfree-build-policy-v1:send=disabled;receive=disabled';
const String _tronGaslessBuildPolicySendOnly =
    'gleec-gasfree-build-policy-v1:send=enabled;receive=disabled';
const String _tronGaslessBuildPolicyReceiveOnly =
    'gleec-gasfree-build-policy-v1:send=disabled;receive=enabled';
const String _tronGaslessBuildPolicyEnabled =
    'gleec-gasfree-build-policy-v1:send=enabled;receive=enabled';

/// Non-secret marker retained in web builds so CI can verify the two compiled
/// GasFree kill switches instead of trusting the requested build arguments.
const String tronGaslessBuildPolicyMarker = tronGaslessEnabled
    ? (tronGaslessReceiveEnabled
          ? _tronGaslessBuildPolicyEnabled
          : _tronGaslessBuildPolicySendOnly)
    : (tronGaslessReceiveEnabled
          ? _tronGaslessBuildPolicyReceiveOnly
          : _tronGaslessBuildPolicyDisabled);

String tronGaslessBuildPolicyMarkerFor({
  required bool sendEnabled,
  required bool receiveEnabled,
}) => sendEnabled
    ? (receiveEnabled
          ? _tronGaslessBuildPolicyEnabled
          : _tronGaslessBuildPolicySendOnly)
    : (receiveEnabled
          ? _tronGaslessBuildPolicyReceiveOnly
          : _tronGaslessBuildPolicyDisabled);

/// Runtime control endpoint for exposing new GasFree custody receive
/// addresses.
///
/// The build-time switches above are necessary but not sufficient: production
/// must also serve a fresh, fail-closed JSON document from this HTTPS URL. The
/// expected schema is intentionally small and strict so an unrelated endpoint,
/// stale cache, or partially deployed response cannot accidentally enable new
/// deposits:
///
/// ```json
/// {
///   "schemaVersion": 1,
///   "receiveEnabled": true,
///   "expiresAt": "2026-07-10T12:00:00Z",
///   "network": "tron",
///   "serviceProvider": "T..."
/// }
/// ```
///
/// Empty is the production-safe disabled default. Query parameters, fragments,
/// embedded credentials, root-only URLs, and non-HTTPS endpoints are rejected.
const String tronGaslessControlUrl = String.fromEnvironment(
  'TRON_GASLESS_CONTROL_URL',
  defaultValue: '',
);

/// Parses a structurally safe GasFree runtime-control endpoint.
Uri? parseTronGaslessControlEndpoint(String rawUrl) {
  final trimmed = rawUrl.trim();
  final uri = Uri.tryParse(trimmed);
  final hasSafeSurface = RegExp(
    r'^https://[A-Za-z0-9.-]+(?::[0-9]+)?/[A-Za-z0-9._~/-]*[A-Za-z0-9._~-]$',
  ).hasMatch(trimmed);
  if (!hasSafeSurface ||
      trimmed.isEmpty ||
      uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      uri.path.isEmpty ||
      uri.path == '/' ||
      uri.path.endsWith('/') ||
      uri.path.contains('//') ||
      trimmed.contains('%') ||
      trimmed.contains('/../') ||
      trimmed.contains('/./') ||
      trimmed.endsWith('/..') ||
      trimmed.endsWith('/.')) {
    return null;
  }

  final pathSegments = uri.pathSegments;
  if (pathSegments.any(
    (segment) => segment.isEmpty || segment == '.' || segment == '..',
  )) {
    return null;
  }

  return uri;
}

/// Tron gas-free (GasFree) relay configuration for gas-free TRC20 withdrawals.
///
/// [tronGaslessBaseUrl] is passed verbatim to KDF as the
/// `tron_gasless_provider.base_url` activation param (via [MM2] / the SDK's
/// `TronGaslessProviderConfig`). In `komodo_proxy` mode KDF preserves this URL
/// as-is and only appends `api/v1/...`, so it must be the FULL GasFree base
/// path — including the per-network segment.
///
/// The Gleec komodo_proxy (`komodo-defi-proxy` `gas_free` route) strips its
/// `/gasfree` inbound prefix and forwards the remaining path verbatim to
/// `https://open.gasfree.io`, attaching the GasFree HMAC credentials
/// server-side. It does NOT inject the network segment, and KDF doesn't either
/// in proxy mode — so the client supplies it. The GasFree API lives under
/// `/tron` (mainnet) or `/nile` (testnet):
///
///   proxy root:  https://quicknode.gleec.com/              (TRON RPC nodes)
///   this value:  https://quicknode.gleec.com/gasfree/tron  (mainnet GasFree)
///
/// Resulting request flow (account-info call shown):
///   KDF      -> https://quicknode.gleec.com/gasfree/tron/api/v1/address/{addr}
///   proxy    -> strips `/gasfree`, HMAC-signs, forwards
///   upstream -> https://open.gasfree.io/tron/api/v1/address/{addr}
///
/// Dropping `/tron` (or the `/gasfree` mount) routes to the wrong upstream path,
/// and because the proxy signs the GasFree HMAC over that path, the request is
/// also rejected. The app treats that as a GasFree provider failure and keeps
/// the explicitly selected Standard rail available.
///
/// Override at build time via `--dart-define=TRON_GASLESS_BASE_URL=...`.
const String tronGaslessBaseUrl = String.fromEnvironment(
  'TRON_GASLESS_BASE_URL',
  defaultValue: '',
);

/// Returns the configured GasFree network path (`tron` or `nile`) when the
/// endpoint is safe to use. Production endpoints must be HTTPS and may not
/// carry client credentials, query parameters, or fragments.
String? tronGaslessNetworkPath(String rawBaseUrl) {
  final uri = Uri.tryParse(rawBaseUrl.trim());
  final isSecureEndpoint = uri?.scheme == 'https';
  final isLoopbackDebugEndpoint =
      kDebugMode &&
      uri?.scheme == 'http' &&
      const {'localhost', '127.0.0.1', '::1'}.contains(uri?.host);
  if (uri == null ||
      (!isSecureEndpoint && !isLoopbackDebugEndpoint) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    return null;
  }

  final segments = uri.pathSegments.where((segment) => segment.isNotEmpty);
  if (segments.isEmpty) return null;
  return switch (segments.last.toLowerCase()) {
    'tron' => 'tron',
    'nile' => 'nile',
    _ => null,
  };
}

/// GasFree service-provider TRON address supplied during ordinary KDF
/// activation.
///
/// The generic SDK permits KDF configurations without a pin, while the Gleec
/// production app requires this value and verifies every provider identity KDF
/// returns before enabling GasFree actions.
/// Override at build time via `--dart-define=TRON_GASLESS_SERVICE_PROVIDER=...`.
const String tronGaslessServiceProvider = String.fromEnvironment(
  'TRON_GASLESS_SERVICE_PROVIDER',
  defaultValue: '',
);

/// Conservative validation for the pinned TRON service-provider address.
///
/// This intentionally checks the Base58Check surface shape only; KDF/provider
/// response binding remains authoritative for the actual account.
bool isValidTronServiceProvider(String value) =>
    RegExp(r'^T[1-9A-HJ-NP-Za-km-z]{33}$').hasMatch(value.trim());

Set<String> tronGaslessAssetIdsFor({
  required bool enabled,
  required String baseUrl,
  required String serviceProvider,
}) {
  if (!enabled) return const <String>{};
  return tronGaslessRecoveryAssetIdsFor(
    baseUrl: baseUrl,
    serviceProvider: serviceProvider,
  );
}

Set<String> tronGaslessRecoveryAssetIdsFor({
  required String baseUrl,
  required String serviceProvider,
}) {
  if (!isValidTronServiceProvider(serviceProvider)) {
    return const <String>{};
  }
  return switch (tronGaslessNetworkPath(baseUrl)) {
    'tron' => const {'USDT-TRC20'},
    'nile' => const {'TESTUSDT-TRC20'},
    _ => const <String>{},
  };
}

bool get hasValidTronGaslessProviderConfig => tronGaslessRecoveryAssetIdsFor(
  baseUrl: tronGaslessBaseUrl,
  serviceProvider: tronGaslessServiceProvider,
).isNotEmpty;

Set<String> get tronGaslessRecoveryAssetIds => tronGaslessRecoveryAssetIdsFor(
  baseUrl: tronGaslessBaseUrl,
  serviceProvider: tronGaslessServiceProvider,
);

Set<String> get tronGaslessConfiguredAssetIds => tronGaslessAssetIdsFor(
  enabled: tronGaslessEnabled,
  baseUrl: tronGaslessBaseUrl,
  serviceProvider: tronGaslessServiceProvider,
);

Set<String> get tronGaslessReceiveConfiguredAssetIds => tronGaslessAssetIdsFor(
  enabled: tronGaslessEnabled && tronGaslessReceiveEnabled,
  baseUrl: tronGaslessBaseUrl,
  serviceProvider: tronGaslessServiceProvider,
);

/// True only when GasFree sending was explicitly enabled and every mandatory
/// production configuration value is present and structurally safe.
bool get isTronGaslessConfigured => tronGaslessConfiguredAssetIds.isNotEmpty;

/// Whether the app may present a GasFree custody address for new deposits.
bool get isTronGaslessReceiveConfigured =>
    tronGaslessReceiveConfiguredAssetIds.isNotEmpty;

const String geoBlockerApiUrl = 'https://gleec-wallet-bouncer.gleec.com/v1';
const String tradingBlacklistUrl =
    'https://defistats.gleec.com/api/v3/utils/blacklist';
