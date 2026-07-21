import 'dart:async';
import 'dart:convert';

import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/market_maker_bot/market_maker_bot/market_maker_bot_bloc.dart';
import 'package:web_dex/bloc/market_maker_bot/market_maker_bot/market_maker_bot_wallet_session.dart';
import 'package:web_dex/bloc/settings/settings_bloc.dart';
import 'package:web_dex/bloc/settings/settings_repository.dart';
import 'package:web_dex/bloc/settings/settings_state.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/mm2/mm2_api/rpc/market_maker_bot/trade_coin_pair_config.dart';
import 'package:web_dex/model/settings/market_maker_bot_settings.dart';
import 'package:web_dex/services/file_loader/file_loader.dart';
import 'package:web_dex/views/dex/common/dex_confirmation_dialog.dart';
import 'package:web_dex/views/settings/widgets/common/settings_section.dart';

const int _maximumMakerOrderImportBytes = 256 * 1024;
const int _maximumMakerOrderImportCodeUnits = _maximumMakerOrderImportBytes;

enum _MakerOrderImportFailure {
  empty,
  tooLarge,
  unsupportedFormat,
  missingConfigList,
  tooManyConfigs,
  invalidConfig,
  duplicateConfig,
  disabledConfig,
  botActive,
}

final class _MakerOrderImportException implements Exception {
  const _MakerOrderImportException(this.failure);

  final _MakerOrderImportFailure failure;
}

class SettingsManageTradingBot extends StatefulWidget {
  const SettingsManageTradingBot({super.key});

  @override
  State<SettingsManageTradingBot> createState() =>
      _SettingsManageTradingBotState();
}

class _SettingsManageTradingBotState extends State<SettingsManageTradingBot> {
  final SettingsRepository _settingsRepository = SettingsRepository();

