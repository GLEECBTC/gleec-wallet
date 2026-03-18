import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/settings_menu_value.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/views/common/page_header/page_header.dart';
import 'package:web_dex/views/common/pages/page_layout.dart';
import 'package:web_dex/views/settings/widgets/common/settings_content_wrapper.dart';
import 'package:web_dex/views/settings/widgets/general_settings/general_settings.dart';
import 'package:web_dex/views/settings/widgets/privacy_notice_page/privacy_notice_page.dart';
import 'package:web_dex/views/settings/widgets/security_settings/security_settings_page.dart';
import 'package:web_dex/views/settings/widgets/settings_menu/settings_menu.dart';
import 'package:web_dex/views/settings/widgets/support_page/support_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key = const Key('settings-page'),
    required this.selectedMenu,
  });

  final SettingsMenuValue selectedMenu;

  @override
  Widget build(BuildContext context) {
    if (isMobile) {
      final showMobileMenu = selectedMenu == SettingsMenuValue.none;
      if (showMobileMenu) return _MobileMenuLayout(selectedMenu);
      return _MobileContentLayout(
        selectedMenu: selectedMenu,
        content: _buildContent(selectedMenu),
      );
    }
    return _DesktopLayout(
      selectedMenu: selectedMenu,
      content: _buildContent(selectedMenu),
    );
  }

  Widget _buildContent(SettingsMenuValue selectedMenu) {
    switch (selectedMenu) {
      case SettingsMenuValue.general:
        return const GeneralSettings();
      case SettingsMenuValue.security:
        return SecuritySettingsPage(onBackPressed: _onBackButtonPressed);
      case SettingsMenuValue.privacy:
        return const PrivacyNoticePage();
      case SettingsMenuValue.support:
        return SupportPage();

      case SettingsMenuValue.feedback:
      case SettingsMenuValue.none:
        return Container();
    }
  }
}

class _MobileMenuLayout extends StatelessWidget {
  const _MobileMenuLayout(this.selectedMenu);

  final SettingsMenuValue selectedMenu;

  @override
  Widget build(BuildContext context) {
    return PageLayout(
      header: PageHeader(title: LocaleKeys.settings.tr()),
      content: Flexible(
        child: SettingsMenu(
          selectedMenu: selectedMenu,
          onMenuSelect: (value) =>
              routingState.settingsState.selectedMenu = value,
        ),
      ),
    );
  }
}

class _MobileContentLayout extends StatelessWidget {
  const _MobileContentLayout({
    required this.selectedMenu,
    required this.content,
  });

  final SettingsMenuValue selectedMenu;
  final Widget content;

  @override
  Widget build(BuildContext context) {
    switch (selectedMenu) {
      case SettingsMenuValue.security:
        return content;
      case SettingsMenuValue.general:
      case SettingsMenuValue.privacy:
      case SettingsMenuValue.support:
      case SettingsMenuValue.feedback:
        return PageLayout(
          header: PageHeader(
            title: selectedMenu.title,
            backText: '',
            onBackButtonPressed: _onBackButtonPressed,
          ),
          content: Flexible(child: SettingsContentWrapper(child: content)),
        );
      case SettingsMenuValue.none:
        throw Error();
    }
  }
}

class _DesktopLayout extends StatelessWidget {
  const _DesktopLayout({required this.selectedMenu, required this.content});

  final SettingsMenuValue selectedMenu;
  final Widget content;

  @override
  Widget build(BuildContext context) {
    final isTopSpace =
        selectedMenu != SettingsMenuValue.security &&
        selectedMenu != SettingsMenuValue.support &&
        selectedMenu != SettingsMenuValue.privacy;

    return PageLayout(
      content: Flexible(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.only(top: 30),
                child: SettingsMenu(
                  selectedMenu: selectedMenu,
                  onMenuSelect: (value) =>
                      routingState.settingsState.selectedMenu = value,
                ),
              ),
            ),
            Expanded(
              flex: 8,
              child: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(30, isTopSpace ? 30 : 0, 0, 0),
                  child: content,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _onBackButtonPressed() {
  routingState.settingsState.selectedMenu = SettingsMenuValue.none;
}
