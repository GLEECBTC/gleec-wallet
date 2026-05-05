import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart'
    show ZhtlcSyncParams;
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart'
    show
        KomodoDefiSdk,
        ZhtlcRecurringSyncMode,
        ZhtlcRecurringSyncPolicy,
        ZhtlcUserConfig,
        ZcashParamsDownloader,
        ZcashParamsDownloaderFactory,
        DownloadProgress,
        DownloadResultSuccess;
import 'package:komodo_defi_types/komodo_defi_types.dart' show Asset;
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';

enum ZhtlcSyncType { recentTransactions, earliest, height, date }

/// Shows ZHTLC configuration dialog similar to handleZhtlcConfigDialog from SDK example
/// This is bad practice (UI logic in utils), but necessary for now because of
/// auto-coin activations from multiple sources in BLoCs.
Future<ZhtlcUserConfig?> confirmZhtlcConfiguration(
  BuildContext context, {
  required Asset asset,
}) async {
  final sdk = RepositoryProvider.of<KomodoDefiSdk>(context);
  final initialConfig = await sdk.activationConfigService.getSavedZhtlc(
    asset.id,
  );
  if (!context.mounted) {
    return null;
  }
  String? prefilledZcashPath;

  if (ZcashParamsDownloaderFactory.requiresDownload) {
    ZcashParamsDownloader? downloader;
    try {
      downloader = ZcashParamsDownloaderFactory.create();

      final areAvailable = await downloader.areParamsAvailable();
      if (!areAvailable) {
        if (!context.mounted) {
          return null;
        }
        final downloadResult = await _showZcashDownloadDialog(
          context,
          downloader,
        );

        if (downloadResult == false) {
          // User cancelled the download
          return null;
        }
      }

      prefilledZcashPath = await downloader.getParamsPath();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(LocaleKeys.zhtlcErrorSettingUpZcash.tr(args: ['$e'])),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      downloader?.dispose();
    }
  }

  if (!context.mounted) {
    return null;
  }
  return showDialog<ZhtlcUserConfig?>(
    context: context,
    barrierDismissible: false,
    builder: (context) => ZhtlcConfigurationDialog(
      asset: asset,
      prefilledZcashPath: prefilledZcashPath,
      initialConfig: initialConfig,
    ),
  );
}

/// Stateful widget for ZHTLC configuration dialog
class ZhtlcConfigurationDialog extends StatefulWidget {
  const ZhtlcConfigurationDialog({
    super.key,
    required this.asset,
    this.prefilledZcashPath,
    this.initialConfig,
  });

  final Asset asset;
  final String? prefilledZcashPath;
  final ZhtlcUserConfig? initialConfig;

  @override
  State<ZhtlcConfigurationDialog> createState() =>
      _ZhtlcConfigurationDialogState();
}

class _ZhtlcConfigurationDialogState extends State<ZhtlcConfigurationDialog> {
  late final TextEditingController zcashPathController;
  late final TextEditingController blocksPerIterController;
  late final TextEditingController intervalMsController;
  StreamSubscription<AuthBlocState>? _authSubscription;
  bool _dismissedDueToAuthChange = false;
  bool _showAdvancedConfig = false;

  final GlobalKey<_SyncFormState> _syncFormKey = GlobalKey<_SyncFormState>();

  @override
  void initState() {
    super.initState();

    // On web, use './zcash-params' as default, otherwise use prefilledZcashPath
    // TODO: get from config factory constructor, or move to constants
    final defaultZcashPath =
        widget.prefilledZcashPath ??
        widget.initialConfig?.zcashParamsPath ??
        (kIsWeb ? './zcash-params' : null);
    zcashPathController = TextEditingController(text: defaultZcashPath);
    blocksPerIterController = TextEditingController(
      text: '${widget.initialConfig?.scanBlocksPerIteration ?? 1000}',
    );
    intervalMsController = TextEditingController(
      text: '${widget.initialConfig?.scanIntervalMs ?? 200}',
    );

    _subscribeToAuthChanges();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    zcashPathController.dispose();
    blocksPerIterController.dispose();
    intervalMsController.dispose();
    super.dispose();
  }

