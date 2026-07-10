import 'dart:async';

import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_models.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_ports.dart';
import 'package:web_dex/features/gnosis_card/infrastructure/gnosis_card_config.dart';

const _fixtureSafe = '0x1111111111111111111111111111111111111111';
const _fixtureDelay = '0x2222222222222222222222222222222222222222';

/// Deterministic in-app adapter. It owns all mock API-shaped payloads,
/// including the address returned by the simulated deployment endpoint.
class DeterministicGnosisPayRepository implements GnosisPayRepository {
  DeterministicGnosisPayRepository({
    required this.scenario,
    SmartAccountIntentCodec codec = const SmartAccountIntentCodec(),
  }) : _codec = codec;

  final GnosisCardScenario scenario;
  final SmartAccountIntentCodec _codec;
  GnosisOnboardingStage _stage = GnosisOnboardingStage.signedOut;
  GnosisCardSession? _session;
  SafeDeployment? _deployment;
  int _deploymentPolls = 0;
  PhysicalCardOrder? _physicalOrder;
  late GnosisCardDashboard _dashboard = _initialDashboard();

  @override
  Future<GnosisOnboardingStage> onboardingStage() async {
    _requireOnline();
    return _stage;
  }

  @override
  Future<String> createSiweMessage({required String ownerAddress}) async {
    _requireOnline();
    return 'gleec.app wants you to sign in with your Ethereum account:\n'
        '$ownerAddress\n\nAuthorize the card workspace. No transaction is sent.\n\n'
        'URI: https://gleec.app/card\nVersion: 1\nChain ID: 100\n'
        'Nonce: gleec-card-0001\nIssued At: 2026-07-10T00:00:00Z';
  }

  @override
  Future<GnosisCardSession> authenticate({
    required String ownerAddress,
    required String signature,
  }) async {
    _requireOnline();
    if (signature.trim().isEmpty) {
      throw const GnosisCardUnavailable(
        'KDF returned an empty SIWE signature.',
      );
    }
    final expiresAt = scenario == GnosisCardScenario.expiredSession
        ? DateTime.now().subtract(const Duration(minutes: 1))
        : DateTime.now().add(const Duration(hours: 1));
    _session = GnosisCardSession(
      ownerAddress: ownerAddress,
      expiresAt: expiresAt,
    );
    _stage = GnosisOnboardingStage.terms;
    return _session!;
  }

  @override
  Future<void> acceptTerms() async {
    _requireSession();
    _stage = GnosisOnboardingStage.registration;
  }

  @override
  Future<void> registerApplicant() async {
    _requireSession();
    _stage = GnosisOnboardingStage.phoneAndSourceOfFunds;
  }

  @override
  Future<void> submitPhoneAndSourceOfFunds() async {
    _requireSession();
    _stage = GnosisOnboardingStage.kycPending;
  }

  @override
  Future<GnosisKycStatus> pollKyc() async {
    _requireSession();
    if (scenario == GnosisCardScenario.kycExpired) {
      return GnosisKycStatus.expired;
    }
    _stage = GnosisOnboardingStage.safeDeployment;
    return GnosisKycStatus.approved;
  }

  @override
  Future<SafeDeployment?> safeDeployment() async {
    _requireOnline();
    return _deployment;
  }

  @override
  Future<SafeDeployment> requestSafeDeployment() async {
    _requireSession();
    _deploymentPolls = 0;
    return _deployment = const SafeDeployment(
      requestId: 'deploy-gleec-0001',
      status: SafeDeploymentStatus.accepted,
    );
  }

  @override
  Future<SafeDeployment> pollSafeDeployment(String requestId) async {
    _requireSession();
    final current = _deployment;
    if (current == null || current.requestId != requestId) {
      throw const GnosisCardUnavailable('Unknown Safe deployment request.');
    }
    _deploymentPolls += 1;
    if (_deploymentPolls == 1) {
      return _deployment = current.copyWith(
        status: SafeDeploymentStatus.processing,
      );
    }
    if (scenario == GnosisCardScenario.deploymentFailure) {
      return _deployment = current.copyWith(
        status: SafeDeploymentStatus.failed,
        failureReason: 'The mock deployment integrity check failed.',
      );
    }
    return _deployment = current.copyWith(
      status: SafeDeploymentStatus.ok,
      safeAddress: _fixtureSafe,
      delayModule: _fixtureDelay,
    );
  }

  @override
  Future<void> validateSafeIntegrity(SafeDeployment deployment) async {
    _requireSession();
    if (deployment.status != SafeDeploymentStatus.ok ||
        deployment.safeAddress != _fixtureSafe ||
        deployment.delayModule != _fixtureDelay) {
      throw const GnosisCardUnavailable(
        'Safe deployment did not match the expected API-owned fixture.',
      );
    }
    if (_stage != GnosisOnboardingStage.ready) {
      _stage = GnosisOnboardingStage.cardIssuance;
    }
  }

