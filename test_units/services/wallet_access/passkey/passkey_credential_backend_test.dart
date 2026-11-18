import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/services/wallet_access/platform/passkey/passkey_credential_backend.dart';
import 'package:web_dex/services/wallet_access/platform/passkey/passkey_envelope.dart';
import 'package:web_dex/services/wallet_access/wallet_access_types.dart';

import 'passkey_test_support.dart';

part 'passkey_credential_removal_cases.dart';
part 'passkey_unattended_return_cases.dart';

Matcher _fails(WalletAccessFailure failure) => throwsA(
  isA<WalletAccessException>().having((e) => e.failure, 'failure', failure),
);

const _key = passkeyWalletKey;
final _slot = PasskeyCredentialBackend.slotFor(_key);

class _Rig {
  _Rig() {
    backend = PasskeyCredentialBackend(
      base: vault,
      authenticator: authenticator,
      monotonicNow: () => now,
    );
  }

  final vault = FakeDeviceVault();
  final authenticator = FakePasskeyAuthenticator();
  late final PasskeyCredentialBackend backend;
  Duration now = Duration.zero;

  Future<String?> unlock({String? purpose}) => backend.read(
    _key,
    reason: 'Unlock your wallet',
    requireAuthentication: true,
    purpose: purpose,
  );

  /// A wallet whose device record is switched to the first held passkey.
  Future<void> bound({bool protected = false}) async {
    await vault.write(_key, passkeyPassword, requireAuthentication: protected);
    if (protected) {
      await vault.read(_key, reason: 'authorize', purpose: 'delete');
    }
    await backend.bindExistingPasskey(_key, passkeyPassword);
    vault.prompts = 0;
    authenticator.assertions = 0;
  }
}