  void _handleSave() {
    final path = zcashPathController.text.trim();
    // On web, allow empty path, otherwise require it
    if (!kIsWeb && path.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(LocaleKeys.zhtlcZcashParamsRequired.tr())),
      );
      return;
    }

    // Build both pieces:
    // - recurringSyncPolicy: persisted user preference for future reconfigures.
    // - syncParams: one-shot override for the next activation only.
    // Later activations omit sync_params unless the user reconfigures again,
    // allowing backend-side resume/default sync behavior.
    final syncState = _syncFormKey.currentState;
    final recurringSyncPolicy = syncState?.buildRecurringSyncPolicy();
    final syncParams = syncState?.buildSyncParams();
    if (recurringSyncPolicy == null || syncParams == null) {
      return;
    }

    final result = ZhtlcUserConfig(
      zcashParamsPath: path,
      scanBlocksPerIteration:
          int.tryParse(blocksPerIterController.text) ?? 1000,
      scanIntervalMs: int.tryParse(intervalMsController.text) ?? 0,
      recurringSyncPolicy: recurringSyncPolicy,
      syncParams: syncParams,
    );
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        LocaleKeys.zhtlcConfigureTitle.tr(args: [widget.asset.id.id]),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700, minWidth: 300),
        child: IntrinsicWidth(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!kIsWeb) ...[
                  TextField(
                    controller: zcashPathController,
                    readOnly: widget.prefilledZcashPath != null,
                    decoration: InputDecoration(
                      labelText: LocaleKeys.zhtlcZcashParamsPathLabel.tr(),
                      helperText: widget.prefilledZcashPath != null
                          ? LocaleKeys.zhtlcPathAutomaticallyDetected.tr()
                          : LocaleKeys.zhtlcSaplingParamsFolder.tr(),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                _SyncForm(
                  key: _syncFormKey,
                  initialPolicy:
                      widget.initialConfig?.recurringSyncPolicy ??
                      (widget.initialConfig?.syncParams == null
                          ? null
                          : ZhtlcRecurringSyncPolicy.fromSyncParams(
                              widget.initialConfig!.syncParams!,
                            )),
                ),
                const SizedBox(height: 24),
                _AdvancedConfigurationSection(
                  showAdvancedConfig: _showAdvancedConfig,
                  onToggle: () => setState(
                    () => _showAdvancedConfig = !_showAdvancedConfig,
                  ),
                  blocksPerIterController: blocksPerIterController,
                  intervalMsController: intervalMsController,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(LocaleKeys.cancel.tr()),
        ),
        FilledButton(onPressed: _handleSave, child: Text(LocaleKeys.ok.tr())),
      ],
    );
  }

  void _subscribeToAuthChanges() {
    _authSubscription = context.read<AuthBloc>().stream.listen((state) {
      if (state.currentUser == null) {
        _handleAuthSignedOut();
      }
    });
  }

  void _handleAuthSignedOut() {
    if (_dismissedDueToAuthChange || !mounted) {
      return;
    }

    _dismissedDueToAuthChange = true;
    Navigator.of(context).maybePop<ZhtlcUserConfig?>(null);
  }
}

class _AdvancedConfigurationSection extends StatelessWidget {
  const _AdvancedConfigurationSection({
    required this.showAdvancedConfig,
    required this.onToggle,
    required this.blocksPerIterController,
    required this.intervalMsController,
  });

