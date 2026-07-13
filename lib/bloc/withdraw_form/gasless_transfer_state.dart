import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Availability of the GasFree rail for the currently selected wallet/asset.
///
/// These states deliberately separate a verified provider response from an
/// unavailable or stale lookup. UI must only present the rail as ready when
/// [GaslessAvailability.ready] is authoritative.
enum GaslessAvailability {
  initial,
  checking,
  ready,
  stale,
  temporarilyUnavailable,
  pendingTransfer,
  providerUnavailable,
  disabled,
  unsupported,
  securityMismatch;

  bool get isVerifiedReady => this == GaslessAvailability.ready;

  bool get isChecking =>
      this == GaslessAvailability.initial ||
      this == GaslessAvailability.checking;

  bool get isNeutralUnknown =>
      this == GaslessAvailability.stale ||
      this == GaslessAvailability.temporarilyUnavailable;

  bool get isBlocked =>
      this == GaslessAvailability.pendingTransfer ||
      this == GaslessAvailability.providerUnavailable ||
      this == GaslessAvailability.disabled ||
      this == GaslessAvailability.unsupported ||
      this == GaslessAvailability.securityMismatch;
}

/// Main-app policy helpers for the SDK's durable transfer lifecycle.
extension GaslessTransferStatePolicy on GaslessTransferState {
  bool get hasRelayAccepted => switch (this) {
    GaslessTransferState.submittedPending ||
    GaslessTransferState.submittedUnknown ||
    GaslessTransferState.confirming ||
    GaslessTransferState.confirmed ||
    GaslessTransferState.failedFinal => true,
    GaslessTransferState.preparing ||
    GaslessTransferState.rejectedBeforeRelay => false,
  };

  bool get isUnresolved => switch (this) {
    GaslessTransferState.submittedPending ||
    GaslessTransferState.submittedUnknown ||
    GaslessTransferState.confirming => true,
    GaslessTransferState.preparing ||
    GaslessTransferState.rejectedBeforeRelay ||
    GaslessTransferState.confirmed ||
    GaslessTransferState.failedFinal => false,
  };

  bool get canRetrySafely =>
      this == GaslessTransferState.rejectedBeforeRelay ||
      this == GaslessTransferState.failedFinal;
}
