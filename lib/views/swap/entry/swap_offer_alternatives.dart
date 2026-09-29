import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/views/swap/common/swap_format.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';

/// Assets someone on the order book does trade with the asset a pair keeps,
/// each a one-tap switch for the side that has no offers.
class SwapOfferAlternatives extends StatelessWidget {
  const SwapOfferAlternatives({
    required this.label,
    required this.assets,
    required this.balanceOf,
    required this.onChosen,
    super.key,
  });

  final String label;
  final List<AssetId> assets;
  final Decimal? Function(AssetId asset) balanceOf;
  final ValueChanged<AssetId> onChosen;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: SwapText.small(context)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final asset in assets)
              _Alternative(
                asset: asset,
                balance: balanceOf(asset),
                onTap: () => onChosen(asset),
              ),
          ],
        ),
      ],
    ),
  );
}

class _Alternative extends StatelessWidget {
  const _Alternative({
    required this.asset,
    required this.balance,
    required this.onTap,
  });

  final AssetId asset;
  final Decimal? balance;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    final ticker = SwapFormat.ticker(asset);
    final balance = this.balance;
    final held = balance == null || balance <= Decimal.zero
        ? null
        : LocaleKeys.swapOffersHeld.tr(
            args: [SwapFormat.amount(balance, rounding: SwapRounding.down)],
          );
    final shape = StadiumBorder(side: BorderSide(color: palette.controlBorder));
    return SwapButtonSemantics(
      label: held == null ? ticker : '$ticker, $held',
      onTap: onTap,
      child: Material(
        color: palette.surfaceHigh,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: SwapGeometry.touchTarget,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwapTokenIcon(asset: asset, size: 20),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      held == null ? ticker : '$ticker · $held',
                      style: SwapText.strong(context).copyWith(fontSize: 14),
                    ),
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
