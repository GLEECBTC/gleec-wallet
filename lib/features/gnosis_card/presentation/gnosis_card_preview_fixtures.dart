part of 'gnosis_card_preview.dart';

GnosisKycStatus _kycForFixture(GnosisCardPreviewFixture fixture) =>
    switch (fixture) {
      GnosisCardPreviewFixture.kycNotStarted => GnosisKycStatus.notStarted,
      GnosisCardPreviewFixture.kycDocumentsRequested =>
        GnosisKycStatus.documentsRequested,
      GnosisCardPreviewFixture.kycPending => GnosisKycStatus.pending,
      GnosisCardPreviewFixture.kycProcessing => GnosisKycStatus.processing,
      GnosisCardPreviewFixture.kycResubmission =>
        GnosisKycStatus.resubmissionRequested,
      GnosisCardPreviewFixture.kycRejected => GnosisKycStatus.rejected,
      GnosisCardPreviewFixture.kycRequiresAction =>
        GnosisKycStatus.requiresAction,
      _ =>
        _stageForFixture(fixture) == GnosisOnboardingStage.kyc
            ? GnosisKycStatus.notStarted
            : GnosisKycStatus.approved,
    };

bool _identityComplete(GnosisOnboardingStage stage) => switch (stage) {
  GnosisOnboardingStage.safeDeployment ||
  GnosisOnboardingStage.cardSelection ||
  GnosisOnboardingStage.virtualCardIssuance ||
  GnosisOnboardingStage.physicalShipping ||
  GnosisOnboardingStage.physicalOrderReview ||
  GnosisOnboardingStage.physicalPayment ||
  GnosisOnboardingStage.physicalCardCreation ||
  GnosisOnboardingStage.physicalPin ||
  GnosisOnboardingStage.ready => true,
  _ => false,
};

bool _safeComplete(GnosisOnboardingStage stage) => switch (stage) {
  GnosisOnboardingStage.cardSelection ||
  GnosisOnboardingStage.virtualCardIssuance ||
  GnosisOnboardingStage.physicalShipping ||
  GnosisOnboardingStage.physicalOrderReview ||
  GnosisOnboardingStage.physicalPayment ||
  GnosisOnboardingStage.physicalCardCreation ||
  GnosisOnboardingStage.physicalPin ||
  GnosisOnboardingStage.ready => true,
  _ => false,
};

bool _isPhysicalStage(GnosisOnboardingStage stage) => switch (stage) {
  GnosisOnboardingStage.physicalShipping ||
  GnosisOnboardingStage.physicalOrderReview ||
  GnosisOnboardingStage.physicalPayment ||
  GnosisOnboardingStage.physicalCardCreation ||
  GnosisOnboardingStage.physicalPin => true,
  _ => false,
};

PhysicalCardOrder? _orderFor(GnosisOnboardingStage stage) {
  final status = switch (stage) {
    GnosisOnboardingStage.physicalOrderReview ||
    GnosisOnboardingStage.physicalPayment =>
      PhysicalCardOrderStatus.pendingTransaction,
    GnosisOnboardingStage.physicalCardCreation => PhysicalCardOrderStatus.ready,
    GnosisOnboardingStage.physicalPin => PhysicalCardOrderStatus.cardCreated,
    _ => null,
  };
  if (status == null) return null;
  return PhysicalCardOrder(
    id: 'preview-order',
    createdAt: DateTime(2026, 7, 14, 12),
    status: status,
    totalAmountMinor: 999,
    totalDiscountMinor: 0,
    currency: 'EUR',
    embossedName: 'Alex Morgan',
    shippingAddress: _previewAddress,
  );
}

CardOrderPaymentReceipt? _receiptFor(
  GnosisOnboardingStage stage,
  PhysicalCardOrder? order,
) => switch (stage) {
  GnosisOnboardingStage.physicalCardCreation ||
  GnosisOnboardingStage.physicalPin => CardOrderPaymentReceipt(
    orderId: order!.id,
    transactionHash: '0xpreview-synthetic-receipt',
    amountMinor: 999,
    currency: 'EUR',
    paidAt: DateTime(2026, 7, 14, 12, 5),
    isSimulated: true,
  ),
  _ => null,
};

