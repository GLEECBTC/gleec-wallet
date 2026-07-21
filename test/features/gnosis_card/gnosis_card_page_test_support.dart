part of 'gnosis_card_page_test.dart';

GnosisCardCoordinator _coordinator(
  DeterministicGnosisPayRepository repository,
  GnosisTestSigner signer,
  RecordingExternalFlowLauncher launcher,
  GnosisTestPaymentGateway payment,
) => GnosisCardCoordinator(
  repository: repository,
  signer: signer,
  externalFlowLauncher: launcher,
  paymentGateway: payment,
);

Widget _pageApp(
  GnosisCardBloc bloc,
  GnosisCardDependencies dependencies, {
  ScreenshotSensitivityController? sensitivity,
  bool manageLifecycle = true,
}) {
  Widget child = _localizedApp(
    RepositoryProvider.value(
      value: dependencies,
      child: BlocProvider.value(
        value: bloc,
        child: Scaffold(body: GnosisCardPage(manageLifecycle: manageLifecycle)),
      ),
    ),
  );
  if (sensitivity != null) {
    child = ScreenshotSensitivity(controller: sensitivity, child: child);
  }
  return child;
}

Widget _stepApp(
  Widget child, {
  TextScaler textScaler = TextScaler.noScaling,
  bool disableAnimations = false,
}) => _localizedApp(
  Scaffold(body: child),
  textScaler: textScaler,
  disableAnimations: disableAnimations,
);

Widget _localizedApp(
  Widget home, {
  TextScaler textScaler = TextScaler.noScaling,
  bool disableAnimations = false,
}) => EasyLocalization(
  supportedLocales: const [Locale('en')],
  fallbackLocale: const Locale('en'),
  useOnlyLangCode: true,
  path: '$assetsPath/translations',
  child: Builder(
    builder: (context) => MaterialApp(
      locale: context.locale,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      theme: theme.global.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: textScaler,
          disableAnimations: disableAnimations,
        ),
        child: child!,
      ),
      home: home,
    ),
  ),
);

void _setViewSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

GnosisOnboardingProgress _safeProgress({SafeDeployment? deployment}) =>
    GnosisOnboardingProgress(
      isAuthenticated: true,
      isRegistered: true,
      email: 'cardholder@example.test',
      countryCode: 'DE',
      phoneCountryCallingCode: '+49',
      terms: _acceptedTerms,
      kycStatus: GnosisKycStatus.approved,
      isSourceOfFundsAnswered: true,
      phoneNumber: '+4915123456789',
      isPhoneValidated: true,
      phoneChallenge: null,
      safeDeployment: deployment,
      safeConfiguration: null,
      isSafeRegistered: false,
      selectedProduct: null,
      physicalOrder: null,
      isPhysicalOrderReviewed: false,
      paymentReceipt: null,
      provisioningHandle: null,
      isPinProvisioned: false,
      cards: const [],
    );

GnosisOnboardingProgress _physicalProgress({
  required PhysicalCardOrderStatus orderStatus,
  CardOrderPaymentReceipt? receipt,
  CardProvisioningHandle? provisioningHandle,
  List<GnosisPaymentCard> cards = const [],
}) => GnosisOnboardingProgress(
  isAuthenticated: true,
  isRegistered: true,
  email: 'cardholder@example.test',
  countryCode: 'DE',
  phoneCountryCallingCode: '+49',
  terms: _acceptedTerms,
  kycStatus: GnosisKycStatus.approved,
  isSourceOfFundsAnswered: true,
  phoneNumber: '+4915123456789',
  isPhoneValidated: true,
  phoneChallenge: null,
  safeDeployment: _safeDeployment,
  safeConfiguration: _safeConfiguration,
  isSafeRegistered: true,
  selectedProduct: _physicalProduct,
  physicalOrder: _physicalOrder(orderStatus),
  isPhysicalOrderReviewed: true,
  paymentReceipt: receipt,
  provisioningHandle: provisioningHandle,
  isPinProvisioned: false,
  cards: cards,
);

PhysicalCardOrder _physicalOrder(PhysicalCardOrderStatus status) =>
    PhysicalCardOrder(
      id: 'physical-order',
      createdAt: DateTime.utc(2026, 7, 14, 12),
      status: status,
      totalAmountMinor: 999,
      totalDiscountMinor: 0,
      currency: 'EUR',
      embossedName: 'Test Cardholder',
      shippingAddress: const ShippingAddress(
        recipientName: 'Test Cardholder',
        address1: '12 Test Street',
        city: 'Berlin',
        postalCode: '10115',
        country: 'DE',
      ),
      transactionHash: '0xtest-synthetic-receipt',
    );

const _owner = '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

const _acceptedTerms = [
  GnosisTerm(
    id: 'terms',
    title: 'Card agreement',
    version: '2026-07',
    documentUrl: 'https://example.test/card-agreement',
    isAccepted: true,
  ),
];

const _virtualProduct = GnosisCardProduct(
  id: 'virtual',
  kind: GnosisCardKind.virtual,
  title: 'Virtual card',
  description: 'Test virtual product',
  feeMinor: 0,
  currency: 'EUR',
  requiresShipping: false,
  requiresPin: false,
);

const _physicalProduct = GnosisCardProduct(
  id: 'physical',
  kind: GnosisCardKind.physical,
  title: 'Physical card',
  description: 'Test physical product',
  feeMinor: 999,
  currency: 'EUR',
  requiresShipping: true,
  requiresPin: true,
);

final _safeDeployment = SafeDeployment(
  requestId: 'deployment',
  ownerAddress: _owner,
  status: SafeDeploymentStatus.ok,
  updatedAt: DateTime.utc(2026, 7, 14, 12),
);

const _safeConfiguration = SafeConfiguration(
  ownerAddress: _owner,
  isDeployed: true,
  integrity: SafeAccountIntegrity.ok,
  safeAddress: '0x1111111111111111111111111111111111111111',
  delayModule: '0x2222222222222222222222222222222222222222',
  tokenSymbol: 'EURe',
  fiatSymbol: 'EUR',
);

const _paymentQuote = CardOrderPaymentQuote(
  orderId: 'physical-order',
  amountMinor: 999,
  currency: 'EUR',
  assetSymbol: 'EURe',
  assetContract: '0x3333333333333333333333333333333333333333',
  recipient: '0x4444444444444444444444444444444444444444',
  isSimulated: true,
);

final _paymentReceipt = CardOrderPaymentReceipt(
  orderId: 'physical-order',
  transactionHash: '0xtest-synthetic-receipt',
  amountMinor: 999,
  currency: 'EUR',
  paidAt: DateTime.utc(2026, 7, 14, 12),
  isSimulated: true,
);