  final bool showAdvancedConfig;
  final VoidCallback onToggle;
  final TextEditingController blocksPerIterController;
  final TextEditingController intervalMsController;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggle,
          child: Row(
            children: [
              Icon(showAdvancedConfig ? Icons.expand_less : Icons.expand_more),
              const SizedBox(width: 8),
              Text(
                LocaleKeys.zhtlcAdvancedConfiguration.tr(),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
        if (showAdvancedConfig) ...[
          const SizedBox(height: 12),
          const _AdvancedConfigurationWarning(),
          const SizedBox(height: 12),
          TextField(
            controller: blocksPerIterController,
            decoration: InputDecoration(
              labelText: LocaleKeys.zhtlcBlocksPerIterationLabel.tr(),
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: intervalMsController,
            decoration: InputDecoration(
              labelText: LocaleKeys.zhtlcScanIntervalLabel.tr(),
            ),
            keyboardType: TextInputType.number,
          ),
        ],
      ],
    );
  }
}

class _AdvancedConfigurationWarning extends StatelessWidget {
  const _AdvancedConfigurationWarning();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final backgroundColor = theme.colorScheme.secondaryContainer;
    final foregroundColor = theme.colorScheme.onSecondaryContainer;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundColor.withValues(alpha: 0.1),
        border: Border.all(color: foregroundColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: foregroundColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              LocaleKeys.zhtlcAdvancedConfigurationHint.tr(),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: foregroundColor),
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncForm extends StatefulWidget {
  const _SyncForm({super.key, this.initialPolicy});

  final ZhtlcRecurringSyncPolicy? initialPolicy;

  @override
  State<_SyncForm> createState() => _SyncFormState();
}

class _SyncFormState extends State<_SyncForm> {
  late final TextEditingController _syncValueController;
  ZhtlcSyncType _syncType = ZhtlcSyncType.recentTransactions;
  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    _applyInitialPolicy(widget.initialPolicy);
    _syncValueController = TextEditingController(text: _initialSyncValue());
  }

  @override
  void dispose() {
    _syncValueController.dispose();
    super.dispose();
  }

  ZhtlcRecurringSyncPolicy? buildRecurringSyncPolicy() {
    switch (_syncType) {
      case ZhtlcSyncType.recentTransactions:
        return ZhtlcRecurringSyncPolicy.recentTransactions();
      case ZhtlcSyncType.earliest:
        return ZhtlcRecurringSyncPolicy.earliest();
      case ZhtlcSyncType.height:
        final rawValue = _syncValueController.text.trim();
        final parsedValue = int.tryParse(rawValue);
        if (parsedValue == null) {
          _showSnackBar(LocaleKeys.zhtlcInvalidBlockHeight.tr());
          return null;
        }
        return ZhtlcRecurringSyncPolicy.height(parsedValue);
      case ZhtlcSyncType.date:
        if (_selectedDate == null) {
          return null;
        }
        return ZhtlcRecurringSyncPolicy.date(
          _selectedDate!.millisecondsSinceEpoch ~/ 1000,
        );
    }
  }

  ZhtlcSyncParams? buildSyncParams() {
    final recurringPolicy = buildRecurringSyncPolicy();
    if (recurringPolicy == null) {
      return null;
    }

    switch (_syncType) {
      case ZhtlcSyncType.recentTransactions:
        return recurringPolicy.toSyncParams();
      case ZhtlcSyncType.earliest:
        return ZhtlcSyncParams.earliest();
      case ZhtlcSyncType.height:
        return ZhtlcSyncParams.height(recurringPolicy.height!);
      case ZhtlcSyncType.date:
        return ZhtlcSyncParams.date(recurringPolicy.unixTimestamp!);
    }
  }

  void _showSnackBar(String message) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  void _applyInitialPolicy(ZhtlcRecurringSyncPolicy? initialPolicy) {
    switch (initialPolicy?.mode) {
      case ZhtlcRecurringSyncMode.earliest:
        _syncType = ZhtlcSyncType.earliest;
        _selectedDate = null;
        return;
      case ZhtlcRecurringSyncMode.height:
        _syncType = ZhtlcSyncType.height;
        _selectedDate = null;
        return;
      case ZhtlcRecurringSyncMode.date:
        _syncType = ZhtlcSyncType.date;
        _selectedDate = DateTime.fromMillisecondsSinceEpoch(
          (initialPolicy?.unixTimestamp ?? 0) * 1000,
          isUtc: true,
        );
        return;
      case ZhtlcRecurringSyncMode.recentTransactions:
      case null:
        _syncType = ZhtlcSyncType.recentTransactions;
        _selectedDate = DateTime.now().subtract(const Duration(days: 2));
        return;
    }
  }

