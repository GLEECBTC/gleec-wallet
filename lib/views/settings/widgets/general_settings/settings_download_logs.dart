import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/services/logger/get_logger.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/views/settings/widgets/common/settings_section.dart';

class SettingsDownloadLogs extends StatefulWidget {
  const SettingsDownloadLogs({Key? key}) : super(key: key);

  @override
  State<SettingsDownloadLogs> createState() => _SettingsDownloadLogsState();
}

class _SettingsDownloadLogsState extends State<SettingsDownloadLogs> {
  bool _isDownloadFile = false;
  bool _isLogFloodBusy = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SettingsSection(
      title: LocaleKeys.logs.tr(),
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          UiBorderButton(
            width: 146,
            height: 32,
            borderWidth: 1,
            borderColor: palette.border,
            backgroundColor: palette.surfaceHigh,
            fontWeight: FontWeight.w500,
            text: LocaleKeys.debugSettingsDownloadButton.tr(),
            icon: _isDownloadFile
                ? const UiSpinner()
                : Icon(
                    Icons.file_download,
                    color: Theme.of(context).textTheme.bodyMedium?.color,
                    size: 18,
                  ),
            onPressed: _isDownloadFile ? null : _downloadLogs,
          ),
          if (shouldShowFloodLogsButton)
            FilledButton.icon(
              label: Text(LocaleKeys.floodLogs.tr()),
              icon: _isLogFloodBusy
                  ? const UiSpinner()
                  : Icon(
                      Icons.warning,
                      color: Theme.of(context).textTheme.bodyMedium?.color,
                      size: 18,
                    ),
              onPressed: _isLogFloodBusy ? null : _runDebugFloodLogs,
            ),
        ],
      ),
    );
  }

  bool get shouldShowFloodLogsButton => kDebugMode || kProfileMode;

  Future<void> _downloadLogs() async {
    setState(() => _isDownloadFile = true);

    await logger
        .getLogFile()
        .whenComplete(() => setState(() => _isDownloadFile = false));
  }

  Future<void> _runDebugFloodLogs() async {
    setState(() => _isLogFloodBusy = true);

    WidgetsBinding.instance.scheduleFrameCallback((_) {
      try {
        for (int i = 0; i < 10000; i++) {
          log('Log spam $i: ${'=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-' * 50}');
        }
      } catch (e) {
        rethrow;
      } finally {
        if (mounted) setState(() => _isLogFloodBusy = false);
      }
    });
  }
}
