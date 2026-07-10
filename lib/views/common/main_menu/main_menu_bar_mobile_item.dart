import 'package:app_theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/common/app_assets.dart';
import 'package:web_dex/model/main_menu_value.dart';
import 'package:web_dex/router/state/routing_state.dart';

class MainMenuBarMobileItem extends StatelessWidget {
  MainMenuBarMobileItem({
    required this.value,
    required this.isActive,
    this.enabled = true,
    this.onTap,
  }) : super(key: Key('main-menu-${value.name}'));

  final MainMenuValue value;
  final bool enabled;
  final bool isActive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: enabled
              ? onTap ?? () => routingState.selectedMenu = value
              : null,
          highlightColor: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Padding(
                  key: Key('main-menu-item-icon-${value.name}'),
                  padding: const EdgeInsets.only(bottom: 6.0),
                  child: NavIcon(item: value, isActive: isActive),
                ),
                AutoScrollText(
                  text: value.title,
                  style: isActive
                      ? theme.currentGlobal.bottomNavigationBarTheme
                          .selectedLabelStyle
                          ?.copyWith(
                          color: theme.currentGlobal.bottomNavigationBarTheme
                              .selectedItemColor,
                        )
                      : theme.currentGlobal.bottomNavigationBarTheme
                          .unselectedLabelStyle
                          ?.copyWith(
                          color: theme.currentGlobal.bottomNavigationBarTheme
                              .unselectedItemColor,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