  @override
  Future<GnosisPaymentCard> issueVirtualCard() async {
    _requireSession();
    const card = GnosisPaymentCard(
      id: 'card-virtual-0001',
      kind: GnosisCardKind.virtual,
      status: GnosisCardStatus.active,
      lastFour: '4242',
      label: 'Everyday card',
    );
    _dashboard = _dashboard.copyWith(cards: [card]);
    _stage = GnosisOnboardingStage.ready;
    return card;
  }

  @override
  Future<PhysicalCardOrder> orderPhysicalCard() async {
    _requireReady();
    return _physicalOrder = const PhysicalCardOrder(
      id: 'order-physical-0001',
      status: PhysicalCardOrderStatus.quoted,
      feeMinor: 999,
      currency: 'EUR',
    );
  }

  @override
  Future<PhysicalCardOrder> payAndShipPhysicalCard(String orderId) async {
    _requireReady();
    if (_physicalOrder?.id != orderId) {
      throw const GnosisCardUnavailable('Unknown physical card order.');
    }
    _physicalOrder = const PhysicalCardOrder(
      id: 'order-physical-0001',
      status: PhysicalCardOrderStatus.shipped,
      feeMinor: 999,
      currency: 'EUR',
      trackingHint: 'Mock shipment · 3–5 business days',
    );
    final cards = [
      ..._dashboard.cards,
      const GnosisPaymentCard(
        id: 'card-physical-0001',
        kind: GnosisCardKind.physical,
        status: GnosisCardStatus.ordered,
        lastFour: '8810',
        label: 'Physical card',
      ),
    ];
    _dashboard = _dashboard.copyWith(
      cards: cards,
      physicalOrder: _physicalOrder,
    );
    return _physicalOrder!;
  }

  @override
  Future<GnosisCardDashboard> dashboard() async {
    _requireReady();
    return _dashboard;
  }

  @override
  Future<GnosisCardDashboard> pollDelayedOperations() async {
    _requireReady();
    _dashboard = _dashboard.copyWith(
      operations: [
        for (final operation in _dashboard.operations)
          operation.copyWith(
            status: switch (operation.status) {
              DelayedOperationStatus.coolingDown =>
                DelayedOperationStatus.executable,
              DelayedOperationStatus.executable =>
                DelayedOperationStatus.executed,
              _ => operation.status,
            },
          ),
      ],
    );
    return _dashboard;
  }

  @override
  Future<GnosisCardDashboard> setFrozen({
    required String cardId,
    required bool frozen,
  }) async {
    _requireReady();
    return _updateCard(
      cardId,
      frozen ? GnosisCardStatus.frozen : GnosisCardStatus.active,
    );
  }

  @override
  Future<GnosisCardDashboard> setCardStatus({
    required String cardId,
    required GnosisCardStatus status,
  }) async {
    _requireReady();
    return _updateCard(cardId, status);
  }

  @override
  Future<GnosisCardDashboard> updateControls(
    GnosisCardControls controls,
  ) async {
    _requireReady();
    _dashboard = _dashboard.copyWith(controls: controls);
    return _dashboard;
  }

  @override
  Future<PreparedSmartAccountIntent> prepareWithdrawal(
    WithdrawalRequest request,
  ) async {
    _requireReady();
    final isNative = request.assetContract == _zeroAddress;
    final inner = isNative
        ? ''
        : 'a9059cbb${_addressWord(request.recipient)}'
              '${_word(request.amountAtomic)}';
    final target = isNative ? request.recipient : request.assetContract;
    final typedData = _moduleTypedData(
      _outer(
        target: target,
        value: isNative ? request.amountAtomic : BigInt.zero,
        inner: inner,
      ),
    );
    return _codec.prepare(
      typedData,
      safeAddress: _fixtureSafe,
      expectedChainId: BigInt.from(100),
      expectedDelayModule: _fixtureDelay,
      requested: SmartAccountRequestedAction.withdrawal(
        assetContract: request.assetContract,
        recipient: request.recipient,
        amount: request.amountAtomic,
      ),
    );
  }

  @override
  Future<PreparedSmartAccountIntent> prepareDailyLimit(
    DailyLimitRequest request,
  ) async {
    _requireReady();
    final inner =
        'a8ec43ee$_allowanceKey'
        '${_word(request.amountAtomic)}${_word(request.amountAtomic)}'
        '${_word(request.amountAtomic)}${_word(BigInt.from(request.periodSeconds))}'
        '${_word(BigInt.zero)}';
    return _codec.prepare(
      _moduleTypedData(_outer(target: request.bouncer, inner: inner)),
      safeAddress: _fixtureSafe,
      expectedChainId: BigInt.from(100),
      expectedDelayModule: _fixtureDelay,
      requested: SmartAccountRequestedAction.dailyLimit(
        bouncer: request.bouncer,
        amount: request.amountAtomic,
        periodSeconds: request.periodSeconds,
      ),
    );
  }

