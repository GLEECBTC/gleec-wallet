import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:intl/intl.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/model/wallets_manager_models.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';

class WalletListItem extends StatelessWidget {
  const WalletListItem({Key? key, required this.wallet, required this.onClick})
    : super(key: key);
  final Wallet wallet;
  final void Function(Wallet, WalletsManagerExistWalletAction) onClick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return UiPrimaryButton(
      backgroundColor: theme.cardColor,
      text: wallet.name,
      prefix: DecoratedBox(
        decoration: const BoxDecoration(shape: BoxShape.circle),
        child: Icon(
          Icons.person,
          size: 21,
          color: theme.textTheme.labelLarge?.color,
        ),
      ),
      height: 68,
      onPressed: () => onClick(wallet, WalletsManagerExistWalletAction.logIn),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: const BoxDecoration(shape: BoxShape.circle),
            child: Icon(
              Icons.person,
              size: 21,
              color: theme.textTheme.labelLarge?.color,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  wallet.name,
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
                    _MetaTag(
                      label: _walletProvenanceLabel(wallet.config.provenance),
                    ),
                    _MetaTag(
                      label: _walletCreatedLabel(wallet.config.createdAt),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () =>
                onClick(wallet, WalletsManagerExistWalletAction.delete),
            icon: const Icon(Icons.close, size: 18),
            visualDensity: VisualDensity.compact,
            tooltip: LocaleKeys.delete.tr(),
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
      WalletProvenance.generated => 'Generated',
      WalletProvenance.imported => 'Imported',
      WalletProvenance.unknown => LocaleKeys.unknown.tr(),
    };
  }

  String _walletCreatedLabel(DateTime? createdAt) {
    if (createdAt == null) return LocaleKeys.unknown.tr();
    return DateFormat('yyyy-MM-dd').format(createdAt);
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
