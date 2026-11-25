import 'dart:async';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';

enum SecurityKeyStage {
  insert,
  noAccess,

  /// The key must be removed and inserted again: it allows no more PIN tries
  /// until then, or it stopped answering.
  reinsert,

  /// Several keys are inserted; the user touches the one to use.
  chooseKey,
  enterPin,
  touch,
  timedOut,

  /// The key holds several Gleec Wallet passkeys.
  chooseAccount,
}

class SecurityKeyAccount extends Equatable {
  const SecurityKeyAccount({required this.usable, this.displayName, this.name});

  final String? displayName;
  final String? name;

  /// False for a passkey the key evaluated no PRF for.
  final bool usable;

  @override
  List<Object?> get props => [displayName, name, usable];
}

/// What the security-key sheet shows. It never holds a PIN.
class SecurityKeyPrompt extends Equatable {
  const SecurityKeyPrompt(
    this.stage, {
    this.product,
    this.retriesLeft,
    this.wrongPin = false,
    this.accounts = const [],
  });

  final SecurityKeyStage stage;
  final String? product;
  final int? retriesLeft;
  final bool wrongPin;
  final List<SecurityKeyAccount> accounts;

  @override
  List<Object?> get props => [stage, product, retriesLeft, wrongPin, accounts];
}

/// Connects the Linux security-key authenticator to the sheet drawn above
/// the app, its lock cover included. One request at a time. A PIN passes
/// through [answerPin] once and is not kept here.
class SecurityKeyPrompts {
  static final instance = SecurityKeyPrompts();

  final _changes = StreamController<SecurityKeyPrompt?>.broadcast();
  final _cancellations = StreamController<void>.broadcast(sync: true);
  SecurityKeyPrompt? _current;
  Completer<Object?>? _reply;
  int _hosts = 0;

  SecurityKeyPrompt? get current => _current;
  Stream<SecurityKeyPrompt?> get changes => _changes.stream;
  bool get hasHost => _hosts > 0;

  /// The user dismissed the sheet, whatever it was showing.
  Stream<void> get cancellations => _cancellations.stream;

  void attachHost() => _hosts++;

  /// The last host to leave ends a request even between steps, when nothing
  /// is on screen; nothing could ask the user after it.
  void detachHost() {
    if (_hosts > 0) _hosts--;
    if (_hosts > 0) return;
    _complete(null);
    _cancellations.add(null);
  }

  /// Hands [pin] to the waiting request. It is wiped here if nothing waits.
  void answerPin(Uint8List pin) {
    if (!_answer(SecurityKeyStage.enterPin, pin)) {
      pin.fillRange(0, pin.length, 0);
    }
  }

  void answerAccount(int index) =>
      _answer(SecurityKeyStage.chooseAccount, index);

  void retry() => _answer(SecurityKeyStage.timedOut, true);

  void cancel() {
    if (_current == null) return;
    _complete(null);
    _cancellations.add(null);
  }

  void show(SecurityKeyPrompt prompt) {
    _complete(null);
    _publish(prompt);
  }

  /// Null when the user cancels.
  Future<Uint8List?> askPin({
    String? product,
    int? retriesLeft,
    bool wrongPin = false,
  }) async {
    final answer = await _ask(
      SecurityKeyPrompt(
        SecurityKeyStage.enterPin,
        product: product,
        retriesLeft: retriesLeft,
        wrongPin: wrongPin,
      ),
    );
    return answer is Uint8List ? answer : null;
  }

  Future<int?> chooseAccount(List<SecurityKeyAccount> accounts) async {
    final answer = await _ask(
      SecurityKeyPrompt(SecurityKeyStage.chooseAccount, accounts: accounts),
    );
    return answer is int && answer >= 0 && answer < accounts.length
        ? answer
        : null;
  }

  Future<bool> askRetry({String? product}) async =>
      await _ask(
        SecurityKeyPrompt(SecurityKeyStage.timedOut, product: product),
      ) ==
      true;

  void close() {
    _complete(null);
    _publish(null);
  }

  Future<Object?> _ask(SecurityKeyPrompt prompt) {
    _complete(null);
    if (!hasHost) return Future.value();
    final reply = _reply = Completer<Object?>();
    _publish(prompt);
    return reply.future;
  }

  bool _answer(SecurityKeyStage stage, Object value) {
    final reply = _reply;
    if (reply == null || _current?.stage != stage) return false;
    _reply = null;
    reply.complete(value);
    return true;
  }

  void _complete(Object? value) {
    final reply = _reply;
    _reply = null;
    if (reply != null && !reply.isCompleted) reply.complete(value);
  }

  void _publish(SecurityKeyPrompt? prompt) {
    _current = prompt;
    _changes.add(prompt);
  }
}
