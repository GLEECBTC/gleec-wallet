import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart' show SecretKey;
import 'package:cryptography/dart.dart' show DartArgon2id;
import 'package:flutter/foundation.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart'
    show DerivationMethod;
import 'package:pointycastle/export.dart'
    show
        AEADParameters,
        AESEngine,
        GCMBlockCipher,
        InvalidCipherTextException,
        KeyParameter;
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/services/wallet_file/legacy_wallet_file.dart';
import 'package:web_dex/services/wallet_file/wallet_file_format.dart';

export 'package:web_dex/services/wallet_file/wallet_file_format.dart'
    show
        WalletFileException,
        WalletFileFailure,
        WalletFileInspection,
        WalletFileKind;

/// A file's wallet with its recovery phrase in plain text.
class OpenedWalletFile {
  const OpenedWalletFile({required this.config, required this.recordedType});

  /// For a legacy file, [WalletConfig.type] is whatever the file said and is
  /// not to be trusted: the caller replaces it with the user's choice.
  final WalletConfig config;

  /// The authenticated wallet type, or null for a legacy file.
  final WalletType? recordedType;
}

/// Writes version 2 wallet files and reads every version.
class WalletFileCodec {
  const WalletFileCodec();

  /// Protects [mnemonic] and [config] with [password], recording how the
  /// wallet's addresses are derived.
  Future<String> seal({
    required String password,
    required String mnemonic,
    required WalletConfig config,
    required DerivationMethod derivation,
  }) async {
    if (mnemonic.isEmpty) throw ArgumentError('No recovery phrase to seal');
    final header = WalletFileHeader(
      walletType: derivation == DerivationMethod.hdWallet
          ? WalletType.hdwallet
          : WalletType.iguana,
      kdf: WalletFileKdf(_random(WalletFileKdf.saltLength)),
      nonce: _random(WalletFileHeader.nonceLength),
    );
    // The type lives in the authenticated header alone.
    final payload = config.copyWith(seedPhrase: mnemonic).toJson()
      ..remove('type');
    final plaintext = utf8.encode(jsonEncode(payload));
    try {
      final ciphertext = await compute(_seal, (
        password: password,
        header: header,
        input: plaintext,
      ));
      return WalletFileDocument(header, ciphertext).encode();
    } finally {
      plaintext.fillRange(0, plaintext.length, 0);
    }
  }

  /// Opens a file of any version with [password].
  ///
  /// Throws a [WalletFileException].
  Future<OpenedWalletFile> open({
    required String password,
    required String content,
  }) async {
    final inspection = WalletFileInspection.of(content);
    switch (inspection.kind) {
      case WalletFileKind.current:
        return _openCurrent(password, inspection.document!);
      case WalletFileKind.newer:
        throw const WalletFileException(WalletFileFailure.newer);
      case WalletFileKind.damaged:
        throw const WalletFileException(WalletFileFailure.damaged);
      case WalletFileKind.legacy:
      case WalletFileKind.unrecognized:
        return OpenedWalletFile(
          config: await openLegacyWalletFile(password, content),
          recordedType: null,
        );
    }
  }

  Future<OpenedWalletFile> _openCurrent(
    String password,
    WalletFileDocument document,
  ) async {
    final plaintext = await compute(_open, (
      password: password,
      header: document.header,
      input: document.ciphertext,
    ));
    if (plaintext == null) {
      throw const WalletFileException(WalletFileFailure.cannotOpen);
    }
    final WalletConfig config;
    try {
      config = WalletConfig.fromJson(
        jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>,
      )..type = document.header.walletType;
    } catch (_) {
      // Authenticated, so written by something holding the password, but
      // not by this format's writer.
      throw const WalletFileException(WalletFileFailure.damaged);
    } finally {
      plaintext.fillRange(0, plaintext.length, 0);
    }
    if (config.seedPhrase.isEmpty) {
      throw const WalletFileException(WalletFileFailure.damaged);
    }
    return OpenedWalletFile(
      config: config,
      recordedType: document.header.walletType,
    );
  }
}

typedef _CipherJob = ({
  String password,
  WalletFileHeader header,
  Uint8List input,
});

Future<Uint8List> _seal(_CipherJob job) =>
    _withKey(job, (key) => _gcm(true, key, job));

Future<Uint8List?> _open(_CipherJob job) => _withKey(job, (key) {
  try {
    return _gcm(false, key, job);
  } on InvalidCipherTextException {
    return null;
  }
});

Future<T> _withKey<T>(_CipherJob job, T Function(Uint8List key) use) async {
  final key = await deriveWalletFileKey(job.password, job.header.kdf);
  try {
    return use(key);
  } finally {
    key.fillRange(0, key.length, 0);
  }
}

Uint8List _gcm(bool encrypt, Uint8List key, _CipherJob job) =>
    (GCMBlockCipher(AESEngine())..init(
          encrypt,
          AEADParameters(
            KeyParameter(key),
            WalletFileHeader.tagLength * 8,
            job.header.nonce,
            job.header.associatedData,
          ),
        ))
        .process(job.input);

/// Blocks of Argon2id memory filled between yields on the web, where the work
/// shares the UI thread. Each yield costs a clamped 4 ms timer, so smaller
/// chunks waste time on fast machines and larger ones stutter on slow ones.
/// At 1,024 a 64 MiB derivation measured 1.4 s with no dropped frame in
/// desktop Chrome, and about 6 s with a worst frame gap under 100 ms at six
/// times CPU throttling.
const _webBlocksPerYield = 1024;

/// The AES-256 key from [password]'s UTF-8 bytes, unnormalised as the engine
/// treats wallet passwords.
Future<Uint8List> deriveWalletFileKey(
  String password,
  WalletFileKdf kdf,
) async {
  final passwordBytes = utf8.encode(password);
  try {
    final key = await DartArgon2id(
      parallelism: WalletFileKdf.parallelism,
      memory: WalletFileKdf.memoryKib,
      iterations: WalletFileKdf.iterations,
      hashLength: WalletFileKdf.keyLength,
      // Native callers already run in a background isolate; the library
      // would otherwise start another one for each derivation.
      maxIsolates: 0,
      blocksPerProcessingChunk: kIsWeb ? _webBlocksPerYield : 0,
    ).deriveKey(secretKey: SecretKey(passwordBytes), nonce: kdf.salt);
    return Uint8List.fromList(await key.extractBytes());
  } finally {
    passwordBytes.fillRange(0, passwordBytes.length, 0);
  }
}

Uint8List _random(int length) {
  final random = Random.secure();
  return Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));
}