GnosisPaymentCard? _cardFor(
  GnosisOnboardingStage stage,
  GnosisCardPreviewFixture fixture,
) => switch (stage) {
  GnosisOnboardingStage.physicalPin => const GnosisPaymentCard(
    id: 'preview-physical-card',
    kind: GnosisCardKind.physical,
    status: GnosisCardStatus.ordered,
    lastFour: '8810',
    label: 'Physical card',
  ),
  GnosisOnboardingStage.ready => GnosisPaymentCard(
    id:
        const {
          GnosisCardPreviewFixture.dashboardOrdered,
          GnosisCardPreviewFixture.dashboardShipped,
          GnosisCardPreviewFixture.dashboardActivatable,
        }.contains(fixture)
        ? 'preview-physical-card'
        : 'preview-virtual-card',
    kind:
        const {
          GnosisCardPreviewFixture.dashboardOrdered,
          GnosisCardPreviewFixture.dashboardShipped,
          GnosisCardPreviewFixture.dashboardActivatable,
        }.contains(fixture)
        ? GnosisCardKind.physical
        : GnosisCardKind.virtual,
    status: _statusForFixture(fixture),
    lastFour:
        const {
          GnosisCardPreviewFixture.dashboardOrdered,
          GnosisCardPreviewFixture.dashboardShipped,
          GnosisCardPreviewFixture.dashboardActivatable,
        }.contains(fixture)
        ? '8810'
        : '4242',
    label:
        const {
          GnosisCardPreviewFixture.dashboardOrdered,
          GnosisCardPreviewFixture.dashboardShipped,
          GnosisCardPreviewFixture.dashboardActivatable,
        }.contains(fixture)
        ? 'Physical card'
        : 'Everyday card',
    isActivatable: fixture == GnosisCardPreviewFixture.dashboardActivatable,
  ),
  _ => null,
};

GnosisCardStatus _statusForFixture(GnosisCardPreviewFixture fixture) =>
    switch (fixture) {
      GnosisCardPreviewFixture.dashboardOrdered => GnosisCardStatus.ordered,
      GnosisCardPreviewFixture.dashboardShipped ||
      GnosisCardPreviewFixture.dashboardActivatable => GnosisCardStatus.shipped,
      GnosisCardPreviewFixture.dashboardFrozen => GnosisCardStatus.frozen,
      GnosisCardPreviewFixture.dashboardLost => GnosisCardStatus.lost,
      GnosisCardPreviewFixture.dashboardStolen => GnosisCardStatus.stolen,
      GnosisCardPreviewFixture.dashboardVoided => GnosisCardStatus.voided,
      _ => GnosisCardStatus.active,
    };

List<GnosisTerm> _previewTerms({required bool accepted}) => [
  GnosisTerm(
    id: 'preview-terms',
    title: 'Gnosis Pay Cardholder Terms',
    version: '2026-06',
    documentUrl: 'https://mock.gnosispay.com/legal/cardholder-terms',
    isAccepted: accepted,
  ),
  GnosisTerm(
    id: 'preview-privacy',
    title: 'Gnosis Pay Privacy Notice',
    version: '2026-05',
    documentUrl: 'https://mock.gnosispay.com/legal/privacy',
    isAccepted: accepted,
  ),
];

const _sourceQuestions = [
  SourceOfFundsQuestion(
    id: 'preview-source',
    title: 'What is the primary source of funds for this card?',
    answers: ['Salary', 'Savings', 'Investments', 'Business income'],
  ),
];

const _virtualProduct = GnosisCardProduct(
  id: 'virtual-eur',
  kind: GnosisCardKind.virtual,
  title: 'Virtual card',
  description: 'Instant digital card',
  feeMinor: 0,
  currency: 'EUR',
  requiresShipping: false,
  requiresPin: false,
);

const _physicalProduct = GnosisCardProduct(
  id: 'physical-eur',
  kind: GnosisCardKind.physical,
  title: 'Physical card',
  description: 'Physical contactless card',
  feeMinor: 999,
  currency: 'EUR',
  requiresShipping: true,
  requiresPin: true,
);

const _previewOwner = '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

const _previewAddress = ShippingAddress(
  recipientName: 'Alex Morgan',
  address1: '12 Example Strasse',
  city: 'Berlin',
  postalCode: '10115',
  country: 'DE',
);

final _previewSiweIssuedAt = DateTime.utc(2026, 7, 16, 10);
final _previewSiweExpiresAt = DateTime.utc(2030, 7, 16, 10);

final _previewSiweChallenge = GnosisSiweChallenge(
  message:
      'gleec.app wants you to sign in with your Ethereum account:\n'
      '$_previewOwner\n\n'
      'Sign in to your Gleec card account. No transaction is sent.\n\n'
      'URI: https://gleec.app/card\nVersion: 1\nChain ID: 100\n'
      'Nonce: previewnonce2026\n'
      'Issued At: ${_previewSiweIssuedAt.toIso8601String()}\n'
      'Expiration Time: ${_previewSiweExpiresAt.toIso8601String()}',
  ownerAddress: _previewOwner,
  domain: 'gleec.app',
  uri: Uri.parse('https://gleec.app/card'),
  nonce: 'previewnonce2026',
  chainId: 100,
  issuedAt: _previewSiweIssuedAt,
  expiresAt: _previewSiweExpiresAt,
);