  String _initialSyncValue() {
    switch (widget.initialPolicy?.mode) {
      case ZhtlcRecurringSyncMode.height:
        return '${widget.initialPolicy?.height ?? ''}';
      case ZhtlcRecurringSyncMode.date:
        final ts = widget.initialPolicy?.unixTimestamp;
        if (ts != null) {
          return _formatDate(
            DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true),
          );
        }
        return _selectedDate == null ? '' : _formatDate(_selectedDate!);
      case ZhtlcRecurringSyncMode.earliest:
      case ZhtlcRecurringSyncMode.recentTransactions:
      case null:
        return '';
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2018),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: _createMaterial3DatePickerTheme(),
          child: child ?? const SizedBox(),
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedDate = DateTime(picked.year, picked.month, picked.day);
        _syncValueController.text = _formatDate(_selectedDate!);
      });
    }
  }

  void _onSyncTypeChanged(ZhtlcSyncType? newType) {
    if (newType == null) {
      return;
    }

    setState(() {
      _syncType = newType;
      if (_syncType == ZhtlcSyncType.date) {
        _selectedDate = DateTime.now().subtract(const Duration(days: 2));
        _syncValueController.text = _formatDate(_selectedDate!);
      } else {
        _selectedDate = null;
        _syncValueController.clear();
      }
    });
  }

  String _formatDate(DateTime dateTime) {
    return dateTime.toIso8601String().split('T')[0];
  }

  ThemeData _createMaterial3DatePickerTheme() {
    final currentTheme = Theme.of(context);
    final currentColorScheme = currentTheme.colorScheme;

    final material3ColorScheme = ColorScheme.fromSeed(
      seedColor: currentColorScheme.primary,
      brightness: currentColorScheme.brightness,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: material3ColorScheme,
      fontFamily: currentTheme.textTheme.bodyMedium?.fontFamily,
    );
  }

  String _syncTypeLabel(ZhtlcSyncType type) {
    switch (type) {
      case ZhtlcSyncType.recentTransactions:
        return LocaleKeys.zhtlcRecentTransactionsOption.tr();
      case ZhtlcSyncType.earliest:
        return LocaleKeys.zhtlcEarliestSaplingOption.tr();
      case ZhtlcSyncType.height:
        return LocaleKeys.zhtlcBlockHeightOption.tr();
      case ZhtlcSyncType.date:
        return LocaleKeys.zhtlcDateTimeOption.tr();
    }
  }

  /// Height and date need a value; earliest and recentTransactions do not.
  bool get _shouldShowValueField =>
      _syncType == ZhtlcSyncType.height || _syncType == ZhtlcSyncType.date;

  bool get _isDate => _syncType == ZhtlcSyncType.date;

  bool get _isHeight => _syncType == ZhtlcSyncType.height;

  @override
  Widget build(BuildContext context) {
    final dropdownItems = ZhtlcSyncType.values
        .map(
          (type) => DropdownMenuItem<ZhtlcSyncType>(
            value: type,
            alignment: Alignment.centerLeft,
            child: Text(_syncTypeLabel(type)),
          ),
        )
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(LocaleKeys.zhtlcStartSyncFromLabel.tr()),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: DropdownButtonFormField<ZhtlcSyncType>(
                initialValue: _syncType,
                items: dropdownItems,
                onChanged: _onSyncTypeChanged,
              ),
            ),
            if (_shouldShowValueField) ...[
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _syncValueController,
                  decoration: InputDecoration(
                    labelText: _isHeight
                        ? LocaleKeys.zhtlcBlockHeightOption.tr()
                        : LocaleKeys.zhtlcSelectDateTimeLabel.tr(),
                    suffixIcon: _isDate
                        ? IconButton(
                            icon: const Icon(Icons.calendar_today),
                            onPressed: _selectDate,
                          )
                        : null,
                  ),
                  keyboardType: _isHeight
                      ? TextInputType.number
                      : TextInputType.none,
                  readOnly: _isDate,
                  onTap: _isDate ? () => _selectDate() : null,
                ),
              ),
            ],
          ],
        ),
        if (_shouldShowValueField) ...[
          const SizedBox(height: 24),
          if (_isDate) ...[const _SyncTimeWarning()],
        ],
      ],
    );
  }
}

