part of 'swap_asset_picker.dart';

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.asset,
    required this.network,
    required this.contract,
    required this.balance,
    required this.usdPrice,
    required this.selected,
    required this.sameTicker,
    required this.active,
    required this.blocked,
    required this.activating,
    this.unreachableWith,
    required this.activationFailed,
    required this.onTap,
  });

  final AssetId asset;
  final String network;
  final String? contract;
  final Decimal? balance;
  final Decimal? usdPrice;
  final bool selected;
  final bool sameTicker;
  final bool active;
  final bool blocked;

  /// The other side's asset, when it cannot be swapped for this one.
  final AssetId? unreachableWith;
  final bool activating;
  final bool activationFailed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    final ticker = SwapFormat.ticker(asset);
    final balance = this.balance;
    final price = usdPrice;
    final contract = this.contract;
    final subtitle = contract == null
        ? network
        : '$network · ${SwapFormat.short(contract)}';

    final Widget trailing;
    if (activating) {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: palette.brand,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            LocaleKeys.swapPickerActivating.tr(),
            style: SwapText.small(context),
          ),
        ],
      );
    } else if (!active && !blocked && unreachableWith == null) {
      trailing = Text(
        LocaleKeys.swapPickerActivate.tr(),
        style: SwapText.strong(
          context,
        ).copyWith(color: palette.brandHover, fontSize: 14),
      );
    } else if (active && balance != null) {
      trailing = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            SwapFormat.amount(balance, rounding: SwapRounding.down),
            style: SwapText.strong(context).copyWith(fontSize: 14),
          ),
          if (price != null)
            Text(
              SwapFormat.usd(balance * price),
              style: SwapText.small(context),
            ),
        ],
      );
    } else {
      trailing = const SizedBox.shrink();
    }

    final badges = [
      if (selected)
        SwapBadge(
          label: LocaleKeys.swapPickerSelected.tr(),
          tone: SwapTone.brand,
        ),
      if (sameTicker)
        SwapBadge(
          label: LocaleKeys.swapPickerSameTicker.tr(),
          tone: SwapTone.info,
        ),
      if (blocked)
        SwapBadge(
          label: LocaleKeys.swapPickerBlocked.tr(),
          tone: SwapTone.warning,
        )
      else if (!active)
        SwapBadge(label: LocaleKeys.swapPickerInactive.tr()),
    ];

    final disabled = blocked || unreachableWith != null;
    return Semantics(
      button: true,
      selected: selected,
      enabled: !disabled,
      hint: unreachableWith == null
          ? null
          : LocaleKeys.swapPickerUnreachableTitle.tr(
              args: [SwapFormat.ticker(unreachableWith!)],
            ),
      child: Opacity(
        opacity: disabled ? 0.55 : 1,
        child: Material(
          color: selected ? palette.selected : palette.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: selected ? palette.brand : palette.controlBorder,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: disabled ? null : onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 68),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    SwapTokenIcon(asset: asset),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(ticker, style: SwapText.strong(context)),
                              ...badges,
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(subtitle, style: SwapText.small(context)),
                          if (activationFailed)
                            Text(
                              LocaleKeys.swapPickerActivationFailed.tr(
                                args: [ticker],
                              ),
                              style: SwapText.small(
                                context,
                              ).copyWith(color: palette.danger),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    trailing,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
