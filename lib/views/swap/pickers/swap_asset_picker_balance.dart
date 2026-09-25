part of 'swap_asset_picker.dart';

/// The rows a picker shows, and how many "Hide 0 balance assets" left out.
typedef _Listed = ({List<AssetId> rows, int hidden});

/// Hiding what the wallet cannot pay with. Only for the pay side: people
/// receive assets they do not hold. Hidden assets stay one tap away, so a
/// price can still be looked up for something the wallet does not hold.
extension _PickerBalance on _SwapAssetPickerState {
  /// Whether the switch applies here. "My assets" lists holdings only.
  bool get _filterable =>
      widget.side == SwapPickerSide.pay &&
      (_tab != _PickerTab.mine || _search.text.trim().isNotEmpty);

  /// Whether the wallet holds some of [id]. An inactive asset's balance is
  /// unknown, so it does not count.
  bool _held(AssetId id, Set<AssetId> activated) =>
      activated.contains(id) &&
      (widget.services.lastKnownBalance(id) ?? Decimal.zero) > Decimal.zero;

  /// Whether the switch leaves [id] out: inactive, or active with nothing to
  /// spend. A balance not read yet, as just after sign-in, is not taken for
  /// zero, or the switch could hide everything.
  bool _empty(AssetId id, Set<AssetId> activated) {
    if (!activated.contains(id)) return true;
    final balance = widget.services.lastKnownBalance(id);
    return balance != null && balance <= Decimal.zero;
  }

  _Listed _listed() {
    final rows = _rows();
    if (!_filterable || !_hideZero) return (rows: rows, hidden: 0);
    final activated = _activated ?? const {};
    final kept = [
      for (final id in rows)
        if (!_empty(id, activated)) id,
    ];
    return (rows: kept, hidden: rows.length - kept.length);
  }

  Widget _allHidden(String query) => SwapStatusHero(
    icon: Icons.visibility_off_outlined,
    tone: SwapTone.neutral,
    title: query.isEmpty
        ? LocaleKeys.swapPickerNoBalanceTitle.tr()
        : LocaleKeys.swapPickerNoBalanceResultsTitle.tr(args: [query]),
    body: LocaleKeys.swapPickerNoBalanceBody.tr(),
    action: SwapButton(
      label: LocaleKeys.swapPickerShowAll.tr(),
      variant: SwapButtonVariant.secondary,
      onPressed: () => _setHideZero(false),
    ),
  );
}

/// "Hide 0 balance assets", and how many it hides from the list below.
class _ZeroBalanceSwitch extends StatelessWidget {
  const _ZeroBalanceSwitch({
    required this.value,
    required this.hidden,
    required this.onChanged,
  });

  final bool value;
  final int hidden;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    return MergeSemantics(
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          // The switch takes keyboard focus; the row only widens the target.
          canRequestFocus: false,
          borderRadius: BorderRadius.circular(12),
          onTap: () => onChanged(!value),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsetsDirectional.only(start: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          LocaleKeys.swapPickerHideZero.tr(),
                          style: SwapText.body(
                            context,
                          ).copyWith(color: palette.text),
                        ),
                        if (value && hidden > 0)
                          Text(
                            LocaleKeys.swapPickerHiddenCount.tr(
                              args: ['$hidden'],
                            ),
                            style: SwapText.small(context),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Switch(
                    value: value,
                    onChanged: onChanged,
                    activeThumbColor: palette.onBrand,
                    activeTrackColor: palette.brand,
                    inactiveThumbColor: palette.textSecondary,
                    inactiveTrackColor: palette.surfaceHigh,
                    trackOutlineColor: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.selected)
                          ? Colors.transparent
                          : palette.controlBorder,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