const _previewMigration = GnosisSafeMigration(
  migrationId: 'preview-migration',
  status: GnosisSafeMigrationStatus.completed,
  previousSafe: GnosisSafeReference(
    address: '0x6666666666666666666666666666666666666666',
    chainId: 100,
    tokenSymbol: 'EURe',
  ),
  currentSafe: GnosisSafeReference(
    address: '0x5555555555555555555555555555555555555555',
    chainId: 100,
    tokenSymbol: 'EURe',
  ),
);

final _previewDeploymentOk = SafeDeployment(
  requestId: 'preview-deployment',
  ownerAddress: _previewOwner,
  status: SafeDeploymentStatus.ok,
  updatedAt: DateTime(2026, 7, 14, 12),
);

const _previewSafeConfiguration = SafeConfiguration(
  ownerAddress: _previewOwner,
  isDeployed: true,
  integrity: SafeAccountIntegrity.delayQueueNotEmpty,
  safeAddress: '0x1111111111111111111111111111111111111111',
  delayModule: '0x2222222222222222222222222222222222222222',
  tokenSymbol: 'EURe',
  fiatSymbol: 'EUR',
);

const _previewMigratedSafeConfiguration = SafeConfiguration(
  ownerAddress: _previewOwner,
  isDeployed: true,
  integrity: SafeAccountIntegrity.delayQueueNotEmpty,
  safeAddress: '0x5555555555555555555555555555555555555555',
  delayModule: '0x2222222222222222222222222222222222222222',
  tokenSymbol: 'EURe',
  fiatSymbol: 'EUR',
);

const _previewInvalidSafeConfiguration = SafeConfiguration(
  ownerAddress: _previewOwner,
  isDeployed: true,
  integrity: SafeAccountIntegrity.safeMisconfigured,
  safeAddress: '0x1111111111111111111111111111111111111111',
  delayModule: '0x2222222222222222222222222222222222222222',
  tokenSymbol: 'EURe',
  fiatSymbol: 'EUR',
);

const _previewQuote = CardOrderPaymentQuote(
  orderId: 'preview-order',
  amountMinor: 999,
  currency: 'EUR',
  assetSymbol: 'EURe',
  assetContract: '0x3333333333333333333333333333333333333333',
  recipient: '0x4444444444444444444444444444444444444444',
  isSimulated: true,
);

final _previewDashboard = GnosisCardDashboard(
  balanceMinor: 184250,
  pendingBalanceMinor: 1230,
  currency: 'EUR',
  dailyLimitMinor: 150000,
  withdrawalAssets: const [
    GnosisCardAsset(
      symbol: 'USDC',
      contractAddress: '0x3333333333333333333333333333333333333333',
      decimals: 6,
      chainId: 100,
    ),
  ],
  dailyLimitTarget: '0x7777777777777777777777777777777777777777',
  dailyLimitAsset: const GnosisCardAsset(
    symbol: 'EURe',
    contractAddress: '0x8888888888888888888888888888888888888888',
    decimals: 6,
    chainId: 100,
  ),
  cards: const [
    GnosisPaymentCard(
      id: 'preview-virtual-card',
      kind: GnosisCardKind.virtual,
      status: GnosisCardStatus.active,
      lastFour: '4242',
      label: 'Everyday card',
    ),
  ],
  controls: const GnosisCardControls(
    contactless: true,
    online: true,
    atm: false,
  ),
  transactions: [
    GnosisCardTransaction(
      id: 'preview-tx',
      merchant: 'City Market',
      amountMinor: -4235,
      currency: 'EUR',
      occurredAt: DateTime(2026, 7, 9, 17, 42),
      isDeclined: false,
    ),
  ],
  operations: const [],
);

GnosisCardDashboard _dashboardForFixture(
  GnosisCardPreviewFixture fixture,
  GnosisPaymentCard card,
) => GnosisCardDashboard(
  balanceMinor: _previewDashboard.balanceMinor,
  pendingBalanceMinor: _previewDashboard.pendingBalanceMinor,
  currency: _previewDashboard.currency,
  dailyLimitMinor: _previewDashboard.dailyLimitMinor,
  withdrawalAssets: _previewDashboard.withdrawalAssets,
  dailyLimitTarget: _previewDashboard.dailyLimitTarget,
  dailyLimitAsset: _previewDashboard.dailyLimitAsset,
  cards: [card],
  controls: _previewDashboard.controls,
  transactions: fixture == GnosisCardPreviewFixture.dashboardEmpty
      ? const []
      : _previewDashboard.transactions,
  operations: _previewDashboard.operations,
);

class _PreviewExternalFlowLauncher implements ExternalFlowLauncher {
  const _PreviewExternalFlowLauncher();

  @override
  Future<void> launch(GnosisExternalFlow flow) async {}
}
