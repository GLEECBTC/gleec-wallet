import 'dart:convert';

import 'package:app_theme/app_theme.dart';
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
  const ImportSwaps({super.key});

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
    return UiBorderButton(
      width: 146,
      height: 32,
      borderWidth: 1,
      borderColor: theme.custom.specificButtonBorderColor,
      backgroundColor: theme.custom.specificButtonBackgroundColor,
      fontWeight: FontWeight.w500,
      text: LocaleKeys.importSwaps.tr(),
      suffix: Icon(
        _showData ? Icons.arrow_drop_up : Icons.arrow_drop_down,
        size: 14,
      ),
      onPressed: _inProgress
          ? null
          : () => setState(() => _showData = !_showData),
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
        UiLightButton(text: LocaleKeys.import.tr(), onPressed: _onImport),
        const SizedBox(width: 10),
      ],
    );
  }

  Widget _buildStatus() {
    if (!_success && _error == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Text(
        _error ?? (_success ? '${LocaleKeys.success.tr()}!' : ''),
        style: TextStyle(
          fontSize: 12,
          color: _success
              ? theme.custom.successColor
              : _error == null
              ? null
              : theme.currentGlobal.colorScheme.error,
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

    late final List<dynamic> swaps;
    try {
      swaps = _parseSwapImportPayload(_controller.text);
    } catch (e) {
      setState(() {
        _inProgress = false;
        _error = _formatImportError(e);
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

List<dynamic> _parseSwapImportPayload(String payload) {
  final dynamic decoded;
  try {
    decoded = jsonDecode(payload);
  } on FormatException catch (e) {
    throw FormatException('Invalid JSON: ${e.message}');
  }

  final List<dynamic>? swaps = _normalizeSwapImportPayload(decoded);
  if (swaps == null) {
    throw const FormatException(
      'Expected a swap list, a single swap object, {"swaps": [...]}, '
      '{"swap": {...}}, or {"result": {"swaps": [...]}}.',
    );
  }

  if (swaps.isEmpty) {
    throw const FormatException('The swap list is empty.');
  }

  if (swaps.any((dynamic swap) => swap is! Map)) {
    throw const FormatException('Each swap entry must be a JSON object.');
  }

  return swaps;
}

List<dynamic>? _normalizeSwapImportPayload(dynamic decoded) {
  if (decoded is List) return List<dynamic>.from(decoded);

  if (decoded is Map) {
    if (decoded.isEmpty) return null;

    if (decoded.containsKey('swap')) {
      final dynamic swap = decoded['swap'];
      return swap is Map ? <dynamic>[swap] : null;
    }

    if (decoded.containsKey('swaps')) {
      final dynamic swaps = decoded['swaps'];
      return swaps is List ? List<dynamic>.from(swaps) : null;
    }

    if (decoded.containsKey('result')) {
      final dynamic result = decoded['result'];
      if (result is Map) {
        final dynamic swaps = result['swaps'];
        if (swaps is List) return List<dynamic>.from(swaps);
      }

      return null;
    }

    return <dynamic>[decoded];
  }

  return null;
}

String _formatImportError(Object error) {
  return error is FormatException ? error.message : error.toString();
}
