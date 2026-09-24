import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/swap/swap_services.dart';
import 'package:web_dex/views/swap/common/swap_format.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/common/swap_sheet.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';

part 'swap_asset_picker_row.dart';

/// Which side of the swap a picker chooses for.
enum SwapPickerSide { pay, receive }

enum _PickerTab { mine, recent, popular, all }

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
  required Set<AssetId> tradable,
  required AssetId? selected,
  required AssetId? other,
  required SwapServices services,
  required bool Function(AssetId asset) isBlocked,
}) {
  return showSwapSheet<AssetId>(
    context: context,
    label: LocaleKeys.swapPickerTitle.tr(),
    builder: (context) => SwapAssetPicker(
      side: side,
      tradable: tradable,
      selected: selected,
      other: other,
      services: services,
      isBlocked: isBlocked,
    ),
  );
}

/// Chooses an asset and its network.
///
/// The same ticker on two networks is two different assets, so every row
/// names its network, and a row sharing the other side's ticker says so.
class SwapAssetPicker extends StatefulWidget {
  const SwapAssetPicker({
    required this.side,
    required this.tradable,
    required this.selected,
    required this.other,
    required this.services,
    required this.isBlocked,
    super.key,
  });

  final SwapPickerSide side;
  final Set<AssetId> tradable;
  final AssetId? selected;
  final AssetId? other;
  final SwapServices services;
  final bool Function(AssetId asset) isBlocked;

  @override
  State<SwapAssetPicker> createState() => _SwapAssetPickerState();
}

class _SwapAssetPickerState extends State<SwapAssetPicker> {
  final TextEditingController _search = TextEditingController();
  _PickerTab _tab = _PickerTab.mine;
  Set<AssetId>? _activated;
  List<AssetId> _recent = const [];
  bool _failed = false;
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
      final activated = await widget.services.activatedAssets();
      final recentTickers = await widget.services.preferences.recentAssets();
      if (!mounted) return;
      final recent = [
        for (final ticker in recentTickers)
          if (widget.services.resolveAsset(ticker) case final AssetId id
              when widget.tradable.contains(id))
            id,
      ];
      setState(() {
        _activated = activated;
        _recent = recent;
        // Open on something useful: holdings when there are any.
        if (_mine(activated).isEmpty) {
          _tab = recent.isNotEmpty ? _PickerTab.recent : _PickerTab.all;
        }
      });
    } on Object {
      if (mounted) setState(() => _failed = true);
    }
  }

  List<AssetId> _mine(Set<AssetId> activated) {
    final held = [
      for (final id in widget.tradable)
        if (activated.contains(id) &&
            (widget.services.lastKnownBalance(id) ?? Decimal.zero) >
                Decimal.zero)
          id,
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
      for (final id in widget.tradable)
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

  List<AssetId> _all() => widget.tradable.toList()..sort(_byName);

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
      _PickerTab.recent => _recent,
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

  @override
  Widget build(BuildContext context) {
    return SwapSheetScaffold(
      title: LocaleKeys.swapPickerTitle.tr(),
      subtitle: widget.side == SwapPickerSide.pay
          ? LocaleKeys.swapPickerSubtitlePay.tr()
          : LocaleKeys.swapPickerSubtitleReceive.tr(),
      scrollable: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _searchField(context),
          const SizedBox(height: 14),
          if (_search.text.trim().isEmpty)
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
          const SizedBox(height: 14),
          Expanded(child: _list(context)),
        ],
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
                isCollapsed: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                hintText: LocaleKeys.swapPickerSearch.tr(),
                hintStyle: SwapText.body(
                  context,
                ).copyWith(color: palette.textTertiary),
              ),
            ),
          ),
          if (_search.text.isNotEmpty)
            SwapLinkButton(
              label: LocaleKeys.clear.tr(),
              onPressed: () => setState(_search.clear),
            ),
        ],
      ),
    );
  }

  Widget _list(BuildContext context) {
    if (_failed) {
      return SingleChildScrollView(
        child: SwapStatusHero(
          icon: Icons.error_outline_rounded,
          tone: SwapTone.danger,
          title: LocaleKeys.swapPickerErrorTitle.tr(),
          body: LocaleKeys.swapPickerErrorBody.tr(),
          action: SwapButton(label: LocaleKeys.tryAgain.tr(), onPressed: _load),
        ),
      );
    }
    if (_activated == null) {
      return Semantics(
        label: LocaleKeys.swapPickerLoading.tr(),
        child: ListView(
          children: [
            for (var i = 0; i < 5; i++) ...[
              const SwapSkeleton(height: 68),
              const SizedBox(height: 8),
            ],
          ],
        ),
      );
    }

    final rows = _rows();
    final query = _search.text.trim();
    if (rows.isEmpty) {
      if (query.isNotEmpty) {
        return SingleChildScrollView(
          child: SwapStatusHero(
            icon: Icons.search_off_rounded,
            tone: SwapTone.neutral,
            title: LocaleKeys.swapPickerNoResultsTitle.tr(args: [query]),
            body: LocaleKeys.swapPickerNoResultsBody.tr(),
            action: SwapButton(
              label: LocaleKeys.swapPickerClearSearch.tr(),
              variant: SwapButtonVariant.secondary,
              onPressed: () => setState(_search.clear),
            ),
          ),
        );
      }
      final (title, body) = switch (_tab) {
        _PickerTab.mine => (
          LocaleKeys.swapPickerNoHoldingsTitle.tr(),
          LocaleKeys.swapPickerNoHoldingsBody.tr(),
        ),
        _PickerTab.recent => (
          LocaleKeys.swapPickerNoRecentTitle.tr(),
          LocaleKeys.swapPickerNoRecentBody.tr(),
        ),
        _ => (
          LocaleKeys.swapPickerNoAssetsTitle.tr(),
          LocaleKeys.swapPickerNoResultsBody.tr(),
        ),
      };
      return SingleChildScrollView(
        child: SwapStatusHero(
          icon: Icons.inventory_2_outlined,
          tone: SwapTone.neutral,
          title: title,
          body: body,
          liveRegion: false,
        ),
      );
    }

    final selected = widget.selected;
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 18),
      itemCount: rows.length + (selected == null ? 0 : 1),
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index == rows.length) return _identity(context, selected!);
        final id = rows[index];
        return _PickerRow(
          asset: id,
          network: widget.services.networks().networkOf(id),
          contract: widget.services.contractOf(id),
          balance: widget.services.lastKnownBalance(id),
          usdPrice: widget.services.usdPrice(id),
          selected: id == selected,
          sameTicker:
              widget.other != null &&
              widget.other != id &&
              SwapFormat.ticker(widget.other!) == SwapFormat.ticker(id),
          active: _activated?.contains(id) ?? false,
          blocked: widget.isBlocked(id),
          activating: _activating == id,
          activationFailed: _activationFailed == id,
          onTap: _activating == null ? () => _choose(id) : null,
        );
      },
    );
  }

  Widget _identity(BuildContext context, AssetId id) {
    final contract = widget.services.contractOf(id);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SwapDetails(
        title: LocaleKeys.swapPickerIdentity.tr(),
        children: [
          Text(
            '${SwapFormat.ticker(id)} · '
            '${widget.services.networks().networkOf(id)}',
            style: SwapText.strong(context),
          ),
          const SizedBox(height: 6),
          SwapCopyLine(value: id.id, label: LocaleKeys.swapPickerIdentity.tr()),
          if (contract != null)
            SwapCopyLine(
              value: contract,
              label: LocaleKeys.swapContractIdentity.tr(args: ['']).trim(),
            ),
        ],
      ),
    );
  }
}
