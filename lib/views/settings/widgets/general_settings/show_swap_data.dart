import 'dart:convert';

import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/mm2/mm2_api/mm2_api.dart';
import 'package:web_dex/mm2/mm2_api/rpc/my_recent_swaps/my_recent_swaps_request.dart';
import 'package:web_dex/services/file_loader/file_loader.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';

/// This version of ShowSwapData keeps the foldable text output for viewing swap
/// data and adds an "Export swap data" button that downloads all swap data as
/// a JSON file.  A spinner indicates progress during export.
class ShowSwapData extends StatefulWidget {
  const ShowSwapData({Key? key}) : super(key: key);

  @override
  State<ShowSwapData> createState() => _ShowSwapDataState();
}

class _ShowSwapDataState extends State<ShowSwapData> {
  final TextEditingController _controller = TextEditingController();
  bool _showData = false;
  bool _inProgress = false;
  bool _isDownloading = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSwitcherButton(),
        if (_showData) ...{const SizedBox(height: 20), _buildData()},
        const SizedBox(height: 20),
        _buildExportButton(),
        const SizedBox(height: 20),
      ],
    );
  }

  /// Builds the button that shows or hides the raw swap data in a text field.
  Widget _buildSwitcherButton() {
    return UiBorderButton(
      width: 160,
      height: 32,
      borderWidth: 1,
      borderColor: theme.custom.specificButtonBorderColor,
      backgroundColor: theme.custom.specificButtonBackgroundColor,
      fontWeight: FontWeight.w500,
      text: LocaleKeys.showSwapData.tr(),
      suffix: Icon(
        _showData ? Icons.arrow_drop_up : Icons.arrow_drop_down,
        size: 14,
      ),
      onPressed: _inProgress
          ? null
          : () {
              if (_showData) {
                setState(() => _showData = false);
              } else {
                _getSwapData();
              }
            },
    );
  }

  /// Builds the editable text field and copy button that display the swap data.
  Widget _buildData() {
    return Row(
      mainAxisSize: MainAxisSize.max,
      children: [
        Flexible(
          child: TextField(
            controller: _controller,
            maxLines: 10,
            style: const TextStyle(fontSize: 12),
          ),
        ),
        const SizedBox(width: 10),
        Material(
          child: IconButton(
            onPressed: () => copyToClipBoard(context, _controller.text),
            icon: const Icon(Icons.copy),
          ),
        ),
        const SizedBox(width: 10),
      ],
    );
  }

  /// Builds the export button that downloads all swap data as a JSON file.
  Widget _buildExportButton() {
    return UiBorderButton(
      width: 160,
      height: 32,
      borderWidth: 1,
      borderColor: theme.custom.specificButtonBorderColor,
      backgroundColor: theme.custom.specificButtonBackgroundColor,
      fontWeight: FontWeight.w500,
      text: LocaleKeys.exportSwapData.tr(),
      icon: _isDownloading
          ? const UiSpinner()
          : Icon(
              Icons.file_download,
              color: Theme.of(context).textTheme.bodyMedium?.color,
              size: 18,
            ),
      onPressed: _isDownloading ? null : _exportSwapData,
    );
  }

  /// Fetches all raw swap data and writes it to a JSON file.
  ///
  /// Covers both swap kinds. `my_recent_swaps` knows nothing about routed
  /// swaps, so an export built from it alone arrives at support with the
  /// routed swap the ticket is about missing entirely.
  Future<void> _exportSwapData() async {
    setState(() => _isDownloading = true);
    try {
      final mm2Api = RepositoryProvider.of<Mm2Api>(context);
      final atomic = await mm2Api.getRawSwapData(MyRecentSwapsRequest());

      final bundle = <String, dynamic>{
        'exported_at': DateTime.now().toUtc().toIso8601String(),
        'atomic': jsonDecode(atomic),
        'routed': await _routedSwapData(),
      };

      // Use ISO timestamp so each file is unique and sorted chronologically.
      final fileName =
          'swap_data_${DateTime.now().toUtc().toIso8601String()}.json';
      await FileLoader.fromPlatform().save(
        fileName: fileName,
        data: jsonEncode(bundle),
        type: LoadFileType.text,
      );
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  /// Routed swaps for the export, or a recorded reason they are absent.
  ///
  /// A failure here must not lose the atomic half of the bundle, and it must
  /// not look like the user simply has no routed swaps — support would draw
  /// the wrong conclusion from an empty list.
  Future<Object> _routedSwapData() async {
    try {
      final sdk = RepositoryProvider.of<KomodoDefiSdk>(context);
      final entries = await sdk.routedSwaps.history(limit: 200);
      return [
        for (final entry in entries)
          {
            'uuid': entry.uuid,
            'phase': entry.phase.name,
            'raw_state': entry.rawState,
            'outcome': entry.receipt?.outcome.wire,
            'received_amount': entry.receipt?.amount.toString(),
            'received_token': entry.receipt?.tokenLabel,
            'failure': entry.failure?.kind.name,
            'failure_message': entry.failure?.message,
            'funds_untouched': entry.failure?.fundsUntouched,
            'approval_tx_hash': entry.approvalTxHash,
            'source_tx_hash': entry.sourceTxHash,
            'destination_tx_hash': entry.destinationTxHash,
            'explorer_url': entry.explorerUrl,
          },
      ];
    } on Object catch (error) {
      return {'unavailable': error.toString()};
    }
  }

  /// Retrieves the raw swap data from MM2 and displays it in the text field.
  Future<void> _getSwapData() async {
    setState(() => _inProgress = true);

    try {
      final mm2Api = RepositoryProvider.of<Mm2Api>(context);
      final response = await mm2Api.getRawSwapData(MyRecentSwapsRequest());
      final Map<String, dynamic> data = jsonDecode(response);
      _controller.text = jsonEncode(data['result']['swaps']).toString();
    } catch (e) {
      _controller.text = e.toString();
    }

    setState(() {
      _showData = true;
      _inProgress = false;
    });
  }
}
