import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:web_dex/features/gnosis_card/application/gnosis_card_bloc.dart';
import 'package:web_dex/features/gnosis_card/application/gnosis_card_coordinator.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_models.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_ports.dart';
import 'package:web_dex/features/gnosis_card/infrastructure/deterministic_gnosis_pay_repository.dart';
import 'package:web_dex/features/gnosis_card/infrastructure/gnosis_card_config.dart';
import 'package:web_dex/features/gnosis_card/infrastructure/kdf_smart_account_signer.dart';
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
    this.coordinator,
  });

  factory GnosisCardDependencies.forAdapters({
    required GnosisCardConfig config,
    required CardSecureElementGateway secureElement,
    ExternalFlowLauncher externalFlowLauncher = const UrlExternalFlowLauncher(),
    CardOrderPaymentGateway paymentGateway =
        const SyntheticCardOrderPaymentGateway(),
    GnosisCardCoordinator? coordinator,
  }) => GnosisCardDependencies._(
    config: config,
    externalFlowLauncher: externalFlowLauncher,
    paymentGateway: paymentGateway,
    secureElement: secureElement,
    coordinator: coordinator,
  );

  factory GnosisCardDependencies.fromEnvironment(KomodoDefiSdk sdk) {
    final config = GnosisCardConfig.fromEnvironment();
    const externalFlowLauncher = UrlExternalFlowLauncher();
    const paymentGateway = SyntheticCardOrderPaymentGateway();
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
    final signer = KdfSmartAccountSigner(sdk);
    return GnosisCardDependencies._(
      config: config,
      externalFlowLauncher: externalFlowLauncher,
      paymentGateway: paymentGateway,
      secureElement: const SyntheticSecureElementGateway(),
      coordinator: GnosisCardCoordinator(
        repository: repository,
        signer: signer,
        externalFlowLauncher: externalFlowLauncher,
        paymentGateway: paymentGateway,
      ),
    );
  }

  final GnosisCardConfig config;
  final ExternalFlowLauncher externalFlowLauncher;
  final CardOrderPaymentGateway paymentGateway;
  final CardSecureElementGateway secureElement;
  final GnosisCardCoordinator? coordinator;

  GnosisCardBloc createBloc() =>
      GnosisCardBloc(config: config, coordinator: coordinator);
}
