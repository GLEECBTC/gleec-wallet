import 'package:flutter/material.dart';

import '../common/theme_custom_base.dart';

class ThemeCustomDark extends ThemeExtension<ThemeCustomDark>
    implements ThemeCustomBase {
  ThemeCustomDark();

  @override
  late final Color suspendedBannerBackgroundColor;

  void initializeThemeDependentColors(ThemeData theme) {
    suspendedBannerBackgroundColor = theme.colorScheme.onSurface;
  }

  @override
  ThemeExtension<ThemeCustomDark> copyWith() {
    return this;
  }

  @override
  ThemeExtension<ThemeCustomDark> lerp(
    ThemeExtension<ThemeCustomDark>? other,
    double t,
  ) {
    if (other is! ThemeCustomDark) return this;
    return this;
  }

  @override
  final Color mainMenuItemColor = const Color.fromRGBO(173, 175, 198, 1);
  @override
  final Color mainMenuSelectedItemColor = Colors.white;
  @override
  final Color checkCheckboxColor = Colors.white;
  @override
  final Color borderCheckboxColor = const Color.fromRGBO(62, 70, 99, 1);
  @override
  final TextStyle tradingFormDetailsLabel = const TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
  );
  @override
  final TextStyle tradingFormDetailsContent = const TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: Color.fromRGBO(106, 139, 235, 1),
  );
  @override
  final Color fiatAmountColor = const Color.fromRGBO(168, 177, 185, 1);
  @override
  final Color headerFloatBoxColor = const Color(0xFF8C41FF); // GLEEC primary
  @override
  final Color headerIconColor = const Color.fromRGBO(255, 255, 255, 1);
  @override
  final Color buttonColorDefault = const Color.fromRGBO(23, 29, 48, 1);

  @override
  final Color buttonColorDefaultHover = const Color.fromRGBO(76, 128, 233, 1);
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
  final Color increaseColor = const Color(0xFF00C058); // GLEEC OK color
  @override
  final Color decreaseColor = const Color(0xFFE52167); // GLEEC Warning color
  @override
  final Color zebraDarkColor = const Color(0xFF0F0F0F);
  @override
  final Color zebraLightColor = const Color(0xFF141414);
  @override
  final Color zebraHoverColor = const Color(0xFF1A1A1A);
  @override
  final Color passwordButtonSuccessColor = const Color.fromRGBO(
    90,
    230,
    205,
    1,
  );
  @override
  final Color simpleButtonBackgroundColor = const Color.fromRGBO(
    136,
    146,
    235,
    0.2,
  );
  @override
  final Color disabledButtonBackgroundColor = const Color.fromRGBO(
    90,
    104,
    230,
    0.3,
  );
  @override
  final Gradient authorizePageBackgroundColor = const RadialGradient(
    center: Alignment.bottomCenter,
    colors: [
      Color.fromRGBO(42, 188, 241, 0.1),
      Color.fromRGBO(42, 188, 241, 0),
    ],
  );
  @override
  final Color authorizePageLineColor = const Color.fromRGBO(255, 255, 255, 0.1);
  @override
  final Color defaultGradientButtonTextColor = Colors.white;
  @override
  final Color defaultCheckboxColor = const Color.fromRGBO(81, 121, 233, 1);
  @override
  final Gradient defaultSwitchColor = const LinearGradient(
    stops: [0, 93],
    colors: [Color(0xFF6B1FE0), Color(0xFF8C41FF)], // GLEEC purple gradient
  );
  @override
  final Color settingsMenuItemBackgroundColor = const Color(0xFF141414);
  @override
  final Gradient userRewardBoxColor = const LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color.fromRGBO(18, 20, 32, 1), Color.fromRGBO(22, 25, 39, 1)],
    stops: [0.05, 0.33],
  );
  @override
  final Color rewardBoxShadowColor = const Color.fromRGBO(0, 0, 0, 0.1);
  @override
  final Color defaultBorderButtonBorder = const Color(0xFF8C41FF); // GLEEC primary
  @override
  final Color defaultBorderButtonBackground = const Color.fromRGBO(
    22,
    25,
    39,
    1,
  );
  @override
  final Color successColor = const Color.fromRGBO(0, 192, 88, 1);

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
  final CoinsManagerTheme coinsManagerTheme = const CoinsManagerTheme(
    searchFieldMobileBackgroundColor: Color(0xFF1A1A1A),
    filtersPopupShadow: BoxShadow(
      offset: Offset(0, 0),
      blurRadius: 8,
      color: Color.fromRGBO(0, 0, 0, 0.3),
    ),
    filterPopupItemBorderColor: Color(0xFF8C41FF), // GLEEC primary
  );
  @override
  final DexPageTheme dexPageTheme = const DexPageTheme(
    activeOrderFormTabColor: Color.fromRGBO(255, 255, 255, 1),
    inactiveOrderFormTabColor: Color.fromRGBO(152, 155, 182, 1),
    activeOrderFormTab: Color.fromRGBO(255, 255, 255, 1),
    inactiveOrderFormTab: Color.fromRGBO(152, 155, 182, 1),
    formPlateGradient: LinearGradient(
      colors: [
        Color.fromRGBO(134, 213, 255, 1),
        Color.fromRGBO(178, 107, 255, 1),
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    frontPlate: Color.fromRGBO(32, 35, 55, 1),
    frontPlateInner: Color.fromRGBO(21, 25, 33, 1),
    frontPlateBorder: Color.fromRGBO(43, 49, 87, 1),
    activeText: Colors.white,
    inactiveText: Color.fromRGBO(123, 131, 152, 1),
    blueText: Color.fromRGBO(100, 124, 233, 1),
    smallButton: Color.fromRGBO(35, 45, 72, 1),
    smallButtonText: Color.fromRGBO(141, 150, 167, 1),
    pagePlateDivider: Color.fromRGBO(32, 37, 63, 1),
    coinPlateDivider: Color.fromRGBO(44, 51, 81, 1),
    formPlateDivider: Color.fromRGBO(48, 57, 96, 1),
    emptyPlace: Color.fromRGBO(40, 44, 69, 1),
    tokenName: Color.fromRGBO(69, 96, 120, 1),
    expandMore: Color.fromRGBO(153, 168, 181, 1),
  );
  @override
  final Color asksColor = const Color(0xFFE52167); // GLEEC Warning
  @override
  final Color bidsColor = const Color(0xFF00C058); // GLEEC OK color
  @override
  final Color targetColor = Colors.orange;
  @override
  final double dexFormWidth = 480;
  @override
  final double dexInputWidth = 320;
  @override
  final Color specificButtonBorderColor = const Color.fromRGBO(38, 40, 52, 1);
  @override
  final Color specificButtonBackgroundColor = const Color(0xFF141414);
  @override
  final Color balanceColor = const Color.fromRGBO(106, 139, 235, 1);
  @override
  final Color subBalanceColor = const Color.fromRGBO(124, 136, 171, 1);
  @override
  final Color subCardBackgroundColor = const Color(0xFF0F0F0F);
  @override
  final Color lightButtonColor = const Color.fromRGBO(0, 212, 170, 0.12);
  @override
  final Color filterItemBorderColor = const Color.fromRGBO(52, 56, 77, 1);
  @override
  final Color warningColor = const Color.fromRGBO(229, 33, 103, 1);
  @override
  final Color progressBarColor = const Color.fromRGBO(69, 96, 120, 0.33);
  @override
  final Color progressBarPassedColor = const Color.fromRGBO(137, 147, 236, 1);
  @override
  final Color progressBarNotPassedColor = const Color.fromRGBO(
    194,
    203,
    210,
    1,
  );
  @override
  final Color dexSubTitleColor = const Color.fromRGBO(255, 255, 255, 1);
  @override
  final Color selectedMenuBackgroundColor = const Color.fromRGBO(
    46,
    52,
    112,
    1,
  );
  @override
  final Color tabBarShadowColor = const Color.fromRGBO(255, 255, 255, 0.08);
  @override
  final Color smartchainLabelBorderColor = const Color.fromRGBO(32, 22, 49, 1);
  @override
  final Color mainMenuSelectedItemBackgroundColor = const Color.fromRGBO(
    0,
    212,
    170,
    0.12,
  );
  @override
  final Color searchFieldMobile = const Color.fromRGBO(42, 47, 62, 1);
  @override
  final Color walletEditButtonsBackgroundColor = const Color.fromRGBO(
    29,
    33,
    53,
    1,
  );
  @override
  final Color swapButtonColor = const Color.fromRGBO(64, 146, 219, 1);
  @override
  final bridgeFormHeader = const TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 3.5,
  );
  @override
  final Color keyPadColor = const Color(0xFF000000);
  @override
  final Color keyPadTextColor = const Color.fromRGBO(129, 151, 182, 1);
  @override
  final Color dexCoinProtocolColor = const Color.fromRGBO(168, 177, 185, 1);
  @override
  final Color dialogBarrierColor = const Color.fromRGBO(3, 26, 43, 0.36);
  @override
  final Color noTransactionsTextColor = const Color.fromRGBO(196, 196, 196, 1);
}
