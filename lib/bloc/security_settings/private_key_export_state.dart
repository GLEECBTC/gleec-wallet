import 'package:equatable/equatable.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/services/security/private_key_export_delivery.dart';
import 'package:web_dex/services/security/private_key_export_service.dart';

enum PrivateKeyExportPhase {
  idle,
  starting,
  awaitingPassword,
  exporting,
  ready,
  failed,
}

class PrivateKeyExportState extends Equatable {
  const PrivateKeyExportState({
    this.phase = PrivateKeyExportPhase.idle,
    this.operationId = 0,
    this.walletName = '',
    this.result,
    this.error,
    this.showKeys = false,
    this.blockedAssets = const {},
    this.permanentlyExcludedAssetIds = const {},
    this.includeBlockedAssets = false,
    this.isDelivering = false,
    this.deliveryOutcome,
    this.deliveryFailed = false,
    this.deliveryRevision = 0,
    this.hasExported = false,
    this.qrKey,
    this.revealedKeys = const {},
  });

  final PrivateKeyExportPhase phase;
  final int operationId;
  final String walletName;
  final PrivateKeyExportResult? result;
  final PrivateKeyExportError? error;
  final bool showKeys;
  final Set<AssetId> blockedAssets;
  final Set<String> permanentlyExcludedAssetIds;
  final bool includeBlockedAssets;
  final bool isDelivering;
  final PrivateKeyExportDeliveryOutcome? deliveryOutcome;
  final bool deliveryFailed;
  final int deliveryRevision;
  final bool hasExported;
  final (AssetId, int)? qrKey;
  final Set<(AssetId, int)> revealedKeys;

  bool get needsPasswordDialog =>
      phase == PrivateKeyExportPhase.awaitingPassword ||
      phase == PrivateKeyExportPhase.exporting;

  bool get hasBlockedAssets =>
      result?.outcomes.any(
        (outcome) =>
            blockedAssets.contains(outcome.assetId) &&
            !permanentlyExcludedAssetIds.contains(outcome.assetId.id),
      ) ??
      false;

  Set<AssetId> get excludedAssets => Set.unmodifiable({
    if (!includeBlockedAssets) ...blockedAssets,
    for (final outcome in result?.outcomes ?? const <PrivateKeyExportOutcome>[])
      if (permanentlyExcludedAssetIds.contains(outcome.assetId.id))
        outcome.assetId,
  });

  List<PrivateKeyExportOutcome> get displayedOutcomes => List.unmodifiable(
    result?.outcomes.where(
          (outcome) => !excludedAssets.contains(outcome.assetId),
        ) ??
        const <PrivateKeyExportOutcome>[],
  );

  bool get canDeliver =>
      phase == PrivateKeyExportPhase.ready &&
      showKeys &&
      !isDelivering &&
      displayedOutcomes.any((o) => o.isSuccess);

  PrivateKey? keyAt(AssetId assetId, int index) {
    for (final outcome in displayedOutcomes) {
      if (outcome.assetId == assetId &&
          index >= 0 &&
          index < outcome.keys.length) {
        return outcome.keys[index];
      }
    }
    return null;
  }

  PrivateKeyExportState copyWith({
    PrivateKeyExportPhase? phase,
    String? walletName,
    PrivateKeyExportResult? result,
    PrivateKeyExportError? error,
    bool clearError = false,
    bool? showKeys,
    bool? includeBlockedAssets,
    bool? isDelivering,
    PrivateKeyExportDeliveryOutcome? deliveryOutcome,
    bool clearDelivery = false,
    bool? deliveryFailed,
    int? deliveryRevision,
    bool? hasExported,
    (AssetId, int)? qrKey,
    bool clearQr = false,
    Set<(AssetId, int)>? revealedKeys,
  }) => PrivateKeyExportState(
    phase: phase ?? this.phase,
    operationId: operationId,
    walletName: walletName ?? this.walletName,
    result: result ?? this.result,
    error: clearError ? null : (error ?? this.error),
    showKeys: showKeys ?? this.showKeys,
    blockedAssets: blockedAssets,
    permanentlyExcludedAssetIds: permanentlyExcludedAssetIds,
    includeBlockedAssets: includeBlockedAssets ?? this.includeBlockedAssets,
    isDelivering: isDelivering ?? this.isDelivering,
    deliveryOutcome: clearDelivery
        ? null
        : (deliveryOutcome ?? this.deliveryOutcome),
    deliveryFailed: deliveryFailed ?? this.deliveryFailed,
    deliveryRevision: deliveryRevision ?? this.deliveryRevision,
    hasExported: hasExported ?? this.hasExported,
    qrKey: clearQr ? null : (qrKey ?? this.qrKey),
    revealedKeys: revealedKeys == null
        ? this.revealedKeys
        : Set.unmodifiable(revealedKeys),
  );

  // An export is immutable and unique to its operation. Never traverse its keys
  // for equality or diagnostics; it is not persisted or replayed by this BLoC.
  @override
  List<Object?> get props => [
    phase,
    operationId,
    error,
    showKeys,
    includeBlockedAssets,
    isDelivering,
    deliveryOutcome,
    deliveryFailed,
    deliveryRevision,
    hasExported,
    qrKey,
    revealedKeys,
  ];

  @override
  String toString() => 'PrivateKeyExportState(${phase.name}, redacted)';
}
