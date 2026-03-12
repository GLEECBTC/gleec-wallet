import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:web_dex/mm2/rpc.dart';
import 'package:web_dex/platform/platform.dart';

class RPCWeb extends RPC {
  const RPCWeb();

  static final _log = Logger('RPCWeb');

  @override
  Future<dynamic> call(String reqStr) async {
    try {
      final dynamic response = await wasmRpc(reqStr);

      if (response == null) {
        throw Exception('Empty RPC response');
      }

      if (response is String) {
        final payload = response.trim();
        if (payload.isEmpty) {
          throw Exception('Empty RPC response');
        }

        try {
          return jsonDecode(payload);
        } catch (_) {
          return payload;
        }
      }

      return response;
    } catch (e, s) {
      _log.warning('Web RPC call failed', e, s);
      throw Exception(_userFacingMessage(e));
    }
  }

  String _userFacingMessage(Object error) {
    final normalized = error.toString().toLowerCase();
    if (normalized.contains('failed to fetch') ||
        normalized.contains('network') ||
        normalized.contains('timeout')) {
      return 'Network request failed. Please check your connection and retry.';
    }
    if (normalized.contains('wasm') ||
        normalized.contains('runtimeerror') ||
        normalized.contains('bindgen')) {
      return 'Wallet engine is still initializing. Please retry in a moment.';
    }
    return 'Unexpected wallet engine error. Please retry.';
  }
}
