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

// anchor: protocols support
const String ercTxHistoryUrl = 'https://etherscan.gleec.com/api';
const String txByHashUrl = '$ercTxHistoryUrl/v1/transactions_by_hash';

const String updateCheckerEndpoint = 'https://defistats.gleec.com/api/v3/dex_version';
const int feedbackMaxLength = 1000;
const int contactDetailsMaxLength = 100;
// Maximum allowed length for passwords across the app
// TODO: Mirror this limit in the SDK validation and any backend API constraints
const int passwordMaxLength = 128;
final RegExp discordUsernameRegex = RegExp(r'^[a-zA-Z0-9._]{2,32}$');
final RegExp telegramUsernameRegex = RegExp(r'^[a-zA-Z0-9_]{5,32}$');
final RegExp matrixIdRegex = RegExp(
  r'^@[a-zA-Z0-9._=-]+:[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
);

const int millisecondsIn24H = 86400000;

const bool isTestMode = bool.fromEnvironment(
  'testing_mode',
  defaultValue: false,
);

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
/// Provide via --dart-define=MATOMO_PLATFORM_DIMENSION_ID=<number>
const int? matomoPlatformDimensionId =
    int.fromEnvironment('MATOMO_PLATFORM_DIMENSION_ID', defaultValue: -1) == -1
    ? null
    : int.fromEnvironment('MATOMO_PLATFORM_DIMENSION_ID');
const String moralisProxyUrl = 'https://moralis.gleec.com';
const String nftAntiSpamUrl = 'https://nft-antispam.gleec.com';

const String geoBlockerApiUrl =
    'https://gleec-wallet-bouncer.gleec.com/v1/';
const String tradingBlacklistUrl =
    'https://defistats.gleec.com/api/v3/utils/blacklist';
