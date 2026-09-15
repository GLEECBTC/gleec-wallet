import 'dart:developer' as developer show log;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:web_dex/app_config/package_information.dart';
import 'package:web_dex/mm2/mm2_api/mm2_api.dart';
import 'package:web_dex/performance_analytics/performance_analytics.dart';
import 'package:web_dex/services/logger/logger.dart';
import 'package:web_dex/services/logger/diagnostic_log_bridge.dart';
import 'package:web_dex/services/logger/mock_logger.dart';
import 'package:web_dex/services/logger/universal_logger.dart';
import 'package:web_dex/services/platform_info/platform_info.dart';
import 'package:web_dex/services/storage/get_storage.dart';
import 'package:web_dex/shared/constants.dart' show isTestMode;

final LoggerInterface logger = _getLogger();
LoggerInterface _getLogger() {
  final platformInfo = PlatformInfo.getInstance();

  if (kIsWeb ||
      Platform.isWindows ||
      Platform.isMacOS ||
      Platform.isLinux ||
      Platform.isAndroid ||
      Platform.isIOS) {
    return UniversalLogger(platformInfo: platformInfo);
  }

  return const MockLogger();
}

Future<void> initializeLogger(Mm2Api mm2Api) async {
  final platformInfo = PlatformInfo.getInstance();
  final localeName =
      await getStorage().read('locale').catchError((_) => null) as String? ??
      '';
  logger.setSessionMetadata({
    'appVersion': packageInformation.packageVersion,
    'mm2Version': await mm2Api.version(),
    'appLanguage': localeName,
    'platform': platformInfo.platform,
    'osLanguage': platformInfo.osLanguage,
    'screenSize': platformInfo.screenSize,
  });

  Logger.root.level = kReleaseMode ? Level.INFO : Level.ALL;
  Logger.root.onRecord.listen(_logToUniversalLogger);
}

Future<void> _logToUniversalLogger(LogRecord record) async {
  final timer = Stopwatch()..start();
  try {
    await forwardDiagnosticRecord(
      record,
      logger,
      debugOutput: isTestMode || kDebugMode
          ? (message) => developer.log(message, name: 'app.diagnostics')
          : null,
    );
    performance.logTimeWritingLogs(timer.elapsedMilliseconds);
  } on Object {
    // Do not stringify sink failures: they can retain the rejected payload.
  } finally {
    timer.stop();
  }
}
