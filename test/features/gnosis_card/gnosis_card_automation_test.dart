import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/features/gnosis_card/application/gnosis_card_coordinator.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_models.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_ports.dart';
import 'package:web_dex/features/gnosis_card/infrastructure/deterministic_gnosis_pay_repository.dart';
import 'package:web_dex/features/gnosis_card/infrastructure/gnosis_card_config.dart';

import 'gnosis_card_test_helpers.dart';

void main() {
  group('automatic wallet preparation and SIWE', () {
    test('single-flights readiness and challenge preparation', () async {
      final signer = GnosisTestSigner();
      final readiness = _CountingReadiness(signer.activeOwner);
      final coordinator = _coordinator(
        DeterministicGnosisPayRepository(
          scenario: GnosisCardScenario.happyPath,
        ),
        signer,
        readiness: readiness,
      );

      final snapshots = await Future.wait([
        coordinator.prepareEntry(),
        coordinator.prepareEntry(),
        coordinator.prepareEntry(),
      ]);

      expect(readiness.calls, 1);
      expect(
        snapshots.map((snapshot) => snapshot.siweChallenge?.approvalId).toSet(),
        hasLength(1),
      );
    });

    test(
      'restores a valid same-wallet session without signing again',
      () async {
        final repository = DeterministicGnosisPayRepository(
          scenario: GnosisCardScenario.happyPath,
        );
        final signer = GnosisTestSigner();
        final first = _coordinator(repository, signer);
        final challenge = (await first.prepareEntry()).siweChallenge!;
        await first.approveSignIn(approvalId: challenge.approvalId);

        final resumed = _coordinator(repository, signer);
        final snapshot = await resumed.prepareEntry();

        expect(snapshot.session?.ownerAddress, signer.activeOwner.address);
        expect(snapshot.siweChallenge, isNull);
        expect(signer.personalSignatureCalls, 1);
      },
    );

    test('approval is bound to the exact displayed message hash', () async {
      final signer = GnosisTestSigner();
      final coordinator = _coordinator(
        DeterministicGnosisPayRepository(
          scenario: GnosisCardScenario.happyPath,
        ),
        signer,
      );
      final challenge = (await coordinator.prepareEntry()).siweChallenge!;

      await expectLater(
        coordinator.approveSignIn(approvalId: 'different-approval'),
        throwsA(
          isA<GnosisCardFailure>().having(
            (failure) => failure.code,
            'code',
            GnosisCardFailureCode.invalidTransition,
          ),
        ),
      );
      expect(signer.personalSignatureCalls, 0);

      await coordinator.approveSignIn(approvalId: challenge.approvalId);
      expect(signer.personalMessages.single, challenge.message);
      expect(
        signer.expectedPersonalOwners.single.address,
        challenge.ownerAddress,
      );
    });

    test('rejects appended SIWE fields before opening the signer', () async {
      final signer = GnosisTestSigner();
      final coordinator = _coordinator(_MalformedChallengeRepository(), signer);

      await expectLater(
        coordinator.prepareEntry(),
        throwsA(
          isA<GnosisCardFailure>().having(
            (failure) => failure.code,
            'code',
            GnosisCardFailureCode.invalidInput,
          ),
        ),
      );
      expect(signer.personalSignatureCalls, 0);
      expect(coordinator.snapshot.siweChallenge, isNull);
    });

    test('rejects a substituted SIWE authorization statement', () async {
      final signer = GnosisTestSigner();
      final coordinator = _coordinator(
        _MisleadingStatementRepository(),
        signer,
      );

      await expectLater(
        coordinator.prepareEntry(),
        throwsA(
          isA<GnosisCardFailure>().having(
            (failure) => failure.code,
            'code',
            GnosisCardFailureCode.invalidInput,
          ),
        ),
      );
      expect(signer.personalSignatureCalls, 0);
    });

    test('nonces are unique, exact, and one-use', () async {
      final repository = DeterministicGnosisPayRepository(
        scenario: GnosisCardScenario.happyPath,
      );
      const owner = '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      final first = await repository.createSiweChallenge(ownerAddress: owner);
      final second = await repository.createSiweChallenge(ownerAddress: owner);

      expect(second.nonce, isNot(first.nonce));
      await repository.authenticate(
        challenge: second,
        ownerAddress: owner,
        signature: '0xsignature',
      );
      await expectLater(
        repository.authenticate(
          challenge: second,
          ownerAddress: owner,
          signature: '0xsignature',
        ),
        throwsA(isA<GnosisCardFailure>()),
      );
    });

    test('identical financial reviews get distinct retry scopes', () async {
      final repository = DeterministicGnosisPayRepository(
        scenario: GnosisCardScenario.migrationPending,
      );
      const owner = '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      final challenge = await repository.createSiweChallenge(
        ownerAddress: owner,
      );
      await repository.authenticate(
        challenge: challenge,
        ownerAddress: owner,
        signature: '0xunique-review-signature',
      );
      await repository.selectCardProduct(productId: 'virtual-eur');
      await repository.issueVirtualCard(productId: 'virtual-eur');
      final request = WithdrawalRequest(
        assetContract: '0x3333333333333333333333333333333333333333',
        assetSymbol: 'USDC',
        recipient: '0x4444444444444444444444444444444444444444',
        amountAtomic: BigInt.from(1000000),
        decimals: 6,
      );

      final first = await repository.prepareWithdrawal(request);
      final second = await repository.prepareWithdrawal(request);

      expect(second.payloadDigest, isNot(first.payloadDigest));
      final signature = const SmartAccountSignature(
        signature: '0xsigned-operation',
        typedDataHash:
            '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        ownerAddress: owner,
      );
      final submitted = await repository.submitSignedOperation(
        intent: first,
        signature: signature,
        idempotencyKey: first.payloadDigest,
      );
      final retried = await repository.submitSignedOperation(
        intent: first,
        signature: signature,
        idempotencyKey: first.payloadDigest,
      );

      expect(retried, submitted);
      expect((await repository.dashboard()).operations, hasLength(1));
    });

    test('wallet invalidation discards the prepared challenge', () async {
      final signer = GnosisTestSigner();
      final readiness = _CountingReadiness(signer.activeOwner);
      final coordinator = _coordinator(
        DeterministicGnosisPayRepository(
          scenario: GnosisCardScenario.happyPath,
        ),
        signer,
        readiness: readiness,
      );
      expect((await coordinator.prepareEntry()).siweChallenge, isNotNull);

      coordinator.resetForWalletChange();

      expect(coordinator.snapshot, const GnosisCardSnapshot.initial());
      expect(readiness.invalidations, 1);
    });
  });

  test('active migration blocks card mutations', () async {
    final signer = GnosisTestSigner();
    final coordinator = _coordinator(
      DeterministicGnosisPayRepository(
        scenario: GnosisCardScenario.migrationPending,
      ),
      signer,
    );
    final challenge = (await coordinator.prepareEntry()).siweChallenge!;
    final snapshot = await coordinator.approveSignIn(
      approvalId: challenge.approvalId,
    );
    expect(snapshot.safeMigration.isActive, isTrue);

    await expectLater(
      coordinator.updateControls(
        cardId: 'card-virtual-0001',
        controls: const GnosisCardControls(
          contactless: false,
          online: true,
          atm: false,
        ),
      ),
      throwsA(
        isA<GnosisCardFailure>().having(
          (failure) => failure.code,
          'code',
          GnosisCardFailureCode.invalidTransition,
        ),
      ),
    );
  });
}

