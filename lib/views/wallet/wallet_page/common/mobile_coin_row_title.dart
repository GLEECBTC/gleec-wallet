import 'package:flutter/material.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';

/// The mobile wallet row's title: the coin's icon beside two lines, the name
/// and held amount, then the market price and the holding's fiat value.
///
/// The amount and fiat value take the width they need, up to half the room
/// beside the icon, and shrink to fit beyond that. They are never cut short:
/// "147…" for a 14,772 VRSC balance reads as a different number. Each line is
/// split on its own, so a long price is not squeezed by a long amount.
///
/// The amount and price shrink no further than [minScale] of the size the
/// text setting asks for, give or take [AutoScrollText.animationThresholdWidth];
/// either still too wide scrolls instead, so they stay readable on a narrow
/// phone or with large text.
class MobileCoinRowTitle extends StatelessWidget {
  const MobileCoinRowTitle({
    super.key,
    required this.icon,
    required this.name,
    required this.price,
    required this.amount,
    required this.fiat,
    this.amountStyle,
  });

  final Widget icon;
  final Widget name;
  final Widget price;

  /// The held amount with its ticker, as one string so they scale together.
  final String amount;
  final Widget fiat;
  final TextStyle? amountStyle;

  /// The smallest the amount and price are drawn, as a share of full size.
  static const minScale = 0.8;

  static const _gap = 8.0;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        icon,
        const SizedBox(width: _gap),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final valueMax = (constraints.maxWidth - _gap) / 2;
              Widget fit(Widget child) => ConstrainedBox(
                constraints: BoxConstraints(maxWidth: valueMax),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerEnd,
                  child: child,
                ),
              );
              Widget line(Widget start, Widget end) => Row(
                children: [
                  Expanded(child: start),
                  const SizedBox(width: _gap),
                  end,
                ],
              );
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  line(name, _amount(context, valueMax, fit)),
                  const SizedBox(height: 2),
                  line(
                    ScaleDownOrScroll(minScale: minScale, child: price),
                    fit(fiat),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _amount(
    BuildContext context,
    double valueMax,
    Widget Function(Widget) fit,
  ) {
    final style = _effectiveAmountStyle(context);
    final smallest = style.copyWith(fontSize: style.fontSize! * minScale);
    // Measured at that size, since glyphs do not scale exactly. An overflow
    // too small for AutoScrollText to scroll would stay cut off, so the
    // amount shrinks that little further instead.
    final overflow = _widthOf(context, amount, smallest) - valueMax;
    if (overflow <= AutoScrollText.animationThresholdWidth) {
      return fit(
        Text(amount, style: amountStyle, maxLines: 1, softWrap: false),
      );
    }
    return SizedBox(
      width: valueMax,
      child: AutoScrollText(text: amount, style: smallest),
    );
  }

  /// [amountStyle] as [Text] resolves it, with a font size to scale.
  TextStyle _effectiveAmountStyle(BuildContext context) {
    final style = amountStyle;
    final resolved = style == null || style.inherit
        ? DefaultTextStyle.of(context).style.merge(style)
        : style;
    return resolved.copyWith(
      fontSize: resolved.fontSize ?? 14,
      fontWeight: MediaQuery.boldTextOf(context) ? FontWeight.bold : null,
      letterSpacing: MediaQuery.maybeLetterSpacingOverrideOf(context),
      wordSpacing: MediaQuery.maybeWordSpacingOverrideOf(context),
    );
  }

  /// The width [text] takes on one line at the text size setting.
  static double _widthOf(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }
}
