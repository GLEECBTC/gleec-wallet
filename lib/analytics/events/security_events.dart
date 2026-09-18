import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:web_dex/bloc/analytics/analytics_event.dart';
import 'package:web_dex/bloc/analytics/analytics_repo.dart';

/// E05: Seed backup finished
/// Business category: Security.
class BackupCompletedEventData extends AnalyticsEventData {
  const BackupCompletedEventData({
    required this.backupTime,
    required this.method,
    required this.hdType,
  });

  /// Seconds from entering the backup flow to completing it. 0 means the
  /// anchor was missing, not that the backup was instant.
  final int backupTime;
  final String method;
  final String hdType;

  @override
  String get name => 'backup_complete';

  @override
  JsonMap get parameters => {
    'backup_time': backupTime,
    'method': method,
    'hd_type': hdType,
  };
}

/// E05: Seed backup finished
class AnalyticsBackupCompletedEvent extends AnalyticsSendDataEvent {
  AnalyticsBackupCompletedEvent({
    required int backupTime,
    required String method,
    required String hdType,
  }) : super(
         BackupCompletedEventData(
           backupTime: backupTime,
           method: method,
           hdType: hdType,
         ),
       );
}

/// E06: Backup skipped / postponed
/// Business category: Security.
class BackupSkippedEventData extends AnalyticsEventData {
  const BackupSkippedEventData({
    required this.stageSkipped,
    required this.hdType,
  });

  final String stageSkipped;
  final String hdType;

  @override
  String get name => 'backup_skipped';

  @override
  JsonMap get parameters => {'stage_skipped': stageSkipped, 'hd_type': hdType};
}

/// E06: Backup skipped / postponed
class AnalyticsBackupSkippedEvent extends AnalyticsSendDataEvent {
  AnalyticsBackupSkippedEvent({
    required String stageSkipped,
    required String hdType,
  }) : super(
         BackupSkippedEventData(stageSkipped: stageSkipped, hdType: hdType),
       );
}
