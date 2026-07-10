import 'package:app_theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/model/main_menu_value.dart';

class Assets {
  static const seedSuccess = '$assetsPath/others/seed_success.svg';
  static const dexSwapCoins = '$assetsPath/others/dex_swap.svg';
  static const dexChevronDown = '$assetsPath/others/dex_chevron_down.svg';
  static const dexChevronUp = '$assetsPath/others/dex_chevron_down.svg';
  static const chevronLeftMobile = '$assetsPath/others/chevron_left_mobile.svg';
  static const chevronDown = '$assetsPath/others/chevron_down.svg';
  static const chevronUp = '$assetsPath/others/chevron_up.svg';
  static const assetTick = '$assetsPath/others/tick.svg';
  static const assetsDenied = '$assetsPath/others/denied.svg';
  static const discord = '$assetsPath/others/discord_icon.svg';
  static const seedBackedUp = '$assetsPath/ui_icons/seed_backed_up.svg';
  static const seedNotBackedUp = '$assetsPath/ui_icons/seed_not_backed_up.svg';
}

enum ColorFilterEnum {
  expandMode,
  headerIconColor,
}

class DexSvgImage extends StatelessWidget {
  final String path;
  final ColorFilterEnum? colorFilter;
  final double? size;
  const DexSvgImage(
      {super.key, required this.path, this.colorFilter, this.size});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      path,
      colorFilter: _getColorFilter(),
      width: size,
    );
  }

  ColorFilter? _getColorFilter() {
    switch (colorFilter) {
      case ColorFilterEnum.expandMode:
        return ColorFilter.mode(dexPageColors.expandMore, BlendMode.srcIn);
      case ColorFilterEnum.headerIconColor:
        return ColorFilter.mode(theme.custom.headerIconColor, BlendMode.srcIn);
      default:
        return null;
    }
  }
}

class RewardBackground extends StatelessWidget {
  const RewardBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      '$assetsPath/others/rewardBackgroundImage.png',
      filterQuality: FilterQuality.high,
    );
  }
}

class NavIcon extends StatelessWidget {
  const NavIcon({
    required this.item,
    required this.isActive,
    super.key,
  });

  final MainMenuValue item;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    if (item == MainMenuValue.card || item == MainMenuValue.more) {
      final color = isActive
          ? theme.custom.mainMenuSelectedItemColor
          : theme.custom.mainMenuItemColor;
      return Icon(
        item == MainMenuValue.card
            ? Icons.credit_card_rounded
            : Icons.more_horiz_rounded,
        color: color,
        size: isTablet ? 30 : 20,
      );
    }
    final String iconPath = '/${item.name.split('.').last}';
    final String screenPath = isMobile ? '/mobile' : '/desktop';
    final String themePath = isMobile
        ? ''
        : theme.mode == ThemeMode.dark
            ? '/dark'
            : '/light';
    final String activeSuffix = isActive ? '_active' : '';

    return SvgPicture.asset(
      '$assetsPath/nav_icons$screenPath$themePath$iconPath$activeSuffix.svg',
      width: isTablet ? 30 : 20,
      height: isTablet ? 30 : 20,
    );
  }
}