void main() {
  group('passkey tier over a device vault', () {
    late _Rig rig;
    setUp(() => rig = _Rig());

    test('offers binding only where the bridge supports it', () async {
      expect(
        (await rig.backend.capabilities()).existingPasskeyCandidate,
        isTrue,
      );
      rig = _Rig()..authenticator.supported = false;
      final capabilities = await rig.backend.capabilities();
      expect(capabilities.existingPasskeyCandidate, isFalse);
      expect(capabilities.deviceAuthentication, isTrue);
    });

    test('binds an existing passkey over unattended storage', () async {
      await rig.vault.write(
        _key,
        passkeyPassword,
        requireAuthentication: false,
      );
      await rig.backend.bindExistingPasskey(_key, passkeyPassword);

      // The user chooses, then the same passkey proves its key again.
      expect(rig.authenticator.assertions, 2);
      final [choose, verify] = rig.authenticator.requests;
      expect(choose.allowCredentials, isEmpty);
      expect(verify.allowCredentials.single, rig.authenticator.passkeys[0].id);
      expect(verify.salt, choose.salt);
      expect(verify.challenge, isNot(choose.challenge));
      expect(rig.vault.holds(_key), isFalse);
      expect(rig.vault.prompts, 0);
      final info = await rig.backend.metadata(_key);
      expect(info?.protection, CredentialProtection.passkey);
      expect(info?.enrolled, isTrue);
      expect(info?.revision, 2);

      expect(await rig.unlock(), passkeyPassword);
      final unlock = rig.authenticator.requests.last;
      expect(unlock.allowCredentials.single, rig.authenticator.passkeys[0].id);
      expect(unlock.salt, rig.authenticator.requests.first.salt);
    });

    test('stores ciphertext only, under a salt of its own', () async {
      await rig.bound();
      final stored = rig.vault.value(_slot)!;
      expect(stored, isNot(contains(passkeyPassword)));
      final envelope = PasskeyEnvelope.decode(
        stored,
        expectedKey: _key,
        expectedRpId: passkeyRp,
      );
      expect(envelope.salt, hasLength(32));
      expect(envelope.userHandle, rig.authenticator.passkeys[0].userHandle);
    });

    test(
      'switches from device unlock without a second device prompt',
      () async {
        await rig.vault.write(
          _key,
          passkeyPassword,
          requireAuthentication: true,
        );
        rig.vault.prompts = 0;
        expect(
          await rig.vault.read(_key, reason: 'authorize', purpose: 'delete'),
          passkeyPassword,
        );
        await rig.backend.bindExistingPasskey(_key, passkeyPassword);
        expect(rig.vault.prompts, 1);
        expect(rig.vault.holds(_key), isFalse);
        expect(
          (await rig.backend.metadata(_key))?.protection,
          CredentialProtection.passkey,
        );
      },
    );

    test('a declined passkey prompt leaves device unlock as it was', () async {
      await rig.vault.write(_key, passkeyPassword, requireAuthentication: true);
      rig.authenticator.failure = WalletAccessFailure.canceled;
      await expectLater(
        rig.backend.bindExistingPasskey(_key, passkeyPassword),
        _fails(WalletAccessFailure.canceled),
      );
      expect(rig.vault.holds(_key), isTrue);
      expect(rig.vault.holds(_slot), isFalse);
    });

    test('a declined removal keeps device unlock and no inert copy', () async {
      await rig.vault.write(_key, passkeyPassword, requireAuthentication: true);
      rig.vault.promptFailure = WalletAccessFailure.canceled;
      await expectLater(
        rig.backend.bindExistingPasskey(_key, passkeyPassword),
        _fails(WalletAccessFailure.canceled),
      );
      expect(rig.vault.holds(_key), isTrue);
      expect(rig.vault.holds(_slot), isFalse);
      expect(
        (await rig.backend.metadata(_key))?.protection,
        CredentialProtection.authenticationBound,
      );
    });

    test('a removal whose reply was lost still completes the switch', () async {
      await rig.vault.write(
        _key,
        passkeyPassword,
        requireAuthentication: false,
      );
      rig.vault.deleteReplyLost = true;
      await rig.backend.bindExistingPasskey(_key, passkeyPassword);
      expect(
        (await rig.backend.metadata(_key))?.protection,
        CredentialProtection.passkey,
      );
    });

    test(
      'a device record in front of an envelope governs the wallet',
      () async {
        await rig.bound();
        await rig.vault.write(
          _key,
          passkeyPassword,
          requireAuthentication: true,
        );
        rig.vault.prompts = 0;
        expect(
          (await rig.backend.metadata(_key))?.protection,
          CredentialProtection.authenticationBound,
        );
        expect(await rig.unlock(), passkeyPassword);
        expect(rig.authenticator.assertions, 0);
        expect(rig.vault.prompts, 1);
      },
    );

    test('a passkey whose key does not reproduce is never bound', () async {
      await rig.vault.write(_key, passkeyPassword, requireAuthentication: true);
      rig.authenticator.unstableWhenNamed = true;
      await expectLater(
        rig.backend.bindExistingPasskey(_key, passkeyPassword),
        _fails(WalletAccessFailure.prfUnavailable),
      );
      expect(rig.vault.holds(_key), isTrue);
      expect(rig.vault.holds(_slot), isFalse);
    });

    test(
      'an envelope left behind a device record does not block binding',
      () async {
        await rig.vault.write(
          _key,
          passkeyPassword,
          requireAuthentication: true,
        );
        await rig.vault.write(
          _slot,
          'left by an interrupted switch',
          requireAuthentication: false,
        );
        await rig.backend.bindExistingPasskey(_key, passkeyPassword);
        expect(rig.vault.holds(_key), isFalse);
        expect(await rig.unlock(), passkeyPassword);
      },
    );

    test(
      'a busy device vault never routes a write in front of a passkey',
      () async {
        await rig.bound();
        rig.vault.metadataFailure = WalletAccessFailure.busy;
        await expectLater(
          rig.backend.write(_key, 'Changed', requireAuthentication: true),
          _fails(WalletAccessFailure.busy),
        );
        await expectLater(rig.unlock(), _fails(WalletAccessFailure.busy));
        rig.vault.metadataFailure = null;
        expect(rig.vault.holds(_key), isFalse);
        expect(await rig.unlock(), passkeyPassword);
      },
    );

    test('a staging relying party keeps envelopes of its own', () async {
      final staging = PasskeyCredentialBackend(
        base: rig.vault,
        authenticator: rig.authenticator,
        rpId: 'staging.gleec.com',
      );
      addTearDown(staging.dispose);
      rig.authenticator
        ..rpIdForHash = 'staging.gleec.com'
        ..origin = 'https://staging.gleec.com';
      await staging.bindExistingPasskey(_key, passkeyPassword);
      expect(
        rig.vault.holds(
          PasskeyCredentialBackend.slotFor(_key, 'staging.gleec.com'),
        ),
        isTrue,
      );
      expect(await rig.backend.metadata(_key), isNull);
      expect(
        (await staging.metadata(_key))?.protection,
        CredentialProtection.passkey,
      );
    });

    test('rejects binding over a passkey and unusable PRF output', () async {
      await rig.bound();
      await expectLater(
        rig.backend.bindExistingPasskey(_key, passkeyPassword),
        _fails(WalletAccessFailure.invalidated),
      );
      rig = _Rig()..authenticator.prfLength = 16;
      await expectLater(
        rig.backend.bindExistingPasskey(_key, passkeyPassword),
        _fails(WalletAccessFailure.prfUnavailable),
      );
      expect(rig.vault.items, isEmpty);
    });

    test('never opens with another passkey or without the bound one', () async {
      await rig.bound();
      rig.authenticator.passkeys
        ..clear()
        ..add(FakePasskey(5));
      await expectLater(
        rig.unlock(),
        _fails(WalletAccessFailure.passkeyNotFound),
      );
      // The same credential ID with different key material.
      final impostor = FakePasskey(5);
      rig.authenticator.passkeys
        ..clear()
        ..add(impostor);
      impostor.id.setAll(0, FakePasskey(1).id);
      impostor.userHandle.setAll(0, FakePasskey(1).userHandle);
      await expectLater(
        rig.unlock(),
        _fails(WalletAccessFailure.envelopeCorrupt),
      );
    });

    test('a passkey record never becomes unattended', () async {
      await rig.bound();
      await expectLater(
        rig.backend.write(_key, 'other', requireAuthentication: false),
        _fails(WalletAccessFailure.invalidated),
      );
      expect(await rig.unlock(), passkeyPassword);
    });

    test(
      'a password change reseals once and reads back without a prompt',
      () async {
        await rig.bound();
        const next = 'Owner-Chosen-Password-42!';
        await rig.backend.write(_key, next, requireAuthentication: true);
        expect(rig.authenticator.assertions, 1);
        expect(await rig.unlock(purpose: 'verifyWrite'), next);
        expect(rig.authenticator.assertions, 1);
        expect((await rig.backend.metadata(_key))?.revision, 3);
        // The grant is single-use.
        expect(await rig.unlock(purpose: 'verifyWrite'), next);
        expect(rig.authenticator.assertions, 2);
      },
    );

    test('the readback grant expires and cancellation revokes it', () async {
      await rig.bound();
      await rig.backend.write(_key, 'Changed-1', requireAuthentication: true);
      rig.now += const Duration(seconds: 31);
      expect(await rig.unlock(purpose: 'verifyWrite'), 'Changed-1');
      expect(rig.authenticator.assertions, 2);

      await rig.backend.write(_key, 'Changed-2', requireAuthentication: true);
      await rig.backend.cancel();
      expect(await rig.unlock(purpose: 'verifyWrite'), 'Changed-2');
      expect(rig.authenticator.assertions, 4);
      expect(rig.authenticator.cancels, 1);
    });

    test('one ceremony at a time', () async {
      await rig.bound();
      final reached = Completer<void>();
      final release = Completer<void>();
      rig.authenticator.beforeReply = (_) {
        reached.complete();
        return release.future;
      };
      final first = rig.unlock();
      await reached.future;
      await expectLater(rig.unlock(), _fails(WalletAccessFailure.busy));
      rig.authenticator.beforeReply = null;
      release.complete();
      expect(await first, passkeyPassword);
    });

    test('a cancellation during the prompt discards its result', () async {
      await rig.bound();
      rig.authenticator.beforeReply = (_) => rig.backend.cancel();
      await expectLater(
        rig.unlock(),
        _fails(WalletAccessFailure.staleOperation),
      );
    });

    test('chooses another passkey after password verification', () async {
      await rig.bound();
      rig.authenticator.passkeys
        ..clear()
        ..add(FakePasskey(8));
      await rig.backend.replacePasskeyAfterPasswordVerification(
        _key,
        passkeyPassword,
        expectedRevision: 2,
        label: 'ignored',
      );
      expect(rig.authenticator.assertions, 2);
      expect((await rig.backend.metadata(_key))?.revision, 3);
      expect(await rig.unlock(), passkeyPassword);
      await expectLater(
        rig.backend.replacePasskeyAfterPasswordVerification(
          _key,
          passkeyPassword,
          expectedRevision: 2,
          label: 'ignored',
        ),
        _fails(WalletAccessFailure.staleOperation),
      );
    });

    test('returns to device unlock without the passkey', () async {
      await rig.bound();
      rig.authenticator.passkeys.clear();
      await rig.backend.replacePasskeyWithDevice(
        _key,
        passkeyPassword,
        expectedRevision: 2,
      );
      expect(rig.vault.prompts, 1);
      expect(rig.authenticator.assertions, 0);
      expect(rig.vault.holds(_slot), isFalse);
      expect(
        (await rig.backend.metadata(_key))?.protection,
        CredentialProtection.authenticationBound,
      );
    });

    _removalCases(() => rig);
    _unattendedReturnCases(() => rig);
  });

  test('the stored form is JSON naming its kind', () async {
    final rig = _Rig();
    await rig.bound();
    final json = jsonDecode(rig.vault.value(_slot)!) as Map;
    expect(json['kind'], PasskeyEnvelope.kind);
    expect(json['rpId'], passkeyRp);
  });
}
