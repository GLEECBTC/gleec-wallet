import 'package:flutter/material.dart';

abstract class ThemeCustomBase {
  const ThemeCustomBase({
    required this.headerIconColor,
    required this.headerFloatBoxColor,
    required this.simpleButtonBackgroundColor,
    required this.disabledButtonBackgroundColor,
    required this.authorizePageBackgroundColor,
    required this.authorizePageLineColor,
    required this.defaultCheckboxColor,
    required this.borderCheckboxColor,
    required this.checkCheckboxColor,
    required this.defaultSwitchColor,
    required this.defaultGradientButtonTextColor,
    required this.settingsMenuItemBackgroundColor,
    required this.passwordButtonSuccessColor,
    required this.defaultBorderButtonBackground,
    required this.defaultBorderButtonBorder,
    required this.defaultCircleButtonBackground,
    required this.userRewardBoxColor,
    required this.rewardBoxShadowColor,
    required this.buttonColorDefault,
    required this.buttonColorDefaultHover,
    required this.buttonTextColorDefaultHover,
    required this.noColor,
    required this.increaseColor,
    required this.decreaseColor,
    required this.successColor,
    required this.protocolTypeColor,
    required this.zebraDarkColor,
    required this.zebraLightColor,
    required this.zebraHoverColor,
    required this.tradingDetailsTheme,
    required this.coinsManagerTheme,
    required this.dexPageTheme,
    required this.asksColor,
    required this.bidsColor,
    required this.targetColor,
    required this.dexFormWidth,
    required this.dexInputWidth,
    required this.specificButtonBorderColor,
    required this.specificButtonBackgroundColor,
    required this.balanceColor,
    required this.subBalanceColor,
    required this.subCardBackgroundColor,
    required this.lightButtonColor,
    required this.filterItemBorderColor,
    required this.warningColor,
    required this.progressBarColor,
    required this.progressBarPassedColor,
    required this.progressBarNotPassedColor,
    required this.dexSubTitleColor,
    required this.selectedMenuBackgroundColor,
    required this.tabBarShadowColor,
    required this.smartchainLabelBorderColor,
    required this.walletEditButtonsBackgroundColor,
    required this.mainMenuSelectedItemBackgroundColor,
    required this.mainMenuItemColor,
    required this.mainMenuSelectedItemColor,
    required this.searchFieldMobile,
    required this.swapButtonColor,
    required this.bridgeFormHeader,
    required this.fiatAmountColor,
    required this.tradingFormDetailsLabel,
    required this.tradingFormDetailsContent,
    required this.keyPadColor,
    required this.keyPadTextColor,
    required this.dexCoinProtocolColor,
    required this.dialogBarrierColor,
    required this.noTransactionsTextColor,
  });

  final Color headerIconColor;
  final Color headerFloatBoxColor;
  final Color simpleButtonBackgroundColor;
  final Color disabledButtonBackgroundColor;
  final Gradient authorizePageBackgroundColor;
  final Color authorizePageLineColor;
  final Color defaultCheckboxColor;
  final Color borderCheckboxColor;
  final Color checkCheckboxColor;
  final Gradient defaultSwitchColor;
  final Color defaultGradientButtonTextColor;
  final Color mainMenuSelectedItemBackgroundColor;
  final Color mainMenuItemColor;
  final Color mainMenuSelectedItemColor;
  final Color settingsMenuItemBackgroundColor;
  final Color passwordButtonSuccessColor;
  final Color defaultBorderButtonBackground;
  final Color defaultBorderButtonBorder;
  final Color defaultCircleButtonBackground;
  final Gradient userRewardBoxColor;
  final Color rewardBoxShadowColor;
  final Color buttonColorDefault;
  final Color buttonColorDefaultHover;
  final Color buttonTextColorDefaultHover;
  final Color noColor;
  final Color increaseColor;
  final Color decreaseColor;
  final Color successColor;
  final Color protocolTypeColor;
  final Color zebraDarkColor;
  final Color zebraHoverColor;
  final Color zebraLightColor;