GnosisCardCoordinator _coordinator(
  DeterministicGnosisPayRepository repository,
  GnosisTestSigner signer, {
  GnosisWalletReadiness? readiness,
}) => GnosisCardCoordinator(
  repository: repository,
  signer: signer,
  readiness: readiness,
  externalFlowLauncher: RecordingExternalFlowLauncher(),
  paymentGateway: GnosisTestPaymentGateway(),
);

class _CountingReadiness implements GnosisWalletReadiness {
  _CountingReadiness(this.owner);

  final SmartAccountOwner owner;
  int calls = 0;
  int invalidations = 0;

  @override
  Future<SmartAccountOwner> ensureReady() async {
    calls += 1;
    return owner;
  }

  @override
  void invalidate() => invalidations += 1;
}

class _MalformedChallengeRepository extends DeterministicGnosisPayRepository {
  _MalformedChallengeRepository()
    : super(scenario: GnosisCardScenario.happyPath);

  @override
  Future<GnosisSiweChallenge> createSiweChallenge({
    required String ownerAddress,
  }) async {
    final challenge = await super.createSiweChallenge(
      ownerAddress: ownerAddress,
    );
    return GnosisSiweChallenge(
      message: '${challenge.message}\nRequest ID: injected-field',
      ownerAddress: challenge.ownerAddress,
      domain: challenge.domain,
      uri: challenge.uri,
      nonce: challenge.nonce,
      chainId: challenge.chainId,
      issuedAt: challenge.issuedAt,
      expiresAt: challenge.expiresAt,
    );
  }
}

class _MisleadingStatementRepository extends DeterministicGnosisPayRepository {
  _MisleadingStatementRepository()
    : super(scenario: GnosisCardScenario.happyPath);

  @override
  Future<GnosisSiweChallenge> createSiweChallenge({
    required String ownerAddress,
  }) async {
    final challenge = await super.createSiweChallenge(
      ownerAddress: ownerAddress,
    );
    return GnosisSiweChallenge(
      message: challenge.message.replaceFirst(
        'Sign in to your Gleec card account. No transaction is sent.',
        'Authorize every future card transaction.',
      ),
      ownerAddress: challenge.ownerAddress,
      domain: challenge.domain,
      uri: challenge.uri,
      nonce: challenge.nonce,
      chainId: challenge.chainId,
      issuedAt: challenge.issuedAt,
      expiresAt: challenge.expiresAt,
    );
  }
}
