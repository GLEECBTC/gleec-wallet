import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/model/wallets_manager_models.dart';

/// One stored wallet. The row opens it; removal sits behind the overflow menu
/// so the trailing edge never starts a destructive flow by itself.
class WalletListItem extends StatelessWidget {
  const WalletListItem({
    super.key,
    required this.wallet,
    required this.onClick,
  });
  final Wallet wallet;
  final void Function(Wallet, WalletsManagerExistWalletAction) onClick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mutedColor = theme.textTheme.bodySmall?.color;
    return UiPrimaryButton(
      backgroundColor: theme.cardColor,
      // A minimum, so the tags can wrap onto more lines at large text sizes.
      height: 68,
      expandForText: true,
      onPressed: () => onClick(wallet, WalletsManagerExistWalletAction.logIn),
      child: Row(
        children: [
          Icon(
            Icons.person,
            size: 21,
            color: theme.textTheme.labelLarge?.color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    wallet.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _MetaTag(label: _walletTypeLabel(wallet.config.type)),
                      if (wallet.config.provenance != WalletProvenance.unknown)
                        _MetaTag(
                          label: _walletProvenanceLabel(
                            wallet.config.provenance,
                          ),
                        ),
                      if (wallet.config.createdAt != null)
                        _MetaTag(
                          label: _walletCreatedLabel(wallet.config.createdAt!),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          _WalletRowMenu(
            iconColor: mutedColor,
            onRemove: () =>
                onClick(wallet, WalletsManagerExistWalletAction.delete),
          ),
          ExcludeSemantics(
            child: Icon(
              UiListActionRow.defaultTrailingIcon,
              size: 20,
              color: mutedColor,
            ),
          ),
        ],
      ),
    );
  }

  String _walletTypeLabel(WalletType type) {
    return switch (type) {
      WalletType.hdwallet => 'HD',
      WalletType.iguana => 'Iguana',
      WalletType.trezor => 'Trezor',
      WalletType.metamask => 'MetaMask',
      WalletType.keplr => 'Keplr',
    };
  }

  String _walletProvenanceLabel(WalletProvenance provenance) {
    return switch (provenance) {
      WalletProvenance.generated => 'authWalletTagGenerated'.tr(),
      WalletProvenance.imported => 'authWalletTagImported'.tr(),
      WalletProvenance.unknown => '',
    };
  }

  String _walletCreatedLabel(DateTime createdAt) {
    return DateFormat('yyyy-MM-dd').format(createdAt);
  }
}

class _WalletRowMenu extends StatelessWidget {
  const _WalletRowMenu({required this.onRemove, required this.iconColor});

  final VoidCallback onRemove;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      // Desktop themes default to a compact 40 dp icon button.
      data: theme.copyWith(visualDensity: VisualDensity.standard),
      child: PopupMenuButton<WalletsManagerExistWalletAction>(
        key: const Key('wallet-list-item-menu'),
        tooltip: 'authWalletOptions'.tr(),
        // Below the row, so the wallet being acted on stays readable.
        position: PopupMenuPosition.under,
        // Quieter than the chevron beside it: opening is the row's action.
        iconSize: 20,
        icon: Icon(Icons.more_vert, color: iconColor),
        onSelected: (_) => onRemove(),
        itemBuilder: (context) => [
          PopupMenuItem(
            key: const Key('wallet-list-item-remove'),
            value: WalletsManagerExistWalletAction.delete,
            child: Row(
              children: [
                Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: 12),
                Flexible(child: Text('authRemoveFromThisDevice'.tr())),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaTag extends StatelessWidget {
  const _MetaTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.4),
        ),
        color: theme.colorScheme.surface.withValues(alpha: 0.35),
      ),
      child: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
      ),
    );
  }
}
