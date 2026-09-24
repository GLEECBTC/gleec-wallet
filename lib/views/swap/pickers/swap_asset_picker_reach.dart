part of 'swap_asset_picker.dart';

/// One line of the picker's list.
sealed class _PickerEntry {
  const _PickerEntry();
}

final class _AssetEntry extends _PickerEntry {
  const _AssetEntry(this.asset, {this.unreachable = false});

  final AssetId asset;

  /// The other side's asset cannot be swapped for this one.
  final bool unreachable;
}

/// Heads the assets the other side's asset cannot reach, and says why.
final class _UnreachableHeader extends _PickerEntry {
  const _UnreachableHeader(this.anchor);

  final AssetId anchor;
}

final class _IdentityEntry extends _PickerEntry {
  const _IdentityEntry(this.asset);

  final AssetId asset;
}

/// What the other side's asset can be swapped for.
///
/// Receive-side only: the pay asset is where a swap starts, so it anchors
/// the list and everything it cannot reach is set apart with the reason,
/// rather than offered and then refused on the form.
extension _PickerReach on _SwapAssetPickerState {
  /// [rows] as list entries, reachable ones first.
  List<_PickerEntry> _entries(List<AssetId> rows) {
    final anchor = widget.other;
    final selected = widget.selected;
    final reachable = <_PickerEntry>[];
    final unreachable = <_PickerEntry>[];
    for (final id in rows) {
      if (anchor == null || _reaches(anchor, id)) {
        reachable.add(_AssetEntry(id));
      } else {
        unreachable.add(_AssetEntry(id, unreachable: true));
      }
    }
    return [
      ...reachable,
      if (unreachable.isNotEmpty) ...[
        _UnreachableHeader(anchor!),
        ...unreachable,
      ],
      if (selected != null) _IdentityEntry(selected),
    ];
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
    final lines = [
      if (atomic && !routed) ...[
        LocaleKeys.swapPickerUnreachableOrderBookOnly.tr(args: [ticker]),
        routesReachDetail(anchor, widget.services.networks()),
      ] else if (routed && !atomic)
        LocaleKeys.swapPickerUnreachableRoutesOnly.tr(args: [ticker]),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 2),
      child: Semantics(
        header: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              LocaleKeys.swapPickerUnreachableTitle.tr(args: [ticker]),
              style: SwapText.strong(context),
            ),
            for (final line in lines) ...[
              const SizedBox(height: 4),
              Text(line, style: SwapText.small(context)),
            ],
          ],
        ),
      ),
    );
  }

  /// Said when some source's list could not be read: the list may be short,
  /// and retrying is the next step.
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
