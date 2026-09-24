import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_ui/komodo_ui.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/views/swap/common/swap_buttons.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/common/swap_status_widgets.dart';

/// An asset's logo with its network badge, or a ticker monogram when the
/// asset is not one the wallet knows.
class SwapTokenIcon extends StatelessWidget {
  const SwapTokenIcon({this.asset, this.ticker, this.size = 34, super.key});

  final AssetId? asset;
  final String? ticker;
  final double size;

  @override
  Widget build(BuildContext context) {
    final asset = this.asset;
    if (asset != null) {
      return ExcludeSemantics(
        child: SizedBox.square(
          dimension: size,
          child: AssetLogo.ofId(asset, size: size),
        ),
      );
    }
    final palette = SwapPalette.of(context);
    final label = (ticker ?? '?').trim();
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: palette.surfaceHighest,
          shape: BoxShape.circle,
        ),
        child: Text(
          label.length > 3 ? label.substring(0, 3).toUpperCase() : label,
          style: SwapText.small(context).copyWith(
            color: palette.text,
            fontWeight: FontWeight.w800,
            fontSize: size * 0.3,
          ),
        ),
      ),
    );
  }
}

/// A full value — an address, hash or id — with a copy action.
class SwapCopyLine extends StatelessWidget {
  const SwapCopyLine({
    required this.value,
    this.label,
    this.copyLabel,
    super.key,
  });

  /// What is copied, shown in full.
  final String value;

  /// What the value is, for the confirmation and screen readers.
  final String? label;

  /// The button text. Defaults to "Copy".
  final String? copyLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          // Read as text: the copy button is the screen-reader action, not
          // an 18 dp long-press to select.
          child: Semantics(
            label: label == null ? value : '$label: $value',
            excludeSemantics: true,
            child: SelectableText(value, style: SwapText.code(context)),
          ),
        ),
        const SizedBox(width: 8),
        SwapLinkButton(
          label: copyLabel ?? LocaleKeys.swapCopy.tr(),
          onPressed: () => copyToClipBoard(
            context,
            value,
            LocaleKeys.swapCopied.tr(args: [label ?? value]),
          ),
        ),
      ],
    );
  }
}

/// A shimmering placeholder. Still when the platform asks for less motion.
class SwapSkeleton extends StatefulWidget {
  const SwapSkeleton({this.height = 18, this.widthFactor = 1, super.key});

  final double height;
  final double widthFactor;

  @override
  State<SwapSkeleton> createState() => _SwapSkeletonState();
}

class _SwapSkeletonState extends State<SwapSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widget.widthFactor,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          return Container(
            height: widget.height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: LinearGradient(
                begin: Alignment(-1 + 2 * t - 1, 0),
                end: Alignment(1 + 2 * t - 1, 0),
                colors: [
                  palette.surfaceHigh,
                  palette.surfaceHighest,
                  palette.surfaceHigh,
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A collapsible section: "Costs & protection", "Route & identities".
class SwapDetails extends StatefulWidget {
  const SwapDetails({
    required this.title,
    required this.children,
    this.initiallyExpanded = false,
    super.key,
  });

  final String title;
  final List<Widget> children;
  final bool initiallyExpanded;

  @override
  State<SwapDetails> createState() => _SwapDetailsState();
}

class _SwapDetailsState extends State<SwapDetails> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.controlBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: _expanded,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => setState(() => _expanded = !_expanded),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.title,
                          style: SwapText.strong(context),
                        ),
                      ),
                      AnimatedRotation(
                        turns: _expanded ? 0.5 : 0,
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 180),
                        child: Icon(
                          Icons.expand_more_rounded,
                          color: palette.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: widget.children,
              ),
            ),
        ],
      ),
    );
  }
}

/// A label and value on one line, stacking when the space is narrow.
class SwapDetailRow extends StatelessWidget {
  const SwapDetailRow({
    required this.label,
    required this.value,
    this.valueColor,
    super.key,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final labelText = Text(label, style: SwapText.body(context));
    final valueStyle = SwapText.strong(
      context,
    ).copyWith(color: valueColor, fontWeight: FontWeight.w700);
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 360) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  labelText,
                  const SizedBox(height: 2),
                  Text(value, style: valueStyle),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: labelText),
                const SizedBox(width: 18),
                Flexible(
                  child: Text(
                    value,
                    style: valueStyle,
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Filter chips in a row: Activity's views, the picker's groups.
class SwapFilterBar<T> extends StatelessWidget {
  const SwapFilterBar({
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
    this.countOf,
    this.semanticLabel,
    super.key,
  });

  final List<T> values;
  final T selected;
  final String Function(T value) labelOf;
  final ValueChanged<T> onChanged;
  final int Function(T value)? countOf;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    return Semantics(
      container: true,
      label: semanticLabel,
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [for (final value in values) _chip(context, palette, value)],
      ),
    );
  }

  Widget _chip(BuildContext context, SwapPalette palette, T value) {
    final isSelected = value == selected;
    final count = countOf?.call(value) ?? 0;
    return Semantics(
      button: true,
      selected: isSelected,
      child: Material(
        color: isSelected ? palette.selected : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isSelected ? palette.brand : palette.controlBorder,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => onChanged(value),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    labelOf(value),
                    style: SwapText.body(context).copyWith(
                      color: isSelected ? palette.text : palette.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (count > 0) ...[
                    const SizedBox(width: 8),
                    SwapCountDot(count: count),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
