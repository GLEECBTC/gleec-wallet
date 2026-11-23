import 'dart:convert';
import 'dart:typed_data';

import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart'
    show DerivationMethod;
import 'package:web_dex/model/wallet.dart' show WalletType;

/// A version 2 file is JSON whose header, every field but `ciphertext`, is
/// the AES-256-GCM associated data.
const walletFileFormatName = 'gleec-wallet-file';
const walletFileFormatVersion = 2;

/// What a wallet file is, as far as can be told before its password.
enum WalletFileKind {
  /// Version 2: authenticated, with the wallet type in its header.
  current,

  /// An older format.
  legacy,

  /// A later version of the current format.
  newer,

  /// Claims to be the current format but is not valid.
  damaged,

  /// No known shape. The legacy reader still tries it.
  unrecognized,
}

enum WalletFileFailure {
  /// A wrong password or a changed file: authenticated encryption cannot
  /// tell the two apart.
  cannotOpen,

  /// The file is not valid, whatever the password.
  damaged,
  newer,
}

class WalletFileException implements Exception {
  const WalletFileException(this.failure);

  final WalletFileFailure failure;

  @override
  String toString() => 'WalletFileException(${failure.name})';
}

/// The Argon2id parameters of a version 2 file: the engine's own parameters
/// for the mnemonic it stores, so a guess costs the same against either.
///
/// A reader accepts exactly these. Other values take a new format version, so
/// an older reader calls such a file newer rather than damaged, and a crafted
/// file cannot ask for more memory or time.
class WalletFileKdf {
  WalletFileKdf(this.salt);

  static const algorithm = 'argon2id';
  static const argon2Version = 0x13;
  static const memoryKib = 65536;
  static const iterations = 2;
  static const parallelism = 1;
  static const saltLength = 16;
  static const keyLength = 32;

  final Uint8List salt;
}

const _derivations = {
  WalletType.hdwallet: DerivationMethod.hdWallet,
  WalletType.iguana: DerivationMethod.iguana,
};

/// The authenticated part of a version 2 file.
class WalletFileHeader {
  WalletFileHeader({
    required this.walletType,
    required this.kdf,
    required this.nonce,
  }) : assert(_derivations.containsKey(walletType));

  factory WalletFileHeader.fromJson(Map<String, Object?> json) {
    _fields(json, const [..._headerKeys, 'ciphertext']);
    _expect(json['format'], walletFileFormatName, 'format');
    _expect(json['version'], walletFileFormatVersion, 'version');

    final wallet = _fields(json['wallet'], const ['type', 'derivation']);
    final walletType = _derivations.keys.where(
      (type) => type.name == wallet['type'],
    );
    if (walletType.isEmpty) {
      throw const FormatException('Unsupported wallet type');
    }
    _expect(
      wallet['derivation'],
      _derivations[walletType.single].toString(),
      'derivation',
    );

    final kdf = _fields(json['kdf'], const [
      'algorithm',
      'version',
      'memory_kib',
      'iterations',
      'parallelism',
      'salt',
    ]);
    _expect(kdf['algorithm'], WalletFileKdf.algorithm, 'kdf algorithm');
    _expect(kdf['version'], WalletFileKdf.argon2Version, 'kdf version');
    _expect(kdf['memory_kib'], WalletFileKdf.memoryKib, 'kdf memory');
    _expect(kdf['iterations'], WalletFileKdf.iterations, 'kdf iterations');
    _expect(kdf['parallelism'], WalletFileKdf.parallelism, 'kdf parallelism');

    final cipher = _fields(json['cipher'], const ['algorithm', 'nonce']);
    _expect(cipher['algorithm'], cipherAlgorithm, 'cipher algorithm');

    return WalletFileHeader(
      walletType: walletType.single,
      kdf: WalletFileKdf(
        _bytes(
          kdf,
          'salt',
          min: WalletFileKdf.saltLength,
          max: WalletFileKdf.saltLength,
        ),
      ),
      nonce: _bytes(cipher, 'nonce', min: nonceLength, max: nonceLength),
    );
  }

  static const cipherAlgorithm = 'aes-256-gcm';
  static const nonceLength = 12;
  static const tagLength = 16;

  final WalletType walletType;
  final WalletFileKdf kdf;
  final Uint8List nonce;

  /// [walletType] in the engine's vocabulary: how it derives the addresses.
  DerivationMethod get derivation => _derivations[walletType]!;

  Map<String, Object> toJson() => {
    'format': walletFileFormatName,
    'version': walletFileFormatVersion,
    'wallet': {'type': walletType.name, 'derivation': derivation.toString()},
    'kdf': {
      'algorithm': WalletFileKdf.algorithm,
      'version': WalletFileKdf.argon2Version,
      'memory_kib': WalletFileKdf.memoryKib,
      'iterations': WalletFileKdf.iterations,
      'parallelism': WalletFileKdf.parallelism,
      'salt': base64Encode(kdf.salt),
    },
    'cipher': {'algorithm': cipherAlgorithm, 'nonce': base64Encode(nonce)},
  };

