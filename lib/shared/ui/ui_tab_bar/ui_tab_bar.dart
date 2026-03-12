import 'package:app_theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/shared/ui/gradient_border.dart';
import 'package:web_dex/shared/ui/ui_tab_bar/ui_tab.dart';

class UiTabBar extends StatefulWidget {
  const UiTabBar({Key? key, required this.currentTabIndex, required this.tabs})
    : super(key: key);

  final int currentTabIndex;
  final List<UiTab> tabs;

  @override
  State<UiTabBar> createState() => _UiTabBarState();
}

class _UiTabBarState extends State<UiTabBar> {
  final GlobalKey _switcherKey = GlobalKey();
  final int _tabsOnMobile = 3;

  @override
  Widget build(BuildContext context) {
    final bool isMobileLayout = isMobile;
    final bool isScrollable = isMobileLayout;
    final tabs = _buildTabs(
      useFlexible: !isScrollable,
      isMobileLayout: isMobileLayout,
    );
    return GradientBorder(
      borderRadius: const BorderRadius.all(Radius.circular(36)),
      innerColor: dexPageColors.frontPlate,
      gradient: dexPageColors.formPlateGradient,
      child: Container(
        constraints: BoxConstraints(maxWidth: theme.custom.dexFormWidth),
        padding: const EdgeInsets.all(2),
        child: SizedBox(
          height: 36,
          child: FocusTraversalGroup(
            child: isScrollable
                ? SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(mainAxisSize: MainAxisSize.min, children: tabs),
                  )
                : Row(children: tabs),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildTabs({
    required bool useFlexible,
    required bool isMobileLayout,
  }) {
    final List<Widget> children = [];

    for (int i = 0; i < widget.tabs.length; i++) {
      Widget tab = widget.tabs[i];
      if (isMobileLayout) {
        tab = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: tab,
        );
      }
      children.add(useFlexible ? Flexible(child: tab) : tab);

      // We need a way to fit all tabs
      // in mobile screens with limited width
      if (_isLastNotHiddenTabMobile(i)) {
        children.add(
          Padding(
            padding: EdgeInsets.only(left: isMobile ? 6.0 : 1.0),
            child: _buildMobileDropdown(),
          ),
        );

        break;
      }
    }

    return children;
  }

  bool _isLastNotHiddenTabMobile(int i) {
    return i == _tabsOnMobile - 1 &&
        isMobile &&
        widget.tabs.length > _tabsOnMobile;
  }

  Widget _buildMobileDropdown() {
    final bool isSelected = widget.currentTabIndex >= _tabsOnMobile;
    return UiDropdown(
      borderRadius: BorderRadius.circular(50),
      switcher: Container(
        key: _switcherKey,
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: isSelected ? Theme.of(context).colorScheme.primary : null,
          shape: BoxShape.circle,
          border: Border.all(color: const Color.fromRGBO(158, 213, 244, 1)),
        ),
        child: Center(
          child: Icon(
            Icons.more_horiz,
            color: isSelected
                ? Colors.white
                : const Color.fromRGBO(158, 213, 244, 1),
          ),
        ),
      ),
      dropdown: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              offset: const Offset(0, 1),
              blurRadius: 8,
              color: theme.custom.tabBarShadowColor,
            ),
          ],
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(children: _buildDropdownTabs()),
        ),
      ),
    );
  }

  List<Widget> _buildDropdownTabs() {
    final List<Widget> childrenMobile = [];

    for (int i = _tabsOnMobile; i < widget.tabs.length; i++) {
      childrenMobile.add(_buildDropdownItem(widget.tabs[i]));
    }

    return childrenMobile;
  }

  Widget _buildDropdownItem(UiTab tab) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: tab.onClick == null
          ? null
          : () {
              tab.onClick!();
              _clickOnDropDownSwitcher();
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 9),
        child: Text(
          tab.text,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  void _clickOnDropDownSwitcher() {
    final RenderBox? box =
        _switcherKey.currentContext?.findRenderObject() as RenderBox?;
    final Offset? position = box?.localToGlobal(Offset.zero);
    if (box != null && position != null) {
      WidgetsBinding.instance.handlePointerEvent(
        PointerDownEvent(pointer: 0, position: position),
      );
      WidgetsBinding.instance.handlePointerEvent(
        PointerUpEvent(pointer: 0, position: position),
      );
    }
  }
}
