import 'dart:convert';

import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/services/storage/base_storage.dart';
import 'package:web_dex/services/storage/get_storage.dart';

/// Per-wallet memory for the swap form: the last pair used, the assets
/// picked recently, and whether the pay picker hides assets without a
/// balance.
///
/// Opening on the pair someone last swapped removes a step, and a short
/// recents list is how the asset picker answers "the one I used yesterday".
class SwapPreferences {
  SwapPreferences({
    required Future<String?> Function() walletKey,
    BaseStorage? storage,
  }) : _walletKey = walletKey,
       _storage = storage ?? getStorage();

  static const _pairKey = 'swap_last_pair_v1';
  static const _recentKey = 'swap_recent_assets_v1';
  static const _hideZeroKey = 'swap_pay_hide_zero_v1';

  /// How many recent assets are kept.
  static const maxRecent = 8;

  final Future<String?> Function() _walletKey;
  final BaseStorage _storage;

  Future<String?> _key(String prefix) async {
    final wallet = await _walletKey();
    return wallet == null ? null : '$prefix:$wallet';
  }

  /// The last pair swapped, as tickers, or null.
  Future<({String from, String to})?> lastPair() async {
    final key = await _key(_pairKey);
    if (key == null) return null;
    try {
      final raw = await _storage.read(key);
      final json = raw is String ? jsonDecode(raw) : raw;
      if (json is! Map) return null;
      final from = json['from'];
      final to = json['to'];
      if (from is! String || to is! String) return null;
      return (from: from, to: to);
    } on Object {
      return null;
    }
  }

  /// Remembers [from] and [to] as the last pair.
  Future<void> rememberPair(AssetId from, AssetId to) async {
    final key = await _key(_pairKey);
    if (key == null) return;
    await _storage.write(key, jsonEncode({'from': from.id, 'to': to.id}));
  }

  /// Recently picked asset tickers, most recent first.
  Future<List<String>> recentAssets() async {
    final key = await _key(_recentKey);
    if (key == null) return const [];
    try {
      final raw = await _storage.read(key);
      final json = raw is String ? jsonDecode(raw) : raw;
      if (json is! List) return const [];
      return [
        for (final entry in json)
          if (entry is String) entry,
      ];
    } on Object {
      return const [];
    }
  }

  /// Puts [asset] at the front of the recents.
  Future<void> rememberAsset(AssetId asset) async {
    final key = await _key(_recentKey);
    if (key == null) return;
    final recent = [
      asset.id,
      for (final id in await recentAssets())
        if (id != asset.id) id,
    ].take(maxRecent).toList();
    await _storage.write(key, jsonEncode(recent));
  }

  /// Whether the pay picker hides assets without a balance. Off until
  /// someone turns it on.
  Future<bool> hideZeroBalances() async {
    final key = await _key(_hideZeroKey);
    if (key == null) return false;
    try {
      final raw = await _storage.read(key);
      return (raw is String ? jsonDecode(raw) : raw) == true;
    } on Object {
      return false;
    }
  }

  /// Remembers whether the pay picker hides assets without a balance.
  Future<void> rememberHideZeroBalances(bool hide) async {
    final key = await _key(_hideZeroKey);
    if (key == null) return;
    await _storage.write(key, jsonEncode(hide));
  }
}
