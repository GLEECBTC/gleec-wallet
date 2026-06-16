import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
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
/// File selection happens in the app (via [FilePicker]); the resolved source is
/// handed to [KomodoDefiSdk.setCustomCoinsPath], which persists it. A full app
/// restart is required for the change to take effect.
class SettingsCustomCoinsPath extends StatelessWidget {
  const SettingsCustomCoinsPath({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: 'customCoinsConfiguration'.tr(),
      child: const _CustomCoinsPathContent(),
    );
  }
}

class _CustomCoinsPathContent extends StatefulWidget {
  const _CustomCoinsPathContent();

  @override
  State<_CustomCoinsPathContent> createState() =>
      _CustomCoinsPathContentState();
}

class _CustomCoinsPathContentState extends State<_CustomCoinsPathContent> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, state) {
        final hasOverride =
            state.customKdfCoinsLabel != null ||
            state.customCoinsConfigLabel != null;
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
              value: state.customKdfCoinsLabel,
              enabled: !_busy,
              onBrowse: () =>
                  _pickFile(_CoinsFileKind.kdfCoins, state.customKdfCoinsLabel),
            ),
            const SizedBox(height: 16),
            _CoinsFileRow(
              label: 'customCoinsConfigFile'.tr(),
              value: state.customCoinsConfigLabel,
              enabled: !_busy,
              onBrowse: () => _pickFile(
                _CoinsFileKind.coinsConfig,
                state.customCoinsConfigLabel,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (hasOverride)
                  TextButton.icon(
                    onPressed: _busy ? null : _reset,
                    icon: const Icon(Icons.restart_alt, size: 18),
                    label: Text('customCoinsResetAll'.tr()),
                  ),
              ],
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

  Future<void> _pickFile(_CoinsFileKind kind, String? currentLabel) async {
    // Capture context-dependent objects before any async gap.
    final sdk = context.read<KomodoDefiSdk>();
    final settingsBloc = context.read<SettingsBloc>();
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _busy = true);
    try {
      final source = await _runPicker(currentLabel);
      if (source == null) return; // cancelled

      switch (kind) {
        case _CoinsFileKind.kdfCoins:
          await sdk.setCustomCoinsPath(kdfCoins: source);
          settingsBloc.add(
            CustomCoinsPathChanged(kdfCoinsLabel: source.displayLabel),
          );
        case _CoinsFileKind.coinsConfig:
          await sdk.setCustomCoinsPath(coinsConfig: source);
          settingsBloc.add(
            CustomCoinsPathChanged(coinsConfigLabel: source.displayLabel),
          );
      }

      if (mounted) await _showRestartDialog();
    } catch (e) {
      log(
        'Failed to set custom coins path: $e',
        path: 'SettingsCustomCoinsPath',
        isError: true,
      ).ignore();
      messenger.showSnackBar(
        SnackBar(content: Text('customCoinsPickError'.tr())),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Opens the file dialog and resolves a [CustomCoinsFileSource].
  ///
  /// On native a real filesystem path is returned and [currentLabel]'s
  /// directory pre-populates the picker. On web the file content is read into
  /// memory (there is no filesystem path), so the dialog always opens fresh.
  Future<CustomCoinsFileSource?> _runPicker(String? currentLabel) async {
    final result = await FilePicker.platform.pickFiles(
      withData: kIsWeb,
      initialDirectory: kIsWeb ? null : _directoryOf(currentLabel),
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.first;

    if (kIsWeb) {
      final bytes = file.bytes;
      if (bytes == null) return null;
      return CustomCoinsFileSource.content(
        content: utf8.decode(bytes),
        fileName: file.name,
      );
    }

    final path = file.path;
    if (path == null || path.isEmpty) return null;
    return CustomCoinsFileSource.path(path);
  }

  Future<void> _reset() async {
    setState(() => _busy = true);
    try {
      context.read<KomodoDefiSdk>().resetCustomCoinsPath();
      context.read<SettingsBloc>().add(const CustomCoinsPathReset());
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

  /// Returns the parent directory of [path] for use as the picker's starting
  /// point, or `null` when unavailable. Works for both `/` and `\` separators.
  static String? _directoryOf(String? path) {
    if (path == null || path.isEmpty) return null;
    final separatorIndex = path.lastIndexOf(RegExp(r'[\\/]'));
    if (separatorIndex <= 0) return null;
    final dir = path.substring(0, separatorIndex);
    // A Windows drive root (e.g. "C:") needs a trailing separator to be a
    // valid directory.
    if (dir.length == 2 && dir.endsWith(':')) return '$dir\\';
    return dir;
  }
}

class _CoinsFileRow extends StatelessWidget {
  const _CoinsFileRow({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onBrowse,
  });

  final String label;
  final String? value;
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
                text: value ?? 'customCoinsNotSet'.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: value == null
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
