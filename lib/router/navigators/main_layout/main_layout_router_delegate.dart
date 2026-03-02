import 'package:flutter/material.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/router/navigators/page_content/page_content_router.dart';
import 'package:web_dex/router/navigators/page_menu/page_menu_router.dart';
import 'package:web_dex/router/routes.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/views/common/main_menu/main_menu_desktop.dart';
import 'package:web_dex/views/main_layout/widgets/main_layout_top_bar.dart';

class MainLayoutRouterDelegate extends RouterDelegate<AppRoutePath>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<AppRoutePath> {
  @override
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        final bool isCompact = width < 1100;
        final double leftPadding = isCompact ? 16 : 24;
        final double rightPadding = isCompact ? 16 : mainLayoutPadding;
        final EdgeInsets contentPadding = EdgeInsets.fromLTRB(
          leftPadding,
          0,
          rightPadding,
          0,
        );

        switch (screenType) {
          case ScreenType.mobile:
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: maxScreenWidth),
                child: _MobileLayout(),
              ),
            );
          case ScreenType.tablet:
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: maxScreenWidth),
                child: _TabletLayout(contentPadding: contentPadding),
              ),
            );
          case ScreenType.desktop:
            return _DesktopLayout(contentPadding: contentPadding);
        }
      },
    );
  }

  @override
  Future<void> setNewRoutePath(AppRoutePath configuration) async {}
}

class _DesktopLayout extends StatelessWidget {
  const _DesktopLayout({required this.contentPadding});

  final EdgeInsets contentPadding;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Full-height drawer sidebar
        Container(
          width: 280, // Fixed width for the sidebar
          decoration: BoxDecoration(
            color: Theme.of(context).appBarTheme.backgroundColor,
            border: Border(
              right: BorderSide(
                color: Theme.of(context).dividerColor,
                width: 1,
              ),
            ),
          ),
          child: MainMenuDesktop(),
        ),
        // Main content area
        Expanded(
          child: Column(
            children: [
              const MainLayoutTopBar(),
              // Main content
              Expanded(
                child: Container(
                  padding: contentPadding,
                  child: PageContentRouter(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TabletLayout extends StatelessWidget {
  const _TabletLayout({required this.contentPadding});

  final EdgeInsets contentPadding;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const MainLayoutTopBar(),
        Expanded(
          child: Container(padding: contentPadding, child: PageContentRouter()),
        ),
      ],
    );
  }
}

class _MobileLayout extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.max,
      children: [
        Flexible(
          child: routingState.isPageContentShown
              ? PageContentRouter()
              : PageMenuRouter(),
        ),
      ],
    );
  }
}
