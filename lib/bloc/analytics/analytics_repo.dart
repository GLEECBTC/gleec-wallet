import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:web_dex/model/settings/analytics_settings.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/shared/constants.dart';
import 'analytics_api.dart';
import 'firebase_analytics_api.dart';
import 'matomo_analytics_api.dart';

abstract class AnalyticsEventData {
  const AnalyticsEventData();

  String get name;
  Map<String, dynamic> get parameters;

  MapEntry<String, dynamic>? get primaryParameter {
    final params = parameters;
    if (params.isEmpty) {
      return null;
    }
    final iterator = params.entries.iterator;
    if (!iterator.moveNext()) {
      return null;
    }
    return iterator.current;
  }
}

/// A simple implementation of AnalyticsEventData for persisted events
class PersistedAnalyticsEventData extends AnalyticsEventData {
  PersistedAnalyticsEventData({required this.name, required this.parameters});

  @override
  final String name;

  @override
  final Map<String, dynamic> parameters;
}

abstract class AnalyticsRepo {
  /// Sends an analytics event immediately
  Future<void> sendData(AnalyticsEventData data);

  /// Activates analytics collection
  Future<void> activate();

  /// Deactivates analytics collection
  Future<void> deactivate();

  /// Queues an event to be sent when possible.
  /// If analytics is enabled, sends immediately.
  /// Otherwise, stores for future sending when enabled.
  Future<void> queueEvent(AnalyticsEventData data);

  /// Check if analytics is initialized
  bool get isInitialized;

  /// Check if analytics is enabled
  bool get isEnabled;

  /// Force a retry of initialization if it previously failed
  Future<void> retryInitialization(AnalyticsSettings settings);

  /// Save the current event queue to persistent storage
  Future<void> persistQueue();

  /// Load any previously persisted events
  Future<void> loadPersistedQueue();

  /// Cleanup resources used by the repository
  Future<void> dispose();
}

/// Unified analytics repository that handles multiple analytics providers
class AnalyticsRepository implements AnalyticsRepo {
  AnalyticsRepository(AnalyticsSettings settings) {
    _initializeProviders(settings);
  }

  final List<AnalyticsApi> _providers = [];
  bool _isInitialized = false;
  bool _isEnabled = false;

  @override
  bool get isInitialized => _isInitialized;

  @override
  bool get isEnabled => _isInitialized && _isEnabled;

  /// Registers the AnalyticsRepository instance with GetIt for dependency injection
  static void register(AnalyticsSettings settings) {
    if (!GetIt.I.isRegistered<AnalyticsRepo>()) {
      final repo = AnalyticsRepository(settings);
      GetIt.I.registerSingleton<AnalyticsRepo>(repo);

      if (kDebugMode) {
        log(
          'AnalyticsRepository registered with GetIt',
          path: 'analytics -> AnalyticsRepository -> register',
        );
      }
    } else if (kDebugMode) {
      log(
        'AnalyticsRepository already registered with GetIt',
        path: 'analytics -> AnalyticsRepository -> register',
      );
    }
  }

  /// Initialize all configured analytics providers
  Future<void> _initializeProviders(AnalyticsSettings settings) async {
    try {
      if (kDebugMode) {
        log(
          'Initializing analytics providers with settings: isSendAllowed=${settings.isSendAllowed}',
          path: 'analytics -> AnalyticsRepository -> _initializeProviders',
        );
      }

      // Add Firebase Analytics provider
      final firebaseProvider = FirebaseAnalyticsApi();
      _providers.add(firebaseProvider);

      // Add Matomo Analytics provider when configuration is present
      final bool hasMatomoConfig =
          matomoUrl.isNotEmpty && matomoSiteId.isNotEmpty;
      if (hasMatomoConfig) {
        final matomoProvider = MatomoAnalyticsApi();
        _providers.add(matomoProvider);
      } else if (kDebugMode) {
        log(
          'Matomo provider not registered: missing MATOMO_URL and/or MATOMO_SITE_ID',
          path: 'analytics -> AnalyticsRepository -> _initializeProviders',
        );
      }

      // Initialize all providers
      final initFutures = _providers.map(
        (provider) => provider.initialize(settings),
      );
      await Future.wait(initFutures, eagerError: false);

      // Check if at least one provider is initialized successfully
      final initializedProviders = _providers
          .where((p) => p.isInitialized)
          .toList();
      _isInitialized = initializedProviders.isNotEmpty;
      // Disable analytics in CI or when analyticsDisabled flag is set
      final bool shouldDisable = analyticsDisabled || isCiEnvironment;
      _isEnabled = settings.isSendAllowed && !shouldDisable;

      if (kDebugMode) {
        log(
          'Analytics providers initialized: ${initializedProviders.length}/${_providers.length} successful',
          path: 'analytics -> AnalyticsRepository -> _initializeProviders',
        );

        for (final provider in _providers) {
          log(
            '${provider.providerName}: initialized=${provider.isInitialized}, enabled=${provider.isEnabled}',
            path: 'analytics -> AnalyticsRepository -> _initializeProviders',
          );
        }
      }

      if (_isInitialized && _isEnabled) {
        await activate();
      } else {
        await deactivate();
      }
    } catch (e) {
      if (kDebugMode) {
        log(
          'Error initializing analytics providers: $e',
          path: 'analytics -> AnalyticsRepository -> _initializeProviders',
          isError: true,
        );
      }
    }
  }