  final TradingDetailsTheme tradingDetailsTheme;
  final CoinsManagerTheme coinsManagerTheme;
  final DexPageTheme dexPageTheme;

  final Color asksColor;
  final Color bidsColor;
  final Color targetColor;
  final double dexFormWidth;
  final double dexInputWidth;
  final Color specificButtonBackgroundColor;
  final Color specificButtonBorderColor;
  final Color balanceColor;
  final Color subBalanceColor;
  final Color subCardBackgroundColor;
  final Color lightButtonColor;
  final Color filterItemBorderColor;
  final Color warningColor;
  final Color progressBarColor;
  final Color progressBarPassedColor;
  final Color progressBarNotPassedColor;
  final Color dexSubTitleColor;
  final Color selectedMenuBackgroundColor;
  final Color tabBarShadowColor;
  final Color smartchainLabelBorderColor;
  final Color searchFieldMobile;
  final Color walletEditButtonsBackgroundColor;
  final Color swapButtonColor;

  final TextStyle bridgeFormHeader;
  final Color fiatAmountColor;
  final TextStyle tradingFormDetailsLabel;
  final TextStyle tradingFormDetailsContent;
  final Color keyPadColor;
  final Color keyPadTextColor;
  final Color dexCoinProtocolColor;
  final Color dialogBarrierColor;
  final Color noTransactionsTextColor;
}

class TradingDetailsTheme {
  const TradingDetailsTheme({
    this.swapStatusColors = const [
      Color.fromRGBO(130, 168, 239, 1),
      Color.fromRGBO(106, 77, 227, 0.59),
      Color.fromRGBO(106, 77, 227, 0.59),
      Color.fromRGBO(34, 121, 241, 0.59),
    ],
    this.swapFailedStatusColors = const [
      Color.fromRGBO(229, 33, 103, 0.6),
      Color.fromRGBO(226, 22, 169, 0.6),
    ],
    this.swapStepTimerColor = const Color.fromRGBO(162, 175, 187, 1),
    this.swapStepCircleNormalColor = const Color.fromRGBO(137, 147, 236, 1),
    this.swapStepCircleFailedColor = const Color.fromRGBO(229, 33, 106, 1),
    this.swapStepCircleDisabledColor = const Color.fromRGBO(194, 203, 210, 1),
    this.swapStepTextFailedColor = const Color.fromRGBO(229, 33, 103, 1),
    this.swapStepTextDisabledColor = const Color.fromRGBO(162, 176, 188, 1),
    this.swapStepTextCurrentColor = const Color.fromRGBO(72, 137, 235, 1),
  });
  final List<Color> swapStatusColors;
  final List<Color> swapFailedStatusColors;
  final Color swapStepTimerColor;
  final Color swapStepCircleNormalColor;
  final Color swapStepCircleFailedColor;
  final Color swapStepCircleDisabledColor;
  final Color swapStepTextFailedColor;
  final Color swapStepTextDisabledColor;
  final Color swapStepTextCurrentColor;
}

class CoinsManagerTheme {
  const CoinsManagerTheme({
    this.searchFieldMobileBackgroundColor = const Color.fromRGBO(
      242,
      242,
      242,
      1,
    ),
    this.filtersPopupShadow = const BoxShadow(
      offset: Offset(0, 0),
      blurRadius: 13,
      color: Color.fromRGBO(0, 0, 0, 0.06),
    ),
    this.filterPopupItemBorderColor = const Color.fromRGBO(136, 146, 235, 1),
    this.listHeaderBorderColor = const Color.fromRGBO(234, 234, 234, 1),
    this.listItemProtocolTextColor = Colors.white,
    this.listItemZeroBalanceColor = const Color.fromRGBO(215, 223, 248, 1),
  });
  final Color searchFieldMobileBackgroundColor;
  final BoxShadow filtersPopupShadow;
  final Color filterPopupItemBorderColor;
  final Color listHeaderBorderColor;
  final Color listItemProtocolTextColor;
  final Color listItemZeroBalanceColor;
}

