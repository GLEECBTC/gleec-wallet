import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/services/wallet_access/wallet_access_record.dart';
import 'package:web_dex/services/wallet_access/wallet_access_service.dart';
import 'package:web_dex/services/wallet_access/wallet_credential_cleanup.dart';

import 'rollback_test_support.dart';

const _records = 'wallet_access_records_v1';
const _phase = String.fromEnvironment(
  'AUTH_ROLLBACK_PHASE',
  defaultValue: 'ci',
);
const _directory = String.fromEnvironment('AUTH_ROLLBACK_STATE_DIR');
const _scenarios = [
  'generated',
  'device',
  'passkey-policy',
  'custom-password',
  'provision-before',
  'provision-after',
  'rotation-before',
  'rotation-after',
  'rotation-vault-write',
  'delete-after-engine',
  'signed-out',
  'renamed',
  'missing-protected',
  'wrong-pubkey',
  'unknown-schema',
  'legacy-backup',
  'recovery-phraseConfirmed',
  'recovery-phraseSupplied',
  'recovery-encryptedFileExported',
];

WalletAccessRecord _record(RollbackFixture fixture) =>
    WalletAccessRecord.fromJson(
      Map<String, dynamic>.from(
        (fixture.storage.values[_records] as Map).values.single as Map,
      ),
    );

Future<RollbackFixture> _write(String scenario) async {
  final fixture = RollbackFixture();
  await fixture.service.initialize();
  final protected =
      scenario == 'device' ||
      scenario == 'missing-protected' ||
      scenario.startsWith('rotation-') ||
      scenario.startsWith('provision-') ||
      scenario == 'delete-after-engine';
  if (scenario.startsWith('provision-')) {
    fixture.auth.creationFailure = scenario.split('-').last;
  }
  final evidence = scenario.startsWith('recovery-')
      ? scenario.substring('recovery-'.length)
      : 'none';
  final creating = fixture.service.createWallet(
    walletType: WalletType.hdwallet,
    useDeviceProtection: protected,
    initialMetadata: {
      'type': 'hdwallet',
      if (scenario != 'legacy-backup') 'recovery_evidence': evidence,
      if (scenario == 'legacy-backup') 'has_backup': true,
    },
  );
  if (scenario.startsWith('provision-')) {
    await expectLater(creating, throwsA(isA<WalletAccessException>()));
    return fixture;
  }
  final user = await creating;
  if (scenario == 'passkey-policy') {
    await fixture.service.enrollPasskey(walletId: user.walletId);
  } else if (scenario == 'custom-password') {
    await fixture.service.changePassword(
      walletId: user.walletId,
      newPassword: rollbackNewPassword,
    );
  } else if (scenario.startsWith('rotation-')) {
    if (scenario == 'rotation-vault-write') {
      fixture.backend.failWrite = true;
    } else {
      fixture.auth.rotationFailure = scenario.split('-').last;
    }
    await expectLater(
      fixture.service.changePassword(
        walletId: user.walletId,
        newPassword: rollbackNewPassword,
      ),
      throwsA(isA<WalletAccessException>()),
    );
    fixture.backend.failWrite = false;
    expect(_record(fixture).phase, 'rotating');
    expect(_record(fixture).rotationEnvelope, isNotNull);
  } else if (scenario == 'delete-after-engine') {
    final cleanup = WalletCredentialCleanup(fixture.storage, fixture.backend);
    await cleanup.prepare(_record(fixture), null);
    fixture.auth.users.clear();
    // Simulates termination after engine deletion, before the vault deletion.
    await cleanup.resume({});
    expect(await cleanup.hasPending, isTrue);
  } else if (scenario == 'signed-out') {
    await fixture.service.signOut();
  } else if (scenario == 'renamed') {
    fixture.auth.users[0] = user.copyWith(
      walletId: user.walletId.copyWith(name: 'Renamed rollback wallet'),
    );
  } else if (scenario == 'missing-protected') {
    fixture.backend.values.clear();
    fixture.backend.infos.clear();
  } else if (scenario == 'wrong-pubkey') {
    final record = _record(fixture);
    fixture.storage.values[_records] = {
      record.entryId: record.copyWith(pubkeyHash: 'wrong-wallet').toJson(),
    };
  } else if (scenario == 'unknown-schema') {
    final record = _record(fixture);
    fixture.storage.values[_records] = {
      record.entryId: {...record.toJson(), 'version': 99},
    };
  }
  return fixture;
}

