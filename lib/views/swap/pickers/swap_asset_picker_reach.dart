part of 'swap_asset_picker.dart';

sealed class _PickerEntry {
  const _PickerEntry();
}

final class _AssetEntry extends _PickerEntry {
  const _AssetEntry(
    this.asset, {
    this.unreachable = false,
    this.noOffers = false,
  });

  final AssetId asset;

  final bool unreachable;

  final bool noOffers;
}

final class _NoOffersHeader extends _PickerEntry {
  const _NoOffersHeader(this.anchor);

  final AssetId anchor;
}

final class _UnreachableHeader extends _PickerEntry {
  const _UnreachableHeader(this.anchor);

  final AssetId anchor;
}

final class _IdentityEntry extends _PickerEntry {
  const _IdentityEntry(this.asset);

  final AssetId asset;
}

/// What the pay asset can be swapped for, on the receive side only: the pay
/// asset is where a swap starts, so what it cannot reach is set apart with
/// the reason rather than refused on the form.
///
/// On both sides, what no one on the order book offers with the other asset
/// is set apart too, and can still be chosen: orders come and go.
extension _PickerReach on _SwapAssetPickerState {
  List<_PickerEntry> _entries(List<AssetId> rows) {
    final anchor = widget.other;
    final selected = widget.selected;
    final counts = widget.offered;
    final offered = anchor != null && counts?.anchor == anchor ? counts : null;
    final reachable = <_PickerEntry>[];
    final withoutOffers = <_PickerEntry>[];
    final unreachable = <_PickerEntry>[];
    for (final id in rows) {
      if (anchor != null && !_reaches(anchor, id)) {
        unreachable.add(_AssetEntry(id, unreachable: true));
      } else if (offered != null && offered.lacks(id)) {
        withoutOffers.add(_AssetEntry(id, noOffers: true));
      } else {
        reachable.add(_AssetEntry(id));
      }
    }
    return [
      ...reachable,
      if (withoutOffers.isNotEmpty) ...[
        _NoOffersHeader(anchor!),
        ...withoutOffers,
      ],
      if (unreachable.isNotEmpty) ...[
        _UnreachableHeader(anchor!),
        ...unreachable,
      ],
      if (selected != null) _IdentityEntry(selected),
    ];
  }

  Widget _noOffersHeader(BuildContext context, AssetId anchor) {
    final ticker = SwapFormat.ticker(anchor);
    final paying = widget.side == SwapPickerSide.pay;
    return _sectionHeader(
      context,
      title: paying
          ? LocaleKeys.swapPickerNoOffersTitlePay.tr(args: [ticker])
          : LocaleKeys.swapPickerNoOffersTitle.tr(args: [ticker]),
      lines: [
        paying
            ? LocaleKeys.swapPickerNoOffersBodyPay.tr(args: [ticker])
            : LocaleKeys.swapPickerNoOffersBody.tr(args: [ticker]),
      ],
    );
  }

  bool _reaches(AssetId anchor, AssetId id) {
    if (widget.side != SwapPickerSide.receive || id == anchor) return true;
    final catalog = widget.catalog;
    for (final source in catalog.sources) {
      if (source.supports(anchor) && source.supports(id)) return true;
    }
    return false;
  }

  Widget _unreachableHeader(BuildContext context, AssetId anchor) {
    final catalog = widget.catalog;
    final atomic =
        catalog.of(SwapLiquiditySource.atomic)?.supports(anchor) ?? false;
    final routed =
        catalog.of(SwapLiquiditySource.routed)?.supports(anchor) ?? false;
    final ticker = SwapFormat.ticker(anchor);
    return _sectionHeader(
      context,
      title: LocaleKeys.swapPickerUnreachableTitle.tr(args: [ticker]),
      lines: [
        if (atomic && !routed) ...[
          LocaleKeys.swapPickerUnreachableOrderBookOnly.tr(args: [ticker]),
          routesReachDetail(anchor, widget.services.networks()),
        ] else if (routed && !atomic)
          LocaleKeys.swapPickerUnreachableRoutesOnly.tr(args: [ticker]),
      ],
    );
  }

  Widget _sectionHeader(
    BuildContext context, {
    required String title,
    required List<String> lines,
  }) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 2),
    child: Semantics(
      header: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: SwapText.strong(context)),
          for (final line in lines) ...[
            const SizedBox(height: 4),
            Text(line, style: SwapText.small(context)),
          ],
        ],
      ),
    ),
  );

  Widget _incompleteNotice(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: SwapCallout(
      tone: SwapTone.warning,
      message: LocaleKeys.swapPickerIncomplete.tr(),
      action: SwapLinkButton(
        label: LocaleKeys.tryAgain.tr(),
        onPressed: widget.onRetryCatalog,
      ),
    ),
  );
}
