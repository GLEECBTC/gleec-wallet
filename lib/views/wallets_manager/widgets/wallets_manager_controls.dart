import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/wallets_manager_models.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';

class WalletsManagerControls extends StatelessWidget {
  const WalletsManagerControls({Key? key, required this.onTap})
    : super(key: key);
  final Function(WalletsManagerAction) onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildCreateButton(context),
        Padding(
          padding: const EdgeInsets.only(top: 10.0),
          child: _buildImportButton(context),
        ),
      ],
    );
  }

  Widget _buildCreateButton(BuildContext context) {
    return UiPrimaryButton(
      key: const Key('create-wallet-button'),
      height: 50,
      prefix: const Padding(
        padding: EdgeInsets.only(right: 10.0),
        child: Icon(Icons.add, size: 15),
      ),
      text: LocaleKeys.walletsManagerCreateWalletButton.tr(),
      onPressed: () => onTap(WalletsManagerAction.create),
    );
  }

  Widget _buildImportButton(BuildContext context) => UiPrimaryButton(
    key: const Key('import-wallet-button'),
    height: 50,
    backgroundColor: Theme.of(context).cardColor,
    onPressed: () => onTap(WalletsManagerAction.import),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.download,
          color: Theme.of(context).textTheme.labelLarge?.color,
          size: 15,
        ),
        Padding(
          padding: const EdgeInsets.only(left: 10.0),
          child: Text(
            LocaleKeys.walletsManagerImportWalletButton.tr(),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}