  bool _isExporting = false;
  bool _isImporting = false;

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: LocaleKeys.expertMode.tr(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _EnableTradingBotSwitcher(),
          const SizedBox(height: 14),
          const _SaveOrdersSwitcher(),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              _buildExportButton(context),
              _buildImportButton(context),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'saveOrdersRestartHint'.tr(),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildExportButton(BuildContext context) {
    return UiBorderButton(
      width: 180,
      height: 32,
      borderWidth: 1,
      borderColor: theme.custom.specificButtonBorderColor,
      backgroundColor: theme.custom.specificButtonBackgroundColor,
      fontWeight: FontWeight.w500,
      text: 'exportMakerOrders'.tr(),
      icon: _isExporting
          ? const UiSpinner()
          : Icon(
              Icons.file_download,
              color: Theme.of(context).textTheme.bodyMedium?.color,
              size: 18,
            ),
      onPressed: _isExporting || _isImporting ? null : _exportMakerOrders,
    );
  }

  Widget _buildImportButton(BuildContext context) {
    return UiBorderButton(
      width: 180,
      height: 32,
      borderWidth: 1,
      borderColor: theme.custom.specificButtonBorderColor,
      backgroundColor: theme.custom.specificButtonBackgroundColor,
      fontWeight: FontWeight.w500,
      text: 'importMakerOrders'.tr(),
      icon: _isImporting
          ? const UiSpinner()
          : Icon(
              Icons.file_upload,
              color: Theme.of(context).textTheme.bodyMedium?.color,
              size: 18,
            ),
      onPressed: _isExporting || _isImporting ? null : _importMakerOrders,
    );
  }

  Future<void> _exportMakerOrders() async {
    setState(() => _isExporting = true);

    try {
      final settings = await _settingsRepository.loadSettings();
      final configs = settings.marketMakerBotSettings.tradeCoinPairConfigs;
      if (configs.isEmpty) {
        _showMessage('noMakerOrdersToExport'.tr());
        return;
      }

      final payload = <String, dynamic>{
        'version': 1,
        'exported_at': DateTime.now().toUtc().toIso8601String(),
        'trade_coin_pair_configs': configs.map((e) => e.toJson()).toList(),
      };
      final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
        ':',
        '-',
      );

      await FileLoader.fromPlatform().save(
        fileName: 'maker_orders_$timestamp.json',
        data: jsonEncode(payload),
        type: LoadFileType.text,
      );
      _showMessage(
        'makerOrdersExportSuccess'.tr(args: [configs.length.toString()]),
      );
    } catch (error) {
      _showMessage(
        'makerOrdersExportFailed'.tr(args: [_readableError(error)]),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Future<void> _importMakerOrders() async {
    if (_isImporting) return;
    setState(() => _isImporting = true);

    final applyCompletion = Completer<void>();
    var callbackHandled = false;

    void completeApply() {
      if (!applyCompletion.isCompleted) applyCompletion.complete();
    }

    try {
      await FileLoader.fromPlatform().upload(
        fileType: LoadFileType.text,
        onUpload: (_, content) {
          if (callbackHandled) return;
          callbackHandled = true;
          unawaited(_applyImportedOrders(content).whenComplete(completeApply));
        },
        onError: (error) {
          if (callbackHandled) return;
          callbackHandled = true;
          _showMessage(
            'makerOrdersImportFailed'.tr(args: [_readableError(error)]),
            isError: true,
          );
          completeApply();
        },
      );
      // Native pickers invoke the callback before returning. The web loader
      // now also waits for selection or cancellation before returning. If a
      // file was selected, keep the single import lease until validation,
      // lifecycle reconciliation and persistence have all completed.
      if (callbackHandled) await applyCompletion.future;
    } catch (error) {
      _showMessage(
        'makerOrdersImportFailed'.tr(args: [_readableError(error)]),
        isError: true,
      );
    } finally {
      if (mounted) {
        // On desktop/native file picker this also handles cancel events.
        setState(() => _isImporting = false);
      }
    }
  }

  Future<void> _applyImportedOrders(String? rawContent) async {
    try {
      if (rawContent != null &&
          rawContent.length > _maximumMakerOrderImportCodeUnits) {
        throw const _MakerOrderImportException(
          _MakerOrderImportFailure.tooLarge,
        );
      }
      final content = rawContent?.trim() ?? '';
      if (content.isEmpty) {
        throw const _MakerOrderImportException(_MakerOrderImportFailure.empty);
      }
      if (utf8.encode(content).length > _maximumMakerOrderImportBytes) {
        throw const _MakerOrderImportException(
          _MakerOrderImportFailure.tooLarge,
        );
      }

      final importedConfigs = _decodeTradePairConfigs(content);
      final walletSession = await _ensureBotIsStoppedForImport();
      if (walletSession == null || !mounted) return;
      final botBloc = context.read<MarketMakerBotBloc>();
      final settingsBloc = context.read<SettingsBloc>();
      final completed = await botBloc.runStoppedConfigurationMutation(
        walletSession: walletSession,
        mutation: (beforeWrite) async {
          await settingsBloc.updateMarketMakerBotSettingsAndWait(
            (current) =>
                current.copyWith(tradeCoinPairConfigs: importedConfigs),
            beforeWrite: beforeWrite,
          );
        },
      );
      if (!completed) {
        throw const _MakerOrderImportException(
          _MakerOrderImportFailure.botActive,
        );
      }
      if (!mounted) return;
      _showMessage(
        'makerOrdersImportSuccess'.tr(
          args: [importedConfigs.length.toString()],
        ),
      );
    } catch (error) {
      _showMessage(
        'makerOrdersImportFailed'.tr(args: [_readableError(error)]),
        isError: true,
      );
    }
  }

  List<TradeCoinPairConfig> _decodeTradePairConfigs(String jsonPayload) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(jsonPayload);
    } on FormatException {
      throw const _MakerOrderImportException(
        _MakerOrderImportFailure.unsupportedFormat,
      );
    }

    final dynamic rawConfigs;
    if (decoded is List) {
      rawConfigs = decoded;
    } else if (decoded is Map<String, dynamic>) {
      final candidates = <Object?>[
        decoded['trade_coin_pair_configs'],
        decoded['tradeCoinPairConfigs'],
        decoded['orders'],
      ].where((value) => value != null).toList(growable: false);
      if (candidates.length != 1) {
        throw const _MakerOrderImportException(
          _MakerOrderImportFailure.missingConfigList,
        );
      }
      final version = decoded['version'];
      if (version != null && version != 1) {
        throw const _MakerOrderImportException(
          _MakerOrderImportFailure.unsupportedFormat,
        );
      }
      rawConfigs = candidates.single;
    } else {
      throw const _MakerOrderImportException(
        _MakerOrderImportFailure.unsupportedFormat,
      );
    }

    if (rawConfigs is! List) {
      throw const _MakerOrderImportException(
        _MakerOrderImportFailure.missingConfigList,
      );
    }
    if (rawConfigs.isEmpty) {
      throw const _MakerOrderImportException(
        _MakerOrderImportFailure.invalidConfig,
      );
    }
    if (rawConfigs.length >
        MarketMakerBotSettings.maximumTradePairConfigCount) {
      throw const _MakerOrderImportException(
        _MakerOrderImportFailure.tooManyConfigs,
      );
    }

    final dedupedByName = <String, TradeCoinPairConfig>{};
    for (final item in rawConfigs) {
      if (item is! Map) {
        throw const _MakerOrderImportException(
          _MakerOrderImportFailure.invalidConfig,
        );
      }

      final TradeCoinPairConfig config;
      try {
        config = TradeCoinPairConfig.fromJson(Map<String, dynamic>.from(item));
      } catch (_) {
        // Imports are atomic. A file with one bad entry must not silently
        // replace a known-good strategy with an incomplete subset.
        throw const _MakerOrderImportException(
          _MakerOrderImportFailure.invalidConfig,
        );
      }

      if (!config.enable) {
        throw const _MakerOrderImportException(
          _MakerOrderImportFailure.disabledConfig,
        );
      }
      final key = config.name.toUpperCase();
      if (dedupedByName.containsKey(key)) {
        throw const _MakerOrderImportException(
          _MakerOrderImportFailure.duplicateConfig,
        );
      }
      dedupedByName[key] = config;
    }

    return List<TradeCoinPairConfig>.unmodifiable(dedupedByName.values);
  }

  Future<MarketMakerBotWalletSession?> _ensureBotIsStoppedForImport() async {
    final botBloc = context.read<MarketMakerBotBloc>();
    final walletSession = botBloc.captureWalletSession();
    if (walletSession == null) {
      throw const _MakerOrderImportException(
        _MakerOrderImportFailure.botActive,
      );
    }
    if (botBloc.isConfigurationMutationSafe(walletSession)) {
      return walletSession;
    }

    final stored = await _settingsRepository.loadSettings();
    if (!mounted || botBloc.captureWalletSession() != walletSession) {
      throw const _MakerOrderImportException(
        _MakerOrderImportFailure.botActive,
      );
    }
    final configuredPairs = List<TradeCoinPairConfig>.unmodifiable(
      stored.marketMakerBotSettings.tradeCoinPairConfigs,
    );
    final labels =
        configuredPairs
            .map((pair) => '${pair.baseCoinId}/${pair.relCoinId}')
            .toSet()
            .toList()
          ..sort();
    final confirmed = await showDexActionConfirmation(
      context: context,
      actionLabel: LocaleKeys.mmBotStop.tr(),
      targetDescription:
          '${'marketMakerStopTarget'.tr(namedArgs: {'count': '${configuredPairs.length}', 'pairs': labels.isEmpty ? '—' : labels.join(', ')})}\n\n'
          '${'marketMakerBootstrapStopImpact'.tr()}',
      confirmButtonKey: const Key('import-maker-orders-stop-confirm'),
    );
    if (!confirmed || !mounted) return null;
    if (botBloc.captureWalletSession() != walletSession) {
      throw const _MakerOrderImportException(
        _MakerOrderImportFailure.botActive,
      );
    }
    final result = await botBloc.stopAndWait(
      walletSession: walletSession,
      expectedTradePairs: configuredPairs,
    );
    if (!result.isStopped || !mounted) {
      throw const _MakerOrderImportException(
        _MakerOrderImportFailure.botActive,
      );
    }
    _requireBotProvenStopped(walletSession);
    return walletSession;
  }

  void _requireBotProvenStopped(MarketMakerBotWalletSession walletSession) {
    final botBloc = context.read<MarketMakerBotBloc>();
    if (!botBloc.isConfigurationMutationSafe(walletSession)) {
      throw const _MakerOrderImportException(
        _MakerOrderImportFailure.botActive,
      );
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  String _readableError(Object error) {
    if (error case _MakerOrderImportException(:final failure)) {
      return switch (failure) {
        _MakerOrderImportFailure.empty => 'The selected file is empty.',
        _MakerOrderImportFailure.tooLarge => 'The selected file is too large.',
        _MakerOrderImportFailure.unsupportedFormat =>
          'The selected file format is not supported.',
        _MakerOrderImportFailure.missingConfigList =>
          'The maker order list is missing or ambiguous.',
        _MakerOrderImportFailure.tooManyConfigs =>
          'The file contains too many maker orders.',
        _MakerOrderImportFailure.invalidConfig =>
          'The file contains an invalid maker order.',
        _MakerOrderImportFailure.duplicateConfig =>
          'The file contains a duplicate maker order.',
        _MakerOrderImportFailure.disabledConfig =>
          'Imported maker orders must be enabled.',
        _MakerOrderImportFailure.botActive =>
          'Stop the market maker bot before importing orders.',
      };
    }
    // File-system and parser errors can contain local paths, payload excerpts,
    // endpoints or credentials. Do not surface their raw text.
    return LocaleKeys.somethingWrong.tr();
  }
}

class _EnableTradingBotSwitcher extends StatefulWidget {
  const _EnableTradingBotSwitcher();

  @override
  State<_EnableTradingBotSwitcher> createState() =>
      _EnableTradingBotSwitcherState();
}

class _EnableTradingBotSwitcherState extends State<_EnableTradingBotSwitcher> {
  bool _isUpdating = false;

  @override
  Widget build(BuildContext context) {
    final botIsUpdating = context.select<MarketMakerBotBloc, bool>(
      (bloc) => bloc.state.isUpdating,
    );
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, state) {
        final isBusy = _isUpdating || botIsUpdating;
        return Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            IgnorePointer(
              ignoring: isBusy,
              child: Opacity(
                opacity: isBusy ? 0.55 : 1,
                child: UiSwitcher(
                  key: const Key('enable-trading-bot-switcher'),
                  value: state.mmBotSettings.isMMBotEnabled,
                  onChanged: (value) {
                    unawaited(_onSwitcherChanged(value));
                  },
                ),
              ),
            ),
            const SizedBox(width: 15),
            Flexible(child: Text(LocaleKeys.enableTradingBot.tr())),
            if (isBusy) ...[
              const SizedBox(width: 8),
              const SizedBox(width: 16, height: 16, child: UiSpinner()),
            ],
          ],
        );
      },
    );
  }

  Future<void> _onSwitcherChanged(bool value) async {
    if (_isUpdating) return;
    final settingsBloc = context.read<SettingsBloc>();
    if (settingsBloc.state.mmBotSettings.isMMBotEnabled == value) return;

    setState(() => _isUpdating = true);
    try {
      if (value) {
        await settingsBloc.updateMarketMakerBotSettingsAndWait(
          (current) => current.copyWith(isMMBotEnabled: true),
        );
        return;
      }

      await _confirmStopAndDisable(settingsBloc);
    } on Object {
      _showMessage('marketMakerDisableFailed'.tr(), isError: true);
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _confirmStopAndDisable(SettingsBloc settingsBloc) async {
    final botBloc = context.read<MarketMakerBotBloc>();
    final walletSession = botBloc.captureWalletSession();
    if (walletSession == null) {
      _showMessage('marketMakerWalletChanged'.tr(), isError: true);
      return;
    }

    final configuredPairs = List<TradeCoinPairConfig>.unmodifiable(
      settingsBloc.state.mmBotSettings.tradeCoinPairConfigs,
    );
    final labels =
        configuredPairs
            .map((pair) => '${pair.baseCoinId}/${pair.relCoinId}')
            .toSet()
            .toList()
          ..sort();

    final confirmed = await showDexActionConfirmation(
      context: context,
      actionLabel: 'disableTradingBot'.tr(),
      targetDescription:
          '${'marketMakerAllConfiguredPairsTarget'.tr(namedArgs: {'count': '${configuredPairs.length}', 'pairs': labels.isEmpty ? '—' : labels.join(', ')})}\n\n'
          '${'marketMakerDisableImpact'.tr()}',
      confirmButtonKey: const Key('disable-trading-bot-confirm'),
    );
    if (!confirmed || !mounted) return;
    if (botBloc.captureWalletSession() != walletSession) {
      _showMessage('marketMakerWalletChanged'.tr(), isError: true);
      return;
    }

    if (!botBloc.isConfigurationMutationSafe(walletSession)) {
      final result = await botBloc.stopAndWait(
        walletSession: walletSession,
        expectedTradePairs: configuredPairs,
      );
      if (!mounted) return;
      if (!result.isStopped) {
        _showMessage(
          result.walletChanged
              ? 'marketMakerWalletChanged'.tr()
              : 'marketMakerDisableFailed'.tr(),
          isError: true,
        );
        return;
      }
    }
    final completed = await botBloc.runStoppedConfigurationMutation(
      walletSession: walletSession,
      mutation: (beforeWrite) {
        return settingsBloc.updateMarketMakerBotSettingsAndWait(
          (current) => current.copyWith(isMMBotEnabled: false),
          beforeWrite: beforeWrite,
        );
      },
    );
    if (!mounted) return;
    if (!completed) {
      _showMessage(
        botBloc.captureWalletSession() == walletSession
            ? 'marketMakerDisableFailed'.tr()
            : 'marketMakerWalletChanged'.tr(),
        isError: true,
      );
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }
}

class _SaveOrdersSwitcher extends StatefulWidget {
  const _SaveOrdersSwitcher();

  @override
  State<_SaveOrdersSwitcher> createState() => _SaveOrdersSwitcherState();
}

class _SaveOrdersSwitcherState extends State<_SaveOrdersSwitcher> {
  bool _isUpdating = false;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, state) => Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          UiSwitcher(
            key: const Key('save-orders-switcher'),
            value: state.mmBotSettings.saveOrdersBetweenLaunches,
            onChanged: _onSwitcherChanged,
          ),
          const SizedBox(width: 15),
          Flexible(child: Text('saveOrders'.tr())),
        ],
      ),
    );
  }

  Future<void> _onSwitcherChanged(bool value) async {
    final settingsBloc = context.read<SettingsBloc>();
    if (_isUpdating ||
        settingsBloc.state.mmBotSettings.saveOrdersBetweenLaunches == value) {
      return;
    }
    setState(() => _isUpdating = true);
    try {
      await settingsBloc.updateMarketMakerBotSettingsAndWait(
        (current) => current.copyWith(saveOrdersBetweenLaunches: value),
      );
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text('marketMakerSettingsSaveFailed'.tr()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }
}
