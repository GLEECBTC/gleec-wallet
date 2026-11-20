import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/settings/settings_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/swap/swap_catalog.dart';
import 'package:web_dex/shared/swap/swap_order_book_offers.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_services.dart';
import 'package:web_dex/shared/swap/swap_tickers.dart';
import 'package:web_dex/views/swap/common/swap_failure_copy.dart';
import 'package:web_dex/views/swap/common/swap_format.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/common/swap_sheet.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';
import 'package:web_dex/views/swap/motion/swap_motion.dart';

part 'swap_asset_picker_balance.dart';
part 'swap_asset_picker_filters.dart';
part 'swap_asset_picker_list.dart';
part 'swap_asset_picker_reach.dart';
part 'swap_asset_picker_row.dart';

/// Which side of the swap a picker chooses for.
enum SwapPickerSide { pay, receive }

enum _PickerTab { mine, recent, popular, all }

/// The height below which the picker's header scrolls with its list rather
/// than staying pinned above it and leaving the list no room.
const _pinnedHeaderMinHeight = 420.0;

/// Tickers offered under "Popular", most traded first.
const swapPopularTickers = [
  'BTC',
  'ETH',
  'USDT',
  'USDC',
  'GLEEC',
  'BNB',
  'TRX',
  'KMD',
  'LTC',
  'DOGE',
  'POL',
  'AVAX',
];

/// Returns the exact chosen asset immediately. The swap BLoC prepares it
/// after selection, so activation never holds the picker open.
Future<AssetId?> showSwapAssetPicker({
  required BuildContext context,
  required SwapPickerSide side,
  required UnifiedSwapBloc bloc,
  required AssetId? selected,
  required AssetId? other,
  required SwapServices services,
  required bool Function(AssetId asset) isBlocked,
}) {
  final showTestCoins = _testCoinsEnabled(context);
  final signedIn = bloc.state.signedIn;
  return showSwapSheet<AssetId>(
    context: context,
    label: LocaleKeys.swapPickerTitle.tr(),
    builder: (context) => BlocProvider.value(
      value: bloc,
      child: BlocBuilder<UnifiedSwapBloc, UnifiedSwapState>(
        buildWhen: (a, b) =>
            a.catalog != b.catalog ||
            a.loadingAssets != b.loadingAssets ||
            a.hints != b.hints,
        builder: (context, state) => SwapAssetPicker(
          side: side,
          catalog: state.catalog,
          loading: state.loadingAssets,
          offered: side == SwapPickerSide.receive
              ? state.hints.payCounts
              : state.hints.receiveCounts,
          signedIn: signedIn,
          selected: selected,
          other: other,
          services: services,
          isBlocked: isBlocked,
          showTestCoins: showTestCoins,
          onRetryCatalog: () =>
              bloc.add(const UnifiedSwapCatalogRefreshRequested()),
        ),
      ),
    ),
  );
}

bool _testCoinsEnabled(BuildContext context) {
  try {
    return context.read<SettingsBloc>().state.testCoinsEnabled;
  } on Object {
    return true;
  }
}

/// Chooses an asset and its network.
///
/// The same ticker on two networks is two different assets, so every row
/// names its network, and a row sharing the other side's ticker says so.
class SwapAssetPicker extends StatefulWidget {
  const SwapAssetPicker({
    required this.side,
    required this.catalog,
    required this.selected,
    required this.other,
    required this.services,
    required this.isBlocked,
    this.loading = false,
    this.signedIn = true,
    this.showTestCoins = true,
    this.onRetryCatalog,
    this.offered,
    super.key,
  });

  final SwapPickerSide side;
  final SwapCatalog catalog;
  final bool loading;
  final AssetId? selected;
  final AssetId? other;
  final SwapServices services;
  final bool Function(AssetId asset) isBlocked;

  /// Whether a wallet is signed in. Without one, nothing is activated.
  final bool signedIn;

  /// Whether inactive test-network assets are offered.
  final bool showTestCoins;

  final VoidCallback? onRetryCatalog;

  /// Which assets anyone on the order book trades against [other]. Rows it
  /// knows have no offers are set apart; unknown ones are not.
  final SwapOfferCounts? offered;

  @override
  State<SwapAssetPicker> createState() => _SwapAssetPickerState();
}

class _SwapAssetPickerState extends State<SwapAssetPicker> {
  final TextEditingController _search = TextEditingController();
  // Signed out, nothing is held: no "My assets" to open on or offer.
  late _PickerTab _tab = widget.signedIn && widget.side == SwapPickerSide.pay
      ? _PickerTab.mine
      : _PickerTab.popular;
  late Set<AssetId>? _activated = widget.signedIn
      ? widget.catalog.activated ?? widget.catalog.assets
      : const <AssetId>{};
  String _network = '';
  bool _tabTouched = false;
  List<String> _recentTickers = const [];
  bool _failed = false;
  bool _hideZero = false;

