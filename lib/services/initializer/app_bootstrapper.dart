part of 'package:web_dex/main.dart';

final class AppBootstrapper {
  AppBootstrapper._();

  static AppBootstrapper get instance => _instance;

  static final _instance = AppBootstrapper._();

  bool _isInitialized = false;

  Future<void> ensureInitialized(
    KomodoDefiSdk kdfSdk,
    Mm2Api mm2Api,
    SparklineRepository sparklineRepository, {
    KomodoLegacyWalletMigration? legacyNativeWalletMigration,
  }) async {
    if (_isInitialized) return;

    // Register core services with GetIt
    _registerDependencies(kdfSdk, mm2Api, sparklineRepository);

    final timer = Stopwatch()..start();
    await logger.init();
    await initializeLogger(mm2Api);

    log('AppBootstrapper: Log initialized in ${timer.elapsedMilliseconds}ms');
    timer.reset();

    await _warmUpInitializers(
      sparklineRepository,
      legacyNativeWalletMigration: legacyNativeWalletMigration,
    ).awaitAll();
    log(
      'AppBootstrapper: Warm-up initializers completed in ${timer.elapsedMilliseconds}ms',
    );
    timer.stop();

    _isInitialized = true;
  }

  /// Register all dependencies with GetIt
  void _registerDependencies(
    KomodoDefiSdk kdfSdk,
    Mm2Api mm2Api,
    SparklineRepository sparklineRepository,
  ) {
    // Register core services
    GetIt.I.registerSingleton<KomodoDefiSdk>(kdfSdk);
    GetIt.I.registerSingleton<Mm2Api>(mm2Api);
    GetIt.I.registerSingleton<SparklineRepository>(sparklineRepository);
  }

  /// A list of futures that should be completed before the app starts
  /// ([runApp]) which do not depend on each other.
  List<Future<void>> _warmUpInitializers(
    SparklineRepository sparklineRepository, {
    KomodoLegacyWalletMigration? legacyNativeWalletMigration,
  }) {
    return [
      app_bloc_root.loadLibrary(),
      packageInformation.init(),
      EasyLocalization.ensureInitialized(),
      CexMarketData.ensureInitialized(),
      PlatformTuner.setWindowTitleAndSize(),
      _initializeSettings(
        legacyNativeWalletMigration: legacyNativeWalletMigration,
      ),
      _initHive(
        isWeb: kIsWeb || kIsWasm,
        appFolder: appFolder,
      ).then((_) => sparklineRepository.init()),
    ];
  }

  /// Initialize settings and register analytics
  Future<void> _initializeSettings({
    KomodoLegacyWalletMigration? legacyNativeWalletMigration,
  }) async {
    final storage = getStorage();
    await LegacyAppSettingsMigrationService(
      storage: storage,
      legacyNativeWalletMigration: legacyNativeWalletMigration,
    ).migrateIfNeeded();

    var stored = await SettingsRepository.loadStoredSettings();
    final mmSettings = stored.marketMakerBotSettings;
    final shouldClearStoredMakerOrders =
        !mmSettings.saveOrdersBetweenLaunches &&
        mmSettings.tradeCoinPairConfigs.isNotEmpty;
    if (shouldClearStoredMakerOrders) {
      final clearedMmSettings = mmSettings.copyWith(
        tradeCoinPairConfigs: const [],
      );
      stored = stored.copyWith(marketMakerBotSettings: clearedMmSettings);
      await SettingsRepository().updateSettings(stored);
    }

    _storedSettings = stored;

    // Register the unified analytics repository with GetIt
    // This will make sure we have a singleton instance across the app
    // that handles both Firebase and Matomo analytics simultaneously
    AnalyticsRepository.register(stored.analytics);

    log(
      'AppBootstrapper: Unified Analytics repository (Firebase + Matomo) registered with GetIt',
    );
    return;
  }
}

Future<void> _initHive({required bool isWeb, required String appFolder}) async {
  if (isWeb) {
    return Hive.initFlutter(appFolder);
  }

  final appDirectory = await getApplicationDocumentsDirectory();
  final path = p.join(appDirectory.path, appFolder);
  return Hive.init(path);
}

StoredSettings? _storedSettings;
