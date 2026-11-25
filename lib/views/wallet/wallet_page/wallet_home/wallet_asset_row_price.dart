part of 'wallet_asset_row.dart';

/// [_PriceLine] as a column: the price over its 24h change.
class _PriceColumn extends StatelessWidget {
  const _PriceColumn({required this.price, required this.change});

  final double? price;
  final double? change;

  @override
  Widget build(BuildContext context) {
    final price = this.price;
    final change = this.change;
    final detail = WalletHomeText.detail(context);
    if (price == null) {
      return Text(
        '—',
        key: WalletAssetRow.priceKey,
        style: detail,
        textAlign: TextAlign.end,
      );
    }
    return Semantics(
      label: [
        FiatFormat.spokenPrice(price),
        if (change != null) FiatFormat.percent(change),
      ].join(', '),
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerEnd,
            child: Text(
              FiatFormat.price(price),
              key: WalletAssetRow.priceKey,
              maxLines: 1,
              style: WalletHomeText.value(context),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            change == null ? '—' : FiatFormat.percent(change),
            maxLines: 1,
            style: change == null
                ? detail
                : detail.copyWith(color: trendColor(context, change)),
          ),
        ],
      ),
    );
  }
}

/// The market price and its 24h change, which stay visible when balances
/// are hidden: they are public, not the user's.
class _PriceLine extends StatelessWidget {
  const _PriceLine({required this.price, required this.change});

  final double? price;
  final double? change;

  @override
  Widget build(BuildContext context) {
    final price = this.price;
    final change = this.change;
    final style = WalletHomeText.detail(context);
    if (price == null) {
      return Text('—', key: WalletAssetRow.priceKey, style: style);
    }
    return Semantics(
      label: [
        FiatFormat.spokenPrice(price),
        if (change != null) FiatFormat.percent(change),
      ].join(', '),
      excludeSemantics: true,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(text: FiatFormat.price(price)),
              if (change != null)
                TextSpan(
                  text: '  ${FiatFormat.percent(change)}',
                  style: TextStyle(color: trendColor(context, change)),
                ),
            ],
          ),
          key: WalletAssetRow.priceKey,
          style: style,
          maxLines: 1,
        ),
      ),
    );
  }
}
