import 'package:flutter/material.dart';

import '../calm_core/gleec_color_tokens.dart';
import '../common/theme_custom_base.dart';

class ThemeCustomLight extends ThemeExtension<ThemeCustomLight>
    implements ThemeCustomBase {
  ThemeCustomLight({GleecColorTokens colors = GleecColorTokens.light})
    : _colors = colors;

  final GleecColorTokens _colors;

  @override
  Color get suspendedBannerBackgroundColor => _colors.canvas;

  void initializeThemeDependentColors(ThemeData theme) {}

  @override
  ThemeExtension<ThemeCustomLight> copyWith() {
    return ThemeCustomLight(colors: _colors);
  }

  @override
  ThemeExtension<ThemeCustomLight> lerp(
    ThemeExtension<ThemeCustomLight>? other,
    double t,
  ) {
    if (other is! ThemeCustomLight) return this;
    return ThemeCustomLight(colors: _colors.lerp(other._colors, t));
  }

  @override
  Color get mainMenuItemColor => _colors.textSecondary;
  @override
  Color get mainMenuSelectedItemColor => _colors.brand;
  @override
  final Color checkCheckboxColor = Colors.white;
  @override
  final Color borderCheckboxColor = const Color.fromRGBO(62, 70, 99, 0.5);
  @override
  final TextStyle tradingFormDetailsLabel = const TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
  );
  @override
  final TextStyle tradingFormDetailsContent = const TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: Color(0xFF8C41FF),
  );
  @override
  final Color fiatAmountColor = const Color.fromRGBO(168, 177, 185, 1);
  @override
  Color get headerFloatBoxColor => _colors.brand;
  @override
  Color get headerIconColor => _colors.brand;
  @override
  Color get buttonColorDefault => _colors.surfaceHigh;
  @override
  Color get buttonColorDefaultHover => _colors.brandHover;
  @override
  final Color buttonTextColorDefaultHover = const Color.fromRGBO(
    245,
    249,
    255,
    1,
  );
  @override
  final Color noColor = Colors.transparent;
  @override
  Color get increaseColor => _colors.success;
  @override
  Color get decreaseColor => _colors.danger;
  @override
  final Color zebraDarkColor = const Color.fromRGBO(251, 251, 251, 1);
  @override
  final Color zebraLightColor = Colors.transparent;
  @override
  final Color zebraHoverColor = const Color.fromRGBO(245, 245, 245, 1);
  @override
  final Color passwordButtonSuccessColor = const Color.fromRGBO(
    90,
    230,
    205,
    1,
  );
  @override
  Color get simpleButtonBackgroundColor => _colors.selected;
  @override
  Color get disabledButtonBackgroundColor => _colors.surfaceHighest;
  @override
  final Gradient authorizePageBackgroundColor = const RadialGradient(
    center: Alignment.bottomCenter,
    colors: [
      Color.fromRGBO(202, 225, 245, 1),
      Color.fromRGBO(241, 242, 250, 1),
    ],
  );
  @override
  final Color authorizePageLineColor = const Color.fromRGBO(197, 212, 247, 1);
  @override
  final Color defaultGradientButtonTextColor = Colors.white;
  @override
  Color get defaultCheckboxColor => _colors.brand;
  @override
  final Gradient defaultSwitchColor = const LinearGradient(
    stops: [0, 93],
    colors: [Color(0xFF6B1FE0), Color(0xFF8C41FF)], // GLEEC purple gradient
  );
  @override
  Color get settingsMenuItemBackgroundColor => _colors.surfaceHigh;
  @override
  final Gradient userRewardBoxColor = const LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Colors.white, Color.fromRGBO(218, 228, 251, 1)],
    stops: [0.05, 0.33],
  );
  @override
  Color get rewardBoxShadowColor => _colors.shadow;
  @override
  Color get defaultBorderButtonBorder => _colors.controlBorder;
  @override
  Color get successColor => _colors.success;
  @override
  Color get defaultBorderButtonBackground => _colors.surfaceHigh;
  @override
  final Color defaultCircleButtonBackground = const Color.fromRGBO(
    222,
    235,
    255,
    0.56,
  );
  @override
  final TradingDetailsTheme tradingDetailsTheme = const TradingDetailsTheme();
  @override
  final Color protocolTypeColor = const Color(0xfffcbb80);
  @override
  CoinsManagerTheme get coinsManagerTheme => CoinsManagerTheme(
    searchFieldMobileBackgroundColor: _colors.surfaceHigh,
    filtersPopupShadow: BoxShadow(blurRadius: 13, color: _colors.shadow),
    filterPopupItemBorderColor: _colors.controlBorder,
    listHeaderBorderColor: _colors.border,
    listItemProtocolTextColor: _colors.textPrimary,
    listItemZeroBalanceColor: _colors.textTertiary,
  );
  @override
  DexPageTheme get dexPageTheme => DexPageTheme(
    takerLabelColor: _colors.info,
    makerLabelColor: _colors.brandHover,
    successfulSwapStatusColor: _colors.success,
    failedSwapStatusColor: _colors.danger,
    successfulSwapStatusBackgroundColor: _colors.successContainer,
    activeOrderFormTabColor: _colors.brand,
    inactiveOrderFormTabColor: _colors.textTertiary,
    takerLabel: _colors.info,
    makerLabel: _colors.brandHover,
    successfulSwapStatus: _colors.success,
    failedSwapStatus: _colors.danger,
    successfulSwapStatusBackground: _colors.successContainer,
    activeOrderFormTab: _colors.brand,
    inactiveOrderFormTab: _colors.textTertiary,
    formPlateGradient: LinearGradient(
      colors: [_colors.brandHover, _colors.brand],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    frontPlate: _colors.surfaceRaised,
    frontPlateInner: _colors.surfaceHigh,
    frontPlateBorder: _colors.border,
    activeText: _colors.brand,
    inactiveText: _colors.textTertiary,
    blueText: _colors.brandHover,
    smallButton: _colors.surfaceHigh,
    smallButtonText: _colors.textSecondary,
    pagePlateDivider: _colors.border,
    coinPlateDivider: _colors.border,
    formPlateDivider: _colors.border,
    emptyPlace: _colors.surfaceHigh,
    tokenName: _colors.textPrimary,
    expandMore: _colors.textTertiary,
  );
  @override
  Color get asksColor => _colors.danger;
  @override
  Color get bidsColor => _colors.success;
  @override
  Color get targetColor => _colors.pending;
  @override
  final double dexFormWidth = 480;
  @override
  final double dexInputWidth = 320;
  @override
  Color get specificButtonBorderColor => _colors.controlBorder;
  @override
  Color get specificButtonBackgroundColor => _colors.surfaceHigh;
  @override
  Color get balanceColor => _colors.brand;
  @override
  final Color subBalanceColor = const Color.fromRGBO(124, 136, 171, 1);
  @override
  Color get subCardBackgroundColor => _colors.surfaceHigh;
  @override
  final Color lightButtonColor = const Color.fromRGBO(0, 212, 170, 0.12);
  @override
  Color get filterItemBorderColor => _colors.border;
  @override
  Color get warningColor => _colors.danger;
  @override
  final Color progressBarColor = const Color.fromRGBO(69, 96, 120, 0.33);
  @override
  Color get progressBarPassedColor => _colors.brand;
  @override
  final Color progressBarNotPassedColor = const Color.fromRGBO(
    194,
    203,
    210,
    1,
  );
  @override
  final Color dexSubTitleColor = const Color.fromRGBO(134, 148, 161, 1);
  @override
  Color get tabBarShadowColor => _colors.shadow;
  @override
  final Color smartchainLabelBorderColor = const Color.fromRGBO(32, 22, 49, 1);
  @override
  Color get mainMenuSelectedItemBackgroundColor => _colors.selected;
  @override
  Color get selectedMenuBackgroundColor => _colors.selected;
  @override
  Color get searchFieldMobile => _colors.surfaceHigh;
  @override
  Color get walletEditButtonsBackgroundColor => _colors.surfaceHigh;
  @override
  Color get swapButtonColor => _colors.brand;
  @override
  final bridgeFormHeader = const TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 3.5,
  );
  @override
  final Color keyPadColor = const Color.fromRGBO(251, 251, 251, 1);
  @override
  final Color keyPadTextColor = const Color.fromRGBO(129, 151, 182, 1);
  @override
  Color get dialogBarrierColor => _colors.shadow;
  @override
  final Color dexCoinProtocolColor = const Color.fromRGBO(168, 177, 185, 1);
  @override
  final Color noTransactionsTextColor = const Color.fromRGBO(196, 196, 196, 1);
}
