import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:web_dex/features/gnosis_card/application/gnosis_card_bloc.dart';
import 'package:web_dex/features/gnosis_card/application/gnosis_card_coordinator.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_models.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_ports.dart';
import 'package:web_dex/features/gnosis_card/infrastructure/deterministic_gnosis_pay_repository.dart';
import 'package:web_dex/features/gnosis_card/infrastructure/gnosis_card_config.dart';
import 'package:web_dex/features/gnosis_card/infrastructure/kdf_smart_account_signer.dart';
import 'package:web_dex/features/gnosis_card/infrastructure/synthetic_secure_element_gateway.dart';

/// Small composition factory. Live mode intentionally has no binding yet and
/// is converted to disabled by [GnosisCardConfig].
class GnosisCardDependencies {
  GnosisCardDependencies._({
    required this.config,
    required this.secureElement,
    this.coordinator,
  });

  factory GnosisCardDependencies.forAdapters({
    required GnosisCardConfig config,
    required CardSecureElementGateway secureElement,
    GnosisCardCoordinator? coordinator,
  }) => GnosisCardDependencies._(
    config: config,
    secureElement: secureElement,
    coordinator: coordinator,
  );

  factory GnosisCardDependencies.fromEnvironment(KomodoDefiSdk sdk) {
    final config = GnosisCardConfig.fromEnvironment();
    if (config.mode != GnosisCardMode.mock) {
      return GnosisCardDependencies._(
        config: config,
        secureElement: const SyntheticSecureElementGateway(),
      );
    }
    final repository = DeterministicGnosisPayRepository(
      scenario: config.scenario,
    );
    final signer = KdfSmartAccountSigner(sdk);
    return GnosisCardDependencies._(
      config: config,
      secureElement: const SyntheticSecureElementGateway(),
      coordinator: GnosisCardCoordinator(
        repository: repository,
        signer: signer,
      ),
    );
  }

  final GnosisCardConfig config;
  final CardSecureElementGateway secureElement;
  final GnosisCardCoordinator? coordinator;

  GnosisCardBloc createBloc() =>
      GnosisCardBloc(config: config, coordinator: coordinator);
}
