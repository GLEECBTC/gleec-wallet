import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/coin.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/shared/utils/utils.dart';

class LaunchNativeExplorerButton extends StatelessWidget {
  const LaunchNativeExplorerButton({Key? key, required this.coin, this.address})
    : super(key: key);
  final Coin coin;
  final String? address;

  @override
  Widget build(BuildContext context) {
    final url = getNativeExplorerUrlByCoin(coin, address);

    return UiPrimaryButton(
      width: 160,
      height: 30,
      onPressed: url.isEmpty ? null : () => launchURLString(url),
      text: LocaleKeys.viewOnExplorer.tr(),
    );
  }
}
