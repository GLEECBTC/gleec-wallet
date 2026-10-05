import 'package:flutter/material.dart';

/// The mobile wallet row's title: the coin's icon beside two lines, the name
/// and held amount, then the market price and the holding's fiat value.
///
/// The amount and fiat value take the width they need, up to half the room
/// beside the icon, and shrink to fit beyond that. They are never cut short:
/// "147…" for a 14,772 VRSC balance reads as a different number. Each line is
/// split on its own, so a long price is not squeezed by a long amount.
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
              Widget line(Widget start, Widget end) => Row(
                children: [
                  Expanded(child: start),
                  const SizedBox(width: _gap),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: valueMax),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerEnd,
                      child: end,
                    ),
                  ),
                ],
              );
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  line(
                    name,
                    Text(
                      amount,
                      style: amountStyle,
                      maxLines: 1,
                      softWrap: false,
                    ),
                  ),
                  const SizedBox(height: 2),
                  line(
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: price,
                    ),
                    fiat,
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
