import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_ui/komodo_ui.dart' show showAddressSearch;
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/utils/formatters.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/shared/widgets/truncate_middle_text.dart';

class CopyableAddressDialog extends StatelessWidget {
  const CopyableAddressDialog({
    required this.address,
    required this.asset,
    required this.pubkeys,
    required this.onAddressChanged,
    super.key,
    this.backgroundColor,
    this.fontColor,
    this.fontSize = 14,
    this.fontWeight = FontWeight.w500,
    this.iconSize = 22,
    this.isTruncated = true,
    this.padding = const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12),
    this.height,
  });

  final PubkeyInfo? address;
  final Asset asset;
  final AssetPubkeys pubkeys;
  final Color? backgroundColor;
  final Color? fontColor;
  final double? fontSize;
  final FontWeight? fontWeight;
  final double iconSize;
  final bool isTruncated;
  final EdgeInsets padding;
  final void Function(PubkeyInfo?) onAddressChanged;
  final double? height;

  @override
  Widget build(BuildContext context) {
    // Handle null address case
    if (address == null) {
      return const SizedBox.shrink();
    }

    final addressText = address!.address;
    final Color? background =
        backgroundColor ?? Theme.of(context).inputDecorationTheme.fillColor;

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(18),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Address selection part
          Expanded(
            child: InkWell(
              onTap: () => _showAddressSearch(context),
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding: padding,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      key: const Key('coin-details-address-field'),
                      child: isTruncated
                          ? Flexible(
                              child: TruncatedMiddleText(
                                addressText,
                                style: TextStyle(
                                  fontSize: fontSize,
                                  fontWeight: fontWeight,
                                  color: fontColor,
                                  height: height,
                                ),
                              ),
                            )
                          : Text(
                              addressText,
                              style: TextStyle(
                                fontSize: fontSize,
                                fontWeight: fontWeight,
                                color: fontColor,
                                height: height,
                              ),
                            ),
                    ),
                    const SizedBox(width: 16),
                    Icon(
                      Icons.arrow_drop_down_circle_rounded,
                      color: Theme.of(context).textTheme.labelLarge?.color,
                      size: iconSize,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Copy button part
          InkWell(
            onTap: () => copyToClipBoard(context, addressText),
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(18),
              bottomRight: Radius.circular(18),
            ),
            child: Padding(
              padding: padding.copyWith(left: 0),
              child: Icon(
                Icons.copy_rounded,
                color: Theme.of(context).textTheme.labelLarge?.color,
                size: iconSize,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _receiveAddressStatus(PubkeyInfo address) {
    final args = [
      formatDexAmt(address.balance.spendable),
      asset.id.symbol.configSymbol,
    ];
    return LocaleKeys.addressBalanceAvailable.tr(args: args);
  }

  Future<void> _showAddressSearch(BuildContext context) async {
    if (!context.mounted) return;

    final selectedAddress = await showAddressSearch(
      context,
      addresses: pubkeys.keys,
      assetNameLabel: asset.id.id,
      balanceLabel: _receiveAddressStatus,
    );

    if (selectedAddress != null) {
      onAddressChanged(selectedAddress);
    }
  }
}
