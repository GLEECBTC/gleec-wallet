import 'package:app_theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/common/app_assets.dart';
import 'package:web_dex/model/main_menu_value.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/motion/swap_motion_tokens.dart';

class MainMenuBarMobileItem extends StatelessWidget {
  MainMenuBarMobileItem({
    required this.value,
    required this.isActive,
    this.enabled = true,
    this.needAttention = false,
  }) : super(key: Key('main-menu-${value.name}'));

  final MainMenuValue value;
  final bool enabled;
  final bool isActive;
  final bool needAttention;

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    final navTheme = theme.currentGlobal.bottomNavigationBarTheme;
    final labelStyle =
        (isActive ? navTheme.selectedLabelStyle : navTheme.unselectedLabelStyle)
            ?.copyWith(
              color: isActive ? palette.text : palette.textTertiary,
              fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
            );
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: enabled
              ? () {
                  routingState.selectedMenu = value;
                }
              : null,
          highlightColor: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Padding(
                  key: Key('main-menu-item-icon-${value.name}'),
                  padding: const EdgeInsets.only(bottom: 4.0),
                  // The selected tab's pill, as in Material's navigation bar:
                  // it marks the tab by shape as well as colour.
                  child: AnimatedContainer(
                    duration: SwapMotion.of(context, SwapMotion.selection),
                    curve: SwapMotion.standard,
                    width: isActive ? 56 : 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isActive
                          ? palette.selected
                          : palette.selected.withValues(alpha: 0),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        NavIcon(item: value, isActive: isActive),
                        if (needAttention)
                          Positioned(
                            top: -2,
                            right: -4,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: theme.currentGlobal.colorScheme.error,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                // Scaled, never cut: "Buy / Sell" read "Buy / Se" on a
                // phone with large text.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(value.title, maxLines: 1, style: labelStyle),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
