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

  Future<Map<String, dynamic>> start({double intervalSeconds = 60.0}) async {
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        'start',
        {'intervalSeconds': intervalSeconds},
      );

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
  final String timestamp;

  FdMonitorStats({
    required this.openCount,
    required this.tableSize,
    required this.softLimit,
    required this.hardLimit,
    required this.percentUsed,
    required this.timestamp,
  });

  factory FdMonitorStats.fromMap(Map<String, dynamic> map) {
    return FdMonitorStats(
      openCount: (map['openCount'] as num?)?.toInt() ?? 0,
      tableSize: (map['tableSize'] as num?)?.toInt() ?? 0,
      softLimit: (map['softLimit'] as num?)?.toInt() ?? 0,
      hardLimit: (map['hardLimit'] as num?)?.toInt() ?? 0,
      percentUsed: (map['percentUsed'] as num?)?.toDouble() ?? 0.0,
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
      'timestamp': timestamp,
    };
  }

  @override
  String toString() {
    return 'FdMonitorStats(open: $openCount/$softLimit (${percentUsed.toStringAsFixed(1)}%), '
        'table: $tableSize, limits: $softLimit/$hardLimit, time: $timestamp)';
  }

  bool get isApproachingLimit => percentUsed > 80.0;

  bool get isCritical => percentUsed > 90.0;
}
