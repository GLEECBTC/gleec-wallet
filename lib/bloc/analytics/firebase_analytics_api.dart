import 'dart:convert';
import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_dex/model/settings/analytics_settings.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/firebase_options.dart';
import 'analytics_api.dart';
import 'analytics_repo.dart';

class FirebaseAnalyticsApi implements AnalyticsApi {
  late FirebaseAnalytics _instance;

  /// Completes when initialisation settles, one way or the other.
  ///
  /// The `ignore()` below is load-bearing. This completer is completed with an
  /// error when every retry has been exhausted, and a `Future` completed with
  /// an error that nothing is listening to becomes an *unhandled* async error -
  /// raised in whatever happens to be running when the last retry gives up,
  /// seconds after the call that caused it. In a test run that lands on an
  /// unrelated test; in the app it reaches the zone error handler as a crash
  /// with no useful stack.
  ///
  /// Callers that care still `await` the future and still see the error. This
  /// only says that *nobody at all* listening is an acceptable state - which it
  /// is, because analytics failing must never take anything else down.
  final Completer<void> _initCompleter = Completer<void>();

  bool _isInitialized = false;
  bool _isEnabled = false;
  int _initRetryCount = 0;
  static const int _maxInitRetries = 3;
  static const String _persistedQueueKey = 'firebase_analytics_persisted_queue';

  /// Queue to store events when analytics is disabled
  final List<AnalyticsEventData> _eventQueue = [];

  /// Timer for periodic queue persistence
  Timer? _queuePersistenceTimer;

  @override
  String get providerName => 'Firebase';

  @override
  bool get isInitialized => _isInitialized;

  @override
  bool get isEnabled => _isEnabled;

  @override
  Future<void> initialize(AnalyticsSettings settings) async {
    // Claim the error before anything can observe it as unhandled. Harmless
    // when a real caller also awaits: a future may have many listeners.
    _initCompleter.future.ignore();
    return _initializeWithRetry(settings);
  }

