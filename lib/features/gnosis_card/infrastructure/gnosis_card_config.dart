import 'package:flutter/foundation.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_models.dart';

enum GnosisCardScenario {
  happyPath,
  deploymentFailure,
  kycExpired,
  offline,
  expiredSession,
}

class GnosisCardConfig {
  const GnosisCardConfig({
    required this.mode,
    required this.scenario,
    required this.failureReason,
  });

  factory GnosisCardConfig.fromEnvironment() {
    const modeValue = String.fromEnvironment(
      'GNOSIS_CARD_MODE',
      defaultValue: 'disabled',
    );
    const scenarioValue = String.fromEnvironment(
      'GNOSIS_CARD_SCENARIO',
      defaultValue: 'happyPath',
    );
    final requestedMode = GnosisCardMode.values.firstWhere(
      (mode) => mode.name == modeValue,
      orElse: () => GnosisCardMode.disabled,
    );
    final scenario = GnosisCardScenario.values.firstWhere(
      (value) => value.name == scenarioValue,
      orElse: () => GnosisCardScenario.happyPath,
    );

    if (kReleaseMode && requestedMode == GnosisCardMode.mock) {
      return const GnosisCardConfig(
        mode: GnosisCardMode.disabled,
        scenario: GnosisCardScenario.happyPath,
        failureReason: 'Mock card mode is rejected in production builds.',
      );
    }
    if (requestedMode == GnosisCardMode.live) {
      return GnosisCardConfig(
        mode: GnosisCardMode.disabled,
        scenario: scenario,
        failureReason:
            'Live Gnosis Pay adapters are not configured. The feature is fail-closed.',
      );
    }
    return GnosisCardConfig(
      mode: requestedMode,
      scenario: scenario,
      failureReason: requestedMode == GnosisCardMode.disabled
          ? 'Gnosis Pay cards are not enabled for this build.'
          : null,
    );
  }

  final GnosisCardMode mode;
  final GnosisCardScenario scenario;
  final String? failureReason;
}