class DexPageTheme {
  const DexPageTheme({
    this.takerLabelColor = const Color.fromRGBO(47, 179, 239, 1),
    this.makerLabelColor = const Color.fromRGBO(106, 77, 227, 1),
    this.successfulSwapStatusColor = const Color.fromRGBO(73, 212, 162, 1),
    this.failedSwapStatusColor = const Color.fromRGBO(229, 33, 103, 1),
    this.successfulSwapStatusBackgroundColor = const Color.fromRGBO(
      73,
      212,
      162,
      0.12,
    ),
    this.activeOrderFormTabColor = const Color.fromRGBO(89, 107, 231, 1),
    this.inactiveOrderFormTabColor = const Color.fromRGBO(206, 210, 247, 1),
    this.takerLabel = const Color.fromRGBO(47, 179, 239, 1),
    this.makerLabel = const Color.fromRGBO(106, 77, 227, 1),
    this.successfulSwapStatus = const Color.fromRGBO(73, 212, 162, 1),
    this.failedSwapStatus = const Color.fromRGBO(229, 33, 103, 1),
    this.successfulSwapStatusBackground = const Color.fromRGBO(
      73,
      212,
      162,
      0.12,
    ),
    this.activeOrderFormTab = const Color.fromRGBO(89, 107, 231, 1),
    this.inactiveOrderFormTab = const Color.fromRGBO(206, 210, 247, 1),
    this.formPlateGradient = const LinearGradient(
      colors: [
        Color.fromRGBO(218, 235, 255, 1),
        Color.fromRGBO(234, 233, 255, 1),
      ],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    ),
    this.frontPlate = const Color.fromRGBO(255, 255, 255, 1),
    this.frontPlateInner = const Color.fromRGBO(255, 255, 255, 1),
    this.frontPlateBorder = const Color.fromRGBO(239, 239, 239, 1),
    this.activeText = const Color.fromRGBO(69, 96, 120, 1),
    this.inactiveText = const Color.fromRGBO(168, 178, 204, 1),
    this.blueText = const Color.fromRGBO(80, 104, 214, 1),
    this.smallButton = const Color.fromRGBO(241, 244, 246, 1),
    this.smallButtonText = const Color.fromRGBO(69, 96, 120, 1),
    this.pagePlateDivider = const Color.fromRGBO(244, 244, 244, 1),
    this.coinPlateDivider = const Color.fromRGBO(244, 244, 244, 1),
    this.formPlateDivider = const Color.fromRGBO(218, 224, 246, 1),
    this.emptyPlace = const Color.fromRGBO(239, 239, 239, 1),
    this.tokenName = Colors.white,
    this.expandMore = const Color.fromRGBO(153, 168, 181, 1),
  });

  final Color takerLabelColor;
  final Color makerLabelColor;
  final Color successfulSwapStatusColor;
  final Color failedSwapStatusColor;
  final Color successfulSwapStatusBackgroundColor;
  final Color activeOrderFormTabColor;
  final Color inactiveOrderFormTabColor;

  final Color activeOrderFormTab;
  final Color inactiveOrderFormTab;
  final Color takerLabel;
  final Color makerLabel;
  final Color successfulSwapStatus;
  final Color failedSwapStatus;
  final Color successfulSwapStatusBackground;
  final Color activeText;
  final Color inactiveText;
  final Color blueText;
  final Color smallButton;
  final Color smallButtonText;

  final Color pagePlateDivider;
  final Color coinPlateDivider;
  final Color formPlateDivider;
  final Color emptyPlace;

  final Color tokenName;
  final Color frontPlate;
  final Color frontPlateInner;
  final Color frontPlateBorder;
  final Color expandMore;

  final LinearGradient formPlateGradient;
}