Future<void> _read(RollbackFixture fixture, String scenario) async {
  final originalUsers = jsonEncode(
    fixture.auth.users.map((u) => u.toJson()).toList(),
  );
  final originalRecords = jsonEncode(fixture.storage.values[_records]);
  final originalRegistrations = fixture.auth.registrations;
  await fixture.service.initialize();
  expect(fixture.service.unlockCoordinator.state.hasWallet, isFalse);
  if (_phase == 'rollback') {
    expect(fixture.service.unlockCoordinator.backgroundGrace, Duration.zero);
    final capabilities = await fixture.service.capabilities();
    expect(capabilities.deviceAuthentication, isFalse);
    expect(capabilities.passkeyCandidate, isFalse);
  }
  if (scenario == 'delete-after-engine') {
    final cleanup = WalletCredentialCleanup(fixture.storage, fixture.backend);
    if (_phase != 'upgrade') {
      expect(await cleanup.hasPending, isTrue);
      expect(fixture.backend.authorizations, 0);
      await fixture.service.retryCredentialCleanup();
    }
    expect(await cleanup.hasIntents, isFalse);
    expect(fixture.backend.values, isEmpty);
    expect(fixture.storage.values[_records], isEmpty);
    return;
  }
  if (scenario.startsWith('provision-')) {
    final id = _record(fixture).entryId;
    if (_phase != 'upgrade') {
      expect(fixture.storage.values['wallet_access_pending_v1'], id);
      final created = await fixture.service.createWallet(
        walletType: WalletType.hdwallet,
        initialMetadata: const {'type': 'hdwallet'},
      );
      expect(WalletAccessService.entryId(created), id);
      expect(fixture.auth.registrations, 1);
      expect(_record(fixture).requiresAuthentication, isTrue);
      expect(fixture.storage.values['wallet_access_pending_v1'], isNull);
    }
    expect(_record(fixture).phase, 'ready');
  }
  final user = fixture.auth.users.single;
  if (scenario == 'missing-protected' ||
      scenario == 'wrong-pubkey' ||
      scenario == 'unknown-schema') {
    await expectLater(
      fixture.service.status(walletId: user.walletId),
      throwsA(isA<WalletAccessException>()),
    );
    expect(jsonEncode(fixture.storage.values[_records]), originalRecords);
    expect(fixture.auth.registrations, originalRegistrations);
    return;
  }
  if (scenario == 'signed-out') {
    expect(await fixture.service.automaticEntrySuppressed, isTrue);
    expect(await fixture.service.lastWallet(), isNull);
    expect(fixture.backend.authorizations, 0);
    return;
  }
  if (scenario == 'renamed') {
    expect((await fixture.service.lastWallet())?.name, user.walletId.name);
  }
  if (scenario.startsWith('rotation-')) {
    await fixture.service.recoverPasswordRotation(
      user.wallet,
      rollbackNewPassword,
    );
    expect(_record(fixture).rotationEnvelope, isNull);
    expect(_record(fixture).requiresAuthentication, isTrue);
    expect(_record(fixture).managed, isTrue);
  }
  if (scenario == 'custom-password') {
    expect(fixture.backend.values, isEmpty);
    expect(_record(fixture).managed, isFalse);
    fixture.auth.activate(user);
    await fixture.service.didAuthenticate(user, password: rollbackNewPassword);
    await fixture.service.authorize(
      walletId: user.walletId,
      password: rollbackNewPassword,
    );
  } else {
    final signedIn = await fixture.service.signInManaged(user.wallet);
    expect(signedIn.walletId, user.walletId);
    expect(WalletAccessService.entryId(signedIn), _record(fixture).entryId);
    final priorAuthorizations = fixture.backend.authorizations;
    await fixture.service.authorize(walletId: user.walletId);
    if (_record(fixture).requiresAuthentication) {
      expect(fixture.backend.authorizations, greaterThan(priorAuthorizations));
    }
  }
  if (_phase == 'rollback') {
    for (final enroll in [
      fixture.service.enrollDevice,
      fixture.service.enrollPasskey,
    ]) {
      await expectLater(
        enroll(walletId: user.walletId),
        throwsA(
          isA<WalletAccessException>().having(
            (error) => error.failure,
            'enrollment disabled',
            WalletAccessFailure.unavailable,
          ),
        ),
      );
    }
  }
  expect((await fixture.service.lastWallet())?.name, user.walletId.name);
  if (!scenario.startsWith('provision-')) {
    expect(
      jsonEncode(fixture.auth.users.map((u) => u.toJson()).toList()),
      originalUsers,
    );
    expect(fixture.auth.registrations, originalRegistrations);
  }
  final expectedEvidence = scenario == 'legacy-backup'
      ? RecoveryEvidence.legacyUnknown
      : scenario.startsWith('recovery-')
      ? RecoveryEvidence.parse(scenario.substring('recovery-'.length))
      : RecoveryEvidence.none;
  expect(user.wallet.config.recoveryEvidence, expectedEvidence);
}

void main() {
  group('Persisted wallet readers across rollback profiles', () {
    test('compiled profile is the intended release profile', () {
      final rollback = _phase == 'rollback';
      expect(WalletAccessService.deviceEnrollmentEnabled, !rollback);
      expect(WalletAccessService.passkeyEnrollmentEnabled, !rollback);
      expect(WalletAccessService.immediateLockRequired, rollback);
    });
    for (final scenario in _scenarios) {
      test(scenario, () async {
        final path = _directory.isEmpty
            ? null
            : File('$_directory/$scenario.json');
        RollbackFixture fixture;
        if (_phase == 'write' || _phase == 'ci') {
          fixture = await _write(scenario);
          final encoded = jsonEncode(fixture.toJson());
          await fixture.service.dispose();
          if (_phase == 'write') {
            await path!.writeAsString(encoded, flush: true);
            return;
          }
          fixture = RollbackFixture()
            ..restore(jsonDecode(encoded) as Map<String, dynamic>);
        } else {
          fixture = RollbackFixture()
            ..restore(
              jsonDecode(await path!.readAsString()) as Map<String, dynamic>,
            );
        }
        try {
          await _read(fixture, scenario);
          if (_phase == 'rollback') {
            await path!.writeAsString(
              jsonEncode(fixture.toJson()),
              flush: true,
            );
          }
        } finally {
          await fixture.service.dispose();
        }
      });
    }
  });
}