  @override
  Future<DelayedOperation> submitSignedOperation({
    required PreparedSmartAccountIntent intent,
    required SmartAccountSignature signature,
  }) async {
    _requireReady();
    if (signature.signature.isEmpty ||
        !signature.typedDataHash.startsWith('0x')) {
      throw const GnosisCardUnavailable('KDF signature response was invalid.');
    }
    final operation = DelayedOperation(
      id: 'operation-${_dashboard.operations.length + 1}',
      kind: intent.kind == SmartAccountIntentKind.withdrawal
          ? DelayedOperationKind.withdrawal
          : DelayedOperationKind.dailyLimit,
      status: DelayedOperationStatus.coolingDown,
      summary: intent.kind == SmartAccountIntentKind.withdrawal
          ? 'Withdrawal of ${intent.amount}'
          : 'Daily limit of ${intent.amount}',
      executableAt: DateTime.now().add(const Duration(minutes: 5)),
    );
    _dashboard = _dashboard.copyWith(
      operations: [operation, ..._dashboard.operations],
    );
    return operation;
  }

  GnosisCardDashboard _updateCard(String cardId, GnosisCardStatus status) {
    final index = _dashboard.cards.indexWhere((card) => card.id == cardId);
    if (index < 0) throw const GnosisCardUnavailable('Card was not found.');
    final cards = [..._dashboard.cards];
    cards[index] = cards[index].copyWith(status: status);
    _dashboard = _dashboard.copyWith(cards: cards);
    return _dashboard;
  }

  void _requireOnline() {
    if (scenario == GnosisCardScenario.offline) {
      throw const GnosisCardUnavailable(
        'Card services are offline. Check your connection and retry.',
      );
    }
  }

  void _requireSession() {
    _requireOnline();
    if (_session == null || _session!.isExpired) {
      _stage = GnosisOnboardingStage.signedOut;
      throw const GnosisCardUnavailable(
        'Your card session expired. Sign in again to continue.',
      );
    }
  }

  void _requireReady() {
    _requireSession();
    if (_stage != GnosisOnboardingStage.ready) {
      throw const GnosisCardUnavailable('Card onboarding is not complete.');
    }
  }
}

GnosisCardDashboard _initialDashboard() => GnosisCardDashboard(
  balanceMinor: 184250,
  currency: 'EUR',
  dailyLimitMinor: 150000,
  cards: const [],
  controls: const GnosisCardControls(
    contactless: true,
    online: true,
    atm: false,
  ),
  transactions: [
    GnosisCardTransaction(
      id: 'tx-1',
      merchant: 'City Market',
      amountMinor: -4235,
      currency: 'EUR',
      occurredAt: DateTime(2026, 7, 9, 17, 42),
      isDeclined: false,
    ),
    GnosisCardTransaction(
      id: 'tx-2',
      merchant: 'Rail Europe',
      amountMinor: -7890,
      currency: 'EUR',
      occurredAt: DateTime(2026, 7, 8, 9, 15),
      isDeclined: false,
    ),
  ],
  operations: const [],
);

Map<String, dynamic> _moduleTypedData(String data) => {
  'primaryType': 'ModuleTx',
  'domain': {'chainId': 100, 'verifyingContract': _fixtureDelay},
  'types': {
    'ModuleTx': [
      {'name': 'data', 'type': 'bytes'},
      {'name': 'salt', 'type': 'bytes32'},
    ],
  },
  'message': {'data': data, 'salt': '0x${_repeat('11', 32)}'},
};

String _outer({required String target, required String inner, BigInt? value}) {
  final byteLength = inner.length ~/ 2;
  final padding = _repeat('00', (32 - (byteLength % 32)) % 32);
  return '0x468721a7${_addressWord(target)}${_word(value ?? BigInt.zero)}'
      '${_word(BigInt.from(128))}${_word(BigInt.zero)}'
      '${_word(BigInt.from(byteLength))}$inner$padding';
}

String _addressWord(String address) => address.substring(2).padLeft(64, '0');
String _word(BigInt value) => value.toRadixString(16).padLeft(64, '0');
String _repeat(String value, int count) => List.filled(count, value).join();

const _zeroAddress = '0x0000000000000000000000000000000000000000';
const _allowanceKey =
    'fe687fc128d1915040376d20ccb1bf40d838ddd82bf9b0ba3da683cc2a251623';