  @override
  void initState() {
    super.initState();
    if (_tab == _PickerTab.mine && _mine(_activated ?? const {}).isEmpty) {
      _tab = _popular().isEmpty ? _PickerTab.all : _PickerTab.popular;
    }
    _load();
  }

  @override
  void didUpdateWidget(covariant SwapAssetPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_network.isNotEmpty &&
        !_offered().any((id) => (id.parentId ?? id).id == _network)) {
      _network = '';
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final preferences = widget.services.preferences;
      final activated = widget.signedIn
          ? await widget.services.activatedAssets()
          : const <AssetId>{};
      final recentTickers = await preferences.recentAssets();
      final hideZero =
          widget.side == SwapPickerSide.pay &&
          await preferences.hideZeroBalances();
      if (!mounted) return;
      setState(() {
        _activated = activated;
        _recentTickers = recentTickers;
        _hideZero = hideZero;
        // Open on something useful: holdings when there are any, else what
        // was chosen lately, else the most traded rather than the alphabet.
        if (!_tabTouched &&
            (widget.side == SwapPickerSide.receive ||
                _mine(activated).isEmpty)) {
          _tab = _recent().isNotEmpty
              ? _PickerTab.recent
              : _popular().isNotEmpty
              ? _PickerTab.popular
              : _PickerTab.all;
        }
      });
    } on Object {
      if (mounted) setState(() => _failed = true);
    }
  }

  Set<AssetId> _offered() {
    final activated = _activated ?? widget.catalog.activated ?? const {};
    return {
      for (final id in widget.catalog.assets)
        if ((widget.showTestCoins ||
                activated.contains(id) ||
                !widget.services.isTestnet(id)) &&
            _suggests(id, activated))
          id,
    };
  }

  List<AssetId> _recent() {
    final offered = _offered();
    return [
      for (final ticker in _recentTickers)
        if (widget.services.resolveAsset(ticker) case final AssetId id
            when offered.contains(id))
          id,
    ];
  }

  List<AssetId> _mine(Set<AssetId> activated) {
    final held = [
      for (final id in _offered())
        if (_held(id, activated)) id,
    ];
    Decimal value(AssetId id) {
      final balance = widget.services.lastKnownBalance(id) ?? Decimal.zero;
      final price = widget.services.usdPrice(id) ?? Decimal.zero;
      return balance * price;
    }

    held.sort((a, b) => value(b).compareTo(value(a)));
    return held;
  }

  List<AssetId> _popular() {
    final rank = {
      for (var i = 0; i < swapPopularTickers.length; i++)
        swapPopularTickers[i]: i,
    };
    final list = [
      for (final id in _offered())
        if (rank.containsKey(SwapFormat.ticker(id).toUpperCase())) id,
    ];
    list.sort((a, b) {
      final byRank = rank[SwapFormat.ticker(a).toUpperCase()]!.compareTo(
        rank[SwapFormat.ticker(b).toUpperCase()]!,
      );
      return byRank != 0 ? byRank : _byName(a, b);
    });
    return list;
  }

  int _byName(AssetId a, AssetId b) {
    final byTicker = SwapFormat.ticker(a).compareTo(SwapFormat.ticker(b));
    if (byTicker != 0) return byTicker;
    // Native coins before tokens of the same ticker.
    if (a.isChildAsset != b.isChildAsset) return a.isChildAsset ? 1 : -1;
    final networks = widget.services.networks();
    return networks.networkOf(a).compareTo(networks.networkOf(b));
  }

  List<AssetId> _all() => _offered().toList()..sort(_byName);

  bool _matches(AssetId id, List<String> terms) {
    final networks = widget.services.networks();
    final haystack = [
      SwapFormat.ticker(id),
      id.id,
      id.name,
      networks.networkOf(id),
      widget.services.contractOf(id) ?? '',
    ].join(' ').toLowerCase();
    return terms.every(haystack.contains);
  }

  /// How closely [id] answers [terms], best first: its id or ticker is a word
  /// typed, its ticker starts with one, or a word of its id or name does. The
  /// rest matched mid-word or on the network, and a network matches every
  /// asset on it: "eth" finds every token on Ethereum, and Tether.
  int _relevance(AssetId id, List<String> terms) {
    final assetId = id.id.toLowerCase();
    final ticker = SwapFormat.ticker(id).toLowerCase();
    final words = '$assetId ${id.name.toLowerCase()}'.split(
      RegExp('[^a-z0-9]+'),
    );
    int rank(String term) {
      if (assetId == term) return 0;
      if (ticker == term) return 1;
      if (ticker.startsWith(term)) return 2;
      if (words.any((word) => word.startsWith(term))) return 3;
      return 4;
    }

    return terms.map(rank).reduce((a, b) => a < b ? a : b);
  }

  List<AssetId> _searched(String query) {
    final terms = query.split(RegExp(r'\s+'));
    final ranks = {
      for (final id in _offered())
        if (_matches(id, terms)) id: _relevance(id, terms),
    };
    return ranks.keys.toList()..sort((a, b) {
      final byRank = ranks[a]!.compareTo(ranks[b]!);
      return byRank != 0 ? byRank : _byName(a, b);
    });
  }

  List<AssetId> _rows() {
    final query = _search.text.trim().toLowerCase();
    final activated = _activated ?? const {};
    final rows = query.isNotEmpty
        ? _searched(query)
        : switch (_tab) {
            _PickerTab.mine => _mine(activated),
            _PickerTab.recent => _recent(),
            _PickerTab.popular => _popular(),
            _PickerTab.all => _all(),
          };
    return _network.isEmpty
        ? rows
        : rows.where((id) => (id.parentId ?? id).id == _network).toList();
  }

  void _choose(AssetId id) {
    if (widget.isBlocked(id)) return;
    SwapHaptics.selection();
    Navigator.of(context).pop(id);
  }

  void _setHideZero(bool hide) {
    setState(() => _hideZero = hide);
    unawaited(widget.services.preferences.rememberHideZeroBalances(hide));
  }

  void _clearSearch() => setState(_search.clear);

  /// The list is a function of the search text; a rebuild shows it.
  void _searchChanged() => setState(() {});

  void _setNetwork(String network) => setState(() => _network = network);

  @override
  Widget build(BuildContext context) {
    final searching = _search.text.trim().isNotEmpty;
    final listed = _activated == null ? null : _listed();
    final search = _searchField(context);
    final filters = [
      const SizedBox(height: 14),
      if (!searching)
        SwapFilterBar<_PickerTab>(
          values: [
            for (final tab in _PickerTab.values)
              if (widget.signedIn || tab != _PickerTab.mine) tab,
          ],
          selected: _tab,
          semanticLabel: LocaleKeys.swapPickerTitle.tr(),
          labelOf: (tab) => switch (tab) {
            _PickerTab.mine => LocaleKeys.swapPickerTabMine.tr(),
            _PickerTab.recent => LocaleKeys.swapPickerTabRecent.tr(),
            _PickerTab.popular => LocaleKeys.swapPickerTabPopular.tr(),
            _PickerTab.all => LocaleKeys.swapPickerTabAll.tr(),
          },
          onChanged: (tab) => setState(() {
            _tab = tab;
            _tabTouched = true;
          }),
        ),
      const SizedBox(height: 10),
      _networkFilter(context),
      if (_filterable) ...[
        if (!searching) const SizedBox(height: 8),
        _ZeroBalanceSwitch(
          value: _hideZero,
          hidden: listed?.hidden ?? 0,
          onChanged: _setHideZero,
        ),
      ],
      const SizedBox(height: 14),
      if (widget.catalog.isIncomplete && !widget.loading)
        _incompleteNotice(context),
    ];
    final content = _content(context, listed);
    // With the keyboard up there is room for the search and little else:
    // the filters then scroll away with the list they narrow.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    return SwapSheetScaffold(
      title: LocaleKeys.swapPickerTitle.tr(),
      subtitle: widget.side == SwapPickerSide.pay
          ? LocaleKeys.swapPickerSubtitlePay.tr()
          : LocaleKeys.swapPickerSubtitleReceive.tr(),
      scrollable: false,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final pinned =
              MediaQuery.textScalerOf(context).scale(1) < 1.3 &&
              constraints.maxHeight >= _pinnedHeaderMinHeight;
          if (!pinned) {
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [search, ...filters],
                  ),
                ),
                content,
                const _KeyboardSpace(),
              ],
            );
          }
          // The search stays the column's first child either way, so it
          // keeps its focus as the keyboard comes and goes.
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              search,
              if (!keyboard) ...filters,
              Expanded(
                key: const ValueKey('swap-picker-list'),
                child: CustomScrollView(
                  slivers: [
                    if (keyboard)
                      SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: filters,
                        ),
                      ),
                    content,
                    const _KeyboardSpace(),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
