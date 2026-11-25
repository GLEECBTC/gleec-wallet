import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:web_dex/services/wallet_access/platform/passkey/security_key/security_key_bridge.dart';
import 'package:web_dex/services/wallet_access/platform/passkey/security_key/security_key_prompts.dart';

import '../passkey_test_support.dart';

SecurityKeyDevice securityKey(
  int n, {
  SecurityKeyDeviceState state = SecurityKeyDeviceState.ready,
  bool hmacSecret = true,
  bool pin = true,
  bool uv = false,
  int? pinRetries = 8,
  int? uvRetries,
}) => SecurityKeyDevice(
  path: '/dev/hidraw$n',
  state: state,
  product: 'Key $n',
  hmacSecret: hmacSecret,
  pin: pin,
  uv: uv,
  pinRetries: pinRetries,
  uvRetries: uvRetries,
);

/// A credential as a key returns it for [rpId], verified and present.
SecurityKeyCandidate keyCandidate(
  int n, {
  String rpId = passkeyRp,
  bool prf = true,
}) => SecurityKeyCandidate(
  credentialId: bytesOf(n, 16),
  userHandle: bytesOf(n + 100),
  userName: 'Wallet $n · 0123abcd',
  userDisplayName: 'Wallet $n',
  authenticatorData: Uint8List.fromList([
    ...sha256.convert(utf8.encode(rpId)).bytes,
    0x05,
    0,
    0,
    0,
    1,
  ]),
  signature: bytesOf(7, 70),
  prf: prf ? bytesOf(n + 50) : null,
);

class AssertCall {
  AssertCall(this.path, this.clientDataHash, this.salt, this.allow, this.pin)
    : pinText = pin == null ? null : utf8.decode(pin);

  final String path;
  final Uint8List clientDataHash;
  final Uint8List salt;
  final List<Uint8List> allow;

  /// The buffer the bridge was handed, to check that it was wiped after.
  final Uint8List? pin;
  final String? pinText;
}

/// The Linux bridge with scripted devices and answers.
class FakeSecurityKeyBridge implements SecurityKeyBridge {
  bool available = true;

  /// Each `devices` call takes the next list; the last one repeats.
  final deviceLists = <List<SecurityKeyDevice>>[
    [securityKey(0)],
  ];
  Object? devicesError;

  /// What `select` answers, or a [SecurityKeyException] it throws.
  Object selection = '/dev/hidraw0';
  final selections = <List<String>>[];

  /// Each `getAssertion` takes the next: candidates or an exception.
  final answers = <Object>[];
  final calls = <AssertCall>[];

  /// While set, `getAssertion` waits for it before answering.
  Completer<void>? hold;
  int cancels = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<List<SecurityKeyDevice>> devices() async {
    if (devicesError case final error?) throw error;
    return deviceLists.length > 1
        ? deviceLists.removeAt(0)
        : deviceLists.single;
  }

  @override
  Future<String> select(List<String> paths, {required Duration timeout}) async {
    selections.add(paths);
    if (selection case final String path) return path;
    throw selection;
  }

  @override
  Future<List<SecurityKeyCandidate>> getAssertion({
    required String path,
    required String rpId,
    required Uint8List clientDataHash,
    required Uint8List salt,
    required List<Uint8List> allowCredentials,
    required Duration timeout,
    Uint8List? pin,
  }) async {
    calls.add(AssertCall(path, clientDataHash, salt, allowCredentials, pin));
    await hold?.future;
    final answer = answers.isEmpty ? [keyCandidate(1)] : answers.removeAt(0);
    if (answer is List<SecurityKeyCandidate>) return answer;
    throw answer;
  }

  @override
  Future<void> cancel() async => cancels++;
}

/// Answers the sheet as a user would. Unscripted stages that wait on the
/// user (a PIN, a choice, a retry) are cancelled.
class PromptScript {
  PromptScript(this.prompts) {
    prompts.attachHost();
    _subscription = prompts.changes.listen(_onPrompt);
  }

  final SecurityKeyPrompts prompts;
  final shown = <SecurityKeyPrompt>[];
  final pins = <String>[];
  int? account;
  bool retry = false;
  late final StreamSubscription<SecurityKeyPrompt?> _subscription;

  /// Runs on the stage, instead of answering it.
  void Function(SecurityKeyPrompt prompt)? onShown;

  List<SecurityKeyStage> get stages => [for (final p in shown) p.stage];

  void _onPrompt(SecurityKeyPrompt? prompt) {
    if (prompt == null) return;
    shown.add(prompt);
    if (onShown case final handler?) return handler(prompt);
    switch (prompt.stage) {
      case SecurityKeyStage.enterPin:
        if (pins.isEmpty) return prompts.cancel();
        prompts.answerPin(Uint8List.fromList(utf8.encode(pins.removeAt(0))));
      case SecurityKeyStage.chooseAccount:
        if (account case final index?) return prompts.answerAccount(index);
        prompts.cancel();
      case SecurityKeyStage.timedOut:
        if (retry) return prompts.retry();
        prompts.cancel();
      default:
        break;
    }
  }

  Future<void> dispose() async {
    await _subscription.cancel();
    prompts.detachHost();
  }
}
