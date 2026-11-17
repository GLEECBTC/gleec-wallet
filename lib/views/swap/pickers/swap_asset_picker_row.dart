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
    required this.signedIn,
    required this.blocked,
    this.unreachableWith,
    this.noOffers = false,
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
  final bool signedIn;
  final bool blocked;

  final AssetId? unreachableWith;

  /// No one is offering it for the other side's asset right now. It can
  /// still be chosen: orders come and go.
  final bool noOffers;
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
    final tickerStyle = SwapText.strong(context);
    final small = SwapText.small(context);
    double widest(Iterable<double> widths) =>
        widths.fold(0.0, (a, b) => a > b ? a : b);

    final Widget? trailing;
    final double trailingWidth;
    if (active && balance != null) {
      final amount = SwapFormat.amount(balance, rounding: SwapRounding.down);
      final usd = price == null ? null : SwapFormat.usd(balance * price);
      final style = SwapText.strong(context).copyWith(fontSize: 14);
      trailing = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(amount, style: style),
          if (usd != null) Text(usd, style: small),
        ],
      );
      trailingWidth = widest([
        SwapText.widthOf(context, amount, style),
        if (usd != null) SwapText.widthOf(context, usd, small),
      ]);
    } else {
      trailing = null;
      trailingWidth = 0;
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
      if (noOffers) SwapBadge(label: LocaleKeys.swapPickerBadgeNoOffers.tr()),
      if (blocked)
        SwapBadge(
          label: LocaleKeys.swapPickerBlocked.tr(),
          tone: SwapTone.warning,
        ),
    ];

    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(ticker, style: tickerStyle),
            ...badges,
          ],
        ),
        const SizedBox(height: 3),
        Text(subtitle, style: small),
      ],
    );
    // Narrower than this, a badge or word of the title would split.
    final titleWidth = widest([
      SwapText.widthOf(context, ticker, tickerStyle),
      for (final badge in badges) SwapBadge.widthOf(context, badge.label),
      SwapText.widthOf(context, subtitle, small, longestWord: true),
    ]);

    final disabled = blocked || unreachableWith != null;
    final onTap = disabled ? null : this.onTap;
    return Semantics(
      button: true,
      selected: selected,
      enabled: onTap != null,
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
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 68),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    SwapTokenIcon(asset: asset),
                    const SizedBox(width: 12),
                    Expanded(
                      child: trailing == null
                          ? title
                          : _TitleAndTrailing(
                              title: title,
                              titleWidth: titleWidth,
                              trailing: trailing,
                              trailingWidth: trailingWidth,
                            ),
                    ),
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

/// [trailing] beside [title] while the title keeps [titleWidth] there, and
/// under it, end-aligned, once it would not.
class _TitleAndTrailing extends StatelessWidget {
  const _TitleAndTrailing({
    required this.title,
    required this.titleWidth,
    required this.trailing,
    required this.trailingWidth,
  });

  final Widget title;
  final double titleWidth;
  final Widget trailing;
  final double trailingWidth;

  static const _gap = 12.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (titleWidth + _gap + trailingWidth <= constraints.maxWidth) {
        return Row(
          children: [
            Expanded(child: title),
            const SizedBox(width: _gap),
            trailing,
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          title,
          const SizedBox(height: 6),
          Align(alignment: AlignmentDirectional.centerEnd, child: trailing),
        ],
      );
    },
  );
}
