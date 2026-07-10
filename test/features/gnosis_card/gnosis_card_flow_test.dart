import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:web_dex/features/gnosis_card/application/gnosis_card_coordinator.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_models.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_ports.dart';
import 'package:web_dex/features/gnosis_card/infrastructure/deterministic_gnosis_pay_repository.dart';
import 'package:web_dex/features/gnosis_card/infrastructure/gnosis_card_config.dart';

void main() {
  group('mock-first Gnosis card flow', () {
    test(
      'API deploys before KDF registration and supports both intents',
      () async {
        final repository = DeterministicGnosisPayRepository(
          scenario: GnosisCardScenario.happyPath,
        );
        final signer = _TestSigner();
        final coordinator = GnosisCardCoordinator(
          repository: repository,
          signer: signer,
        );

        var snapshot = await coordinator.initialize();
        expect(snapshot.stage, GnosisOnboardingStage.signedOut);
        for (var step = 0; step < 7; step += 1) {
          snapshot = await coordinator.advance();
        }

        expect(snapshot.stage, GnosisOnboardingStage.ready);
        expect(snapshot.deployment?.status, SafeDeploymentStatus.ok);
        expect(signer.registeredSafes, hasLength(1));
        expect(snapshot.dashboard?.cards.single.kind, GnosisCardKind.virtual);

        snapshot = await coordinator.orderPhysicalCard();
        expect(
          snapshot.dashboard?.physicalOrder?.status,
          PhysicalCardOrderStatus.shipped,
        );
        expect(snapshot.dashboard?.cards, hasLength(2));
        final physical = snapshot.dashboard!.cards.last;
        snapshot = await coordinator.setCardStatus(
          physical.id,
          GnosisCardStatus.active,
        );
        expect(snapshot.dashboard?.cards.last.status, GnosisCardStatus.active);

        snapshot = await coordinator.prepareWithdrawal(
          WithdrawalRequest(
            assetContract: '0x3333333333333333333333333333333333333333',
            assetSymbol: 'USDC',
            recipient: '0x4444444444444444444444444444444444444444',
            amountAtomic: BigInt.from(1000000),
            decimals: 6,
          ),
        );
        expect(snapshot.reviewIntent?.kind, SmartAccountIntentKind.withdrawal);
        snapshot = await coordinator.confirmPreparedIntent();

        snapshot = await coordinator.prepareDailyLimit(
          DailyLimitRequest(
            bouncer: '0x5555555555555555555555555555555555555555',
            amountAtomic: BigInt.from(250000000),
            decimals: 6,
          ),
        );
        expect(snapshot.reviewIntent?.kind, SmartAccountIntentKind.dailyLimit);
        snapshot = await coordinator.confirmPreparedIntent();
        expect(snapshot.dashboard?.operations, hasLength(2));
        expect(signer.typedDataSignatures, 2);

        snapshot = await coordinator.pollDelayedOperations();
        expect(
          snapshot.dashboard?.operations.map((operation) => operation.status),
          everyElement(DelayedOperationStatus.executable),
        );
        snapshot = await coordinator.pollDelayedOperations();
        expect(
          snapshot.dashboard?.operations.map((operation) => operation.status),
          everyElement(DelayedOperationStatus.executed),
        );

        final restartedKdfCoordinator = GnosisCardCoordinator(
          repository: repository,
          signer: signer,
        );
        snapshot = await restartedKdfCoordinator.initialize();
        expect(snapshot.stage, GnosisOnboardingStage.ready);
        expect(signer.registeredSafes, hasLength(2));
      },
    );

    test('deployment failure never reaches KDF registration', () async {
      final signer = _TestSigner();
      final coordinator = GnosisCardCoordinator(
        repository: DeterministicGnosisPayRepository(
          scenario: GnosisCardScenario.deploymentFailure,
        ),
        signer: signer,
      );
      await coordinator.initialize();
      for (var step = 0; step < 5; step += 1) {
        await coordinator.advance();
      }

      await expectLater(
        coordinator.advance(),
        throwsA(isA<GnosisCardUnavailable>()),
      );
      expect(signer.registeredSafes, isEmpty);
    });

    test(
      'offline and expired scenarios expose recoverable typed failures',
      () async {
        final offline = DeterministicGnosisPayRepository(
          scenario: GnosisCardScenario.offline,
        );
        await expectLater(
          offline.onboardingStage(),
          throwsA(isA<GnosisCardUnavailable>()),
        );

        final expiredSession = GnosisCardCoordinator(
          repository: DeterministicGnosisPayRepository(
            scenario: GnosisCardScenario.expiredSession,
          ),
          signer: _TestSigner(),
        );
        await expiredSession.initialize();
        await expectLater(
          expiredSession.advance(),
          throwsA(isA<GnosisCardUnavailable>()),
        );

        final expiredKyc = GnosisCardCoordinator(
          repository: DeterministicGnosisPayRepository(
            scenario: GnosisCardScenario.kycExpired,
          ),
          signer: _TestSigner(),
        );
        await expiredKyc.initialize();
        for (var step = 0; step < 4; step += 1) {
          await expiredKyc.advance();
        }
        await expectLater(
          expiredKyc.advance(),
          throwsA(isA<GnosisCardUnavailable>()),
        );
      },
    );
  });
}

class _TestSigner implements SmartAccountSigner {
  final List<String> registeredSafes = [];
  int typedDataSignatures = 0;

  @override
  Future<SmartAccountOwner> owner() async => const SmartAccountOwner(
    address: '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    coin: 'GNO',
  );

  @override
  Future<void> registerSafe(String safeAddress) async {
    registeredSafes.add(safeAddress);
  }

  @override
  Future<String> signPersonalMessage(String message) async => 'test-eip191';

  @override
  Future<SmartAccountSignature> signTypedData(
    PreparedSmartAccountIntent intent,
  ) async {
    typedDataSignatures += 1;
    return const SmartAccountSignature(
      signature: 'test-eip712',
      typedDataHash:
          '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      ownerAddress: '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
  }
}