  /// Initialize with retry mechanism
  Future<void> _initializeWithRetry(AnalyticsSettings settings) async {
    try {
      if (kDebugMode) {
        log(
          'Initializing Firebase Analytics with settings: isSendAllowed=${settings.isSendAllowed}',
          path: 'analytics -> FirebaseAnalyticsApi -> _initialize',
        );
      }

      // Setup queue persistence timer
      _queuePersistenceTimer = Timer.periodic(
        const Duration(minutes: 5),
        (_) => _persistQueue(),
      );

      // Load any previously saved events
      await _loadPersistedQueue();

      // Skip unsupported platforms (Linux not supported by Firebase Analytics)
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
        if (kDebugMode) {
          log(
            'Firebase Analytics not supported on Linux; marking as initialized=false and enabled=false',
            path: 'analytics -> FirebaseAnalyticsApi -> _initialize',
          );
        }
        _isInitialized = false;
        _isEnabled = false;
        if (!_initCompleter.isCompleted) {
          _initCompleter.complete();
        }
        return;
      }

      // Initialize Firebase
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      _instance = FirebaseAnalytics.instance;

      _isInitialized = true;
      _isEnabled = settings.isSendAllowed;

      if (kDebugMode) {
        log(
          'Firebase Analytics initialized: _isInitialized=$_isInitialized, _isEnabled=$_isEnabled',
          path: 'analytics -> FirebaseAnalyticsApi -> _initialize',
        );
      }

      if (_isInitialized && _isEnabled) {
        await activate();
      } else {
        await deactivate();
      }

      // Successfully initialized
      if (!_initCompleter.isCompleted) {
        _initCompleter.complete();
      }
    } catch (e) {
      _isInitialized = false;

      if (kDebugMode) {
        log(
          'Error initializing Firebase Analytics: $e',
          path: 'analytics -> FirebaseAnalyticsApi -> _initialize',
          isError: true,
        );
      }

      // Try to initialize again if we haven't exceeded max retries
      if (_initRetryCount < _maxInitRetries) {
        _initRetryCount++;

        if (kDebugMode) {
          log(
            'Retrying Firebase analytics initialization (attempt $_initRetryCount of $_maxInitRetries)',
            path: 'analytics -> FirebaseAnalyticsApi -> _initialize',
          );
        }

        // Retry with exponential backoff
        await Future.delayed(Duration(seconds: 2 * _initRetryCount));
        await _initializeWithRetry(settings);
      } else {
        // Maximum retries exceeded
        if (!_initCompleter.isCompleted) {
          _initCompleter.completeError(e);
        }
      }
    }
  }

  @override
  Future<void> retryInitialization(AnalyticsSettings settings) async {
    if (!_isInitialized) {
      _initRetryCount = 0;
      return _initializeWithRetry(settings);
    }
  }

  @override
  Future<void> sendEvent(AnalyticsEventData event) async {
    // If not initialized or disabled, enqueue for later
    if (!_isInitialized || !_isEnabled) {
      _eventQueue.add(event);
      return;
    }
    final sanitizedParameters = event.parameters.map((key, value) {
      if (value == null) return MapEntry(key, "null");
      if (value is Map || value is List) {
        return MapEntry(key, jsonEncode(value));
      }
      return MapEntry(key, value.toString());
    });

    // Log the event in debug mode with formatted parameters for better readability
    if (kDebugMode) {
      final formattedParams = const JsonEncoder.withIndent(
        '  ',
      ).convert(sanitizedParameters);
      log(
        'Firebase Analytics Event: ${event.name}; Parameters: $formattedParams',
        path: 'analytics -> FirebaseAnalyticsApi -> sendEvent',
      );
    }

    try {
      await _instance.logEvent(
        name: event.name,
        parameters: sanitizedParameters,
      );
    } catch (e, s) {
      log(
        e.toString(),
        path: 'analytics -> FirebaseAnalyticsApi -> sendEvent',
        trace: s,
        isError: true,
      );
    }
  }

  @override
  Future<void> activate() async {
    if (!_isInitialized) {
      return;
    }

    _isEnabled = true;
    await _instance.setAnalyticsCollectionEnabled(true);

    // Process any queued events
    if (_eventQueue.isNotEmpty) {
      if (kDebugMode) {
        log(
          'Processing ${_eventQueue.length} queued Firebase analytics events',
          path: 'analytics -> FirebaseAnalyticsApi -> activate',
        );
      }

      final queuedEvents = List<AnalyticsEventData>.from(_eventQueue);
      _eventQueue.clear();

      int processedCount = 0;
      for (final event in queuedEvents) {
        await sendEvent(event);
        processedCount++;
      }

      if (kDebugMode && processedCount > 0) {
        log(
          'Successfully processed $processedCount queued Firebase analytics events',
          path: 'analytics -> FirebaseAnalyticsApi -> activate',
        );
      }
    }
  }

  @override
  Future<void> deactivate() async {
    if (!_isInitialized) {
      return;
    }

    if (kDebugMode) {
      log(
        'Firebase analytics collection disabled',
        path: 'analytics -> FirebaseAnalyticsApi -> deactivate',
      );
    }

    _isEnabled = false;
    await _instance.setAnalyticsCollectionEnabled(false);
  }

  Future<void> _persistQueue() async {
    if (_eventQueue.isEmpty) {
      if (kDebugMode) {
        log(
          'No Firebase events to persist (queue empty)',
          path: 'analytics -> FirebaseAnalyticsApi -> _persistQueue',
        );
      }
      return;
    }

    try {
      if (kDebugMode) {
        log(
          'Persisting ${_eventQueue.length} queued Firebase analytics events',
          path: 'analytics -> FirebaseAnalyticsApi -> _persistQueue',
        );
      }

      final prefs = await SharedPreferences.getInstance();

      // Convert events to a serializable format
      final serializedEvents = _eventQueue.map((event) {
        return {'name': event.name, 'parameters': event.parameters};
      }).toList();

      // Serialize and store
      final serialized = jsonEncode(serializedEvents);
      await prefs.setString(_persistedQueueKey, serialized);

      if (kDebugMode) {
        log(
          'Successfully persisted ${_eventQueue.length} Firebase events to SharedPreferences',
          path: 'analytics -> FirebaseAnalyticsApi -> _persistQueue',
        );
      }
    } catch (e, s) {
      if (kDebugMode) {
        log(
          'Error persisting Firebase analytics queue: $e',
          path: 'analytics -> FirebaseAnalyticsApi -> _persistQueue',
          trace: s,
          isError: true,
        );
      }
    }
  }

  Future<void> _loadPersistedQueue() async {
    try {
      if (kDebugMode) {
        log(
          'Loading persisted Firebase analytics events from SharedPreferences',
          path: 'analytics -> FirebaseAnalyticsApi -> _loadPersistedQueue',
        );
      }

      final prefs = await SharedPreferences.getInstance();
      final serialized = prefs.getString(_persistedQueueKey);

      if (serialized == null || serialized.isEmpty) {
        if (kDebugMode) {
          log(
            'No persisted Firebase analytics events found',
            path: 'analytics -> FirebaseAnalyticsApi -> _loadPersistedQueue',
          );
        }
        return;
      }

      // Deserialize the data
      final List<dynamic> decodedList = jsonDecode(serialized);

      // Create PersistedAnalyticsEventData instances
      for (final eventMap in decodedList) {
        _eventQueue.add(
          PersistedAnalyticsEventData(
            name: eventMap['name'],
            parameters: Map<String, dynamic>.from(eventMap['parameters']),
          ),
        );
      }

      if (kDebugMode) {
        log(
          'Loaded ${_eventQueue.length} persisted Firebase analytics events',
          path: 'analytics -> FirebaseAnalyticsApi -> _loadPersistedQueue',
        );
      }

      // Clear the persisted data after loading
      await prefs.remove(_persistedQueueKey);
    } catch (e, s) {
      if (kDebugMode) {
        log(
          'Error loading persisted Firebase analytics queue: $e',
          path: 'analytics -> FirebaseAnalyticsApi -> _loadPersistedQueue',
          trace: s,
          isError: true,
        );
      }
    }
  }

  @override
  Future<void> dispose() async {
    if (_queuePersistenceTimer != null) {
      _queuePersistenceTimer!.cancel();
      _queuePersistenceTimer = null;

      if (kDebugMode) {
        log(
          'Cancelled Firebase queue persistence timer',
          path: 'analytics -> FirebaseAnalyticsApi -> dispose',
        );
      }
    }

    // Persist any remaining events before disposing
    await _persistQueue();
  }
}
