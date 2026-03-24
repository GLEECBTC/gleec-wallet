import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';

class HDWalletModeSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const HDWalletModeSwitch({
    required this.value,
    required this.onChanged,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: Row(
        children: [
          Text(LocaleKeys.hdWalletModeSwitchTitle.tr()),
          const SizedBox(width: 8),
          Tooltip(
            message: LocaleKeys.hdWalletModeSwitchTooltip.tr(),
            child: Icon(Icons.info, size: 16),
          ),
        ],
      ),
      subtitle: Text(
        LocaleKeys.hdWalletModeSwitchSubtitle.tr(),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      value: value,
      onChanged: onChanged,
    );
  }
}
