part of 'dex_counterparty.dart';

/// How many of KDF's latest lines [_KdfOutput] keeps for an early exit.
const _tailLength = 60;

/// A key that holds a secret, quoted the way JSON and Rust's debug output
/// quote one, escaped or not: `passphrase` and `rpc_password` in the config,
/// `userpass` in an RPC request.
final _secretKey = RegExp(
  r'''["'](passphrase|rpc_password|userpass)\\*["']\s*[:=]''',
  caseSensitive: false,
);

/// The last lines KDF printed on either stream, with the secrets taken out.
///
/// KDF writes a fatal startup error, and any panic, to stdout through its own
/// `log!` macro, and the `log` crate's lines to stderr, so explaining an exit
/// takes both.
class _KdfOutput {
  _KdfOutput(this._log, this._password, this._passphrase);

  final _Log _log;
  final String _password;
  final String _passphrase;
  final List<String> _tail = [];
  final List<Future<void>> _reads = [];
  var _lineCount = 0;

  /// Reads [bytes] to the end into the tail. With [forwardErrors], a line
  /// that mentions an error or a panic is also printed as it arrives.
  void capture(
    String name,
    Stream<List<int>> bytes, {
    bool forwardErrors = false,
  }) {
    final done = Completer<void>();
    _reads.add(done.future);
    bytes
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(
          (line) {
            final redacted = _redact(line);
            final lowered = line.toLowerCase();
            if (forwardErrors &&
                (lowered.contains('error') || lowered.contains('panic'))) {
              _log.line('kdf: $redacted');
            }
            _lineCount++;
            _tail.add('$name: $redacted');
            if (_tail.length > _tailLength) _tail.removeAt(0);
          },
          onError: (Object error) =>
              _log.line('could not read kdf $name: $error'),
          onDone: done.complete,
        );
  }

  /// Prints the tail once both streams have ended, or after two seconds.
  Future<void> printTail() async {
    // The exit code can arrive before the pipes are read to the end, and the
    // line that says why KDF exited is usually the last one.
    await Future.wait(
      _reads,
    ).timeout(const Duration(seconds: 2), onTimeout: () => const []);
    if (_tail.isEmpty) {
      _log.line('kdf printed nothing');
      return;
    }
    _log.line(
      'last ${_tail.length} of $_lineCount lines kdf printed, '
      'secrets redacted:',
    );
    for (final line in _tail) {
      _log.line('  $line');
    }
  }

  /// [line] with both secrets replaced, or withheld whole if it carries the
  /// config.
  ///
  /// KDF does not print its config today: its parser drops serde's error
  /// rather than quote the input, and clap echoes an argument only to reject
  /// it. A dump would name a secret's key even where the value is escaped or
  /// cut short, so the key is what gets matched.
  String _redact(String line) {
    if (_secretKey.hasMatch(line)) return '<withheld: it carries the config>';

    return line
        .replaceAll(_password, '<rpc-password>')
        .replaceAll(_passphrase, '<passphrase>');
  }
}

/// KDF exited before its RPC answered, so waiting longer cannot help.
class _KdfExited implements Exception {
  const _KdfExited(this.code);

  final int code;

  @override
  String toString() => 'KDF exited with code $code before its RPC answered';
}
