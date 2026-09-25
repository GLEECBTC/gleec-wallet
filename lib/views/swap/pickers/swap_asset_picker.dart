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
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_services.dart';
import 'package:web_dex/views/swap/common/swap_failure_copy.dart';
import 'package:web_dex/views/swap/common/swap_format.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/common/swap_sheet.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';

part 'swap_asset_picker_balance.dart';
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
const _popularTickers = [
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

/// Opens the asset picker and returns the chosen asset, activated.
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
  return showSwapSheet<AssetId>(
    context: context,
    label: LocaleKeys.swapPickerTitle.tr(),
    builder: (context) => BlocProvider.value(
      value: bloc,
      child: BlocBuilder<UnifiedSwapBloc, UnifiedSwapState>(
        buildWhen: (a, b) =>
            a.catalog != b.catalog || a.loadingAssets != b.loadingAssets,
        builder: (context, state) => SwapAssetPicker(
          side: side,
          catalog: state.catalog,
          loading: state.loadingAssets,
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
    this.showTestCoins = true,
    this.onRetryCatalog,
    super.key,
  });

  final SwapPickerSide side;
  final SwapCatalog catalog;
  final bool loading;
  final AssetId? selected;
  final AssetId? other;
  final SwapServices services;
  final bool Function(AssetId asset) isBlocked;

  /// Whether inactive test-network assets are offered.
  final bool showTestCoins;

  final VoidCallback? onRetryCatalog;

  @override
  State<SwapAssetPicker> createState() => _SwapAssetPickerState();
}

class _SwapAssetPickerState extends State<SwapAssetPicker> {
  final TextEditingController _search = TextEditingController();
  _PickerTab _tab = _PickerTab.mine;
  Set<AssetId>? _activated;
  List<String> _recentTickers = const [];
  bool _failed = false;
  bool _hideZero = false;
  AssetId? _activating;
  AssetId? _activationFailed;

  @override
  void initState() {
    super.initState();
    _load();
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
      final activated = await widget.services.activatedAssets();
      final recentTickers = await preferences.recentAssets();
      final hideZero =
          widget.side == SwapPickerSide.pay &&
          await preferences.hideZeroBalances();
      if (!mounted) return;
      setState(() {
        _activated = activated;
        _recentTickers = recentTickers;
        _hideZero = hideZero;
        // Open on something useful: holdings when there are any.
        if (_mine(activated).isEmpty) {
          _tab = _recent().isNotEmpty ? _PickerTab.recent : _PickerTab.all;
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
        if (widget.showTestCoins ||
            activated.contains(id) ||
            !widget.services.isTestnet(id))
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
      for (var i = 0; i < _popularTickers.length; i++) _popularTickers[i]: i,
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

  bool _matches(AssetId id, String query) {
    final networks = widget.services.networks();
    final haystack = [
      SwapFormat.ticker(id),
      id.id,
      id.name,
      networks.networkOf(id),
      widget.services.contractOf(id) ?? '',
    ].join(' ').toLowerCase();
    return query
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .every(haystack.contains);
  }

  List<AssetId> _rows() {
    final query = _search.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      return _all().where((id) => _matches(id, query)).toList();
    }
    final activated = _activated ?? const {};
    return switch (_tab) {
      _PickerTab.mine => _mine(activated),
      _PickerTab.recent => _recent(),
      _PickerTab.popular => _popular(),
      _PickerTab.all => _all(),
    };
  }

  Future<void> _choose(AssetId id) async {
    if (widget.isBlocked(id)) return;
    final activated = _activated ?? const {};
    if (activated.contains(id)) {
      Navigator.of(context).pop(id);
      return;
    }
    setState(() {
      _activating = id;
      _activationFailed = null;
    });
    try {
      await widget.services.activate(id);
      if (!mounted) return;
      Navigator.of(context).pop(id);
    } on Object {
      if (!mounted) return;
      setState(() {
        _activating = null;
        _activationFailed = id;
      });
    }
  }

  void _setHideZero(bool hide) {
    setState(() => _hideZero = hide);
    unawaited(widget.services.preferences.rememberHideZeroBalances(hide));
  }

  void _clearSearch() => setState(_search.clear);

  @override
  Widget build(BuildContext context) {
    final searching = _search.text.trim().isNotEmpty;
    final listed = _activated == null ? null : _listed();
    final header = [
      _searchField(context),
      const SizedBox(height: 14),
      if (!searching)
        SwapFilterBar<_PickerTab>(
          values: _PickerTab.values,
          selected: _tab,
          semanticLabel: LocaleKeys.swapPickerTitle.tr(),
          labelOf: (tab) => switch (tab) {
            _PickerTab.mine => LocaleKeys.swapPickerTabMine.tr(),
            _PickerTab.recent => LocaleKeys.swapPickerTabRecent.tr(),
            _PickerTab.popular => LocaleKeys.swapPickerTabPopular.tr(),
            _PickerTab.all => LocaleKeys.swapPickerTabAll.tr(),
          },
          onChanged: (tab) => setState(() => _tab = tab),
        ),
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
                    children: header,
                  ),
                ),
                content,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...header,
              Expanded(child: CustomScrollView(slivers: [content])),
            ],
          );
        },
      ),
    );
  }

  Widget _searchField(BuildContext context) {
    final palette = SwapPalette.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: palette.surfaceHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.controlBorder),
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, color: palette.textTertiary),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _search,
              autofocus: MediaQuery.sizeOf(context).width >= 768,
              onChanged: (_) => setState(() {}),
              style: SwapText.body(context).copyWith(color: palette.text),
              decoration: InputDecoration(
                contentPadding: EdgeInsets.zero,
                visualDensity: VisualDensity.standard,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                hintText: LocaleKeys.swapPickerSearch.tr(),
                hintMaxLines: 4,
                hintStyle: SwapText.body(
                  context,
                ).copyWith(color: palette.textTertiary),
              ),
            ),
          ),
          if (_search.text.isNotEmpty)
            SwapLinkButton(
              label: LocaleKeys.clear.tr(),
              onPressed: _clearSearch,
            ),
        ],
      ),
    );
  }
}
