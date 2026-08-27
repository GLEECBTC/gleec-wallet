import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class FdMonitorService {
  static const MethodChannel _channel = MethodChannel(
    'com.komodo.wallet/fd_monitor',
  );

  static FdMonitorService? _instance;

  factory FdMonitorService() {
    _instance ??= FdMonitorService._internal();
    return _instance!;
  }

  FdMonitorService._internal();

  bool _isMonitoring = false;

  bool get isMonitoring => _isMonitoring;

  /// Starts monitoring.
  ///
  /// [sampleIntervalSeconds] drives the peak watermark. `0` leaves only the
  /// periodic log, which is the shipping default: the periodic log alone cannot
  /// see an activation burst, but a permanent sub-second timer is a power cost
  /// worth opting into rather than inheriting.
  Future<Map<String, dynamic>> start({
    double intervalSeconds = 60.0,
    double sampleIntervalSeconds = 0,
  }) async {
    try {
      final result = await _channel
          .invokeMethod<Map<Object?, Object?>>('start', {
            'intervalSeconds': intervalSeconds,
            'sampleIntervalSeconds': sampleIntervalSeconds,
          });

      if (result != null) {
        _isMonitoring = true;
        return Map<String, dynamic>.from(result);
      }

      return {'success': false, 'message': 'No response from native code'};
    } on PlatformException catch (e) {
      return {
        'success': false,
        'message': 'Platform error: ${e.message}',
        'code': e.code,
      };
    } on MissingPluginException {
      return {
        'success': false,
        'message': 'FD monitoring not available on this platform',
      };
    } catch (e) {
      return {'success': false, 'message': 'Unexpected error: $e'};
    }
  }

  Future<Map<String, dynamic>> stop() async {
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>('stop');

      if (result != null) {
        _isMonitoring = false;
        return Map<String, dynamic>.from(result);
      }

      return {'success': false, 'message': 'No response from native code'};
    } on PlatformException catch (e) {
      return {
        'success': false,
        'message': 'Platform error: ${e.message}',
        'code': e.code,
      };
    } on MissingPluginException {
      return {
        'success': false,
        'message': 'FD monitoring not available on this platform',
      };
    } catch (e) {
      return {'success': false, 'message': 'Unexpected error: $e'};
    }
  }

  Future<FdMonitorStats?> getCurrentCount() async {
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        'getCurrentCount',
      );

      if (result != null) {
        return FdMonitorStats.fromMap(Map<String, dynamic>.from(result));
      }

      return null;
    } on PlatformException catch (e) {
      print('FD Monitor error getting count: ${e.message}');
      return null;
    } on MissingPluginException {
      return null;
    } catch (e) {
      print('FD Monitor unexpected error: $e');
      return null;
    }
  }

  /// Clears the peak watermark so the next reading measures one named phase.
  ///
  /// Call this at a phase boundary — immediately before login, say — otherwise
  /// a peak set during startup masks the phase you actually want to measure.
  Future<Map<String, dynamic>> resetPeak() async {
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        'resetPeak',
      );

      if (result != null) {
        return Map<String, dynamic>.from(result);
      }

      return {'success': false, 'message': 'No response from native code'};
    } on PlatformException catch (e) {
      return {
        'success': false,
        'message': 'Platform error: ${e.message}',
        'code': e.code,
      };
    } on MissingPluginException {
      return {
        'success': false,
        'message': 'FD monitoring not available on this platform',
      };
    } catch (e) {
      return {'success': false, 'message': 'Unexpected error: $e'};
    }
  }

  Future<Map<String, dynamic>> logDetailedStatus() async {
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        'logDetailedStatus',
      );

      if (result != null) {
        return Map<String, dynamic>.from(result);
      }

      return {'success': false, 'message': 'No response from native code'};
    } on PlatformException catch (e) {
      return {
        'success': false,
        'message': 'Platform error: ${e.message}',
        'code': e.code,
      };
    } on MissingPluginException {
      return {
        'success': false,
        'message': 'FD monitoring not available on this platform',
      };
    } catch (e) {
      return {'success': false, 'message': 'Unexpected error: $e'};
    }
  }

  Future<void> startIfDebugMode({double intervalSeconds = 60.0}) async {
    if (kDebugMode) {
      await start(intervalSeconds: intervalSeconds);
    }
  }
}

