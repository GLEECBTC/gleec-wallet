part of 'swap_quote_strip.dart';

/// One labelled figure of the strip. A null value is not known yet.
typedef _Fact = ({String label, String? value});

/// The strip's figures: side by side where every label and value has a line
/// to itself, else one per row with the values on a common right edge.
class _QuoteFacts extends StatelessWidget {
  const _QuoteFacts({required this.facts, required this.receive});

  final List<_Fact> facts;

  /// The asset to receive, whose ticker the minimum is written with.
  final AssetId? receive;

  static const _columnGap = 10.0;
  static const _rowGap = 8.0;
  static const _labelGap = 4.0;
  static const _rowLabelGap = 12.0;

  /// The most of a row its label takes, leaving the figure the rest.
  static const _labelShare = 0.55;

  static TextStyle _labelStyle(BuildContext context) => SwapText.small(context);

  static TextStyle _valueStyle(BuildContext context) =>
      SwapText.strong(context).copyWith(fontSize: 14);

  static double _line(BuildContext context, TextStyle style) =>
      SwapText.heightOf(context, const TextSpan(text: '0'), style);

  /// Figures of the length an option usually has, in the order of the
  /// facts. Room is kept for these whatever the option turns out to be, so
  /// the layout chosen while waiting is the one its figures land in.
  static List<String> _usualValues(AssetId? receive) => [
    SwapFormat.tokens(
      Decimal.parse('0.00012345'),
      receive == null ? 'USDC' : SwapFormat.ticker(receive),
    ),
    SwapFormat.usd(Decimal.parse('1000')),
    SwapFormat.duration(const Duration(minutes: 12)),
  ];

  static bool _sideBySide(
    BuildContext context,
    List<_Fact> facts,
    double width,
    AssetId? receive,
  ) {
    final column = (width - _columnGap * (facts.length - 1)) / facts.length;
    final label = _labelStyle(context);
    final value = _valueStyle(context);
    bool fits(String text, TextStyle style) =>
        SwapText.widthOf(context, text, style) <= column;
    return facts.every(
          (fact) =>
              fits(fact.label, label) &&
              (fact.value == null || fits(fact.value!, value)),
        ) &&
        _usualValues(receive).every((sample) => fits(sample, value));
  }

  /// How tall the facts set [width] wide with the usual figures in them.
  static double heightOf(
    BuildContext context, {
    required double width,
    required AssetId? receive,
  }) {
    final labelStyle = _labelStyle(context);
    final valueStyle = _valueStyle(context);
    final facts = _placeholderFacts();
    final values = _usualValues(receive);
    if (_sideBySide(context, facts, width, receive)) {
      return _line(context, labelStyle) +
          _labelGap +
          _line(context, valueStyle);
    }
    var height = (facts.length - 1) * _rowGap;
    for (final (index, fact) in facts.indexed) {
      final labelWidth = math.min(
        SwapText.widthOf(context, fact.label, labelStyle),
        width * _labelShare,
      );
      height += math.max(
        SwapText.heightOf(
          context,
          TextSpan(text: fact.label),
          labelStyle,
          maxWidth: labelWidth,
        ),
        SwapText.heightOf(
          context,
          TextSpan(text: values[index]),
          valueStyle,
          maxWidth: math.max(0, width - labelWidth - _rowLabelGap),
        ),
      );
    }
    return height;
  }

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    final labelStyle = _labelStyle(context);
    final valueStyle = _valueStyle(context);
    Widget value(_Fact fact, {TextAlign? align}) => Text(
      fact.value ?? SwapFormat.unknown,
      textAlign: align,
      style: fact.value == null
          ? valueStyle.copyWith(color: palette.textTertiary)
          : valueStyle,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (_sideBySide(context, facts, width, receive)) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (index, fact) in facts.indexed) ...[
                if (index > 0) const SizedBox(width: _columnGap),
                Expanded(
                  child: MergeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(fact.label, style: labelStyle),
                        const SizedBox(height: _labelGap),
                        value(fact),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (index, fact) in facts.indexed) ...[
              if (index > 0) const SizedBox(height: _rowGap),
              MergeSemantics(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    // A long label wraps in its own half rather than
                    // squeezing the figure beside it.
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: width * _labelShare,
                      ),
                      child: Text(fact.label, style: labelStyle),
                    ),
                    const SizedBox(width: _rowLabelGap),
                    Expanded(child: value(fact, align: TextAlign.end)),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
