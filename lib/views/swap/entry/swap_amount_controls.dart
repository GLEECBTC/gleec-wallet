part of 'swap_amount_cards.dart';

/// The button that opens the asset picker for one side.
class SwapAssetPill extends StatefulWidget {
  const SwapAssetPill({
    required this.asset,
    required this.network,
    required this.onTap,
    required this.semanticLabel,
    this.hasError = false,
    super.key,
  });

  final AssetId? asset;
  final String? network;
  final VoidCallback? onTap;
  final String semanticLabel;
  final bool hasError;

  @override
  State<SwapAssetPill> createState() => _SwapAssetPillState();
}

class _SwapAssetPillState extends State<SwapAssetPill>
    with SingleTickerProviderStateMixin {
  late final AppLifecycleListener _lifecycle;
  late final AnimationController _selection = AnimationController(
    vsync: this,
    duration: SwapMotion.selection,
  );

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        if (state != AppLifecycleState.resumed) _selection.value = 0;
      },
    );
  }

  bool get _canAnimate {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    return SwapMotion.enabled(context) &&
        TickerMode.valuesOf(context).enabled &&
        (lifecycle == null || lifecycle == AppLifecycleState.resumed);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_canAnimate) _selection.value = 0;
  }

  @override
  void didUpdateWidget(covariant SwapAssetPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset != widget.asset && _canAnimate) {
      _selection.reverse(from: 1);
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _selection,
    builder: (context, _) => _button(context),
  );

  Widget _button(BuildContext context) {
    final palette = SwapPalette.of(context);
    final asset = widget.asset;
    final network = widget.network;
    final onTap = widget.onTap;
    final semanticLabel = widget.semanticLabel;
    // Nothing chosen yet, it reads as the next thing to do, with its whole
    // label: no icon takes the room a phone has for it.
    final choose = asset == null;
    return SwapButtonSemantics(
      label: asset == null
          ? semanticLabel
          : '$semanticLabel: ${SwapFormat.ticker(asset)}, $network',
      onTap: onTap,
      child: Material(
        color: choose
            ? palette.selected
            : Color.lerp(
                palette.surfaceHigh,
                palette.selected,
                _selection.value,
              ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: widget.hasError
                ? palette.danger
                : choose
                ? palette.brand
                : palette.controlBorder,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: EdgeInsets.fromLTRB(choose ? 14 : 10, 8, 8, 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (asset != null) ...[
                    SwapTokenIcon(asset: asset, size: 28),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          asset == null
                              ? LocaleKeys.swapSelectAsset.tr()
                              : SwapFormat.ticker(asset),
                          style: SwapText.strong(context).copyWith(height: 1.1),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (asset != null && network != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            network,
                            style: SwapText.small(context)
                                .copyWith(height: 1.25),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 22,
                    color: choose ? palette.brandHover : palette.textSecondary,
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

/// The round button between the cards that swaps the two sides.
class SwapSwitchButton extends StatefulWidget {
  const SwapSwitchButton({required this.onPressed, super.key});

  final VoidCallback? onPressed;

  @override
  State<SwapSwitchButton> createState() => _SwapSwitchButtonState();
}

class _SwapSwitchButtonState extends State<SwapSwitchButton> {
  double _turns = 0;

  void _switch() {
    final action = widget.onPressed;
    if (action == null) return;
    action();
    SwapHaptics.selection();
    setState(() => _turns += 0.5);
  }

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    return SwapButtonSemantics(
      label: LocaleKeys.swapSwitchDirection.tr(),
      onTap: widget.onPressed == null ? null : _switch,
      child: Tooltip(
        message: LocaleKeys.swapSwitchDirection.tr(),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: palette.canvas, width: 6),
          ),
          child: Material(
            color: palette.surfaceHighest,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: widget.onPressed == null ? null : _switch,
              child: AnimatedRotation(
                turns: _turns,
                duration: SwapMotion.of(context, SwapMotion.pair),
                curve: SwapMotion.standard,
                child: Icon(
                  Icons.swap_vert_rounded,
                  size: 20,
                  color: palette.text,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Accepts one decimal separator (either `.` or `,`, stored as `.`) and at
/// most [maxDecimals] places. Past them, the last digits drop: a digit typed
/// into full places goes in and pushes the last one out.
class _DecimalInputFormatter extends TextInputFormatter {
  _DecimalInputFormatter({required this.maxDecimals});

  final int maxDecimals;

  static final _number = RegExp(r'^\d*\.?\d*$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.replaceAll(',', '.');
    if (!_number.hasMatch(text)) return oldValue;
    final point = text.indexOf('.');
    if (point < 0) return newValue.copyWith(text: text);
    // An amount set with more places, such as from a link, loses no more
    // than an edit adds, and can always be shortened.
    final oldPoint = oldValue.text.indexOf('.');
    final limit = oldPoint < 0
        ? maxDecimals
        : math.max(maxDecimals, oldValue.text.length - oldPoint - 1);
    if (limit == 0 && oldPoint < 0) return oldValue;
    final end = point + 1 + limit;
    if (text.length <= end) return newValue.copyWith(text: text);
    final selection = newValue.selection;
    return TextEditingValue(
      text: text.substring(0, end),
      selection: selection.copyWith(
        baseOffset: math.min(selection.baseOffset, end),
        extentOffset: math.min(selection.extentOffset, end),
      ),
    );
  }
}
