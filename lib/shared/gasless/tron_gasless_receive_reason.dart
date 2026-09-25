/// Stable, privacy-safe reasons for the GasFree receive capability decision.
///
/// These codes intentionally contain no endpoint, provider response, address,
/// or wallet data, so they are safe to use in diagnostics and metrics.
enum GaslessReceiveReasonCode {
  ready('ready'),
  assetUnsupported('asset_unsupported'),
  receiveBuildDisabled('receive_build_disabled'),
  providerConfigurationInvalid('provider_configuration_invalid'),
  reactivationRequired('reactivation_required'),
  custodyAddressMissing('custody_address_missing'),
  canonicalAddressAmbiguous('canonical_address_ambiguous'),
  walletUnsupported('wallet_unsupported'),
  appBackgrounded('app_backgrounded'),
  accountStatusUnavailable('account_status_unavailable'),
  accountStatusExpired('account_status_expired'),
  malformedAccountStatus('malformed_account_status'),
  providerTemporarilyUnavailable('provider_temporarily_unavailable'),
  pendingTransfer('pending_transfer'),
  providerIdentityMismatch('provider_identity_mismatch'),
  tokenUnsupported('token_unsupported'),
  tokenDecimalsMismatch('token_decimals_mismatch'),
  custodyAddressMismatch('custody_address_mismatch');

  const GaslessReceiveReasonCode(this.code);

  final String code;
}
