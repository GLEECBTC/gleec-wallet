import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/mm2/mm2_api/mm2_api.dart';
import 'package:web_dex/mm2/mm2_api/rpc/import_swaps/import_swaps_request.dart';

import 'package:web_dex/shared/ui/ui_light_button.dart';
import 'package:web_dex/shared/utils/debug_utils.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';

class ImportSwaps extends StatefulWidget {
  const ImportSwaps({Key? key}) : super(key: key);

  @override
  State<ImportSwaps> createState() => _ImportSwapsState();
}

class _ImportSwapsState extends State<ImportSwaps> {
  @override
  void initState() {
    _preloadFromDebugData();

    super.initState();
  }

  final TextEditingController _controller = TextEditingController();
  bool _success = false;
  String? _error;
  bool _showData = false;
  bool _inProgress = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSwitcher(),
        if (_showData) ...{
          const SizedBox(height: 20),
          _buildStatus(),
          _buildData(),
        },
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildSwitcher() {
    final palette = AppPalette.of(context);
    return UiBorderButton(
      width: 146,
      height: 32,
      borderWidth: 1,
      borderColor: palette.border,
      backgroundColor: palette.surfaceHigh,
      fontWeight: FontWeight.w500,
      text: LocaleKeys.importSwaps.tr(),
      suffix: Icon(
        _showData ? Icons.arrow_drop_up : Icons.arrow_drop_down,
        size: 14,
      ),
      onPressed:
          _inProgress ? null : () => setState(() => _showData = !_showData),
    );
  }

  Widget _buildData() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: TextField(
            controller: _controller,
            maxLines: 10,
            style: const TextStyle(fontSize: 12),
          ),
        ),
        const SizedBox(height: 10),
        UiLightButton(
          text: LocaleKeys.import.tr(),
          onPressed: _onImport,
        ),
        const SizedBox(width: 10),
      ],
    );
  }

  Widget _buildStatus() {
    if (!_success && _error == null) return const SizedBox.shrink();

    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Text(
        _error ?? (_success ? '${LocaleKeys.success.tr()}!' : ''),
        style: TextStyle(
          fontSize: 12,
          color: _success
              ? palette.success
              : _error == null
              ? null
              : palette.danger,
        ),
      ),
    );
  }

  Future<void> _preloadFromDebugData() async {
    if (!kDebugMode) return;

    setState(() {
      _inProgress = true;
    });

    final data = await loadDebugSwaps();
    if (data != null) {
      _controller.text = jsonEncode(data);
    }

    setState(() {
      _inProgress = false;
    });
  }

  Future<void> _onImport() async {
    setState(() {
      _inProgress = true;
      _error = null;
      _success = false;
    });

    List<dynamic>? swaps;
    try {
      swaps = jsonDecode(_controller.text) as List;
      if (swaps.isEmpty) throw Exception('The list is empty');
    } catch (e) {
      setState(() {
        _inProgress = false;
        _error = e.toString();
      });
      return;
    }

    try {
      final mm2Api = RepositoryProvider.of<Mm2Api>(context);
      final ImportSwapsRequest request = ImportSwapsRequest(swaps: swaps);
      await mm2Api.importSwaps(request);
    } catch (e) {
      setState(() {
        _inProgress = false;
        _error = e.toString();
      });
      return;
    }

    _controller.clear();
    setState(() {
      _inProgress = false;
      _success = true;
    });
  }
}
