import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/motion/swap_motion_tokens.dart';
import 'package:web_dex/views/wallet/wallet_page/wallet_home/wallet_asset_picker_sheet.dart';
import 'package:web_dex/views/wallet/wallet_page/wallet_home/wallet_home_assets.dart';
import 'package:web_dex/views/wallet/wallet_page/wallet_home/wallet_home_style.dart';

/// The parts of the wallet home under the balance.
enum WalletHomeSection {
  assets,
  growth,
  profitLoss;

  String get label => switch (this) {
    WalletHomeSection.assets => LocaleKeys.assets.tr(),
    WalletHomeSection.growth => LocaleKeys.growth.tr(),
    WalletHomeSection.profitLoss => LocaleKeys.profitAndLoss.tr(),
  };
}

/// The toolbar that stays pinned over the list: the section switcher, and on
/// Assets a search button. Searching swaps the row for a search field.
class WalletAssetsToolbarDelegate extends SliverPersistentHeaderDelegate {
  WalletAssetsToolbarDelegate({
    required this.section,
    required this.onSection,
    required this.searchOpen,
    required this.onSearchOpen,
    required this.onSearchClose,
    required this.searchController,
    required this.searchFocusNode,
    required this.onSearchChanged,
    required this.textScaler,
    this.inlineSearch = false,
    this.addAssets = false,
    this.inset = 0,
  });

  final WalletHomeSection section;
  final ValueChanged<WalletHomeSection> onSection;
  final bool searchOpen;
  final VoidCallback onSearchOpen;
  final VoidCallback onSearchClose;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final ValueChanged<String> onSearchChanged;

  /// The toolbar grows with the text size, so its labels are never clipped.
  final TextScaler textScaler;

  /// Shows the search field beside the sections, where there is room for
  /// it, rather than behind a button.
  final bool inlineSearch;

  /// Puts Add assets beside the search, since at the foot of a long list it
  /// is out of sight.
  final bool addAssets;

  /// Keeps the toolbar to the page's centred column. The header takes it
  /// rather than sitting in a padding sliver, as a viewport only allows for
  /// pinned headers it holds directly: a row scrolled into view would land
  /// under the toolbar.
  final double inset;

  double get _extent => 48 + textScaler.scale(16);

  @override
  double get minExtent => _extent;

  @override
  double get maxExtent => _extent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final palette = SwapPalette.of(context);
    final pinned = shrinkOffset > 0 || overlapsContent;
    return ColoredBox(
      color: palette.canvas,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: inset),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: pinned ? palette.border : palette.canvas,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: WalletHomeGeometry.gutter,
              vertical: 8,
            ),
            child: AnimatedSwitcher(
              duration: SwapMotion.of(context, SwapMotion.selection),
              child: searchOpen
                  ? _SearchRow(
                      key: const ValueKey('search'),
                      controller: searchController,
                      focusNode: searchFocusNode,
                      onChanged: onSearchChanged,
                      onClose: onSearchClose,
                    )
                  : _SectionRow(
                      key: const ValueKey('sections'),
                      section: section,
                      onSection: onSection,
                      onSearchOpen: onSearchOpen,
                      addAssets: addAssets,
                      search: inlineSearch
                          ? WalletHomeSearchField(
                              fieldKey: const Key('wallet-page-search-field'),
                              controller: searchController,
                              focusNode: searchFocusNode,
                              onChanged: onSearchChanged,
                            )
                          : null,
                    ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(WalletAssetsToolbarDelegate oldDelegate) =>
      section != oldDelegate.section ||
      searchOpen != oldDelegate.searchOpen ||
      textScaler != oldDelegate.textScaler ||
      searchController != oldDelegate.searchController ||
      inlineSearch != oldDelegate.inlineSearch ||
      addAssets != oldDelegate.addAssets ||
      inset != oldDelegate.inset;
}

class _SectionRow extends StatelessWidget {
  const _SectionRow({
    required this.section,
    required this.onSection,
    required this.onSearchOpen,
    required this.addAssets,
    this.search,
    super.key,
  });

  /// Below this width Add assets drops its label, so the pills keep room.
  static const _labelledAddFrom = 720.0;

  final WalletHomeSection section;
  final ValueChanged<WalletHomeSection> onSection;
  final VoidCallback onSearchOpen;
  final bool addAssets;

  /// The search field, in place of the button that opens it.
  final Widget? search;

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        children: [
          Expanded(
            child: _FadingScroll(
              child: Row(
                spacing: 4,
                children: [
                  for (final item in WalletHomeSection.values)
                    _Segment(
                      section: item,
                      selected: item == section,
                      onTap: () => onSection(item),
                    ),
                ],
              ),
            ),
          ),
          if (section == WalletHomeSection.assets) ...[
            if (search case final search?)
              SizedBox(width: 280, child: search)
            else
              IconButton(
                key: const Key('wallet-home-search-button'),
                tooltip: LocaleKeys.searchAssets.tr(),
                color: palette.textSecondary,
                onPressed: onSearchOpen,
                icon: const Icon(Icons.search_rounded),
              ),
            if (addAssets) ...[
              const SizedBox(width: 8),
              WalletAddAssetsButton(
                compact: true,
                iconOnly: constraints.maxWidth < _labelledAddFrom,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// Scrolls the pills sideways when they do not fit, as with large text, and
/// fades the edge while more of them lie past it.
class _FadingScroll extends StatefulWidget {
  const _FadingScroll({required this.child});

  final Widget child;

  @override
  State<_FadingScroll> createState() => _FadingScrollState();
}

class _FadingScrollState extends State<_FadingScroll> {
  final _controller = ScrollController();
  bool _more = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_update);
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _update() {
    if (!mounted || !_controller.hasClients) return;
    final more = _controller.position.extentAfter > 1;
    if (more != _more) setState(() => _more = more);
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) {
        _update();
        return false;
      },
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) => LinearGradient(
          colors: [
            Colors.white,
            Colors.white,
            Colors.white.withValues(alpha: _more ? 0 : 1),
          ],
          stops: [0, 1 - 32 / bounds.width.clamp(64, double.infinity), 1],
        ).createShader(bounds),
        child: SingleChildScrollView(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          child: widget.child,
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.section,
    required this.selected,
    required this.onTap,
  });

  final WalletHomeSection section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    final radius = BorderRadius.circular(12);
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: Key('wallet-home-section-${section.name}'),
          borderRadius: radius,
          onTap: selected ? null : onTap,
          child: AnimatedContainer(
            duration: SwapMotion.of(context, SwapMotion.selection),
            curve: SwapMotion.standard,
            constraints: const BoxConstraints(minHeight: 40),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: selected ? palette.selected : Colors.transparent,
              borderRadius: radius,
            ),
            child: Text(
              section.label,
              maxLines: 1,
              style: WalletHomeText.segment(context, selected: selected),
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchRow extends StatelessWidget {
  const _SearchRow({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClose,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    return Row(
      children: [
        Expanded(
          child: WalletHomeSearchField(
            fieldKey: const Key('wallet-page-search-field'),
            controller: controller,
            focusNode: focusNode,
            autofocus: true,
            onChanged: onChanged,
          ),
        ),
        const SizedBox(width: 4),
        TextButton(
          key: const Key('wallet-home-search-close'),
          onPressed: onClose,
          style: TextButton.styleFrom(
            foregroundColor: palette.brandHover,
            minimumSize: const Size(48, 48),
          ),
          child: Text(LocaleKeys.cancel.tr()),
        ),
      ],
    );
  }
}
