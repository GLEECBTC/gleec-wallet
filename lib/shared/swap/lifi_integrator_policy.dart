import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Wallet deployment policy. KDF applies and validates the commission.
LifiIntegratorConfig? gleecLifiIntegratorConfig({
  String enabled = const String.fromEnvironment(
    'LIFI_INTEGRATOR_ENABLED',
    defaultValue: 'true',
  ),
  String name = const String.fromEnvironment(
    'LIFI_INTEGRATOR_NAME',
    defaultValue: 'gleec-dex-staging',
  ),
  String feeBps = const String.fromEnvironment(
    'LIFI_INTEGRATOR_FEE_BPS',
    defaultValue: '178',
  ),
  String lifiFeeBps = const String.fromEnvironment(
    'LIFI_FEE_BPS',
    defaultValue: '22',
  ),
}) {
  if (enabled == 'false') return null;
  if (enabled != 'true') {
    throw ArgumentError('LIFI_INTEGRATOR_ENABLED must be true or false');
  }
  final commission = int.tryParse(feeBps);
  final provider = int.tryParse(lifiFeeBps);
  if (commission == null || provider == null) {
    throw ArgumentError('LI.FI commission rates must be integer basis points');
  }
  return LifiIntegratorConfig(
    name: name.trim(),
    feeBps: commission,
    lifiFeeBps: provider,
  );
}
