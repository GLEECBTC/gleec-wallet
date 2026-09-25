import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/security_settings/private_key_export_bloc.dart';
import 'package:web_dex/bloc/security_settings/private_key_export_event.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/services/security/private_key_export_delivery.dart';

import 'private_key_field.dart';
import 'private_key_secret_field.dart';

/// One exported key: its derivation context, its public halves, and the
/// secret itself behind the reveal gate.
class PrivateKeyExportKeyTile extends StatelessWidget {
  const PrivateKeyExportKeyTile({
    required this.privateKey,
    required this.assetId,
    required this.index,
    required this.showKeys,
    required this.canDeliver,
    required this.showDivider,
    required this.showOrdinal,
    super.key,
  });

  final PrivateKey privateKey;
  final AssetId assetId;
  final int index;
  final bool showKeys;
  final bool canDeliver;

  /// False on the last tile, so a card never ends on a rule.
  final bool showDivider;

  /// Only useful when the asset exported more than one key.
  final bool showOrdinal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final revealed = context.select<PrivateKeyExportBloc, bool>(
      (bloc) => bloc.state.revealedKeys.contains((assetId, index)),
    );
    final bloc = context.read<PrivateKeyExportBloc>();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showOrdinal)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '#${index + 1}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if (privateKey.hdInfo?.derivationPath case final String path)
            PrivateKeyField(
              label: LocaleKeys.privateKeyExportDerivationPath.tr(),
              value: path,
            ),
          PrivateKeyField(
            label: LocaleKeys.privateKeyExportAddressLabel.tr(),
            value: privateKey.publicKeyAddress,
          ),
          if (privateKey.publicKeySecp256k1.isNotEmpty)
            PrivateKeyField(
              label: LocaleKeys.privateKeyExportPublicKey.tr(),
              value: privateKey.publicKeySecp256k1,
            ),
          // Serialized into the export file but never rendered before now,
          // which left shielded-asset holders looking at a key that is not
          // the one they need.
          //
          // Behind the same two-stage gate as the spending key, not beside the
          // public fields above it. A viewing key cannot spend, but it decrypts
          // the account's entire note history, so showing it while the reveal
          // switch is still off would break the promise that screen makes.
          if (privateKey.viewingKey case final String viewingKey) ...[
            PrivateKeySecretField(
              privateKey: viewingKey,
              revealed: showKeys && revealed,
              label: LocaleKeys.privateKeyExportViewingKey.tr(),
            ),
            const SizedBox(height: 8),
          ],
          PrivateKeySecretField(
            privateKey: privateKey.privateKey,
            revealed: showKeys && revealed,
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Flexible(
                child: TextButton.icon(
                  onPressed: showKeys
                      ? () => bloc.add(
                          PrivateKeyExportKeyVisibilityToggled(assetId, index),
                        )
                      : null,
                  icon: Icon(
                    revealed ? Icons.visibility_off : Icons.visibility,
                    size: 18,
                  ),
                  label: Text(
                    revealed
                        ? LocaleKeys.privateKeyExportHideKey.tr()
                        : LocaleKeys.privateKeyExportRevealKey.tr(),
                  ),
                ),
              ),
              IconButton(
                tooltip: LocaleKeys.copyDisplayedKey.tr(),
                onPressed: canDeliver
                    ? () => bloc.add(
                        PrivateKeyExportDeliveryRequested(
                          PrivateKeyExportAction.copy,
                          assetId: assetId,
                          keyIndex: index,
                        ),
                      )
                    : null,
                icon: const Icon(Icons.copy),
              ),
              IconButton(
                tooltip: LocaleKeys.privateKeyExportShowQr.tr(),
                onPressed: canDeliver
                    ? () =>
                          bloc.add(PrivateKeyExportQrRequested(assetId, index))
                    : null,
                icon: const Icon(Icons.qr_code),
              ),
            ],
          ),
          if (showDivider) const Divider(height: 24),
        ],
      ),
    );
  }
}