class FdMonitorStats {
  final int openCount;
  final int tableSize;
  final int softLimit;
  final int hardLimit;
  final double percentUsed;

  /// Highest open-FD count seen since start or the last
  /// [FdMonitorService.resetPeak]. Zero when peak sampling is disabled and
  /// nothing has polled in the meantime.
  final int peakCount;
  final double peakPercentUsed;
  final String peakTimestamp;

  /// FD type counts (`socket`, `file`, `pipe`, …) for the peak. `socket` is the
  /// one that tracks KDF's networking.
  ///
  /// Sampled at or shortly before [peakCount] rather than at the exact instant
  /// it was set — the breakdown is too expensive to recompute at sampling rate.
  /// It describes the shape of the spike, not a decomposition of the number.
  final Map<String, int> peakBreakdown;

  /// The watermark's sampling period. `0` means sampling is off, so
  /// [peakCount] only reflects moments something happened to poll.
  final double sampleIntervalSeconds;

  final String timestamp;

  FdMonitorStats({
    required this.openCount,
    required this.tableSize,
    required this.softLimit,
    required this.hardLimit,
    required this.percentUsed,
    required this.peakCount,
    required this.peakPercentUsed,
    required this.peakTimestamp,
    required this.peakBreakdown,
    required this.sampleIntervalSeconds,
    required this.timestamp,
  });

  factory FdMonitorStats.fromMap(Map<String, dynamic> map) {
    final breakdown = map['peakBreakdown'] as Map<Object?, Object?>?;

    return FdMonitorStats(
      openCount: (map['openCount'] as num?)?.toInt() ?? 0,
      tableSize: (map['tableSize'] as num?)?.toInt() ?? 0,
      softLimit: (map['softLimit'] as num?)?.toInt() ?? 0,
      hardLimit: (map['hardLimit'] as num?)?.toInt() ?? 0,
      percentUsed: (map['percentUsed'] as num?)?.toDouble() ?? 0.0,
      peakCount: (map['peakCount'] as num?)?.toInt() ?? 0,
      peakPercentUsed: (map['peakPercentUsed'] as num?)?.toDouble() ?? 0.0,
      peakTimestamp: map['peakTimestamp'] as String? ?? '',
      peakBreakdown: {
        for (final entry in (breakdown ?? const {}).entries)
          '${entry.key}': (entry.value as num?)?.toInt() ?? 0,
      },
      sampleIntervalSeconds:
          (map['sampleIntervalSeconds'] as num?)?.toDouble() ?? 0.0,
      timestamp: map['timestamp'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'openCount': openCount,
      'tableSize': tableSize,
      'softLimit': softLimit,
      'hardLimit': hardLimit,
      'percentUsed': percentUsed,
      'peakCount': peakCount,
      'peakPercentUsed': peakPercentUsed,
      'peakTimestamp': peakTimestamp,
      'peakBreakdown': peakBreakdown,
      'sampleIntervalSeconds': sampleIntervalSeconds,
      'timestamp': timestamp,
    };
  }

  /// Open sockets at the peak, or `null` if no breakdown was captured.
  int? get peakSockets => peakBreakdown['socket'];

  @override
  String toString() {
    final breakdown = peakBreakdown.isEmpty
        ? ''
        : ', peak breakdown: ${peakBreakdown.entries.map((e) => '${e.key}=${e.value}').join(' ')}';

    return 'FdMonitorStats(open: $openCount/$softLimit (${percentUsed.toStringAsFixed(1)}%), '
        'peak: $peakCount (${peakPercentUsed.toStringAsFixed(1)}%) at $peakTimestamp, '
        'table: $tableSize, limits: $softLimit/$hardLimit, '
        'sampling: ${sampleIntervalSeconds}s, time: $timestamp$breakdown)';
  }

  bool get isApproachingLimit => percentUsed > 80.0;

  bool get isCritical => percentUsed > 90.0;

  /// Whether the *peak* came close to the limit, which the live reading will
  /// almost never show — bursts are over long before anything polls.
  bool get peakApproachedLimit => peakPercentUsed > 80.0;
}
