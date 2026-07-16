import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/features/gnosis_card/application/gnosis_card_bloc.dart';
import 'package:web_dex/features/gnosis_card/application/gnosis_card_coordinator.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_models.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_ports.dart';
import 'package:web_dex/features/gnosis_card/infrastructure/deterministic_gnosis_pay_repository.dart';
import 'package:web_dex/features/gnosis_card/infrastructure/gnosis_card_config.dart';
import 'package:web_dex/features/gnosis_card/infrastructure/kdf_smart_account_signer.dart';
import 'package:web_dex/features/gnosis_card/infrastructure/kdf_wallet_identity_source.dart';
import 'package:web_dex/features/gnosis_card/infrastructure/shared_preferences_gnosis_migration_notice_store.dart';
import 'package:web_dex/features/gnosis_card/infrastructure/synthetic_card_order_payment_gateway.dart';
import 'package:web_dex/features/gnosis_card/infrastructure/synthetic_secure_element_gateway.dart';
import 'package:web_dex/features/gnosis_card/infrastructure/url_external_flow_launcher.dart';

/// Small composition factory. Live mode intentionally has no binding yet and
/// is converted to disabled by [GnosisCardConfig].
class GnosisCardDependencies {
  GnosisCardDependencies._({
    required this.config,
    required this.externalFlowLauncher,
    required this.paymentGateway,
    required this.secureElement,
    this.identitySource,
    this.migrationNoticeStore,
    this.coordinator,
  });

  factory GnosisCardDependencies.forAdapters({
    required GnosisCardConfig config,
    required CardSecureElementGateway secureElement,
    ExternalFlowLauncher externalFlowLauncher = const UrlExternalFlowLauncher(),
    CardOrderPaymentGateway? paymentGateway,
    GnosisCardCoordinator? coordinator,
    GnosisWalletIdentitySource? identitySource,
    GnosisMigrationNoticeStore? migrationNoticeStore,
  }) => GnosisCardDependencies._(
    config: config,
    externalFlowLauncher: externalFlowLauncher,
    paymentGateway: paymentGateway ?? SyntheticCardOrderPaymentGateway(),
    secureElement: secureElement,
    identitySource: identitySource,
    migrationNoticeStore: migrationNoticeStore,
    coordinator: coordinator,
  );

  factory GnosisCardDependencies.fromEnvironment(
    KomodoDefiSdk sdk,
    CoinsRepo coinsRepository,
  ) {
    final config = GnosisCardConfig.fromEnvironment();
    const externalFlowLauncher = UrlExternalFlowLauncher();
    final paymentGateway = SyntheticCardOrderPaymentGateway();
    if (config.mode != GnosisCardMode.mock) {
      return GnosisCardDependencies._(
        config: config,
        externalFlowLauncher: externalFlowLauncher,
        paymentGateway: paymentGateway,
        secureElement: const SyntheticSecureElementGateway(),
      );
    }
    final repository = DeterministicGnosisPayRepository(
      scenario: config.scenario,
    );
    final signer = KdfSmartAccountSigner(sdk, coinsRepository: coinsRepository);
    final readiness = _ScenarioWalletReadiness(signer, config.scenario);
    final identitySource = KdfWalletIdentitySource(sdk);
    final migrationNoticeStore = SharedPreferencesGnosisMigrationNoticeStore();
    return GnosisCardDependencies._(
      config: config,
      externalFlowLauncher: externalFlowLauncher,
      paymentGateway: paymentGateway,
      secureElement: const SyntheticSecureElementGateway(),
      identitySource: identitySource,
      migrationNoticeStore: migrationNoticeStore,
      coordinator: GnosisCardCoordinator(
        repository: repository,
        signer: signer,
        externalFlowLauncher: externalFlowLauncher,
        paymentGateway: paymentGateway,
        readiness: readiness,
      ),
    );
  }

  final GnosisCardConfig config;
  final ExternalFlowLauncher externalFlowLauncher;
  final CardOrderPaymentGateway paymentGateway;
  final CardSecureElementGateway secureElement;
  final GnosisWalletIdentitySource? identitySource;
  final GnosisMigrationNoticeStore? migrationNoticeStore;
  final GnosisCardCoordinator? coordinator;

  GnosisCardBloc createBloc() => GnosisCardBloc(
    config: config,
    coordinator: coordinator,
    identitySource: identitySource,
    migrationNoticeStore: migrationNoticeStore,
  );
}

class _ScenarioWalletReadiness implements GnosisWalletReadiness {
  _ScenarioWalletReadiness(this.delegate, this.scenario);

  final GnosisWalletReadiness delegate;
  final GnosisCardScenario scenario;
  var _activationFailureConsumed = false;

  @override
  void invalidate() => delegate.invalidate();

  @override
  Future<SmartAccountOwner> ensureReady() async {
    if (scenario == GnosisCardScenario.lockedWallet) {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.walletLocked,
        message: 'Unlock your wallet to continue.',
        recovery: GnosisCardRecovery.retry,
      );
    }
    if (scenario == GnosisCardScenario.wrongChain) {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.wrongChain,
        message: 'The card signer is not configured for Gnosis Chain.',
        recovery: GnosisCardRecovery.none,
        isRecoverable: false,
      );
    }
    if (scenario == GnosisCardScenario.activationFailure &&
        !_activationFailureConsumed) {
      _activationFailureConsumed = true;
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.activationFailed,
        message: 'Gnosis Chain could not be prepared.',
        recovery: GnosisCardRecovery.retry,
      );
    }
    return delegate.ensureReady();
  }
}
