import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/model/settings_menu_value.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/services/feedback/feedback_service.dart';
import 'package:web_dex/shared/widgets/hidden_without_wallet.dart';
import 'package:web_dex/views/settings/widgets/general_settings/app_version_number.dart';
import 'package:web_dex/views/settings/widgets/settings_menu/settings_logout_button.dart';
import 'package:web_dex/views/settings/widgets/settings_menu/settings_menu_item.dart';

class SettingsMenu extends StatelessWidget {
  const SettingsMenu({
    super.key,
    required this.onMenuSelect,
    required this.selectedMenu,
  });

  final SettingsMenuValue selectedMenu;

  final void Function(SettingsMenuValue) onMenuSelect;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthBlocState>(
      builder: (context, state) {
        final showSecurity = state.currentUser?.wallet.isHW == false;

        final Set<SettingsMenuValue> menuItems = <SettingsMenuValue>{
          SettingsMenuValue.general,
          if (showSecurity) SettingsMenuValue.security,
          SettingsMenuValue.privacy,
          SettingsMenuValue.kycPolicy,
          if (context.isFeedbackAvailable) SettingsMenuValue.feedback,
        };
        return FocusTraversalGroup(
          child: Column(
            mainAxisSize: MainAxisSize.max,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(18.0),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  children: menuItems
                      .map((item) => _buildItem(item, isMobile, context))
                      .toList(),
                ),
              ),
              if (!isMobile) const Spacer(),
              const HiddenWithoutWallet(child: SettingsLogoutButton()),
              if (isMobile) const Spacer(),
              const AppVersionNumber(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildItem(
    SettingsMenuValue menuValue,
    bool isMobile,
    BuildContext context,
  ) {
    if (menuValue == SettingsMenuValue.feedback) {
      return Container(
        constraints: isMobile ? null : const BoxConstraints(maxWidth: 206),
        child: SettingsMenuItem(
          key: Key('settings-menu-item-${menuValue.name}'),
          isSelected: false,
          isMobile: isMobile,
          menu: menuValue,
          onTap: (_) => context.showFeedback(),
          text: menuValue.title,
        ),
      );
    }

    final Widget item = Container(
      constraints: isMobile ? null : const BoxConstraints(maxWidth: 206),
      child: SettingsMenuItem(
        key: Key('settings-menu-item-${menuValue.name}'),
        isSelected: menuValue == selectedMenu,
        isMobile: isMobile,
        menu: menuValue,
        onTap: onMenuSelect,
        text: menuValue.title,
      ),
    );
    if (menuValue == SettingsMenuValue.security) {
      return HiddenWithoutWallet(child: item);
    }
    return item;
  }
}
