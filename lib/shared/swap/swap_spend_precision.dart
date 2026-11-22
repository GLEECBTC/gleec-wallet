import 'dart:async';

import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

typedef _TokenIdentity = ({
  AssetId asset,
  String protocol,
  String platform,
  String contract,
});

/// Resolves the precision needed to turn dollars into an executable amount.
/// Token precision is contract metadata, never the network coin's precision.
class SwapSpendPrecision {
  SwapSpendPrecision({
    required this.assetOf,
    required this.tokenDecimals,
    this.timeout = const Duration(seconds: 10),
  });

  final Asset? Function(AssetId) assetOf;
  final Future<int> Function({
    required String protocolType,
    required String platform,
    required String contractAddress,
  })
  tokenDecimals;
  final Duration timeout;
  final Map<_TokenIdentity, int> _known = {};
  final Map<_TokenIdentity, Future<int?>> _pending = {};
  Object _session = Object();

  Future<int?> decimalsOf(AssetId id, {bool allowLookup = true}) async {
    if (_valid(id.chainId.decimals)) return id.chainId.decimals;
    try {
      final asset = assetOf(id);
      if (asset == null) return null;
      final config = asset.protocol.config;
      final protocol = config.valueOrNull<JsonMap>('protocol');
      final data = protocol?.valueOrNull<JsonMap>('protocol_data');
      final configured =
          config.valueOrNull<int>('decimals') ??
          data?.valueOrNull<int>('decimals');
      if (_valid(configured)) return configured;
      final type = protocol?.valueOrNull<String>('type');
      // These are the native protocols' base units, not token fallbacks.
      if (id.parentId == null) {
        if (type == 'ETH') return 18;
        if (type == 'UTXO' || type == 'ZHTLC' || type == 'QTUM') return 8;
      }
      final platform = data?.valueOrNull<String>('platform');
      final contract = data?.valueOrNull<String>('contract_address');
      if (type == null ||
          type.isEmpty ||
          platform == null ||
          platform.isEmpty ||
          contract == null ||
          contract.isEmpty ||
          (id.parentId != null && id.parentId!.id != platform)) {
        return null;
      }
      final key = (
        asset: id,
        protocol: type,
        platform: platform,
        contract: contract,
      );
      final cached = _known[key];
      if (cached != null) return cached;
      if (!allowLookup) return null;
      final pending = _pending[key];
      if (pending != null) return await pending;
      final session = _session;
      final read = _read(key, session);
      _pending[key] = read;
      return await read;
    } on Object {
      return null;
    }
  }

  Future<int?> _read(_TokenIdentity key, Object session) async {
    try {
      final decimals = await Future<int>.sync(
        () => tokenDecimals(
          protocolType: key.protocol,
          platform: key.platform,
          contractAddress: key.contract,
        ),
      ).timeout(timeout);
      if (session != _session || !_valid(decimals)) return null;
      _known[key] = decimals;
      return decimals;
    } on Object {
      return null;
    } finally {
      // An older wallet's answer must not remove a newer in-flight read.
      if (session == _session) _pending.remove(key);
    }
  }

  void reset() {
    _session = Object();
    _known.clear();
    _pending.clear();
  }

  static bool _valid(int? value) => value != null && value >= 0 && value <= 255;
}
