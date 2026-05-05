import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWasm, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:komodo_cex_market_data/komodo_cex_market_data.dart';
import 'package:komodo_legacy_wallet_migration/komodo_legacy_wallet_migration.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:web_dex/analytics/widgets/analytics_lifecycle_handler.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/app_config/package_information.dart';
import 'package:web_dex/bloc/analytics/analytics_repo.dart';
import 'package:web_dex/bloc/app_bloc_observer.dart';
import 'package:web_dex/bloc/app_bloc_root.dart' deferred as app_bloc_root;
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/cex_market_data/cex_market_data.dart';
import 'package:web_dex/bloc/cex_market_data/mockup/performance_mode.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/settings/settings_repository.dart';
import 'package:web_dex/bloc/trading_status/trading_status_repository.dart';
import 'package:web_dex/bloc/trading_status/trading_status_service.dart';
import 'package:web_dex/blocs/wallets_repository.dart';
import 'package:web_dex/mm2/mm2.dart';
import 'package:web_dex/mm2/mm2_api/mm2_api.dart';
import 'package:web_dex/model/stored_settings.dart';
import 'package:web_dex/performance_analytics/performance_analytics.dart';
import 'package:web_dex/sdk/widgets/window_close_handler.dart';
import 'package:web_dex/services/arrr_activation/arrr_activation_service.dart';
import 'package:web_dex/services/fd_monitor_service.dart';
import 'package:web_dex/services/feedback/app_feedback_wrapper.dart';
import 'package:web_dex/services/legal_documents/legal_documents_repository.dart';
import 'package:web_dex/services/logger/get_logger.dart';
import 'package:web_dex/services/initializer/legacy_app_settings_migration_service.dart';
import 'package:web_dex/services/storage/get_storage.dart';
import 'package:web_dex/shared/constants.dart';
import 'package:web_dex/shared/screenshot/screenshot_sensitivity.dart';
import 'package:web_dex/shared/utils/platform_tuner.dart';
import 'package:web_dex/shared/utils/utils.dart';

part 'services/initializer/app_bootstrapper.dart';

PerformanceMode? _appDemoPerformanceMode;

PerformanceMode? get appDemoPerformanceMode =>
    _appDemoPerformanceMode ?? _getPerformanceModeFromUrl();

Future<void> main() async {
  await runZonedGuarded(() async {
    usePathUrlStrategy();
    WidgetsFlutterBinding.ensureInitialized();
    Bloc.observer = AppBlocObserver();
    PerformanceAnalytics.init();

    FlutterError.onError = (FlutterErrorDetails details) {
      catchUnhandledExceptions(details.exception, details.stack);
    };

    // Foundational dependencies / setup - everything else builds on these 3.
    // The current focus is migrating mm2Api to the new sdk, so that the sdk
    // is the only/primary API/repository for KDF
    final KomodoDefiSdk komodoDefiSdk = await mm2.initialize();

    // Note: SDK debug logging is now controlled by the diagnostic logging toggle
    // in Settings. The flags are initialized in SettingsBloc from stored settings.

    final mm2Api = Mm2Api(mm2: mm2, sdk: komodoDefiSdk);
    // Sparkline is dependent on Hive initialization, so we pass it on to the
    // bootstrapper here
    final sparklineRepository = SparklineRepository.defaultInstance();
    final legacyNativeWalletMigration = KomodoLegacyWalletMigration();
    await AppBootstrapper.instance.ensureInitialized(
      komodoDefiSdk,
      mm2Api,
      sparklineRepository,
      legacyNativeWalletMigration: legacyNativeWalletMigration,
    );

    final tradingStatusRepository = TradingStatusRepository(komodoDefiSdk);
    final tradingStatusService = TradingStatusService(tradingStatusRepository);
    await tradingStatusService.initialize();
    final arrrActivationService = ArrrActivationService(komodoDefiSdk, mm2);

    final coinsRepo = CoinsRepo(
      kdfSdk: komodoDefiSdk,
      mm2: mm2,
      tradingStatusService: tradingStatusService,
      arrrActivationService: arrrActivationService,
    );
    final walletsRepository = WalletsRepository(
      komodoDefiSdk,
      mm2Api,
      getStorage(),
      legacyNativeWalletMigration: legacyNativeWalletMigration,
    );

    // Start FD monitoring on iOS (works in both Debug and Release)
    if (PlatformTuner.isIOS) {
      try {
        final result = await FdMonitorService().start(intervalSeconds: 60.0);
        if (result['success'] == true) {
          log(
            'FD Monitor started successfully in ${kDebugMode ? "DEBUG" : "RELEASE"} mode',
          );
        } else {
          log('FD Monitor failed to start: ${result['message']}');
        }
      } catch (e) {
        log('Failed to start FD Monitor: $e');
      }
    }

    runApp(
      EasyLocalization(
        supportedLocales: localeList,
        fallbackLocale: localeList.first,
        useFallbackTranslations: true,
        useOnlyLangCode: true,
        path: '$assetsPath/translations',
        child: MultiRepositoryProvider(
          providers: [
            RepositoryProvider.value(value: komodoDefiSdk),
            RepositoryProvider.value(value: mm2Api),
            RepositoryProvider.value(value: arrrActivationService),
            RepositoryProvider.value(value: coinsRepo),
            RepositoryProvider.value(value: walletsRepository),
            RepositoryProvider.value(value: sparklineRepository),
            RepositoryProvider.value(value: tradingStatusRepository),
            RepositoryProvider.value(value: tradingStatusService),
            RepositoryProvider<LegalDocumentsRepository>(
              create: (_) => LegalDocumentsRepository(),
              dispose: (repository) => repository.dispose(),
            ),
          ],
          child: const MyApp(),
        ),
      ),
    );
  }, catchUnhandledExceptions);
}