  /// The header in canonical form. A reader rebuilds it from the validated
  /// values rather than from the file's text, so spacing and key order in the
  /// file do not matter, and every value does.
  Uint8List get associatedData => utf8.encode(jsonEncode(toJson()));
}

const _headerKeys = ['format', 'version', 'wallet', 'kdf', 'cipher'];
const _currentOnlyKeys = ['wallet', 'kdf', 'cipher', 'ciphertext'];

/// A version 2 file: its header and the GCM output, tag last.
class WalletFileDocument {
  const WalletFileDocument(this.header, this.ciphertext);

  factory WalletFileDocument.fromJson(Map<String, Object?> json) =>
      WalletFileDocument(
        WalletFileHeader.fromJson(json),
        _bytes(
          json,
          'ciphertext',
          min: WalletFileHeader.tagLength + 1,
          max: _maxCiphertextLength,
        ),
      );

  final WalletFileHeader header;
  final Uint8List ciphertext;

  String encode() => const JsonEncoder.withIndent('  ')
      .convert({...header.toJson(), 'ciphertext': base64Encode(ciphertext)});
}

// A wallet config is a few kilobytes even with hundreds of activated coins;
// this only bounds the work a crafted file can cause on the web's UI thread.
const _maxCiphertextLength = 64 * 1024;

/// Classifies a file without its password.
class WalletFileInspection {
  const WalletFileInspection._(this.kind, [this.document]);

  factory WalletFileInspection.of(String content) {
    final text = normalizeWalletFileText(content);
    // A truncated, re-wrapped or retyped copy of a current file. Read as
    // legacy, it would ask for a wallet type and then blame the password.
    const damaged = WalletFileInspection._(WalletFileKind.damaged);
    final named = text.contains(walletFileFormatName);
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      if (named) return damaged;
      return WalletFileInspection._(
        _legacyBase64.hasMatch(text) && text.length % 4 == 0
            ? WalletFileKind.legacy
            : WalletFileKind.unrecognized,
      );
    }
    if (json is! Map<String, Object?>) {
      return named
          ? damaged
          : const WalletFileInspection._(WalletFileKind.unrecognized);
    }
    if (json['format'] != walletFileFormatName) {
      if (_isLegacyJson(json)) {
        return const WalletFileInspection._(WalletFileKind.legacy);
      }
      return named || _currentOnlyKeys.any(json.containsKey)
          ? damaged
          : const WalletFileInspection._(WalletFileKind.unrecognized);
    }
    final version = json['version'];
    if (version is int && version > walletFileFormatVersion) {
      return const WalletFileInspection._(WalletFileKind.newer);
    }
    try {
      return WalletFileInspection._(
        WalletFileKind.current,
        WalletFileDocument.fromJson(json),
      );
    } on FormatException {
      return const WalletFileInspection._(WalletFileKind.damaged);
    }
  }

  final WalletFileKind kind;

  /// Set only for [WalletFileKind.current].
  final WalletFileDocument? document;

  /// The type the file will restore, or null when the user has to choose.
  WalletType? get recordedType => document?.header.walletType;
}

/// Removes what editors and transfers add around a file's text: a byte-order
/// mark and surrounding whitespace.
String normalizeWalletFileText(String content) =>
    (content.startsWith('\uFEFF') ? content.substring(1) : content).trim();

// The oldest files are bare base64 of at least one AES block.
final _legacyBase64 = RegExp(r'^[A-Za-z0-9+/]{22,}={0,2}$');

bool _isLegacyJson(Map<String, Object?> json) =>
    json.length == 3 && ['0', '1', '2'].every((key) => json[key] is String);

Map<String, Object?> _fields(Object? value, List<String> keys) {
  if (value is! Map<String, Object?> ||
      value.length != keys.length ||
      !keys.every(value.containsKey)) {
    throw const FormatException('Unexpected wallet file fields');
  }
  return value;
}

void _expect(Object? actual, Object expected, String name) {
  if (actual != expected) throw FormatException('Unsupported $name');
}

Uint8List _bytes(
  Map<String, Object?> fields,
  String key, {
  required int min,
  required int max,
}) {
  final text = fields[key];
  if (text is! String) throw FormatException('$key is not text');
  final Uint8List bytes;
  try {
    bytes = base64Decode(text);
  } on FormatException {
    throw FormatException('$key is not base64');
  }
  // One spelling per value: the decoder also takes the URL-safe alphabet.
  if (base64Encode(bytes) != text || bytes.length < min || bytes.length > max) {
    throw FormatException('$key is not valid');
  }
  return bytes;
}
