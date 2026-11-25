import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart' show AppPalette;
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/ui/ui_tab_bar/ui_tab.dart';
import 'package:web_dex/shared/ui/ui_tab_bar/ui_tab_bar.dart';

class FiatActionTabBar extends StatefulWidget {
  const FiatActionTabBar({
    Key? key,
    required this.currentTabIndex,
    required this.onTabClick,
  }) : super(key: key);
  final int currentTabIndex;
  final Function(int) onTabClick;

  @override
  State<FiatActionTabBar> createState() => _FiatActionTabBarState();
}

class _FiatActionTabBarState extends State<FiatActionTabBar> {
  final List<StreamSubscription> _listeners = [];

  @override
  void initState() {
    _onDataChange(null);

    super.initState();
  }

  @override
  void dispose() {
    _listeners.map((listener) => listener.cancel());

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return UiTabBar(
      currentTabIndex: widget.currentTabIndex,
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(36),
        border: Border.all(color: palette.border),
      ),
      tabs: [
        UiTab(
          key: const Key('fiat-buy-tab'),
          text: LocaleKeys.buy.tr(),
          isSelected: widget.currentTabIndex == 0,
          onClick: () => widget.onTabClick(0),
        ),
        UiTab(
          key: const Key('fiat-sell-tab'),
          text: LocaleKeys.sell.tr(),
          isSelected: widget.currentTabIndex == 1,
          onClick: () => widget.onTabClick(1),
        ),
      ],
    );
  }

  void _onDataChange(dynamic _) {
    if (!mounted) return;
  }
}
