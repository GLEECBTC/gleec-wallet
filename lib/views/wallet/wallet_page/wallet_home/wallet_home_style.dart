import 'package:flutter/material.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';

/// Type for the wallet home, on the swap screens' palette so the app's two
/// main screens read as one product. Sizes are relative to the ambient text
/// theme, so the user's text scaling applies.
abstract final class WalletHomeText {
  static const _tabular = [FontFeature.tabularFigures()];

  static TextStyle _base(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium ?? const TextStyle();

  /// The whole-dollar part of the total balance.
  static TextStyle balance(BuildContext context) => _base(context).copyWith(
    fontSize: 44,
    height: 1.1,
    fontWeight: FontWeight.w800,
    letterSpacing: -1.6,
    fontFeatures: _tabular,
    color: SwapPalette.of(context).text,
  );

  /// The cents of the total balance, a step quieter than the dollars.
  static TextStyle balanceFraction(BuildContext context) => balance(context)
      .copyWith(
        fontSize: 30,
        letterSpacing: -0.8,
        color: SwapPalette.of(context).textTertiary,
      );

  /// Small labels: "Total balance", the change period.
  static TextStyle caption(BuildContext context) => _base(context).copyWith(
    fontSize: 13,
    height: 1.3,
    fontWeight: FontWeight.w600,
    color: SwapPalette.of(context).textTertiary,
  );

  /// A figure in a pill or a small row line.
  static TextStyle figure(BuildContext context) => _base(context).copyWith(
    fontSize: 13,
    height: 1.3,
    fontWeight: FontWeight.w700,
    fontFeatures: _tabular,
    color: SwapPalette.of(context).textSecondary,
  );

  /// The label under a quick action.
  static TextStyle action(BuildContext context) => _base(context).copyWith(
    fontSize: 13,
    height: 1.2,
    fontWeight: FontWeight.w700,
    color: SwapPalette.of(context).textSecondary,
  );

  /// A segment of the section switcher.
  static TextStyle segment(BuildContext context, {required bool selected}) =>
      _base(context).copyWith(
        fontSize: 14,
        height: 1.2,
        fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
        color: selected
            ? SwapPalette.of(context).text
            : SwapPalette.of(context).textTertiary,
      );

  /// An asset's name, and the wallet's name in the header.
  static TextStyle title(BuildContext context) => _base(context).copyWith(
    fontSize: 16,
    height: 1.25,
    fontWeight: FontWeight.w700,
    color: SwapPalette.of(context).text,
  );

  /// An asset's value in dollars.
  static TextStyle value(BuildContext context) =>
      title(context).copyWith(fontFeatures: _tabular);

  /// The line under a title or value: price, change, amount held.
  static TextStyle detail(BuildContext context) => _base(context).copyWith(
    fontSize: 13,
    height: 1.3,
    fontWeight: FontWeight.w600,
    fontFeatures: _tabular,
    color: SwapPalette.of(context).textTertiary,
  );

  /// The network chip beside a token's name.
  static TextStyle chip(BuildContext context) => _base(context).copyWith(
    fontSize: 10.5,
    height: 1.2,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.3,
    color: SwapPalette.of(context).textTertiary,
  );
}

/// Shared geometry of the wallet home.
abstract final class WalletHomeGeometry {
  static const gutter = 16.0;
  static const groupRadius = 20.0;
  static const logoSize = 40.0;
  static const rowPadding = EdgeInsets.symmetric(horizontal: 16, vertical: 12);

  /// Where a row's text starts, for dividers that line up with it.
  static const rowTextInset = 16.0 + logoSize + 12.0;

  /// The readable column the home keeps to on a tablet or desktop.
  static const wideContentWidth = 880.0;

  /// The row width from which an asset's price, trend and holding take
  /// columns of their own.
  static const wideRowFrom = 600.0;
}

/// A sheet's width: the whole screen on a phone, a readable column on a
/// tablet or desktop rather than the full window.
BoxConstraints? get walletSheetConstraints =>
    isMobile ? null : const BoxConstraints(maxWidth: 560);

/// The colour of a change: up, down, or flat. The sign and arrow beside it
/// carry the direction too, so it is never told by colour alone.
Color trendColor(BuildContext context, double change) {
  final palette = SwapPalette.of(context);
  if (change > 0) return palette.success;
  if (change < 0) return palette.danger;
  return palette.textTertiary;
}

/// A rounded, bordered group on the palette's surface.
BoxDecoration walletHomeGroupDecoration(BuildContext context) {
  final palette = SwapPalette.of(context);
  return BoxDecoration(
    color: palette.surface,
    borderRadius: BorderRadius.circular(WalletHomeGeometry.groupRadius),
    border: Border.all(color: palette.border),
  );
}
