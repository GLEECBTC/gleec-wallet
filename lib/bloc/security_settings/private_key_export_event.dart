import 'package:equatable/equatable.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:web_dex/services/security/private_key_export_delivery.dart';

sealed class PrivateKeyExportEvent extends Equatable {
  const PrivateKeyExportEvent();

  @override
  List<Object?> get props => const [];

  @override
  String toString() => '$runtimeType(redacted)';
}

class PrivateKeyExportRequested extends PrivateKeyExportEvent {
  PrivateKeyExportRequested({Set<AssetId> blockedAssets = const {}})
    : blockedAssets = Set.unmodifiable(blockedAssets);

  final Set<AssetId> blockedAssets;
}

class PrivateKeyExportPasswordSubmitted extends PrivateKeyExportEvent {
  const PrivateKeyExportPasswordSubmitted(this.operationId, this.password);

  final int operationId;
  final SensitiveString password;

  @override
  List<Object?> get props => [operationId];
}

class PrivateKeyExportCancelled extends PrivateKeyExportEvent {
  const PrivateKeyExportCancelled();
}

class PrivateKeyExportAuthenticationLost extends PrivateKeyExportEvent {
  const PrivateKeyExportAuthenticationLost();
}

class PrivateKeyExportSessionCheckRequested extends PrivateKeyExportEvent {
  const PrivateKeyExportSessionCheckRequested();
}

class PrivateKeyExportVisibilityChanged extends PrivateKeyExportEvent {
  const PrivateKeyExportVisibilityChanged(this.visible);
  final bool visible;
}

class PrivateKeyExportKeyVisibilityToggled extends PrivateKeyExportEvent {
  const PrivateKeyExportKeyVisibilityToggled(this.assetId, this.keyIndex);
  final AssetId assetId;
  final int keyIndex;
}

class PrivateKeyExportBlockedAssetsChanged extends PrivateKeyExportEvent {
  const PrivateKeyExportBlockedAssetsChanged(this.include);
  final bool include;
}

class PrivateKeyExportDeliveryRequested extends PrivateKeyExportEvent {
  const PrivateKeyExportDeliveryRequested(
    this.action, {
    this.assetId,
    this.keyIndex,
  });

  final PrivateKeyExportAction action;
  final AssetId? assetId;
  final int? keyIndex;
}

class PrivateKeyExportQrRequested extends PrivateKeyExportEvent {
  const PrivateKeyExportQrRequested(this.assetId, this.keyIndex);
  final AssetId assetId;
  final int keyIndex;
}

class PrivateKeyExportQrClosed extends PrivateKeyExportEvent {
  const PrivateKeyExportQrClosed();
}
