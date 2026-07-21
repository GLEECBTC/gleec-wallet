import 'dart:async';

import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_models.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_ports.dart';
import 'package:web_dex/features/gnosis_card/infrastructure/gnosis_card_config.dart';

part 'deterministic_gnosis_pay_authentication.dart';
part 'deterministic_gnosis_pay_identity.dart';
part 'deterministic_gnosis_pay_card_orders.dart';
part 'deterministic_gnosis_pay_dashboard.dart';
part 'deterministic_gnosis_pay_support.dart';

const _fixtureSafe = '0x1111111111111111111111111111111111111111';
const _fixtureMigratedSafe = '0x5555555555555555555555555555555555555555';
const _fixturePreviousSafe = '0x6666666666666666666666666666666666666666';
const _fixtureDelay = '0x2222222222222222222222222222222222222222';
const _fixtureUsdc = '0x3333333333333333333333333333333333333333';
const _fixtureEure = '0x8888888888888888888888888888888888888888';
const _fixtureDailyLimitTarget = '0x7777777777777777777777777777777777777777';
const _verifiedCountry = 'DE';
const _defaultTerms = [
  GnosisTerm(
    id: 'card-terms',
    title: 'Gnosis Pay Cardholder Terms',
    version: '2026-06',
    documentUrl: 'https://mock.gnosispay.com/legal/cardholder-terms',
    isAccepted: false,
  ),
  GnosisTerm(
    id: 'privacy-notice',
    title: 'Gnosis Pay Privacy Notice',
    version: '2026-05',
    documentUrl: 'https://mock.gnosispay.com/legal/privacy',
    isAccepted: false,
  ),
];

abstract class _DeterministicGnosisPayRepositoryState {
  _DeterministicGnosisPayRepositoryState({
    required this.scenario,
    required SmartAccountIntentCodec codec,
  }) : _codec = codec;
  final GnosisCardScenario scenario;
  final SmartAccountIntentCodec _codec;

  bool _isAuthenticated = false;
  bool _isRegistered = false;
  bool _isSourceOfFundsAnswered = false;
  bool _isPhoneValidated = false;
  bool _isPhysicalOrderReviewed = false;
  bool _isPinProvisioned = false;
  String? _stateOwnerAddress;
  String? _email;
  String? _phoneNumber;
  GnosisCardSession? _session;
  GnosisKycStatus _kycStatus = GnosisKycStatus.notStarted;
  PhoneOtpChallenge? _phoneChallenge;
  SafeDeployment? _deployment;
  SafeConfiguration? _safeConfiguration;
  GnosisCardProduct? _selectedProduct;
  PhysicalCardOrder? _physicalOrder;
  CardOrderPaymentReceipt? _paymentReceipt;
  CardProvisioningHandle? _provisioningHandle;
  int _deploymentPolls = 0;
  bool _kycLaunched = false;
  bool _kycResubmissionShown = false;
  bool _kycRecoveryOpened = false;
  bool _offlineFailureConsumed = false;
  bool _expiredSessionConsumed = false;
  bool _invalidOtpConsumed = false;
  bool _deploymentFailureConsumed = false;
  bool _integrityFailureConsumed = false;
  bool _paymentFailureConsumed = false;
  bool _issuanceFailureConsumed = false;
  bool _transientServiceFailureConsumed = false;
  var _nonceSequence = 0;
  var _migrationPolls = 0;
  var _intentSequence = 0;
  final Map<String, GnosisSiweChallenge> _outstandingChallenges = {};
  final Set<String> _usedNonces = {};
  final Map<String, String> _signatureApprovals = {};
  final Map<String, DelayedOperation> _submittedOperations = {};

  List<GnosisTerm> _terms = List.of(_defaultTerms);

  final List<GnosisCardProduct> _products = const [
    GnosisCardProduct(
      id: 'virtual-eur',
      kind: GnosisCardKind.virtual,
      title: 'Virtual card',
      description: 'Instant digital card',
      feeMinor: 0,
      currency: 'EUR',
      requiresShipping: false,
      requiresPin: false,
    ),
    GnosisCardProduct(
      id: 'physical-eur',
      kind: GnosisCardKind.physical,
      title: 'Physical card',
      description: 'Physical contactless card',
      feeMinor: 999,
      currency: 'EUR',
      requiresShipping: true,
      requiresPin: true,
    ),
  ];

  late GnosisCardDashboard _dashboard = _initialDashboard(
    emptyActivity: scenario == GnosisCardScenario.emptyActivity,
  );
}

/// In-memory, API-shaped mock. It deliberately excludes every secret card
/// value and persists only for the lifetime of the root dependency graph.
class DeterministicGnosisPayRepository
    extends _DeterministicGnosisPayRepositoryState
    with
        _DeterministicGnosisPaySupport,
        _DeterministicGnosisPayAuthentication,
        _DeterministicGnosisPayIdentity,
        _DeterministicGnosisPayCardOrders,
        _DeterministicGnosisPayDashboard
    implements GnosisPayRepository, GnosisSafeMigrationRepository {
  DeterministicGnosisPayRepository({
    required super.scenario,
    super.codec = const SmartAccountIntentCodec(),
  });
}
