part of 'swap_asset_picker.dart';

/// The picker's list, as a sliver: under a pinned header, or scrolling with
/// it when large text or a short screen leaves no room.
extension _PickerList on _SwapAssetPickerState {
  Widget _content(BuildContext context, _Listed? listed) {
    if (_failed) {
      return SliverToBoxAdapter(
        child: SwapStatusHero(
          icon: Icons.error_outline_rounded,
          tone: SwapTone.danger,
          title: LocaleKeys.swapPickerErrorTitle.tr(),
          body: LocaleKeys.swapPickerErrorBody.tr(),
          action: SwapButton(label: LocaleKeys.tryAgain.tr(), onPressed: _load),
        ),
      );
    }
    if (listed == null || (widget.loading && widget.catalog.assets.isEmpty)) {
      return SliverToBoxAdapter(
        child: Semantics(
          label: LocaleKeys.swapPickerLoading.tr(),
          child: Column(
            children: [
              for (var i = 0; i < 5; i++) ...[
                const SwapSkeleton(height: 68),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      );
    }

    final rows = listed.rows;
    if (rows.isEmpty) {
      return SliverToBoxAdapter(child: _empty(listed.hidden));
    }

    final selected = widget.selected;
    final entries = _entries(rows);
    return SliverPadding(
      padding: const EdgeInsets.only(bottom: 18),
      sliver: SliverList.separated(
        itemCount: entries.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) => switch (entries[index]) {
          _IdentityEntry(:final asset) => _identity(context, asset),
          _UnreachableHeader(:final anchor) => _unreachableHeader(
            context,
            anchor,
          ),
          _AssetEntry(asset: final id, :final unreachable) => _PickerRow(
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
            unreachableWith: unreachable ? widget.other : null,
            activating: _activating == id,
            activationFailed: _activationFailed == id,
            onTap: _activating == null && !unreachable
                ? () => _choose(id)
                : null,
          ),
        },
      ),
    );
  }

  Widget _empty(int hidden) {
    final query = _search.text.trim();
    if (hidden > 0) return _allHidden(query);
    if (query.isNotEmpty) {
      return SwapStatusHero(
        icon: Icons.search_off_rounded,
        tone: SwapTone.neutral,
        title: LocaleKeys.swapPickerNoResultsTitle.tr(args: [query]),
        body: LocaleKeys.swapPickerNoResultsBody.tr(),
        action: SwapButton(
          label: LocaleKeys.swapPickerClearSearch.tr(),
          variant: SwapButtonVariant.secondary,
          onPressed: _clearSearch,
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
    return SwapStatusHero(
      icon: Icons.inventory_2_outlined,
      tone: SwapTone.neutral,
      title: title,
      body: body,
      liveRegion: false,
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
