import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/coins_bloc/coins_bloc.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/bloc/settings/settings_bloc.dart';
import 'package:web_dex/bloc/settings/settings_event.dart';
import 'package:web_dex/services/arrr_activation/arrr_activation_service.dart';
import 'package:web_dex/shared/utils/balance_utils.dart';
import 'package:web_dex/shared/utils/extensions/sdk_extensions.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/motion/swap_motion_tokens.dart';
import 'package:web_dex/views/wallet/wallet_page/wallet_home/wallet_assets_toolbar.dart';
import 'package:web_dex/views/wallet/wallet_page/wallet_home/wallet_balance_hero.dart';
import 'package:web_dex/views/wallet/wallet_page/wallet_home/wallet_home_assets.dart';
import 'package:web_dex/views/wallet/wallet_page/wallet_home/wallet_home_header.dart';
import 'package:web_dex/views/wallet/wallet_page/wallet_home/wallet_home_insights.dart';
import 'package:web_dex/views/wallet/wallet_page/wallet_home/wallet_home_style.dart';
import 'package:web_dex/views/wallet/wallet_page/wallet_home/wallet_quick_action.dart';
import 'package:web_dex/views/wallet/wallet_page/wallet_home/wallet_quick_actions.dart';
import 'package:web_dex/views/wallet/wallet_page/wallet_main/wallet_swap_status.dart';

/// The signed-in wallet on a phone: who, how much, the everyday actions,
/// then the assets, the part people come back for.
class WalletHomeView extends StatefulWidget {
  const WalletHomeView({
    required this.scrollController,
    this.notices = const [],
    this.arrrActivationService,
    super.key,
  });

  final ScrollController scrollController;

  /// Setup reminders and notices, shown under the swap status in order. A
  /// [Card] is spaced and drawn on the home's surfaces; anything else brings
  /// its own spacing, so a notice with nothing to say leaves no gap.
  final List<Widget> notices;
  final ArrrActivationService? arrrActivationService;

  @override
  State<WalletHomeView> createState() => _WalletHomeViewState();
}

class _WalletHomeViewState extends State<WalletHomeView> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _toolbarAnchor = GlobalKey();
  WalletHomeSection _section = WalletHomeSection.assets;
  bool _searchOpen = false;
  String _searchPhrase = '';

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _openSearch() {
    setState(() => _searchOpen = true);
    // Bring the toolbar to the top, so results show above the keyboard.
    final anchor = _toolbarAnchor.currentContext;
    if (anchor != null) {
      Scrollable.ensureVisible(
        anchor,
        duration: SwapMotion.of(context, SwapMotion.screen),
        curve: SwapMotion.standard,
      );
    }
  }

  void _closeSearch() {
    _searchController.clear();
    _searchFocusNode.unfocus();
    setState(() {
      _searchOpen = false;
      _searchPhrase = '';
    });
  }

  void _selectSection(WalletHomeSection section) {
    SwapHaptics.selection();
    if (_searchOpen) _closeSearch();
    setState(() => _section = section);
  }

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    final hideZeroBalances = context.select(
      (SettingsBloc bloc) => bloc.state.hideZeroBalanceAssets,
    );
    final sdk = context.sdk;
    final isEmpty = context.select<CoinsBloc, bool>(
      (bloc) =>
          computeWalletTotalUsd(
            coins: bloc.state.walletCoins.values,
            coinsState: bloc.state,
            sdk: sdk,
          ) ==
          0,
    );

    final wide = !isMobile;
    final actions = WalletQuickActions(
      highlight: isEmpty ? WalletQuickAction.receive : null,
    );

    // A Material rather than a plain colour, so presses on the canvas show.
    return Material(
      color: palette.canvas,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // A wide screen keeps the home to a centred column. The scroll view
          // itself stays full width, so the wheel scrolls it from anywhere.
          final inset = wide
              ? math.max(
                  0.0,
                  (constraints.maxWidth - WalletHomeGeometry.wideContentWidth) /
                      2,
                )
              : 0.0;
          Widget column(Widget sliver) => inset == 0
              ? sliver
              : SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: inset),
                  sliver: sliver,
                );
          return CustomScrollView(
            key: const Key('wallet-page-scroll-view'),
            controller: widget.scrollController,
            slivers: [
              // On a wide screen the top bar already names the wallet.
              SliverToBoxAdapter(
                child: wide
                    ? const SizedBox(height: 16)
                    : const WalletHomeHeader(),
              ),
              column(
                const SliverToBoxAdapter(
                  child: WalletBalanceHero(key: Key('wallet-overview')),
                ),
              ),
              column(
                SliverToBoxAdapter(
                  child: wide
                      ? Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 560),
                            child: actions,
                          ),
                        )
                      : actions,
                ),
              ),
              column(const SliverToBoxAdapter(child: WalletSwapStatus())),
              for (final notice in widget.notices)
                column(SliverToBoxAdapter(child: _OnPalette(child: notice))),
              const SliverToBoxAdapter(child: SizedBox(height: 20)),
              SliverToBoxAdapter(child: SizedBox(key: _toolbarAnchor)),
              column(
                SliverPersistentHeader(
                  pinned: true,
                  delegate: WalletAssetsToolbarDelegate(
                    section: _section,
                    onSection: _selectSection,
                    // A phrase carried over from the wide layout stays in
                    // view, so a filtered list never looks short of assets.
                    searchOpen:
                        _searchOpen || (!wide && _searchPhrase.isNotEmpty),
                    onSearchOpen: _openSearch,
                    onSearchClose: _closeSearch,
                    searchController: _searchController,
                    searchFocusNode: _searchFocusNode,
                    onSearchChanged: (value) => setState(
                      () => _searchPhrase = value.trim().toLowerCase(),
                    ),
                    textScaler: MediaQuery.textScalerOf(context),
                    inlineSearch: wide,
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 4)),
              for (final sliver in _sectionSlivers(hideZeroBalances))
                column(sliver),
              // Few results would leave too little to scroll, and the field
              // would slide down from the top as the user types.
              SliverToBoxAdapter(
                child: SizedBox(
                  height: _searchOpen ? MediaQuery.sizeOf(context).height : 32,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _sectionSlivers(bool hideZeroBalances) => switch (_section) {
    WalletHomeSection.assets => [
      WalletHomeAssets(
        searchPhrase: _searchPhrase,
        hideZeroBalances: hideZeroBalances,
        onHideZeroBalances: (value) {
          SwapHaptics.selection();
          context.read<SettingsBloc>().add(
            HideZeroBalanceAssetsChanged(hideZeroBalanceAssets: value),
          );
        },
        arrrActivationService: widget.arrrActivationService,
      ),
    ],
    WalletHomeSection.growth => const [
      SliverToBoxAdapter(child: WalletHomeInsights(profitLoss: false)),
    ],
    WalletHomeSection.profitLoss => const [
      SliverToBoxAdapter(child: WalletHomeInsights(profitLoss: true)),
    ],
  };
}

/// Draws cards from elsewhere in the app, such as the setup checklist, on
/// the wallet home's surfaces rather than the older neutral grey.
class _OnPalette extends StatelessWidget {
  const _OnPalette({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = SwapPalette.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(WalletHomeGeometry.groupRadius),
      side: BorderSide(color: palette.border),
    );
    return Theme(
      data: theme.copyWith(
        cardColor: palette.surface,
        cardTheme: theme.cardTheme.copyWith(
          color: palette.surface,
          shape: shape,
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        ),
        colorScheme: theme.colorScheme.copyWith(surface: palette.surface),
      ),
      child: child,
    );
  }
}
