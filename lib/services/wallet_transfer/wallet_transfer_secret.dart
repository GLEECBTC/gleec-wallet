import 'dart:convert';
import 'dart:typed_data';

import 'package:web_dex/model/wallet.dart';

/// How a wallet derives its addresses. Restoring a seed with the other type
/// opens a different wallet, so the type always travels with the seed.
enum TransferWalletType {
  hd('hd'),
  legacy('legacy');

  const TransferWalletType(this.wire);

  final String wire;

  /// Null for wallets without a seed of their own (hardware, extensions).
  static TransferWalletType? fromWalletType(WalletType type) => switch (type) {
    WalletType.hdwallet => TransferWalletType.hd,
    WalletType.iguana => TransferWalletType.legacy,
    _ => null,
  };

  WalletType get walletType =>
      this == hd ? WalletType.hdwallet : WalletType.iguana;
}

/// Everything another device needs to open the same wallet. It only ever
/// exists in memory or sealed; never log, persist or display it.
final class WalletTransferSecret {
  WalletTransferSecret({
    required this.walletName,
    required this.type,
    required this.seed,
    required this.phraseConfirmed,
  }) {
    if (walletName.isEmpty ||
        walletName.length > maxNameLength ||
        seed.isEmpty ||
        utf8.encode(seed).length > maxSeedBytes ||
        encode().length > maxEncodedBytes) {
      throw const FormatException('Invalid wallet transfer secret');
    }
  }

  static const version = 1;
  static const maxNameLength = 64;
  static const maxSeedBytes = 1024;

  /// Exactly what one move QR code holds once sealed, so every valid secret
  /// can move. A 24-word phrase encodes to about 300 bytes; only a long
  /// legacy seed of escaped characters exceeds this, and that wallet moves
  /// by its phrase instead.
  static const maxEncodedBytes = 1448;
  static const _keys = {'v', 'name', 'type', 'seed', 'phraseConfirmed'};

  /// The name the wallet had. The receiving device may need another one.
  final String walletName;
  final TransferWalletType type;

  /// The exact phrase, unnormalised: legacy seeds need every byte as typed.
  final String seed;

  /// Whether the user confirmed holding the phrase. A statement about the
  /// person, so it moves with the wallet.
  final bool phraseConfirmed;

  Uint8List encode() => utf8.encode(
    jsonEncode({
      'v': version,
      'name': walletName,
      'type': type.wire,
      'seed': seed,
      'phraseConfirmed': phraseConfirmed,
    }),
  );

  /// Strict: unknown keys, versions or types are rejected, never ignored.
  static WalletTransferSecret decode(List<int> bytes) {
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw const FormatException('Invalid wallet transfer secret');
    }
    if (json is! Map<String, Object?> ||
        json.length != _keys.length ||
        !json.keys.every(_keys.contains) ||
        json['v'] is! int ||
        json['v'] != version) {
      throw const FormatException('Invalid wallet transfer secret');
    }
    final name = json['name'];
    final wire = json['type'];
    final seed = json['seed'];
    final confirmed = json['phraseConfirmed'];
    final type = TransferWalletType.values
        .where((value) => value.wire == wire)
        .firstOrNull;
    if (name is! String || seed is! String || confirmed is! bool) {
      throw const FormatException('Invalid wallet transfer secret');
    }
    if (type == null) {
      throw const FormatException('Invalid wallet transfer secret');
    }
    final secret = WalletTransferSecret(
      walletName: name,
      type: type,
      seed: seed,
      phraseConfirmed: confirmed,
    );
    // Only the exact encoding this class writes: no duplicate keys, other
    // number forms, whitespace or byte-order mark.
    final canonical = secret.encode();
    var diff = canonical.length ^ bytes.length;
    for (var i = 0; i < canonical.length && i < bytes.length; i++) {
      diff |= canonical[i] ^ bytes[i];
    }
    if (diff != 0) {
      throw const FormatException('Invalid wallet transfer secret');
    }
    return secret;
  }

  @override
  String toString() => 'WalletTransferSecret(${type.wire}, <redacted>)';
}
