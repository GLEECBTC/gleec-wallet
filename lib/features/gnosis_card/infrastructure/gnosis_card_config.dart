import 'package:flutter/foundation.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_models.dart';

enum GnosisCardScenario {
  happyPath,
  offline,
  offlineDashboard,
  expiredSession,
  invalidOtp,
  kycResubmission,
  kycRejected,
  kycRequiresAction,
  deploymentFailure,
  safeIntegrityFailure,
  paymentFailure,
  issuanceFailure,
  lockedWallet,
  wrongChain,
  activationFailure,
  nonceReplay,
  walletSwitch,
  rateLimited,
  serviceFailure,
  slowDeployment,
  migrationPending,
  migrationFailed,
  emptyActivity,
  cardOrdered,
  cardShipped,
  cardActivatable,
  cardActive,
  cardFrozen,
  cardLost,
  cardStolen,
  cardVoided,

  /// Source compatibility for direct test construction. Environment parsing
  /// canonicalizes the former name to [kycResubmission].
  @Deprecated('Use kycResubmission')
  kycExpired,
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
    final scenario = _parseScenario(scenarioValue);

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

GnosisCardScenario _parseScenario(String value) {
  if (value == 'kycExpired') return GnosisCardScenario.kycResubmission;
  return GnosisCardScenario.values.firstWhere(
    (scenario) => scenario.name == value,
    orElse: () => GnosisCardScenario.happyPath,
  );
}