  @override
  Future<void> sendData(AnalyticsEventData event) async {
    if (!_isInitialized || !_isEnabled) {
      return queueEvent(event);
    }

    // Forward to all providers; individual providers handle enabled/queueing
    final sendFutures = _providers.map(
      (provider) => _sendToProvider(provider, event),
    );

    await Future.wait(sendFutures, eagerError: false);
  }

  Future<void> _sendToProvider(
    AnalyticsApi provider,
    AnalyticsEventData event,
  ) async {
    try {
      await provider.sendEvent(event);
    } catch (e) {
      if (kDebugMode) {
        log(
          'Error sending event to ${provider.providerName}: $e',
          path: 'analytics -> AnalyticsRepository -> _sendToProvider',
          isError: true,
        );
      }
    }
  }

  @override
  Future<void> queueEvent(AnalyticsEventData data) async {
    // Always forward to providers; they are responsible for queuing/persisting
    final queueFutures = _providers.map((provider) async {
      try {
        await provider.sendEvent(data);
      } catch (e) {
        if (kDebugMode) {
          log(
            'Error queueing event for ${provider.providerName}: $e',
            path: 'analytics -> AnalyticsRepository -> queueEvent',
            isError: true,
          );
        }
      }
    });

    await Future.wait(queueFutures, eagerError: false);
  }

  @override
  Future<void> activate() async {
    if (!_isInitialized) {
      return;
    }

    _isEnabled = true;

    final activateFutures = _providers
        .where((provider) => provider.isInitialized)
        .map((provider) => _activateProvider(provider));

    await Future.wait(activateFutures, eagerError: false);

    if (kDebugMode) {
      log(
        'Analytics providers activated',
        path: 'analytics -> AnalyticsRepository -> activate',
      );
    }
  }

  Future<void> _activateProvider(AnalyticsApi provider) async {
    try {
      await provider.activate();
    } catch (e) {
      if (kDebugMode) {
        log(
          'Error activating ${provider.providerName}: $e',
          path: 'analytics -> AnalyticsRepository -> _activateProvider',
          isError: true,
        );
      }
    }
  }

  @override
  Future<void> deactivate() async {
    if (!_isInitialized) {
      return;
    }

    _isEnabled = false;

    final deactivateFutures = _providers
        .where((provider) => provider.isInitialized)
        .map((provider) => _deactivateProvider(provider));

    await Future.wait(deactivateFutures, eagerError: false);

    if (kDebugMode) {
      log(
        'Analytics providers deactivated',
        path: 'analytics -> AnalyticsRepository -> deactivate',
      );
    }
  }

  Future<void> _deactivateProvider(AnalyticsApi provider) async {
    try {
      await provider.deactivate();
    } catch (e) {
      if (kDebugMode) {
        log(
          'Error deactivating ${provider.providerName}: $e',
          path: 'analytics -> AnalyticsRepository -> _deactivateProvider',
          isError: true,
        );
      }
    }
  }

  @override
  Future<void> retryInitialization(AnalyticsSettings settings) async {
    final retryFutures = _providers.map((provider) async {
      try {
        await provider.retryInitialization(settings);
      } catch (e) {
        if (kDebugMode) {
          log(
            'Error retrying initialization for ${provider.providerName}: $e',
            path: 'analytics -> AnalyticsRepository -> retryInitialization',
            isError: true,
          );
        }
      }
    });

    await Future.wait(retryFutures, eagerError: false);

    // Update initialization status
    final initializedProviders = _providers
        .where((p) => p.isInitialized)
        .toList();
    _isInitialized = initializedProviders.isNotEmpty;
  }

  @override
  Future<void> persistQueue() async {
    // Each provider handles its own queue persistence
    // This is a no-op at the repository level since providers manage their own queues
    if (kDebugMode) {
      log(
        'Queue persistence handled by individual providers',
        path: 'analytics -> AnalyticsRepository -> persistQueue',
      );
    }
  }

  @override
  Future<void> loadPersistedQueue() async {
    // Each provider handles loading its own persisted queue
    // This is a no-op at the repository level since providers manage their own queues
    if (kDebugMode) {
      log(
        'Queue loading handled by individual providers',
        path: 'analytics -> AnalyticsRepository -> loadPersistedQueue',
      );
    }
  }

  @override
  Future<void> dispose() async {
    final disposeFutures = _providers.map((provider) async {
      try {
        await provider.dispose();
      } catch (e) {
        if (kDebugMode) {
          log(
            'Error disposing ${provider.providerName}: $e',
            path: 'analytics -> AnalyticsRepository -> dispose',
            isError: true,
          );
        }
      }
    });

    await Future.wait(disposeFutures, eagerError: false);

    _providers.clear();

    if (kDebugMode) {
      log(
        'AnalyticsRepository disposed',
        path: 'analytics -> AnalyticsRepository -> dispose',
      );
    }
  }
}