class _SyncTimeWarning extends StatelessWidget {
  const _SyncTimeWarning();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final backgroundColor = theme.colorScheme.secondaryContainer;
    final foregroundColor = theme.colorScheme.onSecondaryContainer;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundColor.withValues(alpha: 0.1),
        border: Border.all(color: foregroundColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: foregroundColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              LocaleKeys.zhtlcDateSyncHint.tr(),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: foregroundColor),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows a download progress dialog for Zcash parameters
Future<bool?> _showZcashDownloadDialog(
  BuildContext context,
  ZcashParamsDownloader downloader,
) async {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => ZcashDownloadProgressDialog(downloader: downloader),
  );
}

/// Stateful widget for Zcash download progress dialog
class ZcashDownloadProgressDialog extends StatefulWidget {
  const ZcashDownloadProgressDialog({required this.downloader, super.key});

  final ZcashParamsDownloader downloader;

  @override
  State<ZcashDownloadProgressDialog> createState() =>
      _ZcashDownloadProgressDialogState();
}

class _ZcashDownloadProgressDialogState
    extends State<ZcashDownloadProgressDialog> {
  static const downloadTimeout = Duration(minutes: 10);
  bool downloadComplete = false;
  bool downloadSuccess = false;
  bool dialogClosed = false;
  late Future<void> downloadFuture;

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  void _startDownload() {
    downloadFuture = widget.downloader
        .downloadParams()
        .timeout(
          downloadTimeout,
          onTimeout: () => throw TimeoutException(
            'Download timed out after ${downloadTimeout.inMinutes} minutes',
            downloadTimeout,
          ),
        )
        .then((result) {
          if (!downloadComplete && !dialogClosed && mounted) {
            downloadComplete = true;
            downloadSuccess = result is DownloadResultSuccess;

            // Close the dialog with the result
            dialogClosed = true;
            Navigator.of(context).pop(downloadSuccess);
          }
        })
        .catchError((Object e, StackTrace? stackTrace) {
          if (!downloadComplete && !dialogClosed && mounted) {
            downloadComplete = true;
            downloadSuccess = false;

            debugPrint('Zcash parameters download failed: $e');
            if (stackTrace != null) {
              debugPrint('Stack trace: $stackTrace');
            }

            // Indicate download failed (null result)
            dialogClosed = true;
            Navigator.of(context).pop();
          }
        });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(LocaleKeys.zhtlcDownloadingZcashParams.tr()),
      content: SizedBox(
        height: 120,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            StreamBuilder<DownloadProgress>(
              stream: widget.downloader.downloadProgress,
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  final progress = snapshot.data;
                  return Column(
                    children: [
                      Text(
                        progress?.displayText ?? '',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: (progress?.percentage ?? 0) / 100,
                      ),
                      Text(
                        '${(progress?.percentage ?? 0).toStringAsFixed(1)}%',
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  );
                }
                return Text(LocaleKeys.zhtlcPreparingDownload.tr());
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            if (!dialogClosed) {
              dialogClosed = true;
              final navigator = Navigator.of(context);
              await widget.downloader.cancelDownload();
              if (!mounted) {
                return;
              }
              navigator.pop(false); // Cancelled
            }
          },
          child: Text(LocaleKeys.cancel.tr()),
        ),
      ],
    );
  }
}
