part of 'swap_amount_cards.dart';

/// The button that opens the asset picker for one side.
class SwapAssetPill extends StatelessWidget {
  const SwapAssetPill({
    required this.asset,
    required this.network,
    required this.onTap,
    required this.semanticLabel,
    this.hasError = false,
    super.key,
  });

  final AssetId? asset;
  final String? network;
  final VoidCallback? onTap;
  final String semanticLabel;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    final asset = this.asset;
    return Semantics(
      button: true,
      label: asset == null
          ? semanticLabel
          : '$semanticLabel: ${SwapFormat.ticker(asset)}, $network',
      excludeSemantics: true,
      child: Material(
        color: palette.surfaceHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: hasError ? palette.danger : palette.controlBorder,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (asset == null)
                    Icon(Icons.add_circle_outline, color: palette.brandHover)
                  else
                    SwapTokenIcon(asset: asset),
                  const SizedBox(width: 9),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          asset == null
                              ? LocaleKeys.swapSelectAsset.tr()
                              : SwapFormat.ticker(asset),
                          style: SwapText.strong(context).copyWith(height: 1.1),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (asset != null && network != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            network!,
                            style: SwapText.small(context),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: palette.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "From 0x5520…7B91" / "To 0x80A1…42F0": tap copies the full address.
class _AddressFooterButton extends StatelessWidget {
  const _AddressFooterButton({required this.prefix, required this.address});

  final String Function(String) prefix;
  final String? address;

  @override
  Widget build(BuildContext context) {
    final address = this.address;
    final palette = SwapPalette.of(context);
    if (address == null) {
      return const SizedBox(height: 48);
    }
    return Semantics(
      button: true,
      label: '${prefix(address)}. ${LocaleKeys.swapCopyAddress.tr()}',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => copyToClipBoard(
          context,
          address,
          LocaleKeys.swapAddressCopied.tr(),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    prefix(SwapFormat.short(address)),
                    style: SwapText.small(
                      context,
                    ).copyWith(color: palette.textSecondary),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.content_copy_rounded,
                  size: 14,
                  color: palette.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The round button between the cards that swaps the two sides.
class SwapSwitchButton extends StatelessWidget {
  const SwapSwitchButton({required this.onPressed, super.key});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    return Tooltip(
      message: LocaleKeys.swapSwitchDirection.tr(),
      child: Semantics(
        button: true,
        label: LocaleKeys.swapSwitchDirection.tr(),
        excludeSemantics: true,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: palette.canvas, width: 6),
          ),
          child: Material(
            color: palette.surfaceHighest,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPressed,
              child: Icon(
                Icons.swap_vert_rounded,
                size: 20,
                color: palette.text,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Accepts one decimal separator (either `.` or `,`, stored as `.`) and at
/// most [maxDecimals] places.
class _DecimalInputFormatter extends TextInputFormatter {
  _DecimalInputFormatter({required this.maxDecimals});

  final int maxDecimals;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.replaceAll(',', '.');
    if (text.isEmpty) return newValue.copyWith(text: '');
    final valid = RegExp(
      maxDecimals == 0 ? r'^\d*$' : '^\\d*\\.?\\d{0,$maxDecimals}\$',
    );
    if (!valid.hasMatch(text)) return oldValue;
    return newValue.copyWith(text: text);
  }
}
