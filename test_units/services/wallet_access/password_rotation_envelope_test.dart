import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/services/wallet_access/password_rotation_envelope.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'rotation recovery binds the old credential to password and wallet',
    () async {
      const old = 'canary-old-credential-do-not-log';
      const password = 'New-custom-password-2026!';
      const identity = 'entry-a';
      final envelope = await PasswordRotationEnvelope.seal(
        password,
        old,
        identity,
      );
      expect(envelope, isNot(contains(old)));
      expect(envelope, isNot(contains(password)));
      expect(
        await PasswordRotationEnvelope.open(password, envelope, identity),
        old,
      );
      expect(
        await PasswordRotationEnvelope.open(
          'wrong-password',
          envelope,
          identity,
        ),
        isNull,
      );
      expect(
        await PasswordRotationEnvelope.open(password, envelope, 'entry-b'),
        isNull,
      );
      final json = jsonDecode(envelope) as Map<String, dynamic>;
      final bytes = base64Decode(json['ciphertext'] as String);
      bytes[0] ^= 1;
      json['ciphertext'] = base64Encode(bytes);
      expect(
        await PasswordRotationEnvelope.open(
          password,
          jsonEncode(json),
          identity,
        ),
        isNull,
      );
    },
  );

  test(
    'malformed or unknown rotation envelopes cannot recover a credential',
    () async {
      for (final envelope in [
        'not-json',
        '{}',
        '{"v":2}',
        '{"v":1,"salt":"!"}',
      ]) {
        expect(
          await PasswordRotationEnvelope.open('password', envelope, 'entry'),
          isNull,
        );
      }
    },
  );
}
