import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/wallet.dart';

class WalletImportTypeDropdown extends StatelessWidget {
  const WalletImportTypeDropdown({
    super.key,
    required this.selectedType,
    required this.onChanged,
    this.isHdOptionEnabled = true,
  });

  final WalletType selectedType;
  final ValueChanged<WalletType> onChanged;
  final bool isHdOptionEnabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          LocaleKeys.selectWalletType.tr(),
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<WalletType>(
          key: const Key('wallet-import-type-dropdown'),
          initialValue: selectedType,
          isExpanded: true,
          borderRadius: BorderRadius.circular(12),
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          selectedItemBuilder: (context) => [
            _buildSelectedItem(context, WalletType.hdwallet),
            _buildSelectedItem(context, WalletType.iguana),
          ],
          items: [
            DropdownMenuItem<WalletType>(
              value: WalletType.hdwallet,
              enabled: isHdOptionEnabled,
              child: _WalletImportTypeMenuItem(
                title: 'walletImportTypeHdLabel'.tr(),
                description: 'walletImportTypeHdDescription'.tr(),
                icon: Icons.account_tree_outlined,
                enabled: isHdOptionEnabled,
              ),
            ),
            DropdownMenuItem<WalletType>(
              value: WalletType.iguana,
              child: _WalletImportTypeMenuItem(
                title: 'walletImportTypeLegacyLabel'.tr(),
                description: 'walletImportTypeLegacyDescription'.tr(),
                icon: Icons.account_balance_wallet_outlined,
              ),
            ),
          ],
          onChanged: (WalletType? value) {
            if (value == null) return;
            if (value == WalletType.hdwallet && !isHdOptionEnabled) return;
            onChanged(value);
          },
        ),
        if (!isHdOptionEnabled) ...[
          const SizedBox(height: 8),
          Text(
            'walletImportTypeHdDisabledHint'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSelectedItem(BuildContext context, WalletType type) {
    final bool isHdType = type == WalletType.hdwallet;
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        isHdType
            ? 'walletImportTypeHdLabel'.tr()
            : 'walletImportTypeLegacyLabel'.tr(),
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}

class _WalletImportTypeMenuItem extends StatelessWidget {
  const _WalletImportTypeMenuItem({
    required this.title,
    required this.description,
    required this.icon,
    this.enabled = true,
  });

  final String title;
  final String description;
  final IconData icon;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleColor = enabled
        ? theme.textTheme.bodyLarge?.color
        : theme.disabledColor;
    final descriptionColor = enabled
        ? theme.textTheme.bodySmall?.color
        : theme.disabledColor;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 20, color: titleColor),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: titleColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: descriptionColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
