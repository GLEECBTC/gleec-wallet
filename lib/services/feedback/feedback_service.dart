import 'package:easy_localization/easy_localization.dart';
import 'package:feedback/feedback.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/services/feedback/feedback_metadata.dart';
import 'package:web_dex/services/feedback/feedback_provider.dart';
import 'package:web_dex/services/feedback/providers/cloudflare_feedback_provider.dart';
import 'package:web_dex/services/feedback/providers/debug_console_feedback_provider.dart';
import 'package:web_dex/services/feedback/providers/trello_feedback_provider.dart';
import 'package:web_dex/services/logger/get_logger.dart' as app_logger;
import 'package:web_dex/services/logger/safe_log_exporter.dart';

export 'feedback_ui_extension.dart';

/// Coordinates optional diagnostics before passing a complete submission to a
/// transport. Providers never reach back into application log storage.
class FeedbackService {
  const FeedbackService({
    required this.provider,
    this.loadMetadata = collectFeedbackMetadata,
    this.loadDiagnostics = exportFeedbackDiagnostics,
    this.diagnosticsTimeout = const Duration(seconds: 3),
  });

  final FeedbackProvider provider;
  final Future<Map<String, dynamic>> Function() loadMetadata;
  final Future<SafeLogAttachment> Function() loadDiagnostics;
  final Duration diagnosticsTimeout;

  static FeedbackService? create() {
    final provider = [
      CloudflareFeedbackProvider.fromEnvironment(),
      TrelloFeedbackProvider.fromEnvironment(),
      if (kDebugMode) DebugConsoleFeedbackProvider(),
    ].firstWhereOrNull((provider) => provider != null && provider.isAvailable);
    return provider != null ? FeedbackService(provider: provider) : null;
  }

  bool get isAvailable => provider.isAvailable;

  Future<bool> handleFeedback(UserFeedback feedback) async {
    var metadata = <String, dynamic>{};
    SafeLogAttachment? diagnostics;
    try {
      metadata = sanitizeFeedbackMetadata(
        await loadMetadata().timeout(diagnosticsTimeout),
      );
    } on Object {
      // Diagnostic availability must not prevent an ordinary feedback report.
    }
    try {
      diagnostics = await loadDiagnostics().timeout(diagnosticsTimeout);
    } on Object {
      // In particular, a pending/failed legacy cleanup never permits raw logs.
    }
    metadata.addAll(submittedFeedbackContact(feedback.extra));
    final type = feedback.extra?['feedback_type'];
    try {
      await provider.submitFeedback(
        description: feedback.text,
        screenshot: feedback.screenshot,
        type: type is String ? type : LocaleKeys.feedbackDefaultType.tr(),
        metadata: metadata,
        diagnostics: diagnostics,
      );
      return true;
    } on Object {
      return false;
    }
  }
}

Future<SafeLogAttachment> exportFeedbackDiagnostics() =>
    app_logger.logger.exportLogs(maxBytes: SafeLogExporter.feedbackMaxBytes);

Future<Map<String, dynamic>> collectFeedbackMetadata() async {
  final metadata = <String, dynamic>{
    'platform': kIsWeb ? 'web' : 'native',
    'targetPlatform': defaultTargetPlatform.name,
    'commitHash': const String.fromEnvironment(
      'COMMIT_HASH',
      defaultValue: 'unknown',
    ),
    'mode': kReleaseMode
        ? 'release'
        : kDebugMode
        ? 'debug'
        : 'profile',
    'timestamp': DateTime.now().toUtc().toIso8601String(),
  };
  try {
    final package = await PackageInfo.fromPlatform();
    metadata.addAll({
      'appName': package.appName,
      'packageName': package.packageName,
      'version': package.version,
      'buildNumber': package.buildNumber,
    });
  } on Object {
    // Optional platform details only.
  }
  if (GetIt.I.isRegistered<KomodoDefiSdk>()) {
    final sdk = GetIt.I<KomodoDefiSdk>();
    try {
      final user = await sdk.auth.currentUser.timeout(
        const Duration(seconds: 2),
      );
      if (user != null) {
        metadata['walletIsHd'] = user.isHd;
        metadata['walletIsBip39'] = user.isBip39Seed;
      }
    } on Object {
      // No wallet identifiers or arbitrary user metadata are exported.
    }
    try {
      metadata['coinsCurrentCommit'] = await sdk.assets.currentCoinsCommit
          .timeout(const Duration(seconds: 2));
      metadata['coinsLatestCommit'] = await sdk.assets.latestCoinsCommit
          .timeout(const Duration(seconds: 2));
    } on Object {
      // A catalogue lookup must not be required to submit feedback.
    }
  }
  return sanitizeFeedbackMetadata(metadata);
}