void catchUnhandledExceptions(Object error, StackTrace? stack) {
  log('Uncaught exception: $error.\n$stack');
  if (isTestMode) {
    debugPrintStack(stackTrace: stack, label: error.toString(), maxFrames: 100);
  }

  // Rethrow the error if it has a stacktrace (valid, traceable error)
  // async errors from the sdk are not traceable so do not rethrow them.
  if (!isTestMode && stack != null && stack.toString().isNotEmpty) {
    Error.throwWithStackTrace(error, stack);
  }
}

PerformanceMode? _getPerformanceModeFromUrl() {
  String? maybeEnvPerformanceMode;

  maybeEnvPerformanceMode = const bool.hasEnvironment('DEMO_MODE_PERFORMANCE')
      ? const String.fromEnvironment('DEMO_MODE_PERFORMANCE')
      : null;

  if (kIsWeb) {
    final uri = Uri.base;
    maybeEnvPerformanceMode =
        uri.queryParameters['demo_mode_performance'] ?? maybeEnvPerformanceMode;
  }

  switch (maybeEnvPerformanceMode) {
    case 'good':
      return PerformanceMode.good;
    case 'mediocre':
      return PerformanceMode.mediocre;
    case 'very_bad':
      return PerformanceMode.veryBad;
    default:
      return null;
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final komodoDefiSdk = RepositoryProvider.of<KomodoDefiSdk>(context);
    final walletsRepository = RepositoryProvider.of<WalletsRepository>(context);
    final tradingStatusService = RepositoryProvider.of<TradingStatusService>(
      context,
    );

    final sensitivityController = ScreenshotSensitivityController();
    return MultiBlocProvider(
      providers: [
        BlocProvider<AuthBloc>(
          create: (_) {
            final bloc = AuthBloc(
              komodoDefiSdk,
              walletsRepository,
              SettingsRepository(),
              tradingStatusService,
            );
            bloc.add(const AuthLifecycleCheckRequested());
            return bloc;
          },
        ),
      ],
      child: AppFeedbackWrapper(
        child: AnalyticsLifecycleHandler(
          child: WindowCloseHandler(
            child: ScreenshotSensitivity(
              controller: sensitivityController,
              child: app_bloc_root.AppBlocRoot(
                storedPrefs: _storedSettings!,
                komodoDefiSdk: komodoDefiSdk,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
