part of 'swap_quote_strip.dart';

/// "1 ETH ≈ 3,219.42 USDC" — tap to flip it round.
class SwapRateLine extends StatefulWidget {
  const SwapRateLine({required this.quote, super.key});

  final SwapQuote quote;

  /// How tall the line is, for keeping its room before a rate is known.
  static double heightOf(BuildContext context) => math.max(
    SwapGeometry.touchTarget,
    MediaQuery.textScalerOf(context).scale(13) * 1.4 + 16,
  );

  @override
  State<SwapRateLine> createState() => _SwapRateLineState();
}

class _SwapRateLineState extends State<SwapRateLine> {
  bool _inverted = false;

  @override
  Widget build(BuildContext context) {
    final quote = widget.quote;
    final rate = quote.expectedRate;
    if (rate == null || rate <= Decimal.zero) return const SizedBox.shrink();
    final from = SwapFormat.ticker(quote.from);
    final to = SwapFormat.ticker(quote.to);
    final inverse = (Decimal.one / rate).toDecimal(
      scaleOnInfinitePrecision: 18,
    );
    final text = _inverted
        ? LocaleKeys.swapRate.tr(args: [to, SwapFormat.amount(inverse), from])
        : LocaleKeys.swapRate.tr(args: [from, SwapFormat.amount(rate), to]);
    final palette = SwapPalette.of(context);
    void invert() => setState(() => _inverted = !_inverted);
    return Align(
      alignment: Alignment.centerLeft,
      child: SwapButtonSemantics(
        label: '$text. ${LocaleKeys.swapRateInvert.tr()}',
        onTap: invert,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: invert,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      text,
                      style: SwapText.small(context)
                          .copyWith(color: palette.textSecondary),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.sync_alt_rounded,
                    size: 14,
                    color: palette.textTertiary,
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

/// Where the rate will be, while it is not known yet: "1 ETH ≈ — USDC".
class SwapRatePlaceholder extends StatelessWidget {
  const SwapRatePlaceholder({required this.from, required this.to, super.key});

  final AssetId from;
  final AssetId to;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: SwapGeometry.touchTarget),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
          child: Text(
            LocaleKeys.swapRate.tr(
              args: [
                SwapFormat.ticker(from),
                SwapFormat.unknown,
                SwapFormat.ticker(to),
              ],
            ),
            style: SwapText.small(context),
          ),
        ),
      ),
    ),
  );
}
