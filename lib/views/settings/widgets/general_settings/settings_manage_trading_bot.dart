import 'dart:async';
import 'dart:convert';

import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/market_maker_bot/market_maker_bot/market_maker_bot_bloc.dart';
import 'package:web_dex/bloc/settings/settings_bloc.dart';
import 'package:web_dex/bloc/settings/settings_event.dart';
import 'package:web_dex/bloc/settings/settings_repository.dart';
import 'package:web_dex/bloc/settings/settings_state.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/mm2/mm2_api/rpc/market_maker_bot/trade_coin_pair_config.dart';
import 'package:web_dex/services/file_loader/file_loader.dart';
import 'package:web_dex/views/settings/widgets/common/settings_section.dart';

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
          _EnableTradingBotSwitcher(settingsRepository: _settingsRepository),
          const SizedBox(height: 14),
          _SaveOrdersSwitcher(settingsRepository: _settingsRepository),
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
    setState(() => _isImporting = true);

    try {
      await FileLoader.fromPlatform().upload(
        fileType: LoadFileType.text,
        onUpload: (_, content) {
          unawaited(_applyImportedOrders(content));
        },
        onError: (error) {
          _showMessage(
            'makerOrdersImportFailed'.tr(args: [error]),
            isError: true,
          );
          if (mounted) {
            setState(() => _isImporting = false);
          }
        },
      );
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
      final content = rawContent?.trim() ?? '';
      if (content.isEmpty) {
        throw const FormatException('File is empty');
      }

      final importedConfigs = _decodeTradePairConfigs(content);
      final stored = await _settingsRepository.loadSettings();
      final updatedMmSettings = stored.marketMakerBotSettings.copyWith(
        tradeCoinPairConfigs: importedConfigs,
      );

      await _settingsRepository.updateSettings(
        stored.copyWith(marketMakerBotSettings: updatedMmSettings),
      );

      if (!mounted) return;
      context.read<SettingsBloc>().add(
        MarketMakerBotSettingsChanged(updatedMmSettings),
      );
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
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  List<TradeCoinPairConfig> _decodeTradePairConfigs(String jsonPayload) {
    final decoded = jsonDecode(jsonPayload);
    final dynamic rawConfigs;
    if (decoded is List) {
      rawConfigs = decoded;
    } else if (decoded is Map<String, dynamic>) {
      rawConfigs =
          decoded['trade_coin_pair_configs'] ??
          decoded['tradeCoinPairConfigs'] ??
          decoded['orders'];
    } else {
      throw const FormatException('Unsupported file format');
    }

    if (rawConfigs is! List) {
      throw const FormatException('Missing maker order configuration list');
    }

    final dedupedByName = <String, TradeCoinPairConfig>{};
    for (final item in rawConfigs) {
      if (item is! Map) {
        continue;
      }

      try {
        final config = TradeCoinPairConfig.fromJson(
          Map<String, dynamic>.from(item),
        );
        dedupedByName[config.name] = config;
      } catch (_) {
        // Skip malformed entries and continue parsing.
      }
    }

    if (dedupedByName.isEmpty) {
      throw const FormatException('No valid maker order configurations found');
    }

    return dedupedByName.values.toList();
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
    final value = error.toString().trim();
    if (value.startsWith('Exception: ')) {
      return value.replaceFirst('Exception: ', '').trim();
    }
    return value.isEmpty ? LocaleKeys.somethingWrong.tr() : value;
  }
}

class _EnableTradingBotSwitcher extends StatelessWidget {
  const _EnableTradingBotSwitcher({required this.settingsRepository});

  final SettingsRepository settingsRepository;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, state) => Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          UiSwitcher(
            key: const Key('enable-trading-bot-switcher'),
            value: state.mmBotSettings.isMMBotEnabled,
            onChanged: (value) => _onSwitcherChanged(context, value),
          ),
          const SizedBox(width: 15),
          Flexible(child: Text(LocaleKeys.enableTradingBot.tr())),
        ],
      ),
    );
  }

  Future<void> _onSwitcherChanged(BuildContext context, bool value) async {
    final stored = await settingsRepository.loadSettings();
    final settings = stored.marketMakerBotSettings.copyWith(
      isMMBotEnabled: value,
    );

    if (!context.mounted) return;
    context.read<SettingsBloc>().add(MarketMakerBotSettingsChanged(settings));

    if (!value) {
      context.read<MarketMakerBotBloc>().add(
        const MarketMakerBotStopRequested(),
      );
    }
  }
}

class _SaveOrdersSwitcher extends StatelessWidget {
  const _SaveOrdersSwitcher({required this.settingsRepository});

  final SettingsRepository settingsRepository;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, state) => Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          UiSwitcher(
            key: const Key('save-orders-switcher'),
            value: state.mmBotSettings.saveOrdersBetweenLaunches,
            onChanged: (value) => _onSwitcherChanged(context, value),
          ),
          const SizedBox(width: 15),
          Flexible(child: Text('saveOrders'.tr())),
        ],
      ),
    );
  }

  Future<void> _onSwitcherChanged(BuildContext context, bool value) async {
    final stored = await settingsRepository.loadSettings();
    final settings = stored.marketMakerBotSettings.copyWith(
      saveOrdersBetweenLaunches: value,
    );

    if (!context.mounted) return;
    context.read<SettingsBloc>().add(MarketMakerBotSettingsChanged(settings));
  }
}
