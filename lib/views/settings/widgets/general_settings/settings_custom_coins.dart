import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/settings/settings_bloc.dart';
import 'package:web_dex/bloc/settings/settings_event.dart';
import 'package:web_dex/bloc/settings/settings_state.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/views/settings/widgets/common/settings_section.dart';

/// Which coins file an override slot targets.
enum _CoinsFileKind { kdfCoins, coinsConfig }

/// Advanced/developer setting that lets the user point KDF and the SDK at local
/// `coins` and `coins_config.json` files instead of the bundled configuration.
///
/// The picked file's content is snapshotted in memory (identically on native
/// and web) and handed to [KomodoDefiSdk.setCustomCoins], which persists it.
/// Only the original file name is kept for display. A full app restart is
/// required for the change to take effect.
class SettingsCustomCoins extends StatelessWidget {
  const SettingsCustomCoins({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: 'customCoinsConfiguration'.tr(),
      child: const _CustomCoinsContent(),
    );
  }
}

class _CustomCoinsContent extends StatefulWidget {
  const _CustomCoinsContent();

  @override
  State<_CustomCoinsContent> createState() => _CustomCoinsContentState();
}

class _CustomCoinsContentState extends State<_CustomCoinsContent> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, state) {
        final hasOverride =
            state.customKdfCoinsFileName != null ||
            state.customCoinsConfigFileName != null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'customCoinsConfigurationDescription'.tr(),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            _CoinsFileRow(
              label: 'customKdfCoinsFile'.tr(),
              fileName: state.customKdfCoinsFileName,
              enabled: !_busy,
              onBrowse: () => _pickFile(_CoinsFileKind.kdfCoins),
            ),
            const SizedBox(height: 16),
            _CoinsFileRow(
              label: 'customCoinsConfigFile'.tr(),
              fileName: state.customCoinsConfigFileName,
              enabled: !_busy,
              onBrowse: () => _pickFile(_CoinsFileKind.coinsConfig),
            ),
            const SizedBox(height: 16),
            if (hasOverride)
              TextButton.icon(
                onPressed: _busy ? null : _reset,
                icon: const Icon(Icons.restart_alt, size: 18),
                label: Text('customCoinsResetAll'.tr()),
              ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'customCoinsRestartRequired'.tr(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickFile(_CoinsFileKind kind) async {
    // Capture context-dependent objects before any async gap.
    final sdk = context.read<KomodoDefiSdk>();
    final settingsBloc = context.read<SettingsBloc>();
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _busy = true);
    try {
      final file = await _runPicker();
      if (file == null) return; // cancelled

      switch (kind) {
        case _CoinsFileKind.kdfCoins:
          await sdk.setCustomCoins(kdfCoins: file);
          settingsBloc.add(
            CustomCoinsChanged(kdfCoinsFileName: file.displayLabel),
          );
        case _CoinsFileKind.coinsConfig:
          await sdk.setCustomCoins(coinsConfig: file);
          settingsBloc.add(
            CustomCoinsChanged(coinsConfigFileName: file.displayLabel),
          );
      }

      if (mounted) await _showRestartDialog();
    } catch (e) {
      log(
        'Failed to set custom coins: $e',
        path: 'SettingsCustomCoins',
        isError: true,
      ).ignore();
      messenger.showSnackBar(
        SnackBar(content: Text('customCoinsPickError'.tr())),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Opens the file dialog and captures the selected file's content as a
  /// [CustomCoinsFile] snapshot. Works identically on native and web — the
  /// bytes are read into memory rather than referencing a filesystem path.
  Future<CustomCoinsFile?> _runPicker() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return null;

    var content = utf8.decode(bytes);
    // Strip a leading UTF-8 BOM, which would otherwise break JSON parsing.
    if (content.isNotEmpty && content.codeUnitAt(0) == 0xFEFF) {
      content = content.substring(1);
    }
    return CustomCoinsFile(content: content, fileName: file.name);
  }

  Future<void> _reset() async {
    setState(() => _busy = true);
    try {
      context.read<KomodoDefiSdk>().resetCustomCoins();
      context.read<SettingsBloc>().add(const CustomCoinsReset());
      await _showRestartDialog();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showRestartDialog() {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('customCoinsRestartDialogTitle'.tr()),
        content: Text('customCoinsRestartDialogContent'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('ok'.tr()),
          ),
        ],
      ),
    );
  }
}

class _CoinsFileRow extends StatelessWidget {
  const _CoinsFileRow({
    required this.label,
    required this.fileName,
    required this.enabled,
    required this.onBrowse,
  });

  final String label;
  final String? fileName;
  final bool enabled;
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 2),
              AutoScrollText(
                text: fileName ?? 'customCoinsNotSet'.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: fileName == null
                      ? theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6)
                      : theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton(
          onPressed: enabled ? onBrowse : null,
          child: Text('browse'.tr()),
        ),
      ],
    );
  }
}
